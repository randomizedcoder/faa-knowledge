#!/usr/bin/env python3
"""Dump every question in database/questions/ to a readable markdown doc.

Usage: python3 scripts/dump_questions.py > docs/all_questions.md
"""
import glob
import json
import os
import re

SRC_TITLE = {"phak": "PHAK — Pilot's Handbook of Aeronautical Knowledge",
             "afh": "AFH — Airplane Flying Handbook"}


def key(path):
    m = re.search(r"(phak|afh)_ch(\d+)", os.path.basename(path))
    return (m.group(1), int(m.group(2))) if m else ("zz", 0)


def main():
    files = sorted(glob.glob("database/questions/*.json"), key=key)
    total = 0
    per_src = {}
    for f in files:
        per_src.setdefault(key(f)[0], 0)
    # header/table of contents
    print("# FAA Knowledge — All Questions\n")
    counts = {}
    for f in files:
        qs = json.load(open(f)).get("questions", [])
        counts[f] = len(qs)
        total += len(qs)
        per_src[key(f)[0]] += len(qs)
    print(f"**{total} questions** across {len(files)} chapters "
          f"(" + ", ".join(f"{SRC_TITLE[s].split(' — ')[0]}: {n}" for s, n in per_src.items()) + ")\n")

    last_src = None
    for f in files:
        src, ch = key(f)
        if src != last_src:
            print(f"\n---\n\n# {SRC_TITLE.get(src, src.upper())}\n")
            last_src = src
        data = json.load(open(f))
        print(f"\n## Chapter {ch} — {counts[f]} questions\n")
        for i, q in enumerate(data.get("questions", []), 1):
            ref = q.get("reference") or {}
            page = ref.get("page", "")
            tag = f"{q.get('section','?')}"
            if page:
                tag += f", p.{page}"
            tag += f", difficulty {q.get('difficulty','?')}"
            print(f"**{ch}.{i} [{tag}]**  \n{q.get('question','')}\n")
            print(f"- ✅ **{q.get('correct_answer','')}**")
            for d in q.get("distractors", []):
                print(f"- {d}")
            if q.get("explanation"):
                print(f"\n  > {q['explanation']}")
            print()


if __name__ == "__main__":
    main()
