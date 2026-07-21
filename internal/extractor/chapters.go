// Copyright (c) 2026 randomizedcoder. All Rights Reserved.
// Proprietary and confidential -- see the LICENSE file in the project root.

package extractor

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

// pageLabel matches FAA handbook page labels like "5-1", "12-3".
var pageLabel = regexp.MustCompile(`(?m)^\s*(\d{1,2})-(\d{1,2})\s*$`)

// chapterHeader matches lines like "Chapter 5" or "Chapter 12".
var chapterHeader = regexp.MustCompile(`(?i)Chapter\s+(\d{1,2})`)

// DetectChapter tries to determine the chapter number from a page's text
// by looking for page labels (e.g., "5-1") or chapter headers.
func DetectChapter(text string) int {
	// Check first few lines for a page label like "5-1"
	lines := strings.SplitN(text, "\n", 10)
	for _, line := range lines {
		if m := pageLabel.FindStringSubmatch(strings.TrimSpace(line)); m != nil {
			ch, _ := strconv.Atoi(m[1])
			return ch
		}
	}

	// Look for "Chapter N" header
	if m := chapterHeader.FindStringSubmatch(text); m != nil {
		ch, _ := strconv.Atoi(m[1])
		return ch
	}

	return 0
}

// DetectPageLabel returns the handbook page label (e.g., "5-12") from a page's text.
func DetectPageLabel(text string) string {
	lines := strings.SplitN(text, "\n", 10)
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if m := pageLabel.FindStringSubmatch(trimmed); m != nil {
			return fmt.Sprintf("%s-%s", m[1], m[2])
		}
	}
	return ""
}

// SplitChapters groups pages by chapter number.
func SplitChapters(pages []Page) map[int][]Page {
	chapters := make(map[int][]Page)
	currentChapter := 0

	for _, p := range pages {
		ch := DetectChapter(p.Text)
		if ch > 0 {
			currentChapter = ch
		}
		if currentChapter > 0 {
			chapters[currentChapter] = append(chapters[currentChapter], p)
		}
	}

	return chapters
}

// ChapterText returns the full text of a specific chapter, concatenated from its pages.
func ChapterText(pages []Page, chapter int) string {
	chapters := SplitChapters(pages)
	chPages, ok := chapters[chapter]
	if !ok {
		return ""
	}

	var b strings.Builder
	for _, p := range chPages {
		label := DetectPageLabel(p.Text)
		if label != "" {
			fmt.Fprintf(&b, "\n--- Page %s ---\n", label)
		}
		b.WriteString(p.Text)
		b.WriteString("\n")
	}
	return b.String()
}
