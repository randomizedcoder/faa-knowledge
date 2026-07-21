// Copyright (c) 2026 randomizedcoder. All Rights Reserved.
// Proprietary and confidential -- see the LICENSE file in the project root.

import 'package:flutter/material.dart';

import '../data/question_repository.dart';
import '../data/session_store.dart';
import '../models/session.dart';
import '../theme.dart';
import 'quiz_screen.dart';
import 'session_setup_screen.dart';

class HomeScreen extends StatefulWidget {
  final QuestionRepository repo;
  final SessionStore store;
  final ThemeController theme;
  const HomeScreen({
    super.key,
    required this.repo,
    required this.store,
    required this.theme,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<QuizSession?> _sessions = List.filled(SessionStore.slots, null);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final s = await widget.store.loadAll();
    if (mounted) setState(() => _sessions = s);
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen));
    _reload(); // refresh progress after returning
  }

  void _quickStart() {
    final session = QuizSession(
      slot: -1,
      name: 'Quick Start',
      chapterKeys: const [],
      order: widget.repo.randomIds(50),
    );
    _open(QuizScreen(
        session: session, repo: widget.repo, store: widget.store));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('FAA Quiz'),
        actions: [
          IconButton(
            tooltip: isDark ? 'Light mode' : 'Dark mode',
            iconSize: 30,
            icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () => widget.theme.toggle(theme.brightness),
          ),
        ],
      ),
      body: SafeArea(
        // Divide the screen into segments that share the available height so
        // everything fits without scrolling on any device. Each segment scales
        // its content to fit its box (FittedBox), so the effective font size
        // follows the segment size. MaxWidth keeps it from stretching on
        // tablets.
        child: MaxWidth(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: _quickStartButton()),
                const SizedBox(height: 12),
                Expanded(flex: 2, child: _savedHeader(theme)),
                const SizedBox(height: 12),
                for (var i = 0; i < SessionStore.slots; i++) ...[
                  Expanded(flex: 3, child: _sessionCard(i, _sessions[i])),
                  if (i < SessionStore.slots - 1) const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Hero action; fills its segment, label scales to fit.
  Widget _quickStartButton() => ElevatedButton(
        onPressed: _quickStart,
        child: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bolt, size: 28),
              SizedBox(width: 10),
              Text('Quick Start · 50 random'),
            ],
          ),
        ),
      );

  Widget _savedHeader(ThemeData theme) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Saved sessions', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Pick chapters, do a few questions, resume anytime.',
                style: theme.textTheme.bodyMedium),
          ],
        ),
      );

  Widget _sessionCard(int slot, QuizSession? session) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child:
            session == null ? _emptyRow(slot) : _filledRow(slot, session),
      ),
    );
  }

  // Compact single-row layouts so a card fits a short segment: text on the
  // left (scaled to fit), action button(s) on the right.
  Widget _emptyRow(int slot) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text('Session ${slot + 1} — empty',
                style: theme.textTheme.bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(width: 10),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 48),
              maximumSize: const Size(150, double.infinity)),
          onPressed: () => _open(SessionSetupScreen(
              slot: slot, repo: widget.repo, store: widget.store)),
          child: const FittedBox(
              fit: BoxFit.scaleDown, child: Text('New Session')),
        ),
      ],
    );
  }

  Widget _filledRow(int slot, QuizSession session) {
    final theme = Theme.of(context);
    final pct = session.percent(widget.repo).toStringAsFixed(0);
    final markedCount = session.marked.length;
    return Row(
      children: [
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(session.name,
                    maxLines: 1,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  session.graded
                      ? 'Graded · ${session.correctCount(widget.repo)}/${session.answered} ($pct%)'
                      : 'Answered ${session.answered}/${session.total}'
                          '${markedCount > 0 ? ' · $markedCount marked' : ''}',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 48),
              maximumSize: const Size(150, double.infinity)),
          onPressed: () => _open(QuizScreen(
              session: session, repo: widget.repo, store: widget.store)),
          child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(session.graded ? 'Review' : 'Continue')),
        ),
        IconButton(
          tooltip: 'Delete session',
          iconSize: 28,
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            await widget.store.clear(slot);
            _reload();
          },
        ),
      ],
    );
  }
}
