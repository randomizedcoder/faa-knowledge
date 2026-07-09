import 'package:shared_preferences/shared_preferences.dart';

import '../models/session.dart';

/// Persists the 3 saved sessions in shared_preferences (keys session_0..2).
class SessionStore {
  static const int slots = 3;
  static String _key(int slot) => 'session_$slot';

  Future<QuizSession?> load(int slot) async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_key(slot));
    if (s == null) return null;
    try {
      return QuizSession.decode(s);
    } catch (_) {
      return null; // ignore a corrupt slot rather than crash
    }
  }

  Future<List<QuizSession?>> loadAll() async =>
      [for (var i = 0; i < slots; i++) await load(i)];

  Future<void> save(QuizSession session) async {
    if (session.isQuickStart) return; // never persist quick start
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(session.slot), session.encode());
  }

  Future<void> clear(int slot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(slot));
  }
}
