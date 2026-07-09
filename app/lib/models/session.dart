import 'dart:convert';

/// Result of answering one question.
class AnswerResult {
  final int id; // global question id (index into the asset)
  final bool correct;
  const AnswerResult(this.id, this.correct);

  Map<String, dynamic> toJson() => {'id': id, 'correct': correct};
  factory AnswerResult.fromJson(Map<String, dynamic> j) =>
      AnswerResult(j['id'] as int, j['correct'] as bool);
}

/// A quiz session: an ordered list of question ids plus progress. Saved
/// sessions (slot 0..2) persist so the user can resume; Quick Start uses
/// slot -1 and is never saved.
class QuizSession {
  final int slot; // 0..2 saved, -1 quick start
  String name;
  final List<String> chapterKeys; // empty for quick start
  final List<int> order; // question ids in play order
  int cursor; // index into order of the next unanswered question
  final List<AnswerResult> results;

  QuizSession({
    required this.slot,
    required this.name,
    required this.chapterKeys,
    required this.order,
    this.cursor = 0,
    List<AnswerResult>? results,
  }) : results = results ?? [];

  bool get isQuickStart => slot < 0;
  int get total => order.length;
  int get answered => results.length;
  int get correct => results.where((r) => r.correct).length;
  bool get isComplete => cursor >= order.length;
  double get percent => answered == 0 ? 0 : 100.0 * correct / answered;

  /// The global id of the current (next unanswered) question, or null if done.
  int? get currentId => isComplete ? null : order[cursor];

  void record(bool wasCorrect) {
    results.add(AnswerResult(order[cursor], wasCorrect));
    cursor++;
  }

  Map<String, dynamic> toJson() => {
        'slot': slot,
        'name': name,
        'chapterKeys': chapterKeys,
        'order': order,
        'cursor': cursor,
        'results': results.map((r) => r.toJson()).toList(),
      };

  factory QuizSession.fromJson(Map<String, dynamic> j) => QuizSession(
        slot: j['slot'] as int,
        name: j['name'] as String,
        chapterKeys: (j['chapterKeys'] as List).cast<String>(),
        order: (j['order'] as List).cast<int>(),
        cursor: j['cursor'] as int,
        results: (j['results'] as List)
            .map((e) => AnswerResult.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  String encode() => jsonEncode(toJson());
  static QuizSession decode(String s) =>
      QuizSession.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
