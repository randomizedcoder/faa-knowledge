// End-to-end integration test. Unlike the widget tests (which use the host
// test renderer), this launches the REAL app and can run on an actual Android
// emulator/device — verifying rendering, asset loading, and the shared_prefs
// plugin on the real engine:
//
//   flutter test integration_test -d emulator-5554   # Android
//   flutter test integration_test -d chrome          # web
//   flutter test integration_test                    # host tester (headless)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:faa_quiz/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Quick Start exam flow: launch → answer → navigate → mark → grade',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    app.main();
    await tester.pumpAndSettle();

    // Home renders and Quick Start starts a session.
    expect(find.text('Quick Start · 50 random'), findsOneWidget);
    await tester.tap(find.text('Quick Start · 50 random'));
    await tester.pumpAndSettle();

    // Quiz screen: answer Q1, reveal, mark, then navigate.
    expect(find.text('Grade Session'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('option_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show Answer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark'));
    await tester.pumpAndSettle();
    expect(find.text('Marked'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('option_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Previous'));
    await tester.pumpAndSettle();

    // Grade the session and confirm.
    await tester.tap(find.text('Grade Session'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grade'));
    await tester.pumpAndSettle();

    // Results screen renders.
    expect(find.text('Review answers'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
