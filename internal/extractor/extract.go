// Copyright (c) 2026 randomizedcoder. All Rights Reserved.
// Proprietary and confidential -- see the LICENSE file in the project root.

package extractor

import (
	"fmt"
	"os/exec"
	"strings"
)

// Page represents a single page from a PDF.
type Page struct {
	Number int
	Text   string
}

// ExtractPDF runs pdftotext and returns the full text of a PDF.
func ExtractPDF(pdfPath string) (string, error) {
	out, err := exec.Command("pdftotext", "-layout", pdfPath, "-").Output()
	if err != nil {
		return "", fmt.Errorf("pdftotext %s: %w", pdfPath, err)
	}
	return string(out), nil
}

// ExtractPages runs pdftotext and splits output into pages using form-feed characters.
func ExtractPages(pdfPath string) ([]Page, error) {
	text, err := ExtractPDF(pdfPath)
	if err != nil {
		return nil, err
	}

	raw := strings.Split(text, "\f")
	var pages []Page
	for i, p := range raw {
		trimmed := strings.TrimSpace(p)
		if trimmed == "" {
			continue
		}
		pages = append(pages, Page{
			Number: i + 1, // 1-indexed physical page
			Text:   trimmed,
		})
	}
	return pages, nil
}
