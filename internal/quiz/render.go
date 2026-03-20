package quiz

import (
	"bufio"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/das/faa-knowledge/internal/db"
)

const (
	colorReset  = "\033[0m"
	colorRed    = "\033[31m"
	colorGreen  = "\033[32m"
	colorYellow = "\033[33m"
	colorCyan   = "\033[36m"
	colorBold   = "\033[1m"
	colorDim    = "\033[2m"
)

func (s *Session) Run() {
	reader := bufio.NewReader(os.Stdin)

	fmt.Printf("\n%s%sFAA Knowledge Quiz%s — %d questions\n\n",
		colorBold, colorCyan, colorReset, s.Total)

	for s.Current < len(s.Questions) {
		q := s.Questions[s.Current]
		opts := Options(q)

		// Header
		fmt.Printf("%s[%d/%d]%s %s%s Ch.%d%s",
			colorDim, s.Current+1, s.Total, colorReset,
			colorDim, q.SourceCode, q.ChapterNum, colorReset)
		if q.Section != "" {
			fmt.Printf(" — %s", q.Section)
		}
		fmt.Println()

		// Difficulty
		diff := strings.Repeat("★", q.Difficulty) + strings.Repeat("☆", 3-q.Difficulty)
		fmt.Printf("%sDifficulty: %s%s\n\n", colorDim, diff, colorReset)

		// Question
		fmt.Printf("%s%s%s\n\n", colorBold, q.QuestionText, colorReset)

		// Options
		labels := []string{"a", "b", "c", "d"}
		for i, opt := range opts {
			if i < len(labels) {
				fmt.Printf("  %s%s)%s %s\n", colorYellow, labels[i], colorReset, opt)
			}
		}

		// Input
		fmt.Printf("\n%sYour answer (a/b/c/d): %s", colorCyan, colorReset)
		start := time.Now()
		input, _ := reader.ReadString('\n')
		elapsed := time.Since(start)
		input = strings.TrimSpace(strings.ToLower(input))

		// Map input to index
		idx := -1
		for i, l := range labels {
			if input == l {
				idx = i
				break
			}
		}

		if idx < 0 || idx >= len(opts) {
			fmt.Printf("%sInvalid input, skipping.%s\n\n", colorRed, colorReset)
			s.Current++
			continue
		}

		selected := opts[idx]
		correct := selected == q.CorrectAnswer

		if correct {
			s.Correct++
			fmt.Printf("\n%s✓ Correct!%s\n", colorGreen, colorReset)
		} else {
			fmt.Printf("\n%s✗ Incorrect.%s The answer is: %s%s%s\n",
				colorRed, colorReset, colorGreen, q.CorrectAnswer, colorReset)
		}

		if q.Explanation != "" {
			fmt.Printf("%s%s%s\n", colorDim, q.Explanation, colorReset)
		}

		// Record attempt
		ms := elapsed.Milliseconds()
		_ = db.RecordAttempt(s.DB, q.ID, selected, correct, ms)

		s.Current++
		fmt.Println()
	}

	// Summary
	pct := float64(s.Correct) / float64(s.Total) * 100
	color := colorGreen
	if pct < 70 {
		color = colorRed
	} else if pct < 80 {
		color = colorYellow
	}

	fmt.Printf("%s%s══════════════════════════════%s\n", colorBold, colorCyan, colorReset)
	fmt.Printf("%sScore: %s%d/%d (%.0f%%)%s\n",
		colorBold, color, s.Correct, s.Total, pct, colorReset)

	if pct >= 70 {
		fmt.Printf("%sPassing score for FAA written: 70%%%s\n", colorDim, colorReset)
	} else {
		fmt.Printf("%sBelow FAA passing score (70%%)%s\n", colorRed, colorReset)
	}
	fmt.Println()
}

