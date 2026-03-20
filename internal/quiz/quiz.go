package quiz

import (
	"database/sql"
	"fmt"
	"math/rand"

	"github.com/das/faa-knowledge/internal/db"
	"github.com/das/faa-knowledge/internal/models"
)

type Session struct {
	DB        *sql.DB
	Questions []models.Question
	Current   int
	Correct   int
	Total     int
}

func NewSession(database *sql.DB, f db.Filters) (*Session, error) {
	questions, err := db.GetQuestions(database, f)
	if err != nil {
		return nil, err
	}

	if len(questions) == 0 {
		return nil, fmt.Errorf("no questions found matching filters")
	}

	// Load distractors for each question
	for i := range questions {
		ds, err := db.GetDistractors(database, questions[i].ID)
		if err != nil {
			return nil, err
		}
		questions[i].Distractors = ds
	}

	return &Session{
		DB:        database,
		Questions: questions,
		Total:     len(questions),
	}, nil
}

// Options returns the shuffled answer options (correct + distractors) for a question.
func Options(q models.Question) []string {
	opts := make([]string, 0, len(q.Distractors)+1)
	opts = append(opts, q.CorrectAnswer)
	for _, d := range q.Distractors {
		opts = append(opts, d.Text)
	}
	rand.Shuffle(len(opts), func(i, j int) {
		opts[i], opts[j] = opts[j], opts[i]
	})
	return opts
}
