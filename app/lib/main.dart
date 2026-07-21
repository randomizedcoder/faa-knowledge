// Copyright (c) 2026 randomizedcoder. All Rights Reserved.
// Proprietary and confidential -- see the LICENSE file in the project root.

import 'package:flutter/material.dart';

import 'data/question_repository.dart';
import 'data/session_store.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = await QuestionRepository.load();
  final theme = await ThemeController.load();
  runApp(FaaQuizApp(repo: repo, store: SessionStore(), theme: theme));
}

class FaaQuizApp extends StatelessWidget {
  final QuestionRepository repo;
  final SessionStore store;
  final ThemeController theme;
  const FaaQuizApp({
    super.key,
    required this.repo,
    required this.store,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: theme,
      builder: (context, mode, _) => MaterialApp(
        title: 'FAA Quiz',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: mode,
        home: HomeScreen(repo: repo, store: store, theme: theme),
      ),
    );
  }
}
