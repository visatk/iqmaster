DROP TABLE IF EXISTS users;
CREATE TABLE users (
    tg_id TEXT PRIMARY KEY,
    first_name TEXT NOT NULL,
    best_score INTEGER DEFAULT 0,
    last_played TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

DROP TABLE IF EXISTS questions;
CREATE TABLE questions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    question_text TEXT NOT NULL,
    options TEXT NOT NULL, -- Stored as JSON array string
    correct_index INTEGER NOT NULL
);

-- Seed initial IQ test questions
INSERT INTO questions (question_text, options, correct_index) VALUES 
('Which number should come next in the pattern? 37, 34, 31, 28...', '["25", "26", "27", "24"]', 0),
('Book is to Reading as Fork is to:', '["Eating", "Food", "Steak", "Spoon"]', 0),
('What is the missing number? 1, 1, 2, 3, 5, 8, ?', '["11", "12", "13", "14"]', 2);
