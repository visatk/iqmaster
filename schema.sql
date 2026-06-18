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
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

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
('numerical', 'Complete the sequence: 2, 4, 8, 16, 32, ...', '["48", "64", "54", "128"]', 1, 1),
('logic', 'If all Bloops are Razzies and all Razzies are Jazzies, then all Bloops are definitely Jazzies.', '["True", "False", "Partially True", "Cannot be determined"]', 0, 1),
('spatial', 'Which shape completes the rule: Square fits inside Circle, Circle fits inside Triangle, Triangle fits inside...', '["Line", "Point", "Square", "Sphere"]', 2, 2),
('numerical', 'Solve for X: 3, 5, 9, 17, X', '["25", "33", "31", "35"]', 1, 2),
('verbal', 'Architect is to Building as Sculptor is to:', '["Chisel", "Stone", "Museum", "Statue"]', 3, 1),
('logic', 'A clock shows 3:15. What is the precise angle between the hour and minute hands?', '["0°", "7.5°", "15°", "90°"]', 1, 3),
('spatial', 'A cube is painted red on all sides, then cut into 27 small equal cubes. How many small cubes have exactly 2 sides painted?', '["8", "12", "6", "1"]', 1, 3),
('numerical', 'What number fills the matrix sequence? [2, 3, 5], [7, 11, 13], [17, 19, ?]', '["21", "23", "25", "29"]', 1, 2),
('verbal', 'Choose the word that is an antonym of "Ephemeral":', '["Fleeting", "Permanent", "Transient", "Beautiful"]', 1, 2),
('logic', 'Five people run a race. A finishes ahead of B but behind C. D finishes ahead of E but behind B. Who wins the race?', '["A", "B", "C", "D"]', 2, 2);

-- Composite performance indexes
CREATE INDEX idx_users_best_iq ON users(best_iq DESC);
CREATE INDEX idx_attempts_user ON quiz_attempts(tg_id);
