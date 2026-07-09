import 'package:flutter/material.dart';

import '../data/question_repository.dart';
import '../data/session_store.dart';
import '../models/session.dart';
import 'quiz_screen.dart';

/// Pick one or more chapters to focus a saved session on.
class SessionSetupScreen extends StatefulWidget {
  final int slot;
  final QuestionRepository repo;
  final SessionStore store;
  const SessionSetupScreen({
    super.key,
    required this.slot,
    required this.repo,
    required this.store,
  });

  @override
  State<SessionSetupScreen> createState() => _SessionSetupScreenState();
}

class _SessionSetupScreenState extends State<SessionSetupScreen> {
  final Set<String> _selected = {};
  final _nameCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  int get _questionCount => widget.repo
      .chapters()
      .where((c) => _selected.contains(c.key))
      .fold(0, (sum, c) => sum + c.count);

  Future<void> _start() async {
    final chapters = widget.repo.chapters();
    final label = _nameCtrl.text.trim().isNotEmpty
        ? _nameCtrl.text.trim()
        : chapters
            .where((c) => _selected.contains(c.key))
            .map((c) => c.label)
            .join(', ');
    final order = widget.repo.idsForChapters(_selected);
    final session = QuizSession(
      slot: widget.slot,
      name: label,
      chapterKeys: _selected.toList(),
      order: order,
    );
    await widget.store.save(session);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => QuizScreen(
          session: session, repo: widget.repo, store: widget.store),
    ));
  }

  /// Build the chapter rows with a source header inserted before each group.
  List<Widget> _chapterRows(ThemeData theme) {
    final rows = <Widget>[];
    String? lastSource;
    for (final c in widget.repo.chapters()) {
      if (c.source != lastSource) {
        rows.add(_sourceHeader(c.source));
        lastSource = c.source;
      }
      rows.add(CheckboxListTile(
        value: _selected.contains(c.key),
        onChanged: (v) => setState(() {
          if (v == true) {
            _selected.add(c.key);
          } else {
            _selected.remove(c.key);
          }
        }),
        title: Text(c.label, style: theme.textTheme.bodyLarge),
        subtitle: Text('${c.count} questions'),
        controlAffinity: ListTileControlAffinity.leading,
      ));
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text('New Session ${widget.slot + 1}')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: TextField(
                controller: _nameCtrl,
                style: theme.textTheme.bodyLarge,
                decoration: const InputDecoration(
                  labelText: 'Session name (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Choose chapters to focus on:',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ),
            Expanded(child: ListView(children: _chapterRows(theme))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: ElevatedButton(
                onPressed: _selected.isEmpty ? null : _start,
                child: Text(_selected.isEmpty
                    ? 'Select at least one chapter'
                    : 'Start · $_questionCount questions'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sourceHeader(String source) {
    final theme = Theme.of(context);
    final title = source == 'PHAK'
        ? "PHAK — Pilot's Handbook"
        : 'AFH — Airplane Flying Handbook';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(title,
          style: theme.textTheme.titleLarge
              ?.copyWith(color: theme.colorScheme.primary)),
    );
  }
}
