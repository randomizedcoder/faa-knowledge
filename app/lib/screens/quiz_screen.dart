import 'package:flutter/material.dart';

import '../data/question_repository.dart';
import '../data/session_store.dart';
import '../models/question.dart';
import '../models/session.dart';
import '../theme.dart';
import 'results_screen.dart';

/// Exam-style quiz: move freely with Previous/Next, answer/re-answer, Mark for
/// review, reveal the correct answer on demand, and Grade Session at the end.
/// After grading the same screen becomes a read-only review (answers shown).
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
  // Whether the correct answer is revealed for the current question. Always
  // revealed once the session is graded (review mode).
  bool _revealed = false;

  QuizSession get s => widget.session;
  bool get _reveal => s.graded || _revealed;

  void _persist() => widget.store.save(s); // no-op for quick start

  void _select(String opt) {
    if (s.graded) return;
    setState(() => s.select(opt));
    _persist();
  }

  void _move(void Function() m) {
    setState(() {
      m();
      _revealed = false;
    });
    _persist();
  }

  void _toggleMark() {
    setState(() => s.toggleMark());
    _persist();
  }

  Future<void> _grade() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Grade session?'),
        content: Text(
            'You have answered ${s.answered} of ${s.total} questions. '
            'Unanswered questions are not counted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep going')),
          FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Grade')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => s.graded = true);
    _persist();
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ResultsScreen(session: s, repo: widget.repo),
    ));
    if (mounted) setState(() {}); // reflect review mode after returning
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = widget.repo.byId(s.currentId);

    return Scaffold(
      appBar: AppBar(
        title: Text('Q ${s.current + 1} / ${s.total}'),
        actions: [
          if (s.graded)
            TextButton(
              onPressed: () =>
                  Navigator.of(context).popUntil((r) => r.isFirst),
              child: Text('Done',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.primary)),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton(
                // A bounded size: the app-wide button theme uses an
                // infinite-width minimumSize for full-width buttons, which
                // can't live in the AppBar's unbounded actions row.
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  textStyle: const TextStyle(
                      fontFamily: 'Lora',
                      fontSize: 16,
                      fontWeight: FontWeight.w700),
                ),
                onPressed: _grade,
                child: const Text('Grade Session'),
              ),
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
                  Row(
                    children: [
                      Expanded(
                        child: Text('${q.source} Ch.${q.chapter}  •  ${q.section}',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                      ),
                      if (s.isCurrentMarked)
                        Icon(Icons.flag, color: theme.colorScheme.primary),
                    ],
                  ),
                  Text(
                      'Difficulty: ${'★' * q.difficulty}${'☆' * (3 - q.difficulty)}',
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  Text(q.question, style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 24),
                  for (final opt in q.options(s.currentId)) _optionTile(opt, q),
                  if (_reveal) _feedback(q),
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
    final selected = s.currentAnswer == opt;
    Color? bg;
    Color border = theme.colorScheme.onSurface.withValues(alpha: 0.4);
    double borderWidth = 1.5;
    Color fg = theme.colorScheme.onSurface;

    if (_reveal) {
      if (opt == q.correctAnswer) {
        bg = answerCorrect.withValues(alpha: 0.18);
        border = answerCorrect;
        borderWidth = 3;
      } else if (selected) {
        bg = answerWrong.withValues(alpha: 0.18);
        border = answerWrong;
        borderWidth = 3;
      } else {
        fg = fg.withValues(alpha: 0.6);
      }
    } else if (selected) {
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
          onTap: s.graded ? null : () => _select(opt),
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
    final answered = s.isCurrentAnswered;
    final correct = answered && s.currentAnswer == q.correctAnswer;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              !answered
                  ? 'Correct answer shown'
                  : (correct ? '✓ Correct' : '✗ Incorrect'),
              style: theme.textTheme.titleLarge?.copyWith(
                  color: correct ? answerCorrect : answerWrong)),
          const SizedBox(height: 8),
          Text(q.explanation, style: theme.textTheme.bodyMedium),
          if (q.referenceText.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Reference: ${q.source} Ch.${q.chapter}, p.${q.referencePage}',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            Text(q.referenceText,
                style: theme.textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.8))),
          ],
        ],
      ),
    );
  }

  Widget _bottomBar() {
    final marked = s.isCurrentMarked;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: s.current > 0 ? () => _move(s.prev) : null,
                  child: const Text('Previous'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed:
                      s.current < s.total - 1 ? () => _move(s.next) : null,
                  child: const Text('Next'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _toggleMark,
                  icon: Icon(marked ? Icons.flag : Icons.outlined_flag),
                  label: Text(marked ? 'Marked' : 'Mark'),
                ),
              ),
              if (!s.graded) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        setState(() => _revealed = !_revealed),
                    child: Text(_revealed ? 'Hide Answer' : 'Show Answer'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
