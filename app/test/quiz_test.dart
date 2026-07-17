import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:faa_quiz/data/question_repository.dart';
import 'package:faa_quiz/data/session_store.dart';
import 'package:faa_quiz/models/question.dart';
import 'package:faa_quiz/models/session.dart';
import 'package:faa_quiz/screens/quiz_screen.dart';
import 'package:faa_quiz/theme.dart';

Question _q(String correct) => Question(
      source: 'PHAK',
      chapter: 8,
      section: 'Test',
      difficulty: 2,
      categories: const ['written_exam'],
      question: 'Q?',
      correctAnswer: correct,
      distractors: const ['x', 'y', 'z'],
      explanation: 'because',
      referencePage: '8-1',
      referenceText: 'ref',
    );

void main() {
  // ids 0..3, correct answers A/B/C/D
  final repo = QuestionRepository([_q('A'), _q('B'), _q('C'), _q('D')]);

  QuizSession newSession() => QuizSession(
        slot: 0,
        name: 'test',
        chapterKeys: const ['PHAK-8'],
        order: [0, 1, 2, 3],
      );

  group('Question', () {
    test('options are 4, include the answer, stable per seed', () {
      final q = _q('A');
      final a = q.options(42);
      expect(a.length, 4);
      expect(a.contains('A'), isTrue);
      expect(a, q.options(42));
    });
  });

  group('QuizSession navigation', () {
    test('prev/next clamp at bounds', () {
      final s = newSession();
      expect(s.current, 0);
      s.prev();
      expect(s.current, 0); // clamped
      s.next();
      s.next();
      expect(s.current, 2);
      s.next();
      s.next();
      s.next();
      expect(s.current, 3); // clamped at last
    });

    test('select stores and overwrites the answer at current', () {
      final s = newSession();
      s.select('A');
      expect(s.currentAnswer, 'A');
      s.select('x'); // change it
      expect(s.currentAnswer, 'x');
      expect(s.answered, 1);
    });

    test('toggleMark flags/unflags current', () {
      final s = newSession();
      expect(s.isCurrentMarked, isFalse);
      s.toggleMark();
      expect(s.isCurrentMarked, isTrue);
      expect(s.marked, {0});
      s.toggleMark();
      expect(s.isCurrentMarked, isFalse);
    });
  });

  group('QuizSession grading', () {
    test('correctCount and percent score only answered questions', () {
      final s = newSession();
      s.select('A'); // q0 correct
      s.next();
      s.select('wrong'); // q1 incorrect
      s.next();
      s.select('C'); // q2 correct
      // q3 left unanswered
      expect(s.answered, 3);
      expect(s.correctCount(repo), 2);
      expect(s.percent(repo), closeTo(66.67, 0.1));
    });

    test('empty session scores 0 without dividing by zero', () {
      final s = newSession();
      expect(s.percent(repo), 0);
    });
  });

  test('json round-trip preserves current/answers/marked/graded', () {
    final s = newSession()
      ..select('A')
      ..next()
      ..select('B')
      ..toggleMark()
      ..graded = true;

    final r = QuizSession.decode(s.encode());
    expect(r.current, 1);
    expect(r.answers, {0: 'A', 1: 'B'});
    expect(r.marked, {1});
    expect(r.graded, isTrue);
    expect(r.correctCount(repo), 2);
  });

  testWidgets('QuizScreen renders without layout errors (AppBar button bounded)',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: QuizScreen(session: newSession(), repo: repo, store: SessionStore()),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('Grade Session'), findsOneWidget);
  });
}
