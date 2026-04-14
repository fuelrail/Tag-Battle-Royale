import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';


class GameSession {
  static const String _prefsKey = 'online_session_exists';
  static const String _fileName = 'online_game_session.json';

  // Save the current game session to disk.
  static Future<void> save({
    required String gameId,
    required String playerId,
    required String playerName,
    required bool isHost,
    required bool gameStarted,
    String? role,
    int? gameStartedAt,
    List<int>? faceOrder,
    int? closureIntervalMs,
    int? gracePeriodMs,
    Map<String, dynamic>? mapJson,
    Map<String, dynamic>? replayJson,
    List<Map<String, dynamic>>? players,
  }) async {
    final data = {
      'gameId': gameId,
      'playerId': playerId,
      'playerName': playerName,
      'isHost': isHost,
      'gameStarted': gameStarted,
      'role': role,
      'gameStartedAt': gameStartedAt,
      'faceOrder': faceOrder,
      'closureIntervalMs': closureIntervalMs,
      'gracePeriodMs': gracePeriodMs,
      'mapJson': mapJson,
      'replayJson': replayJson,
      'players': players,
    };
    final file = await _getFile();
    await file.writeAsString(jsonEncode(data));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);
  }

  static Future<bool> exists() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKey) ?? false;
  }

  // Load a saved game session, or null if none exists.
  static Future<GameSessionData?> load() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefsKey) != true) return null;

    try {
      final file = await _getFile();
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return GameSessionData.fromJson(json);
    } catch (e) {
      print('Failed to load online session: $e');
      return null;
    }
  }

  // Clear the saved session
  static Future<void> clear() async {
    try {
      final file = await _getFile();
      if (await file.exists()) await file.delete();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  // Update just the replay data in the existing session.
  static Future<void> updateReplay(Map<String, dynamic> replayJson) async {
    final session = await load();
    if (session == null) return;
    await save(
      gameId: session.gameId,
      playerId: session.playerId,
      playerName: session.playerName,
      isHost: session.isHost,
      gameStarted: session.gameStarted,
      gameStartedAt: session.gameStartedAt,
      faceOrder: session.faceOrder,
      closureIntervalMs: session.closureIntervalMs,
      gracePeriodMs: session.gracePeriodMs,
      mapJson: session.mapJson,
      replayJson: replayJson,
      players: session.players,
    );
  }

  static Future<void> updateRole(String role) async {
    final session = await load();
    if (session == null) return;
    await save(
      gameId: session.gameId,
      playerId: session.playerId,
      playerName: session.playerName,
      isHost: session.isHost,
      gameStarted: session.gameStarted,
      role: role,
      gameStartedAt: session.gameStartedAt,
      faceOrder: session.faceOrder,
      closureIntervalMs: session.closureIntervalMs,
      gracePeriodMs: session.gracePeriodMs,
      mapJson: session.mapJson,
      replayJson: session.replayJson,
      players: session.players,
    );
  }

  static Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }
}

class GameSessionData {
  final String gameId;
  final String playerId;
  final String playerName;
  final bool isHost;
  final bool gameStarted;
  final String? role;
  final int? gameStartedAt;
  final List<int>? faceOrder;
  final int? closureIntervalMs;
  final int? gracePeriodMs;
  final Map<String, dynamic>? mapJson;
  final Map<String, dynamic>? replayJson;
  final List<Map<String, dynamic>>? players;

  GameSessionData({
    required this.gameId,
    required this.playerId,
    required this.playerName,
    required this.isHost,
    required this.gameStarted,
    this.role,
    this.gameStartedAt,
    this.faceOrder,
    this.closureIntervalMs,
    this.gracePeriodMs,
    this.mapJson,
    this.replayJson,
    this.players,
  });

  factory GameSessionData.fromJson(Map<String, dynamic> json) {
    return GameSessionData(
      gameId: json['gameId'] ?? '',
      playerId: json['playerId'] ?? '',
      playerName: json['playerName'] ?? '',
      isHost: json['isHost'] ?? false,
      gameStarted: json['gameStarted'] ?? false,
      role: json['role'],
      gameStartedAt: json['gameStartedAt'],
      faceOrder: (json['faceOrder'] as List?)?.cast<int>(),
      closureIntervalMs: json['closureIntervalMs'],
      gracePeriodMs: json['gracePeriodMs'],
      mapJson: json['mapJson'] as Map<String, dynamic>?,
      replayJson: json['replayJson'] as Map<String, dynamic>?,
      players: (json['players'] as List?)
          ?.map((p) => Map<String, dynamic>.from(p))
          .toList(),
    );
  }
}