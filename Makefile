.PHONY: build run init-db import validate add-refs download-pdfs clean \
       extract-text chunk-text mine-all merge cross-check pipeline check-llms \
       extract-glm verify-glm check-glm gen-chapters-glm gen-chapter quiz app-assets avd emulator \
       run-web run-android integration-test apk run-device

NIX_RUN = nix develop --command
RUNS ?= 5
FORCE ?=
DRY_RUN ?=

# GLM: a single powerful model that does both extraction and verification.
GLM_URL ?= http://localhost:8000
GLM_MODEL ?= /model
GLM_ENV = FAA_LLM_URL=$(GLM_URL) FAA_LLM_MODEL=$(GLM_MODEL) FAA_LLM_THINK=1

build:
	$(NIX_RUN) go build -o quiz ./cmd/quiz

run: build
	$(NIX_RUN) ./quiz

# Play the quiz with arbitrary flags, e.g.:
#   make quiz ARGS="--count 10 --source PHAK --chapter 8"
#   make quiz ARGS="--category written_exam --difficulty 3"
quiz: build
	$(NIX_RUN) ./quiz $(ARGS)

init-db: build
	$(NIX_RUN) ./quiz --init

import: build
	@if [ -z "$(FILE)" ]; then echo "Usage: make import FILE=database/questions/phak_ch05.json"; exit 1; fi
	$(NIX_RUN) ./quiz --import $(FILE)

validate: build
	$(NIX_RUN) ./quiz --validate

validate-file: build
	@if [ -z "$(FILE)" ]; then echo "Usage: make validate-file FILE=database/questions/phak_ch05.json"; exit 1; fi
	$(NIX_RUN) ./quiz --validate --file $(FILE)

validate-fix: build
	$(NIX_RUN) ./quiz --validate --fix

add-refs: build
	$(NIX_RUN) ./quiz --add-refs

add-refs-file: build
	@if [ -z "$(FILE)" ]; then echo "Usage: make add-refs-file FILE=database/questions/phak_ch05.json"; exit 1; fi
	$(NIX_RUN) ./quiz --add-refs --file $(FILE)

check-llms:
	nix run .#check-llms

check-glm:
	$(GLM_ENV) nix run .#check-glm

# Regenerate the Flutter app's bundled question asset from database/questions.
app-assets:
	python3 scripts/build_app_assets.py

# Create the persistent "faa" AVD if it doesn't exist yet (Pixel, API 34,
# x86_64). `make emulator` also auto-creates it on first boot; this is for
# pre-creating without booting. Override the name with AVD_NAME=<name>.
avd:
	nix develop .#flutter --command bash -c '\
	  name=$(or $(AVD_NAME),faa); \
	  if avdmanager list avd -c | grep -qx "$$name"; then \
	    echo "AVD $$name already exists"; \
	  else \
	    echo no | avdmanager create avd -n "$$name" \
	      -k "system-images;android-34;google_apis;x86_64" -d pixel --force; \
	  fi'

# Boot the persistent Android emulator to run the app on (needs KVM + a
# display). Uses the same SDK/adb as `nix develop .#flutter`.
emulator:
	nix run .#emulator

# One-shot: launch the app in Chrome (hot reload).
run-web:
	nix run .#run-web

# One-shot: boot the emulator (if not already running) and launch the app on
# it (hot reload). QT_QPA_PLATFORM=offscreen make run-android boots headless.
run-android:
	nix run .#run-android

# End-to-end integration test on a real engine. DEVICE defaults to the headless
# host tester; pass DEVICE=emulator-5554 (from `make emulator`) for Android, or
# DEVICE=linux for the desktop build.
integration-test:
	nix develop .#flutter --command bash -c 'cd app && flutter test integration_test -d $(or $(DEVICE),flutter-tester)'

# Build a release APK to sideload onto a phone.
apk:
	nix develop .#flutter --command bash -c 'cd app && flutter build apk --release'
	@echo "APK -> app/build/app/outputs/flutter-apk/app-release.apk"

# Install + launch the app on a connected Android device (USB or wireless
# debugging). Pass DEVICE=<id> from `flutter devices` if more than one attached.
run-device:
	nix develop .#flutter --command bash -c 'cd app && flutter run --release $(if $(DEVICE),-d $(DEVICE),)'

# Extract + verify against the GLM model. Pass CHAPTERS=phak:04 to scope.
extract-glm: build
	$(GLM_ENV) nix run .#extract-glm -- $(if $(CHAPTERS),--chapters $(CHAPTERS),)

# Verify-only: run the GLM validate/fix pass over existing questions.
verify-glm: build
	$(GLM_ENV) nix run .#verify-glm

# Whole-chapter generation (Method C) across all chapters -> database/questions.
# Pass CAP=25 to change questions per chapter.
gen-chapters-glm: build
	$(GLM_ENV) nix run .#gen-chapters-glm -- $(if $(CAP),--gen-cap $(CAP),)

# Single-chapter experiment (outline + direct) -> runs/experiment. e.g. SOURCE=PHAK CH=8
gen-chapter: build
	@if [ -z "$(SOURCE)" ] || [ -z "$(CH)" ]; then echo "Usage: make gen-chapter SOURCE=PHAK CH=8 [METHOD=both]"; exit 1; fi
	$(GLM_ENV) ./quiz --gen-chapter --source $(SOURCE) --chapter $(CH) --method $(or $(METHOD),both) $(if $(CAP),--gen-cap $(CAP),)

download-pdfs:
	$(NIX_RUN) bash scripts/download_pdfs.sh

extract-text: build
	$(NIX_RUN) ./quiz --extract-text

chunk-text: build
	$(NIX_RUN) ./quiz --chunk-text

mine-all: build
	@for i in $$(seq 1 $(RUNS)); do \
	  echo "=== Run $$i ===" ; \
	  $(NIX_RUN) ./quiz --mine --generate --run-id $$i --llm-url http://l2:8095 --small-llm-url http://l2:8096 ; \
	done

merge: build
	$(NIX_RUN) ./quiz --merge --runs $(RUNS)

cross-check: build
	$(NIX_RUN) ./quiz --cross-check

pipeline: build
	$(NIX_RUN) ./quiz --pipeline --runs $(RUNS) $(FORCE) $(DRY_RUN)

resume: build
	$(NIX_RUN) ./quiz --pipeline --runs $(RUNS) --skip-extract --skip-chunk $(FORCE) $(DRY_RUN)

clean:
	rm -f quiz faa-knowledge.db
