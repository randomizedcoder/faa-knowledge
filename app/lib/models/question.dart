// Copyright (c) 2026 randomizedcoder. All Rights Reserved.
// Proprietary and confidential -- see the LICENSE file in the project root.

import 'dart:math';

/// A single multiple-choice question loaded from assets/questions.json.
class Question {
  final String source; // "PHAK" | "AFH"
  final int chapter;
  final String section;
  final int difficulty; // 1..3
  final List<String> categories;
  final String question;
  final String correctAnswer;
  final List<String> distractors; // exactly 3
  final String explanation;
  final String referencePage;
  final String referenceText;

  const Question({
    required this.source,
    required this.chapter,
    required this.section,
    required this.difficulty,
    required this.categories,
    required this.question,
    required this.correctAnswer,
    required this.distractors,
    required this.explanation,
    required this.referencePage,
    required this.referenceText,
  });

  factory Question.fromJson(Map<String, dynamic> j) => Question(
        source: j['source'] as String,
        chapter: j['chapter'] as int,
        section: (j['section'] as String?) ?? '',
        difficulty: (j['difficulty'] as int?) ?? 1,
        categories:
            ((j['categories'] as List?) ?? const []).cast<String>(),
        question: j['question'] as String,
        correctAnswer: j['correct_answer'] as String,
        distractors: (j['distractors'] as List).cast<String>(),
        explanation: (j['explanation'] as String?) ?? '',
        referencePage: (j['reference_page'] as String?) ?? '',
        referenceText: (j['reference_text'] as String?) ?? '',
      );

  /// Stable "PHAK-8" style key used to group by chapter.
  String get chapterKey => '$source-$chapter';

  /// The 4 answer options shuffled deterministically by [seed] so the order is
  /// stable across widget rebuilds for the same question.
  List<String> options(int seed) {
    final opts = <String>[correctAnswer, ...distractors];
    opts.shuffle(Random(seed));
    return opts;
  }
}
