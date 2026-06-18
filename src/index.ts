import { Hono } from 'hono';

type Bindings = {
	DB: D1Database;
	TELEGRAM_BOT_TOKEN: string;
};

type Variables = {
	tgUser: {
		id: number;
		first_name: string;
		username?: string;
		language_code?: string;
	};
};

const app = new Hono<{ Bindings: Bindings; Variables: Variables }>();

/**
 * Validates cryptographically that incoming parameters originated from Telegram
 * and have not been altered via reverse engineering or MITM vectors.
 */
async function verifyTelegramSignature(initData: string, botToken: string): Promise<boolean> {
	try {
		const urlParams = new URLSearchParams(initData);
		const hash = urlParams.get('hash');
		if (!hash) return false;

		urlParams.delete('hash');
		urlParams.sort();

		let dataCheckString = '';
		for (const [key, value] of urlParams.entries()) {
			dataCheckString += `${key}=${value}\n`;
		}
		dataCheckString = dataCheckString.slice(0, -1);

		const encoder = new TextEncoder();
		const secretKey = await crypto.subtle.importKey(
			'raw',
			encoder.encode('WebAppData'),
			{ name: 'HMAC', hash: 'SHA-256' },
			false,
			['sign']
		);
		const secret = await crypto.subtle.sign('HMAC', secretKey, encoder.encode(botToken));
		const signatureKey = await crypto.subtle.importKey(
			'raw',
			secret,
			{ name: 'HMAC', hash: 'SHA-256' },
			false,
			['sign']
		);
		const signature = await crypto.subtle.sign('HMAC', signatureKey, encoder.encode(dataCheckString));
		const calculatedHash = [...new Uint8Array(signature)].map((b) => b.toString(16).padStart(2, '0')).join('');

		return calculatedHash === hash;
	} catch {
		return false;
	}
}

// POST /webhook - Handles incoming Telegram Bot updates
app.post('/webhook', async (c) => {
	const update = await c.req.json<any>();
	
	if (update.message && update.message.text) {
		const text = update.message.text;
		const chatId = update.message.chat.id;

		if (text.startsWith('/start') || text.startsWith('/help')) {
			// Construct the Web App URL from the request origin
			const origin = new URL(c.req.url).origin;
			
			const messageText = `🧠 *Welcome to IQ Master!* 🧠\n\nTest your cognitive abilities with our premium psychometric assessment.\n\nClick the button below to launch the Mini App and discover your IQ!`;
			
			const payload = {
				chat_id: chatId,
				text: messageText,
				parse_mode: 'Markdown',
				reply_markup: {
					inline_keyboard: [
						[
							{
								text: "🚀 Launch IQ Master",
								web_app: { url: origin }
							}
						]
					]
				}
			};

			c.executionCtx.waitUntil(
				fetch(`https://api.telegram.org/bot${c.env.TELEGRAM_BOT_TOKEN}/sendMessage`, {
					method: 'POST',
					headers: {
						'Content-Type': 'application/json'
					},
					body: JSON.stringify(payload)
				})
			);
		}
	}

	return c.text('OK');
});

// Global Middleware implementing explicit API perimeter isolation
app.use('/api/*', async (c, next) => {
	const initData = c.req.header('X-Telegram-Init-Data');
	if (!initData) return c.json({ error: 'Missing security payload credentials.' }, 401);

	const isValid = await verifyTelegramSignature(initData, c.env.TELEGRAM_BOT_TOKEN);
	if (!isValid) return c.json({ error: 'Signature mismatch. Request untrusted.' }, 403);

	const urlParams = new URLSearchParams(initData);
	const rawUser = urlParams.get('user');
	if (!rawUser) return c.json({ error: 'Identity extraction failed.' }, 400);

	c.set('tgUser', JSON.parse(rawUser));
	await next();
});

// GET /api/me - Performs safe transactional synchronization of identity parameters
app.get('/api/me', async (c) => {
	const tgUser = c.get('tgUser');
	const idStr = tgUser.id.toString();

	const user = await c.env.DB.prepare(`
		INSERT INTO users (tg_id, username, first_name, language_code) 
		VALUES (?, ?, ?, ?)
		ON CONFLICT(tg_id) DO UPDATE SET 
			username = excluded.username, 
			first_name = excluded.first_name, 
			updated_at = CURRENT_TIMESTAMP
		RETURNING *
	`)
		.bind(idStr, tgUser.username || null, tgUser.first_name, tgUser.language_code || null)
		.first();

	return c.json(user);
});

// POST /api/quiz/start - Spawns a stateful session to prevent puzzle scrubbing
app.post('/api/quiz/start', async (c) => {
	const tgUser = c.get('tgUser');
	const attemptId = crypto.randomUUID();
	
	// Build a progressive 10-question matrix across difficulty tiers
	const queries = [
		c.env.DB.prepare('SELECT id, category, question_text, options FROM questions WHERE difficulty = 1 ORDER BY RANDOM() LIMIT 3'),
		c.env.DB.prepare('SELECT id, category, question_text, options FROM questions WHERE difficulty = 2 ORDER BY RANDOM() LIMIT 3'),
		c.env.DB.prepare('SELECT id, category, question_text, options FROM questions WHERE difficulty = 3 ORDER BY RANDOM() LIMIT 2'),
		c.env.DB.prepare('SELECT id, category, question_text, options FROM questions WHERE difficulty = 4 ORDER BY RANDOM() LIMIT 1'),
		c.env.DB.prepare('SELECT id, category, question_text, options FROM questions WHERE difficulty = 5 ORDER BY RANDOM() LIMIT 1')
	];
	
	const batchedResults = await c.env.DB.batch(queries);
	const orderedQuestions = batchedResults.flatMap((res: any) => res.results).map((q: any) => ({
		id: q.id,
		category: q.category,
		question_text: q.question_text,
		options: JSON.parse(q.options)
	}));
	const questionIds = orderedQuestions.map((q: any) => q.id);

	const now = Date.now();
	const durationLimit = 10 * 60 * 1000; // Hard bounded window allocation (10 minutes for 10 questions)
	const expiresAt = now + durationLimit;

	await c.env.DB.prepare(
		'INSERT INTO quiz_attempts (id, tg_id, question_ids, answers, started_at, expires_at) VALUES (?, ?, ?, ?, ?, ?)'
	)
		.bind(attemptId, tgUser.id.toString(), JSON.stringify(questionIds), JSON.stringify({}), now, expiresAt)
		.run();

	return c.json({ attemptId, questions: orderedQuestions, expiresAt });
});

// POST /api/quiz/submit - Evaluates answers server-side within the stateful session time box
app.post('/api/quiz/submit', async (c) => {
	const tgUser = c.get('tgUser');
	const payload = await c.req.json<{ attemptId: string; answers: Record<number, number> }>();
	const now = Date.now();

	const attempt = await c.env.DB.prepare('SELECT * FROM quiz_attempts WHERE id = ? AND tg_id = ?')
		.bind(payload.attemptId, tgUser.id.toString())
		.first() as any;

	if (!attempt) return c.json({ error: 'Session execution context not found.' }, 404);
	if (attempt.is_completed === 1) return c.json({ error: 'Quiz transaction already settled.' }, 400);
	if (now > attempt.expires_at) return c.json({ error: 'Temporal boundary limit exceeded. Submission void.' }, 400);

	const activeQuestionIds = JSON.parse(attempt.question_ids) as number[];
	const placeholders = activeQuestionIds.map(() => '?').join(',');
	
	const truthSet = await c.env.DB.prepare(
		`SELECT id, correct_index, difficulty FROM questions WHERE id IN (${placeholders})`
	)
		.bind(...activeQuestionIds)
		.all();

	let earnedPoints = 0;
	let aggregatePossiblePoints = 0;
	const evaluationMatrix: Record<number, { correct: boolean; solution: number }> = {};

	truthSet.results.forEach((q: any) => {
		// Exponential difficulty weighting: 10, 20, 40, 80, 160
		const weight = Math.pow(2, q.difficulty - 1) * 10;
		aggregatePossiblePoints += weight;
		
		const selectedIndex = payload.answers[q.id];
		const isCorrect = selectedIndex !== undefined && selectedIndex === q.correct_index;
		
		if (isCorrect) {
			earnedPoints += weight;
		}

		evaluationMatrix[q.id] = {
			correct: isCorrect,
			solution: q.correct_index
		};
	});

	// Standard psychometric computation scale: baseline 70, max ~150
	const accuracyRatio = earnedPoints / (aggregatePossiblePoints || 1);
	const computedIq = Math.round(70 + (accuracyRatio * 80));

	// Save verification record atomic modifications asynchronously
	c.executionCtx.waitUntil(
		c.env.DB.batch([
			c.env.DB.prepare('UPDATE quiz_attempts SET answers = ?, score = ?, is_completed = 1 WHERE id = ?')
				.bind(JSON.stringify(payload.answers), computedIq, payload.attemptId),
			c.env.DB.prepare('UPDATE users SET total_quizzes = total_quizzes + 1, best_iq = MAX(best_iq, ?), updated_at = CURRENT_TIMESTAMP WHERE tg_id = ?')
				.bind(computedIq, tgUser.id.toString())
		])
	);

	return c.json({
		iq: computedIq,
		pointsEarned: earnedPoints,
		breakdown: evaluationMatrix
	});
});

// GET /api/leaderboard - Returns indexed system scaling standings global ranking array
app.get('/api/leaderboard', async (c) => {
	const { results } = await c.env.DB.prepare(
		'SELECT first_name, username, best_iq FROM users WHERE best_iq > 0 ORDER BY best_iq DESC LIMIT 10'
	).all();
	return c.json(results);
});

export default app;
