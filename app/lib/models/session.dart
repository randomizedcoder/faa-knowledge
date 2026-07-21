// Copyright (c) 2026 randomizedcoder. All Rights Reserved.
// Proprietary and confidential -- see the LICENSE file in the project root.

import 'dart:convert';

import '../data/question_repository.dart';

/// An exam-style quiz session: an ordered list of questions the user can move
/// through freely (Previous/Next), answer and re-answer, mark for review, and
/// grade at the end. Saved sessions (slot 0..2) persist so the user resumes
/// exactly where they left off; Quick Start uses slot -1 and is never saved.
class QuizSession {
  final int slot; // 0..2 saved, -1 quick start
  String name;
  final List<String> chapterKeys; // empty for quick start
  final List<int> order; // question ids, shuffled at creation
  int current; // index into order, freely navigable (0..total-1)
  final Map<int, String> answers; // order index -> selected option text
  final Set<int> marked; // order indices flagged for review
  bool graded;

  QuizSession({
    required this.slot,
    required this.name,
    required this.chapterKeys,
    required this.order,
    this.current = 0,
    Map<int, String>? answers,
    Set<int>? marked,
    this.graded = false,
  })  : answers = answers ?? {},
        marked = marked ?? {};

  bool get isQuickStart => slot < 0;
  int get total => order.length;
  int get answered => answers.length;

  /// The global question id at [current].
  int get currentId => order[current];

  bool isAnswered(int index) => answers.containsKey(index);
  bool get isCurrentAnswered => isAnswered(current);
  bool get isCurrentMarked => marked.contains(current);
  String? get currentAnswer => answers[current];

  /// Number of answered questions whose selection matches the correct answer.
  int correctCount(QuestionRepository repo) {
    var n = 0;
    answers.forEach((index, selected) {
      if (repo.byId(order[index]).correctAnswer == selected) n++;
    });
    return n;
  }

  /// Score as a percentage of *answered* questions.
  double percent(QuestionRepository repo) =>
      answered == 0 ? 0 : 100.0 * correctCount(repo) / answered;

  // --- mutators (caller persists via SessionStore) ---
  void select(String option) => answers[current] = option;
  void toggleMark() =>
      marked.contains(current) ? marked.remove(current) : marked.add(current);
  void next() {
    if (current < total - 1) current++;
  }

  void prev() {
    if (current > 0) current--;
  }

  Map<String, dynamic> toJson() => {
        'slot': slot,
        'name': name,
        'chapterKeys': chapterKeys,
        'order': order,
        'current': current,
        // JSON object keys must be strings.
        'answers': answers.map((k, v) => MapEntry(k.toString(), v)),
        'marked': marked.toList(),
        'graded': graded,
      };

  factory QuizSession.fromJson(Map<String, dynamic> j) => QuizSession(
        slot: j['slot'] as int,
        name: j['name'] as String,
        chapterKeys: (j['chapterKeys'] as List).cast<String>(),
        order: (j['order'] as List).cast<int>(),
        current: j['current'] as int,
        answers: (j['answers'] as Map).map(
            (k, v) => MapEntry(int.parse(k as String), v as String)),
        marked: (j['marked'] as List).cast<int>().toSet(),
        graded: j['graded'] as bool,
      );

  String encode() => jsonEncode(toJson());
  static QuizSession decode(String s) =>
      QuizSession.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
