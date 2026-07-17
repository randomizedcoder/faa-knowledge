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
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ElevatedButton.icon(
              onPressed: _quickStart,
              icon: const Icon(Icons.bolt, size: 28),
              label: const Text('Quick Start · 50 random'),
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(80)),
            ),
            const SizedBox(height: 28),
            Text('Saved sessions',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Pick chapters, do a few questions, resume anytime.',
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            for (var i = 0; i < SessionStore.slots; i++)
              _sessionCard(i, _sessions[i]),
          ],
        ),
      ),
    );
  }

  Widget _sessionCard(int slot, QuizSession? session) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: session == null
            ? _emptyCard(slot)
            : _filledCard(slot, session),
      ),
    );
  }

  Widget _emptyCard(int slot) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Session ${slot + 1} — empty',
            style: theme.textTheme.bodyLarge
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: () => _open(SessionSetupScreen(
              slot: slot, repo: widget.repo, store: widget.store)),
          child: const Text('New Session'),
        ),
      ],
    );
  }

  Widget _filledCard(int slot, QuizSession session) {
    final theme = Theme.of(context);
    final pct = session.percent(widget.repo).toStringAsFixed(0);
    final markedCount = session.marked.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(session.name,
            style: theme.textTheme.bodyLarge
                ?.copyWith(fontWeight: FontWeight.w800),
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 6),
        Text(
          session.graded
              ? 'Graded · ${session.correctCount(widget.repo)}/${session.answered} ($pct%)'
              : 'Answered ${session.answered}/${session.total}'
                  '${markedCount > 0 ? ' · $markedCount marked' : ''}',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () => _open(QuizScreen(
                    session: session,
                    repo: widget.repo,
                    store: widget.store)),
                child: Text(session.graded ? 'Review' : 'Continue'),
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              tooltip: 'Delete session',
              iconSize: 30,
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await widget.store.clear(slot);
                _reload();
              },
            ),
          ],
        ),
      ],
    );
  }
}
