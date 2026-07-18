# faa-knowledge

A Private Pilot License study tool — interactive CLI quiz backed by a SQLite database of FAA knowledge questions sourced from the Pilot's Handbook of Aeronautical Knowledge (PHAK) and the Airplane Flying Handbook (AFH).

106 multiple-choice questions across 13 chapters, with categories for FAA Written Exam, Checkride Oral, and General Knowledge.

## Quick Start

### With Nix (recommended)

```bash
nix develop          # enter dev shell with go, sqlite, curl
nix build            # build the binary
./result/bin/quiz --init     # create DB + import all 635 bundled questions
./result/bin/quiz --count 5
```

### With Go

```bash
go build -o quiz ./cmd/quiz
./quiz --init                # create DB + import all 635 bundled questions
./quiz --count 10
```

### Run the app (web)

Prefer a GUI? Launch the Flutter app in a browser:

```bash
nix develop .#flutter                 # Flutter + Android SDK + Chrome dev shell
cd app
flutter run -d chrome                 # opens the app in Chromium (hot reload)
# headless/remote instead:
flutter run -d web-server --web-port 8080 --web-hostname 0.0.0.0   # open http://localhost:8080
```

See [Mobile / Web App (Flutter)](#mobile--web-app-flutter) for Android/iOS and the emulator.

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

## Knowledge Extraction Pipeline

This project includes an automated pipeline for generating quiz questions
directly from FAA handbook PDFs. See [docs/pipeline.md](docs/pipeline.md)
for the full design.

**Quick overview:** PDFs → text extraction → paragraph chunking → LLM-powered
knowledge mining → question generation → multi-run consensus → cross-validation
→ final validation. The pipeline produces 500+ grounded questions from the
PHAK and AFH handbooks.

The pipeline targets two llama.cpp endpoints (managed by the NixOS configs on hosts `l`/`l2`):
the **large** model — mine/generate/validate — on `http://l2:8095` (MI50 32GB), and the **small**
cross-check model on `http://l2:8096` (W5700 8GB) — all inference stays on host `l2`. Override with
`--llm-url` / `--small-llm-url` or the `FAA_LLM_URL` / `FAA_SMALL_LLM_URL` env vars. Run
`nix run .#check-llms` (or `make check-llms`) to confirm both are reachable before a run.

### Single powerful model (GLM)

When a single, much stronger model is available (e.g. GLM served at `http://localhost:8000`),
use the **extract + verify** target instead of the multi-run consensus pipeline:

```bash
nix run .#extract-glm                 # extract from all chapters, then GLM-verify each question
nix run .#extract-glm -- --chapters phak:04   # scope to one chapter
make extract-glm CHAPTERS=phak:04     # same, via Make
make verify-glm                       # GLM verify/fix pass over existing questions only
make check-glm                        # confirm the GLM endpoint is reachable
```

This does a single generation run (no consensus voting) and then re-checks every generated
question with the same GLM. It runs the model in **reasoning mode** — `chat_template_kwargs.enable_thinking`
is set, `response_format` is dropped, and JSON is parsed out of the reasoned output — which is
slower but higher quality. Configure it with:

| Flag | Env var | Default | Purpose |
|---|---|---|---|
| `--llm-url` | `FAA_LLM_URL` | `http://localhost:8000` (GLM target) | Model endpoint |
| `--llm-model` | `FAA_LLM_MODEL` | `/model` (GLM target) | Served model name |
| `--think` | `FAA_LLM_THINK` | `1` (GLM target) | Enable reasoning mode on every call |

The `--llm-model` / `--think` flags also work with the individual stage commands (`--mine`,
`--generate`, `--cross-check`, `--validate`), so any stage can be pointed at GLM. Defaults for
the plain `quiz` binary keep the l2 behavior unchanged (`model=local`, thinking off).

### Whole-chapter generation (recommended with a large-context model)

The paragraph-by-paragraph miner was designed for small-context models. With GLM's 128K window an
entire chapter (~47K–77K tokens) fits in one request, so the model can find real subject boundaries
and generate better-organised questions. An experiment on **PHAK ch08 (Flight Instruments)**
compared three approaches (see [docs/experiment_ch08.md](docs/experiment_ch08.md)):

| Method | Questions | Distinct sections | Section labels |
|---|---|---|---|
| **A — paragraph** (per-paragraph mine→generate) | 17 | 8 | noisy — figure axis labels like `"30°C 15°C 0°C"`, `"UPTHOUSAND FT PER MIN"` |
| **B — outline→generate** (LLM splits chapter into sections, then per-point generate) | 18 | 8 | clean, real topics |
| **C — whole-chapter→direct** (chapter → finished questions in one call) | 18 | **14** | clean, broadest coverage |

**Method C won** — clean section names, the broadest topical coverage (it reached the gyroscopic
and compass material the others missed), and just one LLM call per chapter (no mining or merge).
It is the production path:

```bash
nix run .#gen-chapters-glm            # Method C over all chapters -> database/questions
make gen-chapters-glm CAP=25          # same, 25 questions/chapter
make gen-chapter SOURCE=PHAK CH=8 METHOD=both   # single-chapter experiment -> runs/experiment
```

`--gen-chapter` flags: `--source`/`--chapter` (which chapter), `--method outline|direct|both`,
`--gen-cap N` (questions per chapter, default 18), `--out-dir` (empty = `runs/experiment`; set to
`database/questions` for production, which the target does automatically). Spurious mis-detected
chapters (PHAK >17, AFH >18) are skipped.

## CLI Flags

| Flag | Description |
|---|---|
| `--init` | Create database, seed data, and import all bundled questions |
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

## Mobile / Web App (Flutter)

`app/` is a Flutter quiz app that mirrors the CLI on **web, Android, and iOS**, with a deliberately
simple, high-contrast, low-vision-friendly UI (large text in a bundled serif face, big buttons,
light/dark toggle). It bundles all 635 questions offline (`app/assets/questions.json`, regenerate with
`make app-assets`).

Features: **Quick Start** (50 random, fresh each time); **3 saved sessions** that let you pick chapters
to focus on and remember exactly where you left off so you can resume later. Exam-style flow — move
freely with **Previous/Next**, **Mark** questions for review, reveal the correct answer + explanation
on demand (**Show Answer**), and **Grade Session** to score `correct/answered (%)` against the 70% FAA
pass line, then page back through with the answers shown.

```bash
nix develop .#flutter        # Flutter + Android SDK + Chrome dev shell
cd app
flutter run -d chrome        # run on the web (hot reload)
# or headless/remote:
flutter run -d web-server --web-port 8080 --web-hostname 0.0.0.0   # open http://localhost:8080
flutter build apk            # Android APK  (build web: flutter build web)
flutter analyze && flutter test
```

### Android emulator

```bash
nix run .#emulator           # boot an Android emulator (Pixel, API 34, x86_64)
# then in the Flutter dev shell:
cd app && flutter run        # runs the app on the booted emulator
```

The emulator pulls a ~1 GB system image on first run and needs **KVM** (`/dev/kvm`). The target sets
`QT_QPA_PLATFORM=xcb` (the bundled emulator's Qt has no Wayland plugin; `xcb` works on most desktops
via XWayland). To boot headless — no window, but `adb`/`flutter` still connect — override it:

```bash
QT_QPA_PLATFORM=offscreen nix run .#emulator
```

### Deploy to a phone (Android)

Install the app on a real device (e.g. a Pixel). The release build is signed with the debug key, so
it installs without setting up a keystore.

1. On the phone: enable **Developer options** (tap Build number 7×), then either **USB debugging**
   (plug in over USB) or **Wireless debugging** (Android 11+; avoids NixOS udev-rule setup).
2. Point `adb` at the phone (in `nix develop .#flutter`):
   ```bash
   adb devices                          # USB: authorise the prompt on the phone
   # or wireless: Settings → Developer → Wireless debugging → Pair with code
   adb pair <phone-ip>:<pair-port>      # enter the 6-digit code
   adb connect <phone-ip>:<debug-port>
   ```
3. Build and install:
   ```bash
   make run-device                      # build + install + launch on the connected device
   # or just build an APK to sideload:
   make apk                             # -> app/build/app/outputs/flutter-apk/app-release.apk
   ```

> **NixOS + USB:** if `adb devices` shows nothing over USB, add `services.udev.packages = [
> pkgs.android-udev-rules ];` to your NixOS config (or use wireless debugging, which needs no udev
> rules).

iOS is code-supported (the `ios/` project is scaffolded) but must be built on macOS with Xcode; the
Nix dev shell covers web + Android on Linux.

### Tests

```bash
cd app
flutter test                                    # unit + widget tests
```

- **Model tests** (`test/quiz_test.dart`) cover session navigation, scoring, and JSON round-trips.
- **Render matrix** (`test/render_matrix_test.dart`) pumps every screen in light + dark at 4 widths
  (320–1400) asserting no layout errors — catches overflow/constraint bugs headlessly. These use the
  host test renderer (layout logic is identical across platforms).

To verify rendering/behaviour on the **real Android engine** (asset loading, plugins, device sizes),
run the end-to-end integration test on an emulator or device:

```bash
nix run .#emulator                              # boot an emulator (needs KVM + display)
make integration-test DEVICE=emulator-5554      # drive the app on Android
make integration-test                           # or headless on the host tester
make integration-test DEVICE=linux              # or the desktop build
```

It launches the real app and drives the full flow (Quick Start → answer → navigate → mark → grade →
results), asserting no exceptions.

## Project Structure

```
app/                          Flutter app (web/android/ios) — lib/{models,data,screens}, theme.dart
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
