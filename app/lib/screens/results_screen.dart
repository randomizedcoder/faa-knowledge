import 'package:flutter/material.dart';

import '../data/question_repository.dart';
import '../models/session.dart';

/// Score for a graded session (correct out of answered), with the option to
/// page back through the questions with the correct answers shown.
class ResultsScreen extends StatelessWidget {
  final QuizSession session;
  final QuestionRepository repo;
  const ResultsScreen({super.key, required this.session, required this.repo});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final correct = session.correctCount(repo);
    final answered = session.answered;
    final pct = session.percent(repo);
    final passed = pct >= 70;
    final color = passed ? const Color(0xFF2E7D32) : theme.colorScheme.error;
    final skipped = session.total - answered;

    return Scaffold(
      appBar: AppBar(title: const Text('Results')),
      body: SafeArea(
        // Center when the content fits, scroll when it doesn't (large fonts on
        // short screens would otherwise overflow).
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '$correct / $answered',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 72,
                        fontWeight: FontWeight.w900,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${pct.toStringAsFixed(0)}%',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      passed ? 'PASS' : 'Keep practicing',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Scored on the $answered you answered'
                      '${skipped > 0 ? ' ($skipped skipped)' : ''}. '
                      'FAA written exam passing score is 70%.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 40),
                    ElevatedButton(
                      onPressed: () =>
                          Navigator.of(context).pop(), // back to review
                      child: const Text('Review answers'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () =>
                          Navigator.of(context).popUntil((r) => r.isFirst),
                      child: const Text('Back to Home'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
