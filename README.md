# faa-knowledge

A Private Pilot License study tool — interactive CLI quiz backed by a SQLite database of FAA knowledge questions sourced from the Pilot's Handbook of Aeronautical Knowledge (PHAK) and the Airplane Flying Handbook (AFH).

106 multiple-choice questions across 13 chapters, with categories for FAA Written Exam, Checkride Oral, and General Knowledge.

## Quick Start

### With Nix (recommended)

```bash
nix develop          # enter dev shell with go, sqlite, curl
nix build            # build the binary
./result/bin/quiz --init
./result/bin/quiz --import database/questions/phak_ch05.json
./result/bin/quiz --count 5
```

### With Go

```bash
go build -o quiz ./cmd/quiz
./quiz --init                    # create database + seed data
```

Import all questions:

```bash
for f in database/questions/*.json; do ./quiz --import "$f"; done
```

Run the quiz:

```bash
./quiz --count 10                # random 10 questions
./quiz --category written_exam   # FAA written exam questions only
./quiz --category checkride_oral --source PHAK --chapter 5
./quiz --difficulty 3            # hardest questions
```

### With Make

```bash
make build
make init-db
make import FILE=database/questions/phak_ch05.json
make run
make download-pdfs               # fetch FAA PDFs into pdfs/
```

## CLI Flags

| Flag | Description |
|---|---|
| `--init` | Create database with schema and seed data |
| `--import FILE` | Import questions from a JSON seed file |
| `--count N` | Limit to N random questions (default: all) |
| `--category` | Filter: `written_exam`, `checkride_oral`, `general_knowledge` |
| `--source` | Filter by source: `PHAK` or `AFH` |
| `--chapter N` | Filter by chapter number |
| `--difficulty N` | Filter by difficulty (1=easy, 2=medium, 3=hard) |
| `--db PATH` | Database file path (default: `faa-knowledge.db`) |

## Question Bank

| Source | Chapters | Questions |
|---|---|---|
| PHAK | Ch.4 Principles of Flight, Ch.5 Aerodynamics, Ch.7 Aircraft Systems, Ch.8 Flight Instruments, Ch.10 Weight & Balance, Ch.12 Weather, Ch.14 Airport Ops, Ch.15 Airspace, Ch.17 Aeromedical | 76 |
| AFH | Ch.3 Basic Maneuvers, Ch.5 Takeoffs, Ch.8 Approaches & Landings, Ch.17 Emergencies | 30 |

## Adding Questions

Create a JSON file in `database/questions/`:

```json
{
  "source": "PHAK",
  "chapter": 5,
  "questions": [
    {
      "section": "Lift and Drag",
      "difficulty": 2,
      "categories": ["written_exam", "checkride_oral"],
      "question": "What happens to lift as angle of attack increases below critical AoA?",
      "correct_answer": "Lift increases",
      "distractors": ["Lift decreases", "Lift stays constant", "Lift oscillates"],
      "explanation": "Below critical AoA, increasing AoA increases pressure differential..."
    }
  ]
}
```

Then import: `./quiz --import database/questions/your_file.json`

## Project Structure

```
cmd/quiz/main.go              CLI entry point
internal/db/                  SQLite open, migrate, queries
internal/models/              Domain structs
internal/quiz/                Session logic + terminal rendering
internal/importer/            JSON seed file importer
database/schema.sql           8-table schema
database/seed.sql             Categories, sources, chapters
database/questions/           JSON question files
scripts/download_pdfs.sh      PDF downloader
```

## Source Material

- [Pilot's Handbook of Aeronautical Knowledge (PHAK)](https://www.faa.gov/regulations_policies/handbooks_manuals/aviation/phak) — FAA-H-8083-25B
- [Airplane Flying Handbook (AFH)](https://www.faa.gov/regulations_policies/handbooks_manuals/aviation/airplane_handbook) — FAA-H-8083-3C
- [FAA Knowledge Test Questions & Answers](https://www.faa.gov/sites/faa.gov/files/training_testing/testing/questions_answers.pdf)
- [FAA Testing Matrix](https://www.faa.gov/sites/faa.gov/files/testing_matrix.pdf)
- [PAR Test Questions](https://www.faa.gov/sites/faa.gov/files/training_testing/testing/test_questions/par_questions.pdf)
- [AvSem Private Pilot Book](https://www.avsem.com/private/pvtbook.pdf)
- [AvSport Test Bank](https://avsport.org/docs/Test_Bank_pvt.pdf)
- [CAP Private Pilot Final](https://fullerton.cap.gov/moduledocuments/embed/3615/Private_Pilot_Final_60_7898663A8F75F.pdf)
