import 'package:flutter/material.dart';

import '../data/question_repository.dart';
import '../data/session_store.dart';
import '../models/question.dart';
import '../models/session.dart';
import '../theme.dart';
import 'results_screen.dart';

/// Runs a quiz session: one question at a time, Submit reveals the answer with
/// an explanation, Next advances, Done ends and shows the score.
class QuizScreen extends StatefulWidget {
  final QuizSession session;
  final QuestionRepository repo;
  final SessionStore store;
  const QuizScreen({
    super.key,
    required this.session,
    required this.repo,
    required this.store,
  });

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  String? _selected;
  bool _submitted = false;
  bool _wasCorrect = false;

  QuizSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    if (s.isComplete) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _goResults());
    }
  }

  void _submit() {
    final q = widget.repo.byId(s.currentId!);
    setState(() {
      _submitted = true;
      _wasCorrect = _selected == q.correctAnswer;
    });
  }

  Future<void> _next() async {
    s.record(_wasCorrect); // append result + advance cursor
    await widget.store.save(s);
    if (s.isComplete) {
      _goResults();
    } else {
      setState(() {
        _selected = null;
        _submitted = false;
      });
    }
  }

  Future<void> _done() async {
    if (_submitted) {
      s.record(_wasCorrect); // capture the revealed answer before ending
      await widget.store.save(s);
    }
    _goResults();
  }

  void _goResults() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => ResultsScreen(session: s)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (s.isComplete) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final id = s.currentId!;
    final q = widget.repo.byId(id);
    final options = q.options(id);

    return Scaffold(
      appBar: AppBar(
        title: Text('Q ${s.cursor + 1} / ${s.total}'),
        actions: [
          TextButton(
            onPressed: _done,
            child: Text('Done',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.primary)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            LinearProgressIndicator(
                value: s.total == 0 ? 0 : s.answered / s.total, minHeight: 6),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text('${q.source} Ch.${q.chapter}  •  ${q.section}',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  Text('Difficulty: ${'★' * q.difficulty}${'☆' * (3 - q.difficulty)}',
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  Text(q.question, style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 24),
                  for (final opt in options) _optionTile(opt, q),
                  if (_submitted) _feedback(q),
                ],
              ),
            ),
            _bottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _optionTile(String opt, Question q) {
    final theme = Theme.of(context);
    Color? bg;
    Color border = theme.colorScheme.onSurface.withValues(alpha: 0.4);
    double borderWidth = 1.5;
    Color fg = theme.colorScheme.onSurface;

    if (_submitted) {
      if (opt == q.correctAnswer) {
        bg = answerCorrect.withValues(alpha: 0.18);
        border = answerCorrect;
        borderWidth = 3;
      } else if (opt == _selected) {
        bg = answerWrong.withValues(alpha: 0.18);
        border = answerWrong;
        borderWidth = 3;
      } else {
        fg = fg.withValues(alpha: 0.6);
      }
    } else if (opt == _selected) {
      bg = theme.colorScheme.primary.withValues(alpha: 0.18);
      border = theme.colorScheme.primary;
      borderWidth = 3;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: bg ?? Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _submitted ? null : () => setState(() => _selected = opt),
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: border, width: borderWidth),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(opt,
                style: theme.textTheme.bodyLarge?.copyWith(color: fg)),
          ),
        ),
      ),
    );
  }

  Widget _feedback(Question q) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_wasCorrect ? '✓ Correct' : '✗ Incorrect',
              style: theme.textTheme.titleLarge?.copyWith(
                  color: _wasCorrect ? answerCorrect : answerWrong)),
          const SizedBox(height: 8),
          Text(q.explanation, style: theme.textTheme.bodyMedium),
          if (!_wasCorrect && q.referenceText.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Reference: ${q.source} Ch.${q.chapter}, p.${q.referencePage}',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            Text(q.referenceText,
                style: theme.textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.8))),
          ],
        ],
      ),
    );
  }

  Widget _bottomBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: _submitted
          ? ElevatedButton(onPressed: _next, child: const Text('Next'))
          : ElevatedButton(
              onPressed: _selected == null ? null : _submit,
              child: const Text('Submit'),
            ),
    );
  }
}
