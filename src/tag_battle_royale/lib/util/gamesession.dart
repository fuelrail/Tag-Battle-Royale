import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';


class GameSession {
  static const String _prefsKey = 'online_session_exists';
  static const String _fileName = 'online_game_session.json';
  static const String _replayFileName = 'online_game_replay.json';
  static const String _mapFileName = 'online_game_map.json';

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
    bool? replaySubmitted,
    bool? replayFileAssembled,
    bool? replayFileSentToServer,
    List<Map<String, dynamic>>? players,
    bool? gameFinished,
    String? finishReason,
    double? finalElapsedSeconds,
    bool? outOfZoneTimerEnabled,
    int? outOfZoneTimerMs,
    int? outOfZoneRemainingMs,
    bool? inBadZone,
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
      'replaySubmitted': replaySubmitted,
      'replayFileAssembled': replayFileAssembled,
      'replayFileSentToServer': replayFileSentToServer,
      'players': players,
      'gameFinished': gameFinished,
      'finishReason': finishReason,
      'finalElapsedSeconds': finalElapsedSeconds,
      'outOfZoneTimerEnabled': outOfZoneTimerEnabled,
      'outOfZoneTimerMs': outOfZoneTimerMs,
      'outOfZoneRemainingMs': outOfZoneRemainingMs,
      'inBadZone': inBadZone,
    };
    final file = await _getFile();
    await file.writeAsString(jsonEncode(data));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);
  }

  // Save the map data separately (called once when the map is received).
  static Future<void> saveMap(Map<String, dynamic> mapJson) async {
    final file = await _getMapFile();
    await file.writeAsString(jsonEncode(mapJson));
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

      // Load replay from separate file
      final replayFile = await _getReplayFile();
      if (await replayFile.exists()) {
        try {
          final replayContent = await replayFile.readAsString();
          json['replayJson'] = jsonDecode(replayContent);
        } catch (_) {}
      }

      // Load map from separate file
      final mapFile = await _getMapFile();
      if (await mapFile.exists()) {
        try {
          final mapContent = await mapFile.readAsString();
          json['mapJson'] = jsonDecode(mapContent);
        } catch (_) {}
      }

      return GameSessionData.fromJson(json);
    } catch (e) {
      print('Failed to load online session: $e');
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final file = await _getFile();
      if (await file.exists()) await file.delete();
    } catch (_) {}
    try {
      final replayFile = await _getReplayFile();
      if (await replayFile.exists()) await replayFile.delete();
    } catch (_) {}
    try {
      final mapFile = await _getMapFile();
      if (await mapFile.exists()) await mapFile.delete();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  static Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<File> _getReplayFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_replayFileName');
  }

  static Future<File> _getMapFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_mapFileName');
  }

  // Update just the replay data in the existing session.
  static Future<void> updateReplay(Map<String, dynamic> replayJson) async {
    final file = await _getReplayFile();
    await file.writeAsString(jsonEncode(replayJson));
  }

  static Future<void> updateRole(String role) async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      json['role'] = role;
      await file.writeAsString(jsonEncode(json));
    } catch (_) {}
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
  final bool? replaySubmitted;
  final bool? replayFileAssembled;
  final bool? replayFileSentToServer;
  final List<Map<String, dynamic>>? players;
  final bool? gameFinished;
  final String? finishReason;
  final double? finalElapsedSeconds;
  final bool? outOfZoneTimerEnabled;
  final int? outOfZoneTimerMs;
  final int? outOfZoneRemainingMs;
  final bool? inBadZone;

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
    this.replaySubmitted,
    this.replayFileAssembled,
    this.replayFileSentToServer,
    this.players,
    this.gameFinished,
    this.finishReason,
    this.finalElapsedSeconds,
    this.outOfZoneTimerEnabled,
    this.outOfZoneTimerMs,
    this.outOfZoneRemainingMs,
    this.inBadZone,
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
      replaySubmitted: json['replaySubmitted'],
      replayFileAssembled: json['replayFileAssembled'],
      replayFileSentToServer: json['replayFileSentToServer'],
      players: (json['players'] as List?)?.map((p) => Map<String, dynamic>.from(p)).toList(),
      gameFinished: json['gameFinished'],
      finishReason: json['finishReason'],
      finalElapsedSeconds: (json['finalElapsedSeconds'] as num?)?.toDouble(),
      outOfZoneTimerEnabled: json['outOfZoneTimerEnabled'],
      outOfZoneTimerMs: json['outOfZoneTimerMs'],
      outOfZoneRemainingMs: json['outOfZoneRemainingMs'],
      inBadZone: json['inBadZone'],
    );
  }
}