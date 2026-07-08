.PHONY: build run init-db import validate add-refs download-pdfs clean \
       extract-text chunk-text mine-all merge cross-check pipeline check-llms \
       extract-glm verify-glm check-glm

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

# Extract + verify against the GLM model. Pass CHAPTERS=phak:04 to scope.
extract-glm: build
	$(GLM_ENV) nix run .#extract-glm -- $(if $(CHAPTERS),--chapters $(CHAPTERS),)

# Verify-only: run the GLM validate/fix pass over existing questions.
verify-glm: build
	$(GLM_ENV) nix run .#verify-glm

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
