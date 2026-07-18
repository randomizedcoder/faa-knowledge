// Table-driven render matrix: pump every screen in both themes at several
// screen sizes and assert no layout exception. This catches layout bugs like
// the AppBar infinite-width crash — including RenderFlex overflows on narrow
// phones, which matter for the large-font accessibility target.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:faa_quiz/data/question_repository.dart';
import 'package:faa_quiz/data/session_store.dart';
import 'package:faa_quiz/models/question.dart';
import 'package:faa_quiz/models/session.dart';
import 'package:faa_quiz/screens/home_screen.dart';
import 'package:faa_quiz/screens/quiz_screen.dart';
import 'package:faa_quiz/screens/results_screen.dart';
import 'package:faa_quiz/screens/session_setup_screen.dart';
import 'package:faa_quiz/theme.dart';

const _longQuestion =
    'The most effective method of scanning for other aircraft for collision '
    'avoidance during daylight hours is to use which of the following '
    'techniques recommended in the handbook for a thorough visual scan?';

Question _q(String source, int chapter, String correct, {String? question}) =>
    Question(
      source: source,
      chapter: chapter,
      section: 'Blockage of the Pitot-Static System',
      difficulty: 2,
      categories: const ['written_exam', 'checkride_oral'],
      question: question ?? 'What does this instrument measure?',
      correctAnswer: correct,
      distractors: const [
        'A plausible but incorrect first distractor',
        'Another plausible but incorrect option',
        'A third clearly-wrong-but-tempting choice',
      ],
      explanation:
          'A reasonably long explanation that references the source material '
          'and wraps across several lines on a narrow phone screen.',
      referencePage: '$chapter-3',
      referenceText: 'Quoted reference text from the FAA handbook chapter.',
    );

QuestionRepository _repo() => QuestionRepository([
      _q('PHAK', 8, 'The correct answer, which can be a fairly long sentence.',
          question: _longQuestion),
      _q('PHAK', 8, 'Correct B'),
      _q('PHAK', 5, 'Correct C'),
      _q('AFH', 3, 'Correct D'),
      _q('AFH', 3, 'Correct E'),
    ]);

QuizSession _fresh() => QuizSession(
      slot: 0,
      name: 'A saved session with a deliberately long name to test truncation',
      chapterKeys: const ['PHAK-8'],
      order: [0, 1, 2, 3, 4],
    );

QuizSession _graded() => _fresh()
  ..select('The correct answer, which can be a fairly long sentence.')
  ..next()
  ..select('wrong')
  ..graded = true;

void main() {
  final repo = _repo();

  final screens = <String, Widget Function()>{
    'Home': () => HomeScreen(
        repo: repo, store: SessionStore(), theme: ThemeController(ThemeMode.light)),
    'SessionSetup': () =>
        SessionSetupScreen(slot: 0, repo: repo, store: SessionStore()),
    'Quiz-fresh': () =>
        QuizScreen(session: _fresh(), repo: repo, store: SessionStore()),
    'Quiz-review': () =>
        QuizScreen(session: _graded(), repo: repo, store: SessionStore()),
    'Results': () => ResultsScreen(session: _graded(), repo: repo),
  };

  const sizes = <String, Size>{
    'narrow-320': Size(320, 640),
    'phone-400': Size(400, 800),
    'tablet-800': Size(800, 1200),
    'wide-1400': Size(1400, 900),
  };

  for (final screen in screens.entries) {
    for (final brightness in Brightness.values) {
      for (final size in sizes.entries) {
        testWidgets(
            '${screen.key} · ${brightness.name} · ${size.key} renders without layout errors',
            (tester) async {
          SharedPreferences.setMockInitialValues({});
          tester.view.physicalSize = size.value;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(MaterialApp(
            theme: buildTheme(brightness),
            home: screen.value(),
          ));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull,
              reason: '${screen.key} threw at ${size.key} (${brightness.name})');
        });
      }
    }
  }
}
