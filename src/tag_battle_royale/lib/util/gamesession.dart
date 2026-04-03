import 'package:shared_preferences/shared_preferences.dart';

// Stores and retrieves game session data so the app can offer
// reconnection after being closed and reopened.
class GameSession {
  static const _keyGameId = 'session_game_id';
  static const _keyPlayerId = 'session_player_id';
  static const _keyPlayerName = 'session_player_name';
  static const _keyIsHost = 'session_is_host';
  static const _keyGameStarted = 'session_game_started';

  // Save the current game session to disk.
  static Future<void> save({
    required String gameId,
    required String playerId,
    required String playerName,
    required bool isHost,
    required bool gameStarted,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGameId, gameId);
    await prefs.setString(_keyPlayerId, playerId);
    await prefs.setString(_keyPlayerName, playerName);
    await prefs.setBool(_keyIsHost, isHost);
    await prefs.setBool(_keyGameStarted, gameStarted);
  }

  // Load a saved game session, or null if none exists.
  static Future<GameSessionData?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final gameId = prefs.getString(_keyGameId);
    final playerId = prefs.getString(_keyPlayerId);
    final playerName = prefs.getString(_keyPlayerName);
    final isHost = prefs.getBool(_keyIsHost);
    final gameStarted = prefs.getBool(_keyGameStarted);

    if (gameId == null || playerId == null || playerName == null ||
        isHost == null || gameStarted == null) {
      return null;
    }

    return GameSessionData(
      gameId: gameId,
      playerId: playerId,
      playerName: playerName,
      isHost: isHost,
      gameStarted: gameStarted,
    );
  }

  // Clear the saved session (game ended, player intentionally left, etc.)
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyGameId);
    await prefs.remove(_keyPlayerId);
    await prefs.remove(_keyPlayerName);
    await prefs.remove(_keyIsHost);
    await prefs.remove(_keyGameStarted);
  }
}

class GameSessionData {
  final String gameId;
  final String playerId;
  final String playerName;
  final bool isHost;
  final bool gameStarted;

  GameSessionData({
    required this.gameId,
    required this.playerId,
    required this.playerName,
    required this.isHost,
    required this.gameStarted,
  });
}