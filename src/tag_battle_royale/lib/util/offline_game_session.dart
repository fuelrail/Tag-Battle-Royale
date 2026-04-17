import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';


/// File session storage for offline games.
class OfflineGameSession {
  static const String _prefsKey = 'offline_session_exists';
  static const String _fileName = 'offline_game_session.json';
  static const String _replayFileName = 'offline_game_replay.json';

  final String playerName;
  final String displayName;
  final bool isHost;
  final String role;
  final bool gameStarted;
  final int? gameStartedAt; // milliseconds since epoch
  final String lobbyName;
  final List<int> faceOrder;
  final int closureIntervalMs;
  final int gracePeriodMs;
  final Map<String, dynamic>? mapJson;
  final Map<String, dynamic>? replayJson;
  final List<Map<String, dynamic>> players;
  final bool gameFinished;
  final double? finalElapsedSeconds;
  final bool outOfZoneTimerEnabled;
  final int outOfZoneTimerMs;
  final int? outOfZoneRemainingMs;
  final bool inBadZone;

  OfflineGameSession({
    required this.playerName,
    required this.displayName,
    required this.isHost,
    required this.role,
    required this.gameStarted,
    this.gameStartedAt,
    this.lobbyName = '',
    this.faceOrder = const [],
    this.closureIntervalMs = 900000,
    this.gracePeriodMs = 90000,
    this.mapJson,
    this.replayJson,
    this.players = const [],
    this.gameFinished = false,
    this.finalElapsedSeconds,
    this.outOfZoneTimerEnabled = false,
    this.outOfZoneTimerMs = 300000,
    this.outOfZoneRemainingMs,
    required this.inBadZone,
  });

  Map<String, dynamic> toJson() => {
        'playerName': playerName,
        'displayName': displayName,
        'isHost': isHost,
        'role': role,
        'gameStarted': gameStarted,
        'gameStartedAt': gameStartedAt,
        'lobbyName': lobbyName,
        'faceOrder': faceOrder,
        'closureIntervalMs': closureIntervalMs,
        'gracePeriodMs': gracePeriodMs,
        'mapJson': mapJson,
        'replayJson': replayJson,
        'players': players,
        'gameFinished': gameFinished,
        'finalElapsedSeconds': finalElapsedSeconds,
        'outOfZoneTimerEnabled': outOfZoneTimerEnabled,
        'outOfZoneTimerMs': outOfZoneTimerMs,
        'outOfZoneRemainingMs': outOfZoneRemainingMs,
        'inBadZone': inBadZone,
      };

  factory OfflineGameSession.fromJson(Map<String, dynamic> json) {
    return OfflineGameSession(
      playerName: json['playerName'] ?? '',
      displayName: json['displayName'] ?? '',
      isHost: json['isHost'] ?? false,
      role: json['role'] ?? 'runner',
      gameStarted: json['gameStarted'] ?? false,
      gameStartedAt: json['gameStartedAt'],
      lobbyName: json['lobbyName'] ?? '',
      faceOrder: (json['faceOrder'] as List?)?.cast<int>() ?? [],
      closureIntervalMs: json['closureIntervalMs'] ?? 900000,
      gracePeriodMs: json['gracePeriodMs'] ?? 90000,
      mapJson: json['mapJson'] as Map<String, dynamic>?,
      replayJson: json['replayJson'] as Map<String, dynamic>?,
      players: (json['players'] as List?)
        ?.map((p) => Map<String, dynamic>.from(p))
        .toList() ?? [],
      gameFinished: json['gameFinished'] ?? false,
      finalElapsedSeconds: (json['finalElapsedSeconds'] as num?)?.toDouble(),
      outOfZoneTimerEnabled: json['outOfZoneTimerEnabled'] ?? false,
      outOfZoneTimerMs: json['outOfZoneTimerMs'] ?? 300000,
      outOfZoneRemainingMs: json['outOfZoneRemainingMs'],
      inBadZone: json['inBadZone'] ?? false,
    );
  }

  static Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  // Save session to disk and set the exists flag.
  static Future<void> save(OfflineGameSession session) async {
    final file = await _getFile();
    await file.writeAsString(jsonEncode(session.toJson()));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true); 
  }

  // Check if an offline session exists.
  static Future<bool> exists() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKey) ?? false;
  }

  // Load session from disk. Returns null if no session or error.
  static Future<OfflineGameSession?> load() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefsKey) != true) return null;

    try {
      final file = await _getFile();
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;

      // Check for separate replay file
      final replayFile = await _getReplayFile();
      if (await replayFile.exists()) {
        try {
          final replayContent = await replayFile.readAsString();
          json['replayJson'] = jsonDecode(replayContent);
        } catch (_) {}
      }

      return OfflineGameSession.fromJson(json);
    } catch (e) {
      print('Failed to load offline session: $e');
      return null;
    }
  }

  // Clear the session from disk.
  static Future<void> clear() async {
    try {
      final file = await _getFile();
      if (await file.exists()) await file.delete();
    } catch (_) {}
    try {
      final replayFile = await _getReplayFile();
      if (await replayFile.exists()) await replayFile.delete();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  static Future<File> _getReplayFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_replayFileName');
  }

  // Update just the replay data in the existing session.
  static Future<void> updateReplay(Map<String, dynamic> replayJson) async {
    final file = await _getReplayFile();
    await file.writeAsString(jsonEncode(replayJson));
  }

  // Update just the role in the existing session.
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