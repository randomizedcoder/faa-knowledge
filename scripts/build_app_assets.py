#!/usr/bin/env python3
"""Flatten database/questions/*.json into a single ordered asset for the Flutter app.

Usage: python3 scripts/build_app_assets.py

Writes app/assets/questions.json — a flat array of question objects in a stable
order (PHAK ch1..17, then AFH ch1..18). The array index is the stable question
id that saved sessions persist, so the order must never change arbitrarily.
"""
import glob
import json
import os
import re

OUT = "app/assets/questions.json"
SRC_ORDER = {"phak": 0, "afh": 1}


def sort_key(path):
    m = re.search(r"(phak|afh)_ch(\d+)", os.path.basename(path))
    if not m:
        return (9, 999)
    return (SRC_ORDER.get(m.group(1), 9), int(m.group(2)))


def main():
    files = sorted(glob.glob("database/questions/*.json"), key=sort_key)
    out = []
    for f in files:
        data = json.load(open(f))
        src = data["source"]
        ch = data["chapter"]
        for q in data["questions"]:
            ref = q.get("reference") or {}
            out.append({
                "source": src,
                "chapter": ch,
                "section": q.get("section", ""),
                "difficulty": q.get("difficulty", 1),
                "categories": q.get("categories", []),
                "question": q["question"],
                "correct_answer": q["correct_answer"],
                "distractors": q["distractors"],
                "explanation": q.get("explanation", ""),
                "reference_page": ref.get("page", ""),
                "reference_text": ref.get("text", ""),
            })

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as fh:
        json.dump(out, fh, ensure_ascii=False, indent=0)
        fh.write("\n")
    print(f"Wrote {OUT}: {len(out)} questions from {len(files)} files")


if __name__ == "__main__":
    main()
