-- visatk/iqmaster Database Schema
DROP TABLE IF EXISTS leaderboard;
DROP TABLE IF EXISTS quiz_attempts;
DROP TABLE IF EXISTS questions;
DROP TABLE IF EXISTS users;

-- Core User profile matching Telegram payload metadata
CREATE TABLE users (
    tg_id TEXT PRIMARY KEY,
    username TEXT,
    first_name TEXT NOT NULL,
    language_code TEXT,
    best_iq INTEGER DEFAULT 0,
    total_quizzes INTEGER DEFAULT 0,
    streak_count INTEGER DEFAULT 0,
    last_played_date TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- OPTIMIZATION: Index to ensure global leaderboard queries scale gracefully
CREATE INDEX IF NOT EXISTS idx_users_best_iq ON users(best_iq DESC);

-- Question matrix containing diverse cognitive categories
CREATE TABLE questions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    category TEXT NOT NULL, -- 'spatial', 'numerical', 'verbal', 'logic'
    question_text TEXT NOT NULL,
    options TEXT NOT NULL, -- JSON array of strings
    correct_index INTEGER NOT NULL,
    difficulty INTEGER DEFAULT 1 -- 1: Easy, 2: Medium, 3: Hard
);

-- State tracking table to prevent cheating and track sessions
CREATE TABLE quiz_attempts (
    id TEXT PRIMARY KEY,
    tg_id TEXT NOT NULL,
    question_ids TEXT NOT NULL, -- JSON array of selected question numbers
    current_index INTEGER DEFAULT 0,
    answers TEXT NOT NULL, -- JSON object tracking {question_id: selected_index}
    score INTEGER DEFAULT 0,
    is_completed INTEGER DEFAULT 0,
    started_at INTEGER NOT NULL, -- Epoch millisecond timestamp
    expires_at INTEGER NOT NULL, -- Anti-cheating expiration threshold
    FOREIGN KEY(tg_id) REFERENCES users(tg_id)
);

-- Pre-populate curated, high-fidelity psychometric question items
INSERT INTO questions (category, question_text, options, correct_index, difficulty) VALUES 
-- NUMERICAL
('numerical', 'Complete the sequence: 2, 4, 8, 16, 32, ...', '["48", "64", "54", "128"]', 1, 1),
('numerical', 'Find the missing number in the sequence: 1, 1, 2, 3, 5, 8, 13, ?', '["19", "20", "21", "22"]', 2, 1),
('numerical', 'What is the missing value? 4, 9, 16, 25, ?, 49', '["30", "36", "42", "32"]', 1, 1),
('numerical', 'Solve for X: 3, 5, 9, 17, X', '["25", "33", "31", "35"]', 1, 2),
('numerical', 'What comes next? 144, 121, 100, 81, 64, ?', '["49", "50", "42", "36"]', 0, 2),
('numerical', 'Which number does not belong: 2, 3, 5, 7, 9, 11, 13', '["5", "7", "9", "11"]', 2, 2),
('numerical', 'What number fills the matrix sequence? [2, 3, 5], [7, 11, 13], [17, 19, ?]', '["21", "23", "25", "29"]', 1, 3),
('numerical', 'If 3 cats can catch 3 bunnies in 3 minutes, how long will it take 100 cats to catch 100 bunnies?', '["100 minutes", "3 minutes", "300 minutes", "10 minutes"]', 1, 3),
('numerical', 'If 1/2 of x is 1/3 of y, and x + y = 30, what is the value of x?', '["10", "12", "15", "18"]', 1, 3),
('numerical', 'A train running at 60 km/h crosses a 200m long platform in 27 seconds. What is the length of the train?', '["200m", "250m", "300m", "350m"]', 1, 4),
('numerical', 'A bat and a ball cost $1.10 in total. The bat costs $1.00 more than the ball. How much does the ball cost?', '["10 cents", "5 cents", "1 cent", "15 cents"]', 1, 4),
('numerical', 'Solve the equation sequence: 1+4=5, 2+5=12, 3+6=21, 8+11=?', '["40", "96", "52", "72"]', 1, 5),
-- LOGIC
('logic', 'If all Bloops are Razzies and all Razzies are Jazzies, then all Bloops are definitely Jazzies.', '["True", "False", "Partially True", "Cannot be determined"]', 0, 1),
('logic', 'Mary''s father has five daughters: Nana, Nene, Nini, Nono, and...', '["Nunu", "Mary", "None", "Nina"]', 1, 1),
('logic', 'David''s father has three sons: Snap, Crackle, and...?', '["Pop", "David", "John", "None of the above"]', 1, 1),
('logic', 'Five people run a race. A finishes ahead of B but behind C. D finishes ahead of E but behind B. Who wins the race?', '["A", "B", "C", "D"]', 2, 2),
('logic', 'If you rearrange the letters "CIFAIPC", you would have the name of a(n):', '["City", "Animal", "Ocean", "River"]', 2, 2),
('logic', 'Some months have 31 days. How many have 28?', '["1", "2", "6", "12"]', 3, 2),
('logic', 'If some Flops are Glops, and all Glops are Plops, are some Flops definitely Plops?', '["Yes", "No", "Cannot be determined", "Only if Flops are not Plops"]', 0, 3),
('logic', 'John is taller than Peter, and Bill is shorter than John. Which of the following statements is most accurate?', '["Bill is taller than Peter", "Peter is taller than Bill", "It is impossible to tell who is taller between Peter and Bill", "John is the tallest"]', 2, 3),
('logic', 'A clock shows 3:15. What is the precise angle between the hour and minute hands?', '["0°", "7.5°", "15°", "90°"]', 1, 4),
('logic', 'If it takes 5 machines 5 minutes to make 5 widgets, how long would it take 100 machines to make 100 widgets?', '["100 minutes", "5 minutes", "50 minutes", "1 minute"]', 1, 4),
('logic', 'You have a 3-liter jug and a 5-liter jug. How can you measure exactly 4 liters?', '["Fill 5, pour 3 out, keep 2", "Fill 3, pour to 5, fill 3, pour 2 to 5", "Impossible", "Fill 5, pour to 3, drink 1 liter"]', 1, 5),
-- SPATIAL
('spatial', 'If you fold a flat net of 6 squares arranged in a cross shape, what 3D object does it form?', '["Pyramid", "Cylinder", "Cube", "Sphere"]', 2, 1),
('spatial', 'Which shape completes the rule: Square fits inside Circle, Circle fits inside Triangle, Triangle fits inside...', '["Line", "Point", "Square", "Sphere"]', 2, 2),
('spatial', 'Which direction does the gear on the far right turn if the leftmost gear (of 5 interlocking gears) turns clockwise?', '["Clockwise", "Counter-clockwise", "It doesn''t turn", "Both"]', 0, 3),
('spatial', 'If you rotate a right-angled triangle 360 degrees around its vertical axis, what 3D shape do you get?', '["Pyramid", "Cone", "Cylinder", "Sphere"]', 1, 3),
('spatial', 'Imagine the letter "d" is rotated 180 degrees horizontally, then 180 degrees vertically. What letter does it look like?', '["p", "b", "q", "d"]', 3, 3),
('spatial', 'How many edges does a standard hexagonal prism have?', '["12", "18", "24", "16"]', 1, 4),
('spatial', 'A cube is painted red on all sides, then cut into 27 small equal cubes. How many small cubes have exactly 2 sides painted?', '["8", "12", "6", "1"]', 1, 4),
('spatial', 'Imagine a large wooden cube painted blue on all sides. It is cut into 64 smaller identical cubes. How many have zero sides painted blue?', '["4", "8", "16", "24"]', 1, 5),
-- VERBAL
('verbal', 'Find the odd one out:', '["Apple", "Banana", "Carrot", "Mango"]', 2, 1),
('verbal', 'Architect is to Building as Sculptor is to:', '["Chisel", "Stone", "Museum", "Statue"]', 3, 1),
('verbal', 'Window is to pane as book is to:', '["Cover", "Page", "Words", "Novel"]', 1, 1),
('verbal', 'Choose the word that is an antonym of "Ephemeral":', '["Fleeting", "Permanent", "Transient", "Beautiful"]', 1, 2),
('verbal', 'Which word does not belong with the others?', '["Guitar", "Flute", "Violin", "Cello"]', 1, 2),
('verbal', 'Odometer is to mileage as compass is to:', '["Speed", "Hiking", "Needle", "Direction"]', 3, 2),
('verbal', 'Elation is the opposite of:', '["Joy", "Despair", "Surprise", "Anger"]', 1, 3),
('verbal', 'What is a synonym for "Mellifluous"?', '["Harsh", "Sweet-sounding", "Loud", "Silent"]', 1, 4),
('verbal', 'Which word means "a person who dislikes humankind"?', '["Philanthropist", "Misanthrope", "Introvert", "Ascetic"]', 1, 4),
('verbal', '"Cacophony" is to "Harmony" as "Belligerent" is to:', '["Peaceful", "Aggressive", "Loud", "Silent"]', 0, 5);

-- Composite performance indexes
CREATE INDEX idx_users_best_iq ON users(best_iq DESC);
CREATE INDEX idx_attempts_user ON quiz_attempts(tg_id);
