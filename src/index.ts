import { Hono } from 'hono';

// Types definition mapping to wrangler.jsonc bindings
type Bindings = {
	DB: D1Database;
	TELEGRAM_BOT_TOKEN: string;
};

type Variables = {
	tgUser: { id: number; first_name: string };
};

const app = new Hono<{ Bindings: Bindings; Variables: Variables }>();

/**
 * Validates Telegram Web App initData to prevent spoofing attacks.
 * Utilizes native Web Crypto API for zero-dependency edge performance.
 */
async function verifyTelegramWebAppData(initData: string, botToken: string): Promise<boolean> {
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
		const secretKey = await crypto.subtle.importKey('raw', encoder.encode('WebAppData'), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
		const secret = await crypto.subtle.sign('HMAC', secretKey, encoder.encode(botToken));
		const signatureKey = await crypto.subtle.importKey('raw', secret, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
		const signature = await crypto.subtle.sign('HMAC', signatureKey, encoder.encode(dataCheckString));

		const hex = [...new Uint8Array(signature)].map((b) => b.toString(16).padStart(2, '0')).join('');
		return hex === hash;
	} catch (e) {
		return false;
	}
}

// Middleware: Authenticate Telegram User
app.use('/api/*', async (c, next) => {
	const initData = c.req.header('x-telegram-init-data');
	if (!initData) return c.json({ error: 'Unauthorized: Missing initData' }, 401);

	const isValid = await verifyTelegramWebAppData(initData, c.env.TELEGRAM_BOT_TOKEN);
	if (!isValid) return c.json({ error: 'Unauthorized: Invalid signature' }, 403);

	const urlParams = new URLSearchParams(initData);
	const userStr = urlParams.get('user');
	if (!userStr) return c.json({ error: 'Unauthorized: Missing user data' }, 401);

	c.set('tgUser', JSON.parse(userStr));
	await next();
});

// Route: Initialize or fetch user profile
app.get('/api/me', async (c) => {
	const user = c.get('tgUser');
	
	// Parameterized query prevents SQL Injection
	let dbUser = await c.env.DB.prepare('SELECT * FROM users WHERE tg_id = ?').bind(user.id.toString()).first();

	if (!dbUser) {
		await c.env.DB.prepare('INSERT INTO users (tg_id, first_name) VALUES (?, ?)')
			.bind(user.id.toString(), user.first_name)
			.run();
		dbUser = { tg_id: user.id.toString(), first_name: user.first_name, best_score: 0 };
	}

	return c.json(dbUser);
});

// Route: Fetch questions
app.get('/api/questions', async (c) => {
	const { results } = await c.env.DB.prepare('SELECT id, question_text, options FROM questions ORDER BY RANDOM() LIMIT 5').all();
	// Parse JSON options before sending to client
	const formattedResults = results.map((q: any) => ({
		...q,
		options: JSON.parse(q.options)
	}));
	return c.json(formattedResults);
});

// Route: Submit answers and calculate score securely on the backend
app.post('/api/submit', async (c) => {
	const user = c.get('tgUser');
	const { answers } = await c.req.json<{ answers: Record<number, number> }>();
	
	const questionIds = Object.keys(answers).map(Number);
	if (questionIds.length === 0) return c.json({ score: 0 });

	// Fetch correct answers
	const placeholders = questionIds.map(() => '?').join(',');
	const query = `SELECT id, correct_index FROM questions WHERE id IN (${placeholders})`;
	const { results } = await c.env.DB.prepare(query).bind(...questionIds).all();

	let score = 0;
	results.forEach((row: any) => {
		if (answers[row.id] === row.correct_index) score += 20; // 20 points per correct answer
	});

	// Update high score transactionally
	await c.env.DB.prepare(
		`UPDATE users SET best_score = MAX(best_score, ?), last_played = CURRENT_TIMESTAMP WHERE tg_id = ?`
	).bind(score, user.id.toString()).run();

	return c.json({ score, maxPossible: questionIds.length * 20 });
});

export default app;
