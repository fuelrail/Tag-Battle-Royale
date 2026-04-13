import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../util/map_file_handler.dart';
import '../util/replay/replay.dart';

/// File session storage for offline games.
class OfflineGameSession {
  static const String _prefsKey = 'offline_session_exists';
  static const String _fileName = 'offline_game_session.json';

  final String playerName;
  final String displayName;
  final bool isHost;
  final String role;
  final bool gameStarted;
  final int? gameStartedAt; // milliseconds since epoch
  final List<int> faceOrder;
  final int closureIntervalMs;
  final int gracePeriodMs;
  final Map<String, dynamic>? mapJson;
  final Map<String, dynamic>? replayJson;
  final List<Map<String, dynamic>> players;

  OfflineGameSession({
    required this.playerName,
    required this.displayName,
    required this.isHost,
    required this.role,
    required this.gameStarted,
    this.gameStartedAt,
    this.faceOrder = const [],
    this.closureIntervalMs = 900000,
    this.gracePeriodMs = 90000,
    this.mapJson,
    this.replayJson,
    this.players = const [],
  });

  Map<String, dynamic> toJson() => {
        'playerName': playerName,
        'displayName': displayName,
        'isHost': isHost,
        'role': role,
        'gameStarted': gameStarted,
        'gameStartedAt': gameStartedAt,
        'faceOrder': faceOrder,
        'closureIntervalMs': closureIntervalMs,
        'gracePeriodMs': gracePeriodMs,
        'mapJson': mapJson,
        'replayJson': replayJson,
        'players': players,
      };

  factory OfflineGameSession.fromJson(Map<String, dynamic> json) {
    return OfflineGameSession(
      playerName: json['playerName'] ?? '',
      displayName: json['displayName'] ?? '',
      isHost: json['isHost'] ?? false,
      role: json['role'] ?? 'runner',
      gameStarted: json['gameStarted'] ?? false,
      gameStartedAt: json['gameStartedAt'],
      faceOrder: (json['faceOrder'] as List?)?.cast<int>() ?? [],
      closureIntervalMs: json['closureIntervalMs'] ?? 900000,
      gracePeriodMs: json['gracePeriodMs'] ?? 90000,
      mapJson: json['mapJson'] as Map<String, dynamic>?,
      replayJson: json['replayJson'] as Map<String, dynamic>?,
      players: (json['players'] as List?)
        ?.map((p) => Map<String, dynamic>.from(p))
        .toList() ?? [],
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
      return OfflineGameSession.fromJson(jsonDecode(content));
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  // Update just the replay data in the existing session.
  static Future<void> updateReplay(Map<String, dynamic> replayJson) async {
    final session = await load();
    if (session == null) return;
    await save(OfflineGameSession(
      playerName: session.playerName,
      displayName: session.displayName,
      isHost: session.isHost,
      role: session.role,
      gameStarted: session.gameStarted,
      gameStartedAt: session.gameStartedAt,
      faceOrder: session.faceOrder,
      closureIntervalMs: session.closureIntervalMs,
      gracePeriodMs: session.gracePeriodMs,
      mapJson: session.mapJson,
      replayJson: replayJson,
      players: session.players,
    ));
  }

  // Update just the role in the existing session.
  static Future<void> updateRole(String role) async {
    final session = await load();
    if (session == null) return;
    await save(OfflineGameSession(
      playerName: session.playerName,
      displayName: session.displayName,
      isHost: session.isHost,
      role: role,
      gameStarted: session.gameStarted,
      gameStartedAt: session.gameStartedAt,
      faceOrder: session.faceOrder,
      closureIntervalMs: session.closureIntervalMs,
      gracePeriodMs: session.gracePeriodMs,
      mapJson: session.mapJson,
      replayJson: session.replayJson,
      players: session.players,
    ));
  }
}