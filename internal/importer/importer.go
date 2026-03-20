package importer

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"os"

	"github.com/das/faa-knowledge/internal/db"
	"github.com/das/faa-knowledge/internal/models"
)

type SeedFile struct {
	Source    string         `json:"source"`
	Chapter  int            `json:"chapter"`
	Questions []SeedQuestion `json:"questions"`
}

type SeedQuestion struct {
	Section       string   `json:"section"`
	Difficulty    int      `json:"difficulty"`
	Categories    []string `json:"categories"`
	Question      string   `json:"question"`
	CorrectAnswer string   `json:"correct_answer"`
	Distractors   []string `json:"distractors"`
	Explanation   string   `json:"explanation"`
}

func ImportFile(database *sql.DB, path string) (int, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return 0, fmt.Errorf("read %s: %w", path, err)
	}
	return ImportData(database, data, path)
}

func ImportData(database *sql.DB, data []byte, name string) (int, error) {
	var seed SeedFile
	if err := json.Unmarshal(data, &seed); err != nil {
		return 0, fmt.Errorf("parse %s: %w", name, err)
	}

	chapterID, err := db.GetChapterID(database, seed.Source, seed.Chapter)
	if err != nil {
		return 0, err
	}

	// Pre-resolve category IDs
	catIDs := make(map[string]int64)
	for _, sq := range seed.Questions {
		for _, cat := range sq.Categories {
			if _, ok := catIDs[cat]; !ok {
				id, err := db.GetCategoryID(database, cat)
				if err != nil {
					return 0, err
				}
				catIDs[cat] = id
			}
		}
	}

	tx, err := database.Begin()
	if err != nil {
		return 0, fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback()

	count := 0
	for _, sq := range seed.Questions {
		q := models.Question{
			ChapterID:     chapterID,
			Section:       sq.Section,
			Difficulty:    sq.Difficulty,
			QuestionText:  sq.Question,
			CorrectAnswer: sq.CorrectAnswer,
			Explanation:   sq.Explanation,
		}

		qID, err := db.InsertQuestion(tx, q)
		if err != nil {
			return 0, err
		}

		for i, d := range sq.Distractors {
			if err := db.InsertDistractor(tx, qID, d, i); err != nil {
				return 0, fmt.Errorf("insert distractor: %w", err)
			}
		}

		for _, cat := range sq.Categories {
			if err := db.LinkCategory(tx, qID, catIDs[cat]); err != nil {
				return 0, fmt.Errorf("link category: %w", err)
			}
		}

		count++
	}

	if err := tx.Commit(); err != nil {
		return 0, fmt.Errorf("commit: %w", err)
	}

	return count, nil
}
