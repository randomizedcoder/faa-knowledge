#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PDF_DIR="$PROJECT_DIR/pdfs"

download() {
  local url="$1"
  local dest="$2"

  if [[ -f "$dest" ]]; then
    echo "  SKIP  $(basename "$dest") (already exists)"
    return
  fi

  echo "  FETCH $(basename "$dest")"
  mkdir -p "$(dirname "$dest")"
  curl --fail --location --continue-at - --silent --show-error -o "$dest" "$url"
}

echo "=== FAA Test Materials ==="
download "https://www.faa.gov/sites/faa.gov/files/training_testing/testing/questions_answers.pdf" \
  "$PDF_DIR/faa_test/questions_answers.pdf"
download "https://www.faa.gov/sites/faa.gov/files/testing_matrix.pdf" \
  "$PDF_DIR/faa_test/testing_matrix.pdf"
download "https://www.faa.gov/sites/faa.gov/files/training_testing/testing/test_questions/par_questions.pdf" \
  "$PDF_DIR/faa_test/par_questions.pdf"

echo ""
echo "=== External Study Materials ==="
download "https://www.avsem.com/private/pvtbook.pdf" \
  "$PDF_DIR/external/avsem_pvtbook.pdf"
download "https://avsport.org/docs/Test_Bank_pvt.pdf" \
  "$PDF_DIR/external/avsport_test_bank.pdf"
download "https://fullerton.cap.gov/moduledocuments/embed/3615/Private_Pilot_Final_60_7898663A8F75F.pdf" \
  "$PDF_DIR/external/cap_private_pilot_final.pdf"

echo ""
echo "=== PHAK & AFH (large, optional) ==="
echo "  To download the full handbooks (~260MB each), run:"
echo "    curl -L -o pdfs/phak.pdf 'https://www.faa.gov/sites/faa.gov/files/2022-03/pilot_handbook.pdf'"
echo "    curl -L -o pdfs/afh.pdf 'https://www.faa.gov/sites/faa.gov/files/2024-03/airplane_flying_handbook.pdf'"

echo ""
echo "Done."
