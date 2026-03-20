package models

import "time"

type Source struct {
	ID        int64
	Code      string
	Title     string
	FAANumber string
	URL       string
}

type Chapter struct {
	ID       int64
	SourceID int64
	Number   int
	Title    string
	PDFURL   string
}

type Category struct {
	ID    int64
	Name  string
	Label string
}

type KnowledgeItem struct {
	ID        int64
	ChapterID int64
	Section   string
	Fact      string
	Notes     string
	CreatedAt time.Time
}

type Question struct {
	ID            int64
	ChapterID     int64
	Section       string
	Difficulty    int
	QuestionText  string
	CorrectAnswer string
	Explanation   string
	KnowledgeID   *int64
	Active        bool
	CreatedAt     time.Time

	// Populated by queries
	Distractors []Distractor
	Categories  []string
	SourceCode  string
	ChapterNum  int
}

type Distractor struct {
	ID         int64
	QuestionID int64
	Text       string
	SortHint   int
}

type UserProgress struct {
	ID             int64
	QuestionID     int64
	AnsweredAt     time.Time
	SelectedAnswer string
	IsCorrect      bool
	TimeSpentMs    *int64
}
