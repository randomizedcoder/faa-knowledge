import 'package:flutter_test/flutter_test.dart';
import 'package:faa_quiz/models/question.dart';
import 'package:faa_quiz/models/session.dart';

const _sampleJson = {
  'source': 'PHAK',
  'chapter': 8,
  'section': 'Altimeter',
  'difficulty': 2,
  'categories': ['written_exam'],
  'question': 'What does an altimeter measure?',
  'correct_answer': 'Altitude',
  'distractors': ['Airspeed', 'Heading', 'Vertical speed'],
  'explanation': 'An altimeter measures altitude via static pressure.',
  'reference_page': '8-3',
  'reference_text': 'The altimeter is a static pressure instrument.',
};

void main() {
  group('Question', () {
    test('parses all fields', () {
      final q = Question.fromJson(Map<String, dynamic>.from(_sampleJson));
      expect(q.source, 'PHAK');
      expect(q.chapter, 8);
      expect(q.chapterKey, 'PHAK-8');
      expect(q.difficulty, 2);
      expect(q.distractors.length, 3);
      expect(q.correctAnswer, 'Altitude');
    });

    test('options returns 4 items including the correct answer, stable per seed',
        () {
      final q = Question.fromJson(Map<String, dynamic>.from(_sampleJson));
      final a = q.options(42);
      final b = q.options(42);
      expect(a.length, 4);
      expect(a.contains('Altitude'), isTrue);
      expect(a, b); // deterministic for the same seed
    });
  });

  group('QuizSession', () {
    test('records answers, advances, and scores', () {
      final s = QuizSession(
        slot: 0,
        name: 'test',
        chapterKeys: const ['PHAK-8'],
        order: [10, 11, 12, 13],
      );
      expect(s.total, 4);
      expect(s.isComplete, isFalse);
      expect(s.currentId, 10);

      s.record(true);
      s.record(false);
      expect(s.answered, 2);
      expect(s.correct, 1);
      expect(s.percent, 50.0);
      expect(s.currentId, 12);

      s.record(true);
      s.record(true);
      expect(s.isComplete, isTrue);
      expect(s.currentId, isNull);
      expect(s.correct, 3);
    });

    test('json round-trip preserves progress', () {
      final s = QuizSession(
        slot: 1,
        name: 'resume me',
        chapterKeys: const ['AFH-3'],
        order: [1, 2, 3],
      )..record(true);

      final restored = QuizSession.decode(s.encode());
      expect(restored.slot, 1);
      expect(restored.name, 'resume me');
      expect(restored.cursor, 1);
      expect(restored.answered, 1);
      expect(restored.correct, 1);
      expect(restored.currentId, 2);
    });
  });
}
