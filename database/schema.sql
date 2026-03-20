-- FAA Knowledge Quiz — Database Schema

CREATE TABLE IF NOT EXISTS sources (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    code        TEXT    NOT NULL UNIQUE,
    title       TEXT    NOT NULL,
    faa_number  TEXT,
    url         TEXT
);

CREATE TABLE IF NOT EXISTS chapters (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    source_id   INTEGER NOT NULL REFERENCES sources(id),
    number      INTEGER NOT NULL,
    title       TEXT    NOT NULL,
    pdf_url     TEXT,
    UNIQUE(source_id, number)
);

CREATE TABLE IF NOT EXISTS categories (
    id    INTEGER PRIMARY KEY AUTOINCREMENT,
    name  TEXT NOT NULL UNIQUE,
    label TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS knowledge_items (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    chapter_id  INTEGER NOT NULL REFERENCES chapters(id),
    section     TEXT,
    fact        TEXT    NOT NULL,
    notes       TEXT,
    created_at  TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS questions (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    chapter_id      INTEGER NOT NULL REFERENCES chapters(id),
    section         TEXT,
    difficulty      INTEGER NOT NULL DEFAULT 1 CHECK (difficulty BETWEEN 1 AND 3),
    question_text   TEXT    NOT NULL,
    correct_answer  TEXT    NOT NULL,
    explanation     TEXT,
    knowledge_id    INTEGER REFERENCES knowledge_items(id),
    active          INTEGER NOT NULL DEFAULT 1,
    created_at      TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS distractors (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    question_id INTEGER NOT NULL REFERENCES questions(id),
    text        TEXT    NOT NULL,
    sort_hint   INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS question_categories (
    question_id INTEGER NOT NULL REFERENCES questions(id),
    category_id INTEGER NOT NULL REFERENCES categories(id),
    PRIMARY KEY (question_id, category_id)
);

CREATE TABLE IF NOT EXISTS user_progress (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    question_id     INTEGER NOT NULL REFERENCES questions(id),
    answered_at     TEXT    NOT NULL DEFAULT (datetime('now')),
    selected_answer TEXT    NOT NULL,
    is_correct      INTEGER NOT NULL,
    time_spent_ms   INTEGER
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_questions_chapter    ON questions(chapter_id);
CREATE INDEX IF NOT EXISTS idx_questions_difficulty  ON questions(difficulty);
CREATE INDEX IF NOT EXISTS idx_questions_active      ON questions(active);
CREATE INDEX IF NOT EXISTS idx_distractors_question  ON distractors(question_id);
CREATE INDEX IF NOT EXISTS idx_knowledge_chapter     ON knowledge_items(chapter_id);
CREATE INDEX IF NOT EXISTS idx_progress_question     ON user_progress(question_id);
CREATE INDEX IF NOT EXISTS idx_progress_answered     ON user_progress(answered_at);
