import 'package:flutter/material.dart';

import '../models/session.dart';

/// Final score for a session (shown when the user taps Done or finishes).
class ResultsScreen extends StatelessWidget {
  final QuizSession session;
  const ResultsScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = session.percent;
    final passed = pct >= 70;
    final color = passed ? const Color(0xFF2E7D32) : theme.colorScheme.error;

    return Scaffold(
      appBar: AppBar(title: const Text('Results')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${session.correct} / ${session.answered}',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 72, fontWeight: FontWeight.w900, color: color),
              ),
              const SizedBox(height: 8),
              Text(
                '${pct.toStringAsFixed(0)}%',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 48, fontWeight: FontWeight.w800, color: color),
              ),
              const SizedBox(height: 24),
              Text(
                passed ? 'PASS' : 'Keep practicing',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(color: color),
              ),
              const SizedBox(height: 8),
              Text(
                'FAA written exam passing score is 70%.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () =>
                    Navigator.of(context).popUntil((r) => r.isFirst),
                child: const Text('Back to Home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
