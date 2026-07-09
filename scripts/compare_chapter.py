#!/usr/bin/env python3
"""Side-by-side comparison of question-generation methods for one chapter.

Usage: python3 scripts/compare_chapter.py PHAK 8 > docs/experiment_ch08.md

Compares three JSON question sets:
  A paragraph : database/questions/{src}_ch{NN}.json      (existing baseline)
  B outline   : runs/experiment/{src}_ch{NN}_outline.json (chapter -> sections -> questions)
  C direct    : runs/experiment/{src}_ch{NN}_direct.json  (whole chapter -> questions)
"""
import json
import sys
from difflib import SequenceMatcher


def load(path):
    try:
        with open(path) as f:
            return json.load(f).get("questions", [])
    except FileNotFoundError:
        return None


def norm(s):
    return " ".join(s.lower().split())


def dup_pairs(qs, thresh=0.85):
    n = 0
    texts = [norm(q.get("question", "")) for q in qs]
    for i in range(len(texts)):
        for j in range(i + 1, len(texts)):
            if SequenceMatcher(None, texts[i], texts[j]).ratio() > thresh:
                n += 1
    return n


def sections(qs):
    seen = []
    for q in qs:
        s = (q.get("section") or "").strip()
        if s and s not in seen:
            seen.append(s)
    return seen


def render(name, qs):
    print(f"\n## {name} — {len(qs)} questions\n")
    print(f"Distinct sections ({len(sections(qs))}): " + ", ".join(sections(qs)) + "\n")
    for i, q in enumerate(qs, 1):
        ref = q.get("reference") or {}
        page = ref.get("page", "")
        print(f"**{i}. [{q.get('section','?')}{' p.'+page if page else ''}, d{q.get('difficulty','?')}]** {q.get('question','')}")
        print(f"- ✅ {q.get('correct_answer','')}")
        for d in q.get("distractors", []):
            print(f"- ❌ {d}")
        print(f"- _{q.get('explanation','')}_\n")


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: compare_chapter.py SOURCE CHAPTER")
    src, ch = sys.argv[1], int(sys.argv[2])
    lo, nn = src.lower(), f"{ch:02d}"
    sets = {
        "A · paragraph (baseline)": load(f"database/questions/{lo}_ch{nn}.json"),
        "B · outline→generate": load(f"runs/experiment/{lo}_ch{nn}_outline.json"),
        "C · whole-chapter→direct": load(f"runs/experiment/{lo}_ch{nn}_direct.json"),
    }

    print(f"# Chapter-level experiment — {src} ch{ch}\n")
    print("| Method | Questions | Distinct sections | Near-dup pairs (>0.85) |")
    print("|---|---|---|---|")
    for name, qs in sets.items():
        if qs is None:
            print(f"| {name} | _missing_ | | |")
        else:
            print(f"| {name} | {len(qs)} | {len(sections(qs))} | {dup_pairs(qs)} |")

    for name, qs in sets.items():
        if qs is not None:
            render(name, qs)


if __name__ == "__main__":
    main()
