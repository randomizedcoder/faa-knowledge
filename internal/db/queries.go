package db

import (
	"database/sql"
	"fmt"
	"strings"
	"time"

	"github.com/das/faa-knowledge/internal/models"
)

type Filters struct {
	Category   string
	SourceCode string
	Chapter    int
	Difficulty int
	Limit      int
}

func GetQuestions(db *sql.DB, f Filters) ([]models.Question, error) {
	query := `
		SELECT q.id, q.chapter_id, q.section, q.difficulty,
		       q.question_text, q.correct_answer, q.explanation,
		       s.code, ch.number
		FROM questions q
		JOIN chapters ch ON ch.id = q.chapter_id
		JOIN sources s ON s.id = ch.source_id
	`

	var conditions []string
	var args []interface{}

	conditions = append(conditions, "q.active = 1")

	if f.Category != "" {
		query += " JOIN question_categories qc ON qc.question_id = q.id"
		query += " JOIN categories c ON c.id = qc.category_id"
		conditions = append(conditions, "c.name = ?")
		args = append(args, f.Category)
	}

	if f.SourceCode != "" {
		conditions = append(conditions, "s.code = ?")
		args = append(args, f.SourceCode)
	}

	if f.Chapter > 0 {
		conditions = append(conditions, "ch.number = ?")
		args = append(args, f.Chapter)
	}

	if f.Difficulty > 0 {
		conditions = append(conditions, "q.difficulty = ?")
		args = append(args, f.Difficulty)
	}

	if len(conditions) > 0 {
		query += " WHERE " + strings.Join(conditions, " AND ")
	}

	query += " ORDER BY RANDOM()"

	if f.Limit > 0 {
		query += fmt.Sprintf(" LIMIT %d", f.Limit)
	}

	rows, err := db.Query(query, args...)
	if err != nil {
		return nil, fmt.Errorf("query questions: %w", err)
	}
	defer rows.Close()

	var questions []models.Question
	for rows.Next() {
		var q models.Question
		var section, explanation sql.NullString
		if err := rows.Scan(
			&q.ID, &q.ChapterID, &section, &q.Difficulty,
			&q.QuestionText, &q.CorrectAnswer, &explanation,
			&q.SourceCode, &q.ChapterNum,
		); err != nil {
			return nil, fmt.Errorf("scan question: %w", err)
		}
		q.Section = section.String
		q.Explanation = explanation.String
		questions = append(questions, q)
	}

	return questions, rows.Err()
}

func GetDistractors(db *sql.DB, questionID int64) ([]models.Distractor, error) {
	rows, err := db.Query(
		"SELECT id, question_id, text, sort_hint FROM distractors WHERE question_id = ? ORDER BY sort_hint",
		questionID,
	)
	if err != nil {
		return nil, fmt.Errorf("query distractors: %w", err)
	}
	defer rows.Close()

	var ds []models.Distractor
	for rows.Next() {
		var d models.Distractor
		if err := rows.Scan(&d.ID, &d.QuestionID, &d.Text, &d.SortHint); err != nil {
			return nil, fmt.Errorf("scan distractor: %w", err)
		}
		ds = append(ds, d)
	}
	return ds, rows.Err()
}

func RecordAttempt(db *sql.DB, questionID int64, selected string, correct bool, ms int64) error {
	_, err := db.Exec(
		`INSERT INTO user_progress (question_id, answered_at, selected_answer, is_correct, time_spent_ms)
		 VALUES (?, ?, ?, ?, ?)`,
		questionID, time.Now().UTC().Format(time.RFC3339), selected, correct, ms,
	)
	return err
}

func GetChapterID(db *sql.DB, sourceCode string, chapterNum int) (int64, error) {
	var id int64
	err := db.QueryRow(
		`SELECT ch.id FROM chapters ch
		 JOIN sources s ON s.id = ch.source_id
		 WHERE s.code = ? AND ch.number = ?`,
		sourceCode, chapterNum,
	).Scan(&id)
	if err != nil {
		return 0, fmt.Errorf("get chapter id for %s ch%d: %w", sourceCode, chapterNum, err)
	}
	return id, nil
}

func GetCategoryID(db *sql.DB, name string) (int64, error) {
	var id int64
	err := db.QueryRow("SELECT id FROM categories WHERE name = ?", name).Scan(&id)
	if err != nil {
		return 0, fmt.Errorf("get category %q: %w", name, err)
	}
	return id, nil
}

func InsertQuestion(tx *sql.Tx, q models.Question) (int64, error) {
	res, err := tx.Exec(
		`INSERT INTO questions (chapter_id, section, difficulty, question_text, correct_answer, explanation)
		 VALUES (?, ?, ?, ?, ?, ?)`,
		q.ChapterID, q.Section, q.Difficulty, q.QuestionText, q.CorrectAnswer, q.Explanation,
	)
	if err != nil {
		return 0, fmt.Errorf("insert question: %w", err)
	}
	return res.LastInsertId()
}

func InsertDistractor(tx *sql.Tx, questionID int64, text string, sortHint int) error {
	_, err := tx.Exec(
		"INSERT INTO distractors (question_id, text, sort_hint) VALUES (?, ?, ?)",
		questionID, text, sortHint,
	)
	return err
}

func LinkCategory(tx *sql.Tx, questionID, categoryID int64) error {
	_, err := tx.Exec(
		"INSERT OR IGNORE INTO question_categories (question_id, category_id) VALUES (?, ?)",
		questionID, categoryID,
	)
	return err
}
