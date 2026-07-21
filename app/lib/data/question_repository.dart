// Copyright (c) 2026 randomizedcoder. All Rights Reserved.
// Proprietary and confidential -- see the LICENSE file in the project root.

import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;

import '../models/question.dart';

/// One chapter's summary for the session-setup picker.
class ChapterInfo {
  final String key; // "PHAK-8"
  final String source;
  final int chapter;
  final int count;
  const ChapterInfo(this.key, this.source, this.chapter, this.count);

  String get label => '$source Ch.$chapter';
}

/// Loads the bundled questions once and provides lookups/filters.
class QuestionRepository {
  final List<Question> all;
  QuestionRepository(this.all);

  static Future<QuestionRepository> load() async {
    final raw = await rootBundle.loadString('assets/questions.json');
    final list = (jsonDecode(raw) as List)
        .map((e) => Question.fromJson(e as Map<String, dynamic>))
        .toList();
    return QuestionRepository(list);
  }

  Question byId(int id) => all[id];

  /// Chapters in asset order, each with a question count.
  List<ChapterInfo> chapters() {
    final order = <String>[];
    final counts = <String, int>{};
    for (final q in all) {
      final k = q.chapterKey;
      if (!counts.containsKey(k)) order.add(k);
      counts[k] = (counts[k] ?? 0) + 1;
    }
    return [
      for (final k in order)
        ChapterInfo(k, k.split('-')[0], int.parse(k.split('-')[1]), counts[k]!)
    ];
  }

  /// Question ids belonging to any of the given chapter keys, shuffled.
  List<int> idsForChapters(Set<String> keys, {int? seed}) {
    final ids = <int>[
      for (var i = 0; i < all.length; i++)
        if (keys.contains(all[i].chapterKey)) i
    ];
    ids.shuffle(seed == null ? Random() : Random(seed));
    return ids;
  }

  /// n random question ids across the whole bank.
  List<int> randomIds(int n, {int? seed}) {
    final ids = List<int>.generate(all.length, (i) => i);
    ids.shuffle(seed == null ? Random() : Random(seed));
    return ids.take(n).toList();
  }
}
