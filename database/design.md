# FAA Knowledge Quiz — Database Design

## Schema Overview

```
sources ──< chapters ──< questions ──< distractors
                            │
                            ├──< question_categories >── categories
                            │
                            └──< user_progress

knowledge_items (optional link from questions)
```

## Tables

### `sources`
Handbooks (PHAK, AFH, etc.)
- `id`, `code` (UNIQUE), `title`, `faa_number`, `url`

### `chapters`
Chapters within a source.
- `id`, `source_id` FK, `number`, `title`, `pdf_url`
- UNIQUE(`source_id`, `number`)

### `categories`
Exam types: `written_exam`, `checkride_oral`, `general_knowledge`.
- `id`, `name` (UNIQUE), `label`

### `knowledge_items`
Ground truth facts extracted from handbooks.
- `id`, `chapter_id` FK, `section`, `fact`, `notes`, `created_at`

### `questions`
Question with correct answer stored inline.
- `id`, `chapter_id` FK, `section`, `difficulty` (1-3), `question_text`, `correct_answer`, `explanation`, `knowledge_id` FK (nullable), `active`, `created_at`

### `distractors`
Wrong answers (typically 3 per question).
- `id`, `question_id` FK, `text`, `sort_hint`

### `question_categories`
Many-to-many join between questions and categories.
- `question_id` FK, `category_id` FK (composite PK)

### `user_progress`
Append-only attempt history (for future Flutter app / spaced repetition).
- `id`, `question_id` FK, `answered_at`, `selected_answer`, `is_correct`, `time_spent_ms`

## Design Decisions

- **Correct answer inline** on `questions` — avoids a join for the most common operation (checking answers).
- **Distractors separate** — supports variable distractor count, easy to extend.
- **Many-to-many categories** — a question can belong to multiple exam types.
- **`user_progress` append-only** — supports spaced repetition analytics later.
- **Pure Go SQLite** (`modernc.org/sqlite`) — no CGO dependency, easier cross-compilation.
