.PHONY: build run init-db import download-pdfs clean

build:
	go build -o quiz ./cmd/quiz

run: build
	./quiz

init-db: build
	./quiz --init

import: build
	@if [ -z "$(FILE)" ]; then echo "Usage: make import FILE=database/questions/phak_ch05.json"; exit 1; fi
	./quiz --import $(FILE)

download-pdfs:
	bash scripts/download_pdfs.sh

clean:
	rm -f quiz faa-knowledge.db
