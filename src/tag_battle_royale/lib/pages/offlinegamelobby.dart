// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'package:nearby_connections/nearby_connections.dart';

import '../util/player_data.dart';
import '../util/map_file_handler.dart';
import '../util/offline_game_session.dart';
import '../util/replay/replay.dart';
import '../util/player.dart';
import '../util/replay/replay_file_handler.dart';
import '../services/location_service.dart';
import '../main.dart';
import '../widgets/lobby.dart';
import '../widgets/game_banner.dart';
import '../widgets/hold_button.dart';
import '../widgets/map_selector.dart';
import '../widgets/game_display.dart';

// --------------------------------------------------------------------------
//  Commands for relaying
// --------------------------------------------------------------------------

class Cmd {
  static const String _username = 'CMD:USERNAME:';
  static const String _becomeHost = 'CMD:BECOME_HOST:';
  static const String _reportChild = 'CMD:REPORT_CHILD:';
  static const String _reportDisconnect = 'CMD:REPORT_DISCONNECT:';
  static const String _relay = 'CMD:RELAY:';
  static const String _chat = 'CMD:CHAT:';
  static const String _playerList = 'CMD:PLAYERLIST:';
  static const String hostTarget = 'HOST';
  static const String _joinRequest = 'CMD:JOIN_REQUEST:';
  static const String _playerAccept = 'CMD:PLAYER_ACCEPT:';
  static const String _playerReject = 'CMD:PLAYER_REJECT:';
  static const String _roleUpdate = 'CMD:ROLE_UPDATE:';
  static const String _kick = 'CMD:KICK:';
  static const String _pseudoConfirm = 'CMD:PSEUDOHOST_CONFIRM:';
  static const String _pseudoFail = 'CMD:PSEUDOHOST_FAIL:';
  static const String _pendingDisconnect = 'CMD:PENDING_DISCONNECT:';
  static const String _gameMap = 'CMD:GAME_MAP:';
  static const String _mapConfirmed = 'CMD:MAP_CONFIRMED:';
  static const String _gameStarted = 'CMD:GAME_STARTED:';
  static const String _replayData = 'CMD:REPLAY_DATA:';
  static const String _replayAck = 'CMD:REPLAY_ACK:';
  static const String _replayFileData = 'CMD:REPLAY_FILE:';
  static const String _replayFileAck = 'CMD:REPLAY_FILE_ACK:';
  static const String _chunk = 'CMD:CHUNK:';

  // Build
  static String username(String userName, String displayName) =>
      '$_username$userName:$displayName';
  static String becomeHost(String lobby) => '$_becomeHost$lobby';
  static String reportChild(String parent, String child) =>
      '$_reportChild$parent:$child';
  static String reportDisconnect(String parent, String child) =>
      '$_reportDisconnect$parent:$child';
  static String relay(String from, String to, String inner) =>
      '$_relay$from:$to:$inner';
  static String chat(String playerId, String playerName, String text) =>
      '$_chat$playerId:$playerName:$text';
  static String playerList(List<PlayerData> players) {
      final entries = players.map((p) => '${p.id}:${p.name}:${p.role}:${p.isHost ? '1' : '0'}').join(',');
      return '$_playerList$entries';
  }
  static String joinRequest(String advertiser, String joinerUser, String joinerDisplay) =>
      '$_joinRequest$advertiser:$joinerUser:$joinerDisplay';
  static String playerAccept(String joinerUserName) =>
      '$_playerAccept$joinerUserName';
  static String playerReject(String joinerUserName, String reason) =>
      '$_playerReject$joinerUserName:$reason';
  static String roleUpdate(String playerId, String role) =>
      '$_roleUpdate$playerId:$role';
  static String kick(String playerId) =>
      '$_kick$playerId';
  static String pseudoConfirm(String userName) =>
      '$_pseudoConfirm$userName';
  static String pseudoFail(String userName) =>
      '$_pseudoFail$userName';
  static String pendingDisconnect(String joinerUserName) =>
      '$_pendingDisconnect$joinerUserName';
  static String gameMap(Map<String, dynamic> payload) {
      final jsonStr = jsonEncode(payload);
      return '$_gameMap${base64Encode(utf8.encode(jsonStr))}';
  }
  static String mapConfirmed(String userName) => 
      '$_mapConfirmed$userName';
  static String gameStarted(int startedAtMs) => 
      '$_gameStarted$startedAtMs';
  static String replayData(String userName, Map<String, dynamic> replay) {
      final jsonStr = jsonEncode({'userName': userName, 'replay': replay});
      return '$_replayData${base64Encode(utf8.encode(jsonStr))}';
  }
  static String replayAck(String userName) => 
      '$_replayAck$userName';
  static String replayFileData(Map<String, dynamic> replayFile) {
      final jsonStr = jsonEncode(replayFile);
      return '$_replayFileData${base64Encode(utf8.encode(jsonStr))}';
  }
  static String replayFileAck(String userName) => 
      '$_replayFileAck$userName';
  static String chunk(String transferId, int index, int total, bool flood, String data) =>
      '$_chunk$transferId:$index:$total:${flood ? '1' : '0'}:$data';

  // Check
  static bool isUsername(String m) => m.startsWith(_username);
  static bool isBecomeHost(String m) => m.startsWith(_becomeHost);
  static bool isReportChild(String m) => m.startsWith(_reportChild);
  static bool isReportDisconnect(String m) => m.startsWith(_reportDisconnect);
  static bool isRelay(String m) => m.startsWith(_relay);
  static bool isChat(String m) => m.startsWith(_chat);
  static bool isPlayerList(String m) => m.startsWith(_playerList);
  static bool isJoinRequest(String m) => m.startsWith(_joinRequest);
  static bool isPlayerAccept(String m) => m.startsWith(_playerAccept);
  static bool isPlayerReject(String m) => m.startsWith(_playerReject);
  static bool isRoleUpdate(String m) => m.startsWith(_roleUpdate);
  static bool isKick(String m) => m.startsWith(_kick);
  static bool isPseudoConfirm(String m) => m.startsWith(_pseudoConfirm);
  static bool isPseudoFail(String m) => m.startsWith(_pseudoFail);
  static bool isPendingDisconnect(String m) => m.startsWith(_pendingDisconnect);
  static bool isGameMap(String m) => m.startsWith(_gameMap);
  static bool isMapConfirmed(String m) => m.startsWith(_mapConfirmed);
  static bool isGameStarted(String m) => m.startsWith(_gameStarted);
  static bool isReplayData(String m) => m.startsWith(_replayData);
  static bool isReplayAck(String m) => m.startsWith(_replayAck);
  static bool isReplayFileData(String m) => m.startsWith(_replayFileData);
  static bool isReplayFileAck(String m) => m.startsWith(_replayFileAck);
  static bool isChunk(String m) => m.startsWith(_chunk);

  // Parse
  static (String userName, String displayName) parseUsername(String m) {
      final parts = m.substring(_username.length).split(':');
      return (parts[0], parts[1]);
  }

  static String parseBecomeHost(String m) => 
      m.substring(_becomeHost.length);

  static (String parent, String child) parseReportChild(String m) {
      final p = m.substring(_reportChild.length).split(':');
      return (p[0], p[1]);
  }

  static (String parent, String child) parseReportDisconnect(String m) {
      final p = m.substring(_reportDisconnect.length).split(':');
      return (p[0], p[1]);
  }

  static (String sender, String target, String inner) parseRelay(String m) {
      final payload = m.substring(_relay.length);
      final i1 = payload.indexOf(':');
      final i2 = payload.indexOf(':', i1 + 1);
      return (payload.substring(0, i1), payload.substring(i1 + 1, i2), payload.substring(i2 + 1));
  }

  static (String playerId, String playerName, String text) parseChat(String m) {
      final parts = m.substring(_chat.length).split(':');
      return (parts[0], parts[1], parts.sublist(2).join(':')); // sublist used because reason may contain ':'
  }

  static List<PlayerData> parsePlayerList(String m) {
      final payload = m.substring(_playerList.length);
      if (payload.isEmpty) return [];
      return payload.split(',').where((s) => s.isNotEmpty).map((entry) {
        final parts = entry.split(':');
        return PlayerData(
          id: parts[0],
          name: parts.length > 1 ? parts[1] : parts[0],
          role: parts.length > 2 ? parts[2] : 'runner',
          isHost: parts.length > 3 && parts[3] == '1',
        );
      }).toList();
  }

  static (String advertiser, String joinerUser, String joinerDisplay) parseJoinRequest(String m) {
      final parts = m.substring(_joinRequest.length).split(':');
      return (parts[0], parts[1], parts[2]);
  }

  static String parsePlayerAccept(String m) =>
      m.substring(_playerAccept.length);
  
  static (String joinerUser, String reason) parsePlayerReject(String m) {
      final parts = m.substring(_playerReject.length).split(':');
      return (parts[0], parts.sublist(1).join(':'));
  }

  static (String playerId, String role) parseRoleUpdate(String m) {
      final p = m.substring(_roleUpdate.length).split(':');
      return (p[0], p[1]);
  }

  static String parseKick(String m) => 
      m.substring(_kick.length);

  static String parsePseudoConfirm(String m) =>
      m.substring(_pseudoConfirm.length);

  static String parsePseudoFail(String m) => 
      m.substring(_pseudoFail.length);

  static String parsePendingDisconnect(String m) =>
      m.substring(_pendingDisconnect.length);

  static Map<String, dynamic> parseGameMap(String m) {
      final b64 = m.substring(_gameMap.length);
      final jsonStr = utf8.decode(base64Decode(b64));
      return jsonDecode(jsonStr) as Map<String, dynamic>;
  }

  static String parseMapConfirmed(String m) => 
      m.substring(_mapConfirmed.length);

  static int parseGameStarted(String m) => 
      int.parse(m.substring(_gameStarted.length));

  static Map<String, dynamic> parseReplayData(String m) {
      final b64 = m.substring(_replayData.length);
      return jsonDecode(utf8.decode(base64Decode(b64))) as Map<String, dynamic>;
  }

  static String parseReplayAck(String m) => 
      m.substring(_replayAck.length);

  static Map<String, dynamic> parseReplayFileData(String m) {
      final b64 = m.substring(_replayFileData.length);
      return jsonDecode(utf8.decode(base64Decode(b64))) as Map<String, dynamic>;
  }

  static String parseReplayFileAck(String m) => 
      m.substring(_replayFileAck.length);

  static (String transferId, int index, int total, bool flood, String data) parseChunk(String m) {
      final payload = m.substring(_chunk.length);
      final i1 = payload.indexOf(':');
      final i2 = payload.indexOf(':', i1 + 1);
      final i3 = payload.indexOf(':', i2 + 1);
      final i4 = payload.indexOf(':', i3 + 1);
      return (
        payload.substring(0, i1),
        int.parse(payload.substring(i1 + 1, i2)),
        int.parse(payload.substring(i2 + 1, i3)),
        payload.substring(i3 + 1, i4) == '1',
        payload.substring(i4 + 1),
      );
  }
}

// --------------------------------------------------------------------------
//  Discovered endpoint
// --------------------------------------------------------------------------

class DiscoveredEndpoint {
  final String id;
  final String name;
  final String serviceId;
  
  DiscoveredEndpoint({
    required this.id, 
    required this.name, 
    required this.serviceId,
  });
}

// --------------------------------------------------------------------------
//  Offline Lobby Screen
// --------------------------------------------------------------------------

class OfflineConnectionScreen extends StatefulWidget {
  const OfflineConnectionScreen({
    super.key, 
    required this.role, 
    required this.nickName, 
    required this.lobbyName, 
    this.resumeSession
  });

  final ConnectionRole role;
  final String nickName;
  final String lobbyName;
  final OfflineGameSession? resumeSession;

  @override
  State<OfflineConnectionScreen> createState() =>
      _OfflineConnectionScreenState();
}

class _OfflineConnectionScreenState extends State<OfflineConnectionScreen> {
  late final String userName;
  late final String displayName; // nickName if provided, otherwise userName
  final Strategy strategy = Strategy.P2P_CLUSTER;
  final int maxConnections = 1;

  // Network
  Map<String, ConnectionInfo> endpointMap = {}; // { endpointId: ConnectionInfo }
  Map<String, String> connectedNames = {}; // { endpointId: userName }
  Map<String, DiscoveredEndpoint> discoveredEndpoints = {}; // { endpointId: DiscoveredEndpoint }
  bool _isAdvertising = false;
  bool _isDiscovering = false;
  bool _isPseudoHost = false; 
  late String _lobbyName;
  bool _isDisconnectingAll = false;
  String? _parentEndpointId;

  // Topology (for host)
  final Map<String, List<String>> _tree = {}; // Tree structure
  final Set<String> _pseudoHosts = {}; // set of userNames that are pseudoHosts already

  // Lobby data
  // Endpoints connected via Nearby but not yet game-accepted.
  // Key: endpointId, Value: { userName, displayName }
  final Map<String, ({String userName, String displayName})>
      _localPendingEndpoints = {};
  final List<PlayerData> _players = []; // [{ id: userName, name: displayName }]
  final List<OfflinePendingPlayer> _pendingGamePlayers = []; // host UI
  final Map<String, Color> _playerColourMap = {}; // { playerId: Color }
  final Map<String, List<ChatMessage>> _chatMessages = {'all': []};
  final String _activeChannel = 'all';
  final List<String> _log = [];
  bool _pendingAcceptance = false; // joiner waiting for host acceptance
  bool _inLobby = false; // joiner accepted into lobby

  // Map & config
  MapFile? _selectedMap;
  MapFile? _receivedMap;
  List<int>? _faceOrder; // ordered faceIDs
  int _closureMinutes = 15;
  int _gracePeriodSeconds = 90;
  final TextEditingController _closureMinutesController =
      TextEditingController(text: '15');
  final TextEditingController _gracePeriodController =
      TextEditingController(text: '90');

  // Game start
  bool _isStarting = false;
  final Set<String> _mapConfirmations = {};

  // Active game
  bool _gameStarted = false;
  bool _gameFinished = false;
  DateTime? _gameStartedAt;
  List<int> _activeFaceOrder = [];
  int _activeClosureIntervalMs = 15 * 60 * 1000;
  int _activeGracePeriodMs = 90 * 1000;

  // Grace period
  Timer? _graceTimer;
  int _graceSecondsRemaining = 0;

  // Display zone close
  Timer? _bannerTimer;

  // Location and replay
  LocationService? _location;
  Replay? _replay;
  late ConfettiController _confettiController;
  final GlobalKey<LobbyLayoutState> _lobbyKey = GlobalKey<LobbyLayoutState>();
  final ScrollController _playersScrollController = ScrollController();

  // Display
  final ValueNotifier<int?> _displayCurrentZone = ValueNotifier(null);
  final ValueNotifier<Set<int>> _displayClosedZones = ValueNotifier({});
  final ValueNotifier<int?> _displayNextZone = ValueNotifier(null);
  final Players _displayPlayers = Players();

  // Replay exchange
  bool _collectingReplays = false;
  bool _distributingReplay = false;
  bool _replayExchangeActive = false; // non-host has pressed Send
  bool _individualReplaySent = false;
  bool _assembledReplayReceived = false;
  final Map<String, Map<String, dynamic>> _collectedReplays = {};
  Map<String, dynamic>? _offlineAssembledReplayJson;
  final Set<String> _distributedTo = {};
  final Map<String, String> _replayConnectedNames = {}; // { endpointId: userName }
  bool _replayAdvertising = false;

  // Chunking
  static const int _maxChunkSize = 32000;
  final Map<String, Map<int, String>> _chunkBuffers = {};
  final Map<String, int> _chunkTotals = {};

  // Gets
  bool get isHost => widget.role == ConnectionRole.host;
  bool get amHost => isHost || _isPseudoHost;
  String get _myRole {
    final me = _players.where((p) => p.id == userName).firstOrNull;
    return me?.role ?? 'runner';
  }
  int get _childConnectionCount {
    if (_isPseudoHost) return endpointMap.length - 1;
    return endpointMap.length;
  }
  bool get _inGracePeriod {
    if (_gameStartedAt == null || _activeGracePeriodMs <= 0) return false;
    return DateTime.now().difference(_gameStartedAt!).inMilliseconds < _activeGracePeriodMs;
  }
  Set<int> get _closedZones {
    if (_gameStartedAt == null || _activeFaceOrder.isEmpty) return {};
    final elapsed = DateTime.now().difference(_gameStartedAt!).inMilliseconds - _activeGracePeriodMs;
    if (elapsed <= 0) return {};
    return _activeFaceOrder.take(elapsed ~/ _activeClosureIntervalMs).toSet();
  }

  // --------------------------------------------------------------------------
  // Lifecycle
  // --------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 5));

    if (widget.resumeSession != null) {
      _initFromSession(widget.resumeSession!);
    } else {
      userName = 'User-${Random().nextInt(100000)}';
      displayName = widget.nickName;
      _lobbyName = widget.lobbyName;
      if (isHost) {
        _tree[userName] = [];
        // Add self to player list
        _players.add(PlayerData(
          id: userName,
          name: displayName,
          role: 'chaser',
          isHost: true,
        ));
        _inLobby = true;
        _startAdvertising();
      } else {
        _startDiscovery();
      }
    }
  }

  void _initFromSession(OfflineGameSession session) {
    userName = session.playerName;
    displayName = session.displayName;
    _lobbyName = session.lobbyName;;
    _inLobby = true;
    _gameStarted = true;
    _gameStartedAt = DateTime.fromMillisecondsSinceEpoch(session.gameStartedAt!);
    _activeFaceOrder = List<int>.from(session.faceOrder);
    _activeClosureIntervalMs = session.closureIntervalMs;
    _activeGracePeriodMs = session.gracePeriodMs;

    if (session.mapJson != null) {
      _receivedMap = MapFile.fromJson(session.mapJson!);
    }

    // Restore replay
    if (session.replayJson != null) {
      try {
        final restored = Replay.fromJson(session.replayJson!);
        final oldPositions = restored.positions;
        _replay = Replay(
          playerID: userName,
          playerName: displayName,
          colour: session.role == 'chaser' ? Colors.red : Colors.black,
          gameStartedAt: _gameStartedAt,
        );
        _replay!.positions.addAll(oldPositions);
        _addLog('Restored replay with ${oldPositions.length} frames');
      } catch (e) {
        _addLog('Failed to restore replay: $e');
      }
    }

    _players.clear();
    for (final p in session.players) {
      _players.add(PlayerData(
        id: p['id'] ?? '',
        name: p['name'] ?? '',
        role: p['role'] ?? 'runner',
        isHost: p['isHost'] == true,
      ));
    }

    _displayPlayers.addPlayer(Player(
      id: userName,
      name: displayName,
      colour: session.role == 'chaser' ? Colors.red : Colors.black,
    ));

    // Start location tracking
    _location = LocationService(sendIntervalMs: 5000);
    _location!.onLog = (msg) => _addLog(msg);
    _location!.map = _receivedMap;
    _location!.role = session.role;
    _location!.getClosedZones = () => _closedZones;
    _location!.onFrameRecorded = _onFrameRecorded;
    _startGraceCountdown();
    _startBannerTimer();

    if (_receivedMap != null) {
      _location!.startTracking();
    }
  }
  
  @override
  void dispose() {
    _isDisconnectingAll = true;
    Nearby().stopAdvertising();
    Nearby().stopDiscovery();
    Nearby().stopAllEndpoints();
    _graceTimer?.cancel();
    _bannerTimer?.cancel();
    _confettiController.dispose();
    _location?.onLog = null;
    _location?.onFrameRecorded = null;
    _location?.dispose();
    _displayCurrentZone.dispose();
    _displayClosedZones.dispose();
    _displayNextZone.dispose();
    _playersScrollController.dispose();
    _closureMinutesController.dispose();
    _gracePeriodController.dispose();
    _replayConnectedNames.clear();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  //  Logging
  // --------------------------------------------------------------------------

  void _addLog(String message) {
    if (!mounted) return;
    print('[$userName] $message');
    setState(() {
      _log.insert(0,
          '${DateTime.now().toIso8601String().substring(11, 19)} $message');
      if (_log.length > 100) _log.removeLast();
    });
  }

  // --------------------------------------------------------------------------
  //  Grace period
  // --------------------------------------------------------------------------

  void _startGraceCountdown() {
    _graceTimer?.cancel();
    _location?.inGracePeriod = _inGracePeriod;

    if (!_inGracePeriod) {
      _graceSecondsRemaining = 0;
      return;
    }

    final elapsed = DateTime.now().difference(_gameStartedAt!).inMilliseconds;
    _graceSecondsRemaining = ((_activeGracePeriodMs - elapsed) / 1000).ceil();

    _graceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _graceTimer?.cancel();
        return;
      }
      setState(() {
        _graceSecondsRemaining--;
        if (_graceSecondsRemaining <= 0) {
          _graceSecondsRemaining = 0;
          _graceTimer?.cancel();
          _graceTimer = null;
          _location?.inGracePeriod = false;
        }
      });
    });
  }

  // timer to display when zones will close
  void _startBannerTimer() {
    _bannerTimer?.cancel();
    _bannerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_gameStarted || _gameFinished) {
        _bannerTimer?.cancel();
        _bannerTimer = null;
        return;
      }
      setState(() {});
    });
  }

  void _stopBannerTimer() {
    _bannerTimer?.cancel();
    _bannerTimer = null;
  }

  // --------------------------------------------------------------------------
  //  Replay persistence
  // --------------------------------------------------------------------------

  void _onFrameRecorded(ui.Offset position, int? zone, String role) {
    _replay?.add(position, zone: zone, role: role);
    _displayCurrentZone.value = zone;
    _displayClosedZones.value = _closedZones;
    _displayPlayers.updatePlayerPosition(userName, position, null);
    final closedZoneLength = _closedZones.length;
    _displayNextZone.value = closedZoneLength < _activeFaceOrder.length ? _activeFaceOrder[closedZoneLength] : null;
    _persistReplay();
  }

  Future<void> _persistReplay() async {
    if (_replay == null) return;
    try {
      await OfflineGameSession.updateReplay(_replay!.toJson());
    } catch (e) {
      print('Failed to persist replay: $e');
    }
  }

  void _startReplay() {
    final me = _players.where((p) => p.id == userName).firstOrNull;
    if (me == null || _gameStartedAt == null) return;

    _replay = Replay(
      playerID: userName,
      playerName: displayName,
      colour: me.nameColour,
      gameStartedAt: _gameStartedAt,
    );

    _location?.onFrameRecorded = _onFrameRecorded;
    _addLog('Replay recording started');
  }

  // --------------------------------------------------------------------------
  //  Session persistence
  // --------------------------------------------------------------------------

  Future<void> _saveSession() async {
    await OfflineGameSession.save(OfflineGameSession(
      playerName: userName,
      displayName: displayName,
      isHost: isHost,
      role: _myRole,
      gameStarted: _gameStarted,
      gameStartedAt: _gameStartedAt?.millisecondsSinceEpoch,
      lobbyName: _lobbyName,
      faceOrder: _activeFaceOrder,
      closureIntervalMs: _activeClosureIntervalMs,
      gracePeriodMs: _activeGracePeriodMs,
      mapJson: _receivedMap?.toJson(),
      replayJson: _replay?.toJson(),
      players: _players.map((p) => {
        'id': p.id,
        'name': p.name,
        'role': p.role,
        'isHost': p.isHost,
      }).toList(),
    ));
  }

  // --------------------------------------------------------------------------
  //  Games
  // --------------------------------------------------------------------------

  void _hostStartGame() {
    if (_selectedMap == null || _faceOrder == null) return;
    if (!_players.any((p) => p.role == 'runner')) return;

    setState(() => _isStarting = true);

    // Reject all pending
    for (final pending in List.from(_pendingGamePlayers)) {
      _hostRejectPlayer(pending.userName);
    }

    _activeClosureIntervalMs = _closureMinutes * 60 * 1000;
    _activeGracePeriodMs = _gracePeriodSeconds * 1000;
    _activeFaceOrder = List<int>.from(_faceOrder!);
    _receivedMap = _selectedMap;
    _mapConfirmations.clear();
    _mapConfirmations.add(userName); // host auto-confirms

    // Send map to all players
    final mapPayload = {
      'map': _selectedMap!.toJson(),
      'faceOrder': _activeFaceOrder,
      'closureIntervalMs': _activeClosureIntervalMs,
      'gracePeriodMs': _activeGracePeriodMs,
    };
    final mapCmd = Cmd.gameMap(mapPayload);
    _addLog('Map command size: ${mapCmd.length} bytes');
    _floodChunked(mapCmd);
    _addLog('Map sent to ${_players.length - 1} players, waiting for confirmations...');

    _checkMapConfirmations();
  }

  void _checkMapConfirmations() {
    final accepted = _players.map((p) => p.id).toSet();
    if (_mapConfirmations.containsAll(accepted)) {
      _finishStarting();
    }
  }

  void _finishStarting() {
    final startedAt = DateTime.now().millisecondsSinceEpoch;
    _gameStartedAt = DateTime.fromMillisecondsSinceEpoch(startedAt);

    // Tell everyone
    _flood(Cmd.gameStarted(startedAt));

    _addLog('All confirmed. Starting game and disconnecting from mesh...');

    setState(() {
      _isStarting = false;
      _gameStarted = true;
    });

    _beginActiveGame();

    // Disconnect from nearby after a short delay to ensure the start message is sent
    Future.delayed(const Duration(milliseconds: 500), () {
      _isDisconnectingAll = true;
      Nearby().stopAdvertising();
      Nearby().stopDiscovery();
      Nearby().stopAllEndpoints();
      _isDisconnectingAll = false;

      setState(() {
        _isAdvertising = false;
        _isDiscovering = false;
        endpointMap.clear();
        connectedNames.clear();
        discoveredEndpoints.clear();
        _localPendingEndpoints.clear();
      });
    });
  }

  void _beginActiveGame() {
    // Add self to display players
    final me = _players.where((p) => p.id == userName).firstOrNull;
    _displayPlayers.addPlayer(Player(
      id: userName,
      name: displayName,
      colour: me?.nameColour ?? Colors.black,
    ));

    _location = LocationService(sendIntervalMs: 5000);
    _location!.onLog = (msg) => _addLog(msg);
    _location!.map = _receivedMap;
    _location!.role = _myRole;
    _location!.getClosedZones = () => _closedZones;

    _startReplay();
    _startGraceCountdown();
    _startBannerTimer();

    if (_receivedMap != null) {
      _location!.startTracking();
    }

    _saveSession();
    _addLog('Game started! Playing independently.');
  }

  // --------------------------------------------------------------------------
  //  End game
  // --------------------------------------------------------------------------

  Future<void> _endGame() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End game?'),
        content: const Text('This will end the game.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('End Game')),
        ],
      ),
    );
    if (confirmed != true) return;

    _location?.stopTracking();
    _stopBannerTimer();
    await _persistReplay();

    setState(() => _gameFinished = true);
    _confettiController.play();
    _addLog('Game ended');
  }

  // --------------------------------------------------------------------------
  //  Caught button
  // --------------------------------------------------------------------------

  void _onCaught() {
    final me = _players.where((p) => p.id == userName).firstOrNull;
    if (me == null) return;

    setState(() => me.role = 'chaser');
    _location?.role = 'chaser';
    OfflineGameSession.updateRole('chaser');
    _addLog("I've been caught, now a chaser");
  }

  // --------------------------------------------------------------------------
  //  Leave confirmation
  // --------------------------------------------------------------------------

  Future<bool> _confirmLeave() async {
    final String title;
    final String content;

    if (_gameFinished) {
      if (isHost && _offlineAssembledReplayJson != null) return true;
      if (!isHost && _assembledReplayReceived) return true;
      if (!isHost && !_replayExchangeActive) return true; // haven't started, just leave
      title = 'Leave game?';
      content = isHost
        ? 'Replay exchange is in progress.'
        : _individualReplaySent
            ? 'You have not received the assembled replay yet.'
            : 'Your replay has not been sent yet.';
    } else if (_gameStarted) {
      title = 'Leave game?';
      content = 'Your game progress will be saved. You can resume from the main menu.';
    } else if (isHost) {
      title = 'Disband game?';
      content = 'Leaving will disband the game for all players.';
    } else {
      title = 'Leave game?';
      content = 'Are you sure you want to leave?';
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Stay')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Leave')),
        ],
      ),
    );
    return result ?? false;
  }

  // --------------------------------------------------------------------------
  // Message Sending
  // --------------------------------------------------------------------------

  void _sendBytes(String endpointId, String message) {
    Nearby().sendBytesPayload(
        endpointId, Uint8List.fromList(message.codeUnits));
  }

  /// Flood a message to all direct connections except [excludeEndpointId].
  void _flood(String message, {String? excludeEndpointId}) {
    for (final eid in endpointMap.keys) {
      if (eid != excludeEndpointId) {
        _sendBytes(eid, message);
      }
    }
  }

  /// Send upward toward the parent.
  void _sendToParent(String message) {
    if (_parentEndpointId != null &&
        endpointMap.containsKey(_parentEndpointId)) {
      _sendBytes(_parentEndpointId!, message);
    }
  }

  /// Send a relayed message to the host by going up the tree.
  void _sendToHost(String innerMessage) {
    if (isHost) {
      // I am the host, process
      _processMessage(innerMessage, relaySender: userName);
      return;
    }
    _sendToParent(Cmd.relay(userName, Cmd.hostTarget, innerMessage));
  }

  /// Send a relayed message to a specific device by userName.
  /// Floods to all connections and relay ensures only the
  /// target processes it.
  void _sendToDevice(String targetUserName, String innerMessage) {
    _flood(Cmd.relay(userName, targetUserName, innerMessage));
  }

  /// Send directly to a local endpoint (no relay).
  void _sendDirect(String endpointId, String message) {
    _sendBytes(endpointId, message);
  }

  String _generateTransferId() {
     return '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(10000)}';
  }

  void _sendChunked(String endpointId, String message) {
    if (message.length <= _maxChunkSize) {
      _sendBytes(endpointId, message);
      return;
    }

    final transferId = _generateTransferId();
    final total = (message.length / _maxChunkSize).ceil();
    _addLog('Sending chunked: ${message.length} bytes in $total chunks');

    for (int i = 0; i < total; i++) {
      final start = i * _maxChunkSize;
      final end = min(start + _maxChunkSize, message.length);
      _sendBytes(endpointId, Cmd.chunk(transferId, i, total, false, message.substring(start, end)));
    }
  }


  void _floodChunked(String message, {String? excludeEndpointId}) {
    if (message.length <= _maxChunkSize) {
      _flood(message, excludeEndpointId: excludeEndpointId);
      return;
    }

    final transferId = _generateTransferId();
    final total = (message.length / _maxChunkSize).ceil();
    _addLog('Flooding chunked: ${message.length} bytes in $total chunks');

    for (int i = 0; i < total; i++) {
      final start = i * _maxChunkSize;
      final end = min(start + _maxChunkSize, message.length);
      _flood(Cmd.chunk(transferId, i, total, true, message.substring(start, end)), excludeEndpointId: excludeEndpointId);
    }
  }

  String? _handleChunkReceived(String transferId, int index, int total, String data) {
    _chunkBuffers.putIfAbsent(transferId, () => {});
    _chunkTotals[transferId] = total;
    _chunkBuffers[transferId]![index] = data;

    if (_chunkBuffers[transferId]!.length >= total) {
      final sorted = List.generate(total, (i) => _chunkBuffers[transferId]![i]!);
      final fullMessage = sorted.join();
      _chunkBuffers.remove(transferId);
      _chunkTotals.remove(transferId);
      _addLog('Chunk reassembly complete: ${fullMessage.length} bytes from $total chunks');
      return fullMessage;
    }
    return null;
  }

  // --------------------------------------------------------------------------
  // Incoming Bytes
  // --------------------------------------------------------------------------

  void _onBytesReceived(String endpointId, Uint8List bytes) {
    final message = String.fromCharCodes(bytes);

    if (Cmd.isChunk(message)) {
      final (transferId, index, total, flood, data) = Cmd.parseChunk(message);

      if (flood) {
        _flood(message, excludeEndpointId: endpointId);
      }

      final complete = _handleChunkReceived(transferId, index, total, data);
      if (complete != null) {
        // Flooded chunks were already forwarded, so pass no fromEndpointId
        // to prevent re-flooding the reassembled message
        if (flood) {
          _processMessage(complete);
        } else {
          _processMessage(complete, fromEndpointId: endpointId);
        }
      }
      return;
    }

    print('[$userName] recv from $endpointId: $message');

    if (Cmd.isRelay(message)) {
      _handleRelay(endpointId, message);
    } else {
      // Direct message from node
      _processMessage(message, fromEndpointId: endpointId);
    }
  }

  void _handleRelay(String fromEndpointId, String raw) {
    final (from, to, inner) = Cmd.parseRelay(raw);
    final bool forMe = to == userName || (to == Cmd.hostTarget && isHost);

    if (forMe) {
      _processMessage(inner, relaySender: from);
    } else if (to == Cmd.hostTarget) {
      _sendToParent(raw);
    } else {
      // Flood downward away from source
      _flood(raw, excludeEndpointId: fromEndpointId);
    }
  }

  /// Process a command.
  void _processMessage(String message, {String? fromEndpointId, String? relaySender}) {
    if (Cmd.isUsername(message)) {
      _handleUsername(message, fromEndpointId);
    } else if (Cmd.isBecomeHost(message)) {
      _handleBecomeHost(message);
    } else if (Cmd.isReportChild(message) && isHost) {
      final (parent, child) = Cmd.parseReportChild(message);
      _hostAddChild(parent, child);
    } else if (Cmd.isReportDisconnect(message) && isHost) {
      final (parent, child) = Cmd.parseReportDisconnect(message);
      _hostHandleDisconnect(parent, child);
    } else if (Cmd.isChat(message)) {
      _handleChat(message, fromEndpointId);
    } else if (Cmd.isPlayerList(message)) {
      _handlePlayerList(message, fromEndpointId);
    } else if (Cmd.isJoinRequest(message) && isHost) {
      _handleJoinRequest(message);
    } else if (Cmd.isPlayerAccept(message)) {
      _handlePlayerAccept(message, fromEndpointId);
    } else if (Cmd.isPlayerReject(message)) {
      _handlePlayerReject(message, fromEndpointId);
    } else if (Cmd.isRoleUpdate(message)) {
      _handleRoleUpdate(message, fromEndpointId);
    } else if (Cmd.isKick(message)) {
      _handleKick(message, fromEndpointId);
    } else if (Cmd.isPseudoConfirm(message) && isHost) {
      final name = Cmd.parsePseudoConfirm(message);
      _addLog('Pseudo-host confirmed: $name');
    } else if (Cmd.isPseudoFail(message) && isHost) {
      final name = Cmd.parsePseudoFail(message);
      _addLog('Pseudo-host failed: $name');
      _pseudoHosts.remove(name);
      _hostEnsureAdvertiser();
    } else if (Cmd.isPendingDisconnect(message) && isHost) {
      final joinerUser = Cmd.parsePendingDisconnect(message);
      setState(() => _pendingGamePlayers.removeWhere((p) => p.userName == joinerUser));
      _addLog('Pending player $joinerUser disconnected');
    } else if (Cmd.isGameMap(message)) {
      _handleGameMap(message, fromEndpointId);
    } else if (Cmd.isMapConfirmed(message) && isHost) {
      final confirmer = Cmd.parseMapConfirmed(message);
      _mapConfirmations.add(confirmer);
      _addLog('Map confirmed by $confirmer (${_mapConfirmations.length}/${_players.length})');
      _checkMapConfirmations();
    } else if (Cmd.isGameStarted(message)) {
      _handleGameStarted(message, fromEndpointId);
    } else {
      _addLog('Unknown message: $message');
    }
  }

  // --------------------------------------------------------------------------
  // Message Handlers
  // --------------------------------------------------------------------------

  void _handleUsername(String message, String? fromEndpointId) {
    final (user, display) = Cmd.parseUsername(message);
    if (fromEndpointId != null) {
      setState(() => connectedNames[fromEndpointId] = user);
    }

    // If this endpoint is the parent, ignore
    if (fromEndpointId == _parentEndpointId) return;

    // If this endpoint is already game-accepted, just update name
    if (fromEndpointId != null && !_localPendingEndpoints.containsKey(fromEndpointId)) {
      // New connection store as locally pending
      _localPendingEndpoints[fromEndpointId] =
          (userName: user, displayName: display);
      _addLog('$display ($user) connected, pending acceptance');

      // Send join request to host
      if (isHost) {
        setState(() {
          _pendingGamePlayers.add(OfflinePendingPlayer(
            userName: user,
            displayName: display,
            advertiserUserName: userName,
          ));
        });
        _addLog('$display wants to join');
      } else {
        // Relay to host
        _sendToHost(Cmd.joinRequest(userName, user, display));
      }
    }
  }

  void _handleBecomeHost(String message) {
    final lobby = Cmd.parseBecomeHost(message);
    _addLog('Promoted to pseudo-host for "$lobby"');
    _becomePseudoHost(lobby);
  }

  void _handleChat(String message, String? fromEndpointId) {
    final (playerId, playerName, text) = Cmd.parseChat(message);
    setState(() {
      _chatMessages['all'] ??= [];
      _chatMessages['all']!.add(ChatMessage(
        playerId: playerId,
        playerName: playerName,
        text: text,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        channel: 'all',
      ));
    });
    // Flood again to reach everyone in tree
    if (fromEndpointId != null) {
      _flood(message, excludeEndpointId: fromEndpointId);
    }
  }

  void _handlePlayerList(String message, String? fromEndpointId) {
    final players = Cmd.parsePlayerList(message);
    setState(() {
      _players.clear();
      _players.addAll(players);
    });
    // Flood again to reach everyone in tree
    if (fromEndpointId != null) {
      _flood(message, excludeEndpointId: fromEndpointId);
    }
  }

  void _handleJoinRequest(String message) {
    final (advertiser, joinerUser, joinerDisplay) = Cmd.parseJoinRequest(message);
    setState(() {
      _pendingGamePlayers.add(OfflinePendingPlayer(
        userName: joinerUser,
        displayName: joinerDisplay,
        advertiserUserName: advertiser,
      ));
    });
    _addLog('$joinerDisplay ($joinerUser) wants to join (at $advertiser)');
  }

  void _handlePlayerAccept(String message, String? fromEndpointId) {
    final joinerUserName = Cmd.parsePlayerAccept(message);

    // Check if this accept is for a pending player at my node
    final localEntry = _localPendingEndpoints.entries
        .where((e) => e.value.userName == joinerUserName)
        .firstOrNull;

    if (localEntry != null) {
      // I'm the advertiser, accept the player
      final endpointId = localEntry.key;
      final info = localEntry.value;
      _localPendingEndpoints.remove(endpointId);

      // Send accept directly to the joiner
      _sendDirect(endpointId, Cmd.playerAccept(joinerUserName));

      // Send current player list
      _sendDirect(endpointId, Cmd.playerList(_players));

      // Report child to host
      _sendToHost(Cmd.reportChild(userName, joinerUserName));

      _addLog('Accepted ${info.displayName} locally, reported to host');
      return;
    }

    // If I'm the joiner being accepted
    if (joinerUserName == userName) {
      setState(() {
        _pendingAcceptance = false;
        _inLobby = true;
      });
      _addLog('Accepted into game!');
      return;
    }

    // Flood network
    if (fromEndpointId != null) {
      _flood(message, excludeEndpointId: fromEndpointId);
    }
  }

  void _handlePlayerReject(String message, String? fromEndpointId) {
    final (joinerUserName, reason) = Cmd.parsePlayerReject(message);

    // Check if this reject is for a pending player at my node
    final localEntry = _localPendingEndpoints.entries
        .where((e) => e.value.userName == joinerUserName)
        .firstOrNull;

    if (localEntry != null) {
      final endpointId = localEntry.key;
      _localPendingEndpoints.remove(endpointId);

      // Notify and disconnect
      _sendDirect(endpointId, Cmd.playerReject(joinerUserName, reason));

      Future.delayed(const Duration(milliseconds: 200), () {
        Nearby().disconnectFromEndpoint(endpointId);
      });

      _addLog('Rejected ${localEntry.value.displayName}, disconnecting');
      _checkReAdvertise();
      return;
    }

    // If I'm the joiner being rejected
    if (joinerUserName == userName) {
      _addLog('Rejected: $reason');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(reason)));
        Navigator.popUntil(context, (route) => route.isFirst);
      }
      return;
    }

    // Flood network
    if (fromEndpointId != null) {
      _flood(message, excludeEndpointId: fromEndpointId);
    }
  }

  void _handleRoleUpdate(String message, String? fromEndpointId) {
    final (playerId, role) = Cmd.parseRoleUpdate(message);
    setState(() {
      final player = _players.where((p) => p.id == playerId).firstOrNull;
      if (player != null) player.role = role;
    });
    _addLog('${_players.where((p) => p.id == playerId).firstOrNull?.name ?? playerId} is now $role');
    if (fromEndpointId != null) {
      _flood(message, excludeEndpointId: fromEndpointId);
    }
  }

  void _handleKick(String message, String? fromEndpointId) {
    final playerId = Cmd.parseKick(message);

    // Am I being kicked
    if (playerId == userName) {
      _addLog('Kicked from game');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You have been kicked by the host')));
        Navigator.popUntil(context, (route) => route.isFirst);
      }
      return;
    }

    // Remove from player list
    setState(() => _players.removeWhere((p) => p.id == playerId));

    // If the kicked player is connected to me, disconnect them
    final entry = connectedNames.entries
        .where((e) => e.value == playerId)
        .firstOrNull;
    if (entry != null) {
      Nearby().disconnectFromEndpoint(entry.key);
    }

    if (fromEndpointId != null) {
      _flood(message, excludeEndpointId: fromEndpointId);
    }
  }

  void _handleGameMap(String message, String? fromEndpointId) {
    try {
      final payload = Cmd.parseGameMap(message);
      _receivedMap = MapFile.fromJson(payload['map']);
      _activeFaceOrder = List<int>.from(payload['faceOrder']);
      _activeClosureIntervalMs = payload['closureIntervalMs'];
      _activeGracePeriodMs = payload['gracePeriodMs'];
      _addLog('Map received and stored');

      // Confirm to host
      _sendToHost(Cmd.mapConfirmed(userName));

      // Forward to rest of network
      if (fromEndpointId != null) {
        _flood(message, excludeEndpointId: fromEndpointId);
      }
    } catch (e) {
      _addLog('ERROR: Failed to parse map: $e');
    }
  }

  void _handleGameStarted(String message, String? fromEndpointId) {
    final startedAtMs = Cmd.parseGameStarted(message);
    _addLog('Game started signal received');

    // Forward first
    if (fromEndpointId != null) {
      _flood(message, excludeEndpointId: fromEndpointId);
    }

    if (_receivedMap == null) {
      _addLog('ERROR: No map data when game started');
      return;
    }

    _gameStartedAt = DateTime.fromMillisecondsSinceEpoch(startedAtMs);
    setState(() {
      _gameStarted = true;
      _isStarting = false;
    });

    // Disconnect from network after a short delay
    Future.delayed(const Duration(milliseconds: 300), () {
      _isDisconnectingAll = true;
      Nearby().stopAdvertising();
      Nearby().stopDiscovery();
      Nearby().stopAllEndpoints();
      _isDisconnectingAll = false;
      setState(() {
        _isAdvertising = false;
        _isDiscovering = false;
        endpointMap.clear();
        connectedNames.clear();
        discoveredEndpoints.clear();
        _localPendingEndpoints.clear();
      });
    });

    _beginActiveGame();
  }

  // --------------------------------------------------------------------------
  // Host, Player Acceptance
  // --------------------------------------------------------------------------
      
  void _hostAcceptPlayer(String joinerUserName) {
    final pending = _pendingGamePlayers
        .where((p) => p.userName == joinerUserName)
        .firstOrNull;
    if (pending == null) return;

    setState(() => _pendingGamePlayers.removeWhere((p) => p.userName == joinerUserName));

    if (pending.advertiserUserName == userName) {
      // Player is directly connected to host
      final localEntry = _localPendingEndpoints.entries
          .where((e) => e.value.userName == joinerUserName)
          .firstOrNull;
      if (localEntry != null) {
        final endpointId = localEntry.key;
        _localPendingEndpoints.remove(endpointId);

        // Send accept
        _sendDirect(endpointId, Cmd.playerAccept(joinerUserName));

        // Add with correct display name
        _players.add(PlayerData(
          id: joinerUserName,
          name: pending.displayName,
          role: 'runner',
        ));

        // Add to tree
        _hostAddChild(userName, joinerUserName);

        // Send player list
        _sendDirect(endpointId, Cmd.playerList(_players));
      }
    } else {
      // Player is at a remote advertiser, relay accept
      _sendToDevice(pending.advertiserUserName, Cmd.playerAccept(joinerUserName));

      // Add player to local list immediately (tree update comes via REPORT_CHILD)
      _players.add(PlayerData(
        id: joinerUserName,
        name: pending.displayName,
        role: 'runner',
      ));
    }

    _addLog('Accepted ${pending.displayName}');
  }

  void _hostRejectPlayer(String joinerUserName) {
    final pending = _pendingGamePlayers
        .where((p) => p.userName == joinerUserName)
        .firstOrNull;
    if (pending == null) return;

    setState(() => _pendingGamePlayers.removeWhere((p) => p.userName == joinerUserName));

    const reason = 'Host rejected your join request';

    if (pending.advertiserUserName == userName) {
      // Directly connected
      final localEntry = _localPendingEndpoints.entries
          .where((e) => e.value.userName == joinerUserName)
          .firstOrNull;
      if (localEntry != null) {
        _localPendingEndpoints.remove(localEntry.key);
        _sendDirect(localEntry.key, Cmd.playerReject(joinerUserName, reason));
        Future.delayed(const Duration(milliseconds: 200), () {
          Nearby().disconnectFromEndpoint(localEntry.key);
        });
        _checkReAdvertise();
      }
    } else {
      _sendToDevice(pending.advertiserUserName, Cmd.playerReject(joinerUserName, reason));
    }

    _addLog('Rejected ${pending.displayName}');
  }

  // --------------------------------------------------------------------------
  // Host, Roles
  // --------------------------------------------------------------------------

  void _hostSwitchRole(String playerId) {
    if (playerId == userName) return; // can't change host role

    final player = _players.where((p) => p.id == playerId).firstOrNull;
    if (player == null) return;

    final newRole = player.role == 'runner' ? 'chaser' : 'runner';
    setState(() => player.role = newRole);

    // Flood to network
    _flood(Cmd.roleUpdate(playerId, newRole));
    _addLog('${player.name} switched to $newRole');
  }

  // --------------------------------------------------------------------------
  // Host, Kick
  // --------------------------------------------------------------------------

  Future<void> _hostKickPlayer(String playerId) async {
    if (playerId == userName) return;
    final player = _players.where((p) => p.id == playerId).firstOrNull;
    if (player == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kick player?'),
        content: Text('Are you sure you want to kick ${player.name}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Kick')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _players.removeWhere((p) => p.id == playerId));

    // Remove from tree
    _removeSubtree(playerId);
    for (final children in _tree.values) {
      children.remove(playerId);
    }

    // Flood kick command
    _flood(Cmd.kick(playerId));

    // Disconnect if directly connected
    final entry = connectedNames.entries.where((e) => e.value == playerId).firstOrNull;
    if (entry != null) {
      Nearby().disconnectFromEndpoint(entry.key);
    }

    _broadcastPlayerList();
    _addLog('Kicked ${player.name}');
  }

  // --------------------------------------------------------------------------
  //  Host, Topology
  // --------------------------------------------------------------------------

  void _hostAddChild(String parentName, String childName) {
    _tree.putIfAbsent(parentName, () => []);
    _tree[parentName]!.add(childName);
    _tree.putIfAbsent(childName, () => []);
    print('[$userName] topology add: $parentName -> $childName');

    // Ensure player is in the list with correct display name
    if (!_players.any((p) => p.id == childName)) {
      // Check connections for display name
      String displayName = childName;
      for (final entry in _localPendingEndpoints.entries) {
        if (entry.value.userName == childName) {
          displayName = entry.value.displayName;
          break;
        }
      }
      // Also check pending game players
      final pending = _pendingGamePlayers
          .where((p) => p.userName == childName)
          .firstOrNull;
      if (pending != null) displayName = pending.displayName;

      _players.add(PlayerData(id: childName, name: displayName, role: 'runner'));
    }

    _broadcastPlayerList();
    setState(() {}); // refresh topology UI

    // Check if the parent is now at capacity, if so, find next promotion target
    if (_tree[parentName]!.length >= maxConnections) {
      _pseudoHosts.add(parentName);
      _addLog("$parentName is now full. Finding next promotion target…");

      final target = _findClosestNonPseudo();
      if (target == null) {
        _addLog("Network is full, no promotion target.");
        return;
      }
      
      _addLog("Promoting $target to pseudo-host");
      _pseudoHosts.add(target);
      _sendToDevice(target, Cmd.becomeHost(_lobbyName));
    }
  }

  /// Called by the host when a child disconnects from any node in the tree.
  void _hostHandleDisconnect(String parentName, String childName) {
    _addLog("$childName disconnected from $parentName");

    // Remove the child and its subtree from the tree
    final removed = _removeSubtree(childName);
    // Remove the child from the parent's children list
    _tree[parentName]?.remove(childName);

    // Clear pseudo-host status for all removed nodes
    for (final node in removed) {
      _pseudoHosts.remove(node);
    }

    // Remove from players
    setState(() {
      _players.removeWhere((p) => removed.contains(p.id));
      _pendingGamePlayers.removeWhere((p) => removed.contains(p.advertiserUserName));
    });

    print('[$userName] topology after disconnect: $_tree');
    print('[$userName] pseudoHosts after disconnect: $_pseudoHosts');
    _broadcastPlayerList();

    // Check if someone needs to be advertising.
    // If nobody is currently a non-full pseudo-host (which is not
    // advertising), we need to promote someone.
    _hostEnsureAdvertiser();
  }

  /// Called by the host when one of its OWN direct children disconnects.
  void _hostHandleOwnDisconnect(String childName) {
    _hostHandleDisconnect(userName, childName);
  }

  /// Remove a node and everything below it from the tree. Returns the set
  /// of all removed userNames (including the root node).
  Set<String> _removeSubtree(String root) {
    final removed = <String>{};
    final queue = Queue<String>();
    queue.add(root);

    while (queue.isNotEmpty) {
      final node = queue.removeFirst();
      removed.add(node);
      for (final child in _tree[node] ?? <String>[]) {
        queue.add(child);
      }
      _tree.remove(node);
    }

    return removed;
  }

  /// Make sure exactly one device is advertising. If nobody below capacity
  /// exists in the pseudo-host set, find the closest non-pseudo and promote.
  void _hostEnsureAdvertiser() {
    // Check if the host itself is below capacity
    if ((_tree[userName]?.length ?? 0) < maxConnections) {
      if (!_isAdvertising && isHost) {
        _addLog("Host has capacity again, re-advertising");
        _startAdvertising();
      }
      return;
    }

    // Host is full. Check if any existing pseudo-host is below capacity
    for (final ph in _pseudoHosts) {
      if (ph == userName) continue;
      if ((_tree[ph]?.length ?? 0) < maxConnections) {
        // This pseudo-host should be advertising already.
        return;
      }
    }

    // Everyone is full or gone, find a new pseudohost for promotion.
    final target = _findClosestNonPseudo();
    if (target == null) {
      _addLog("Network is full, no promotion target.");
      return;
    }

    _addLog("Promoting $target to pseudo-host (post-disconnect)");
    _pseudoHosts.add(target);
    _sendToDevice(target, Cmd.becomeHost(_lobbyName));
  }

  /// Breadth First Search to find the closest userName that is not in [_pseudoHosts].
  String? _findClosestNonPseudo() {
    final queue = Queue<String>();
    final visited = <String>{userName};
    queue.add(userName);

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      for (final child in _tree[current] ?? <String>[]) {
        if (visited.contains(child)) continue;
        visited.add(child);
        if (!_pseudoHosts.contains(child)) return child;
        queue.add(child);
      }
    }
    return null;
  }

  void _broadcastPlayerList() {
    // Sync tree with player list
    for (final node in _tree.keys) {
      if (!_players.any((p) => p.id == node)) {
        _players.add(PlayerData(id: node, name: node, role: 'runner'));
      }
    }
    _players.removeWhere((p) => !_tree.containsKey(p.id) && p.id != userName);

    // Mark host
    for (final p in _players) {
      p.isHost = (p.id == userName && isHost);
    }

    final msg = Cmd.playerList(_players);
    _flood(msg);
    setState(() {});
  }

  // --------------------------------------------------------------------------
  //  Chat
  // --------------------------------------------------------------------------

  void _sendChatMessage(String text) {
    if (text.isEmpty) return;
    final msg = Cmd.chat(userName, displayName, text);
    setState(() {
      _chatMessages['all'] ??= [];
      _chatMessages['all']!.add(ChatMessage(
        playerId: userName,
        playerName: displayName,
        text: text,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        channel: 'all',
      ));
    });
    _flood(msg);
  }

  // --------------------------------------------------------------------------
  //  Replay Exchange, Connections
  // --------------------------------------------------------------------------

  void _replayOnConnectionInit(String id, ConnectionInfo info) {
    print('[$userName] replay onConnectionInit id=$id name=${info.endpointName}');

    Nearby().acceptConnection(
      id,
      onPayLoadRecieved: (endpointId, payload) async {
        if (payload.type == PayloadType.BYTES && payload.bytes != null) {
          _replayOnBytesReceived(endpointId, payload.bytes!);
        }
      },
      onPayloadTransferUpdate: (_, __) {},
    );
  }

  void _replayOnConnectionResult(String id, Status status) {
    _addLog('Replay exchange connection result $id: $status');

    if (status != Status.CONNECTED) {
      _replayConnectedNames.remove(id);
      return;
    }

    // Exchange identity
    _sendBytes(id, Cmd.username(userName, displayName));

    // Non-host: if connected during collection phase, send replay
    if (!isHost && _replayExchangeActive && !_individualReplaySent && _replay != null) {
      // Wait briefly for username exchange then send
      Future.delayed(const Duration(milliseconds: 300), () {
        final msg = Cmd.replayData(userName, _replay!.toJson());
        _addLog('Replay data size: ${msg.length} bytes');
        _sendChunked(id, msg);
        _addLog('Sending replay to host...');
      });
    }
  }

  void _replayOnDisconnected(String id) {
    final name = _replayConnectedNames.remove(id) ?? id;
    _addLog('Replay exchange disconnected: $name');
    _replayCheckReAdvertise();
  }

  void _replayOnBytesReceived(String endpointId, Uint8List bytes) {
    final message = String.fromCharCodes(bytes);

    if (Cmd.isChunk(message)) {
      final (transferId, index, total, _, data) = Cmd.parseChunk(message);
      final complete = _handleChunkReceived(transferId, index, total, data);
      if (complete != null) {
        _replayOnBytesReceived(endpointId, Uint8List.fromList(complete.codeUnits));
      }
      return;
    }

    if (Cmd.isUsername(message)) {
      final (user, display) = Cmd.parseUsername(message);
      _replayConnectedNames[endpointId] = user;
      _addLog('Replay exchange: $display ($user) identified');

      // Host in distribution phase: send assembled file immediately
      if (isHost && _distributingReplay && _offlineAssembledReplayJson != null) {
        if (!_distributedTo.contains(user)) {
          _addLog('Sending assembled replay to $display...');
          _sendChunked(endpointId, Cmd.replayFileData(_offlineAssembledReplayJson!));
        } else {
          // Already distributed, disconnect
          _addLog('$display already has the replay, disconnecting');
          Future.delayed(const Duration(milliseconds: 200), () {
            Nearby().disconnectFromEndpoint(endpointId);
          });
        }
      }
      return;
    }

    if (Cmd.isReplayData(message) && isHost && _collectingReplays) {
      final parsed = Cmd.parseReplayData(message);
      final senderName = parsed['userName'] as String;
      final replayJson = parsed['replay'] as Map<String, dynamic>;

      setState(() => _collectedReplays[senderName] = replayJson);
      _addLog('Received replay from $senderName (${_collectedReplays.length + 1}/${_players.length})');

      // Ack and disconnect
      _sendBytes(endpointId, Cmd.replayAck(userName));
      Future.delayed(const Duration(milliseconds: 300), () {
        Nearby().disconnectFromEndpoint(endpointId);
      });

      // +1 for host's own replay
      if (_collectedReplays.length + 1 >= _players.length) {
        _addLog('All replays collected!');
        _assembleAndDistributeOffline();
      }
      return;
    }

    if (Cmd.isReplayAck(message) && !isHost) {
      setState(() => _individualReplaySent = true);
      _addLog('Host acknowledged replay receipt');

      // Disconnect, then rediscover for distribution phase
      Future.delayed(const Duration(milliseconds: 300), () {
        Nearby().disconnectFromEndpoint(endpointId);
      });

      // Wait then start discovering again for the distribution phase
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && !_assembledReplayReceived) {
          _addLog('Rediscovering for distribution phase...');
          _startReplayDiscovery();
        }
      });
      return;
    }

    if (Cmd.isReplayFileData(message) && !isHost) {
      final replayFileJson = Cmd.parseReplayFileData(message);
      _addLog('Received assembled replay file');

      // Ack
      _sendBytes(endpointId, Cmd.replayFileAck(userName));

      // Save
      _saveReceivedOfflineReplayFile(replayFileJson);

      Future.delayed(const Duration(milliseconds: 300), () {
        Nearby().disconnectFromEndpoint(endpointId);
        Nearby().stopDiscovery();
        setState(() => _isDiscovering = false);
      });
      return;
    }

    if (Cmd.isReplayFileAck(message) && isHost && _distributingReplay) {
      final senderName = _replayConnectedNames[endpointId] ?? 'unknown';
      setState(() => _distributedTo.add(senderName));
      _addLog('$senderName confirmed replay receipt (${_distributedTo.length}/${_players.length - 1})');

      Future.delayed(const Duration(milliseconds: 200), () {
        Nearby().disconnectFromEndpoint(endpointId);
      });

      // Check if all non-hosts received it
      if (_distributedTo.length >= _players.length - 1) {
        _addLog('All players received the assembled replay');
        _stopReplayAdvertising();
      }
      return;
    }
  }

  // --------------------------------------------------------------------------
  //  Replay Exchange, Logic
  // --------------------------------------------------------------------------

  Future<void> _startCollecting() async {
    // Add host's own replay
    if (_replay != null) {
      _collectedReplays[userName] = _replay!.toJson();
    }

    setState(() => _collectingReplays = true);

    // Check if host already has all replays
    if (_collectedReplays.length >= _players.length) {
      _assembleAndDistributeOffline();
      return;
    }

    await _startReplayAdvertising('COLLECT:$_lobbyName');
    _addLog('Collecting replays... advertising as COLLECT:$_lobbyName');
  }

  Future<void> _assembleAndDistributeOffline() async {
    _addLog('Assembling replay...');
    await _stopReplayAdvertising();

    if (_receivedMap == null) {
      _addLog('ERROR: No map data for replay assembly');
      return;
    }

    final Map<int, double> zoneClosings = {};
    for (int i = 0; i < _activeFaceOrder.length; i++) {
      final closingTimeMs = _activeGracePeriodMs + ((i + 1) * _activeClosureIntervalMs);
      zoneClosings[_activeFaceOrder[i]] = closingTimeMs / 1000.0;
    }

    final List<Replay> replays = [];
    for (final entry in _collectedReplays.entries) {
      try {
        replays.add(Replay.fromJson(entry.value));
      } catch (e) {
        _addLog('WARNING: Failed to parse replay from ${entry.key}: $e');
      }
    }

    try {
      final replayFile = await ReplayFile.create(
        map: _receivedMap!,
        replays: replays,
        zoneClosings: zoneClosings,
      );
      await replayFile.saveReplayFile();
      await _receivedMap!.saveMapFile();
      _offlineAssembledReplayJson = replayFile.toJson();
      _addLog('Replay assembled and saved: ${replayFile.replayName}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Replay saved: ${replayFile.replayName}')),
        );
      }
    } catch (e) {
      _addLog('ERROR: Failed to assemble replay: $e');
      return;
    }

    // Start distributing
    _startDistributing();
  }

  Future<void> _sendAssembledNow() async {
    await _stopReplayAdvertising();
    await _assembleAndDistributeOffline();
  }

  Future<void> _startDistributing() async {
    setState(() {
      _collectingReplays = false;
      _distributingReplay = true;
    });

    // If only host is playing, no one to distribute to
    if (_players.length <= 1) {
      _addLog('No other players to distribute to');
      setState(() => _distributingReplay = false);
      return;
    }

    await _startReplayAdvertising('DISTRIBUTE:$_lobbyName');
    _addLog('Distributing replay... advertising as DISTRIBUTE:$_lobbyName');
  }

  void _startReplayExchange() {
    setState(() => _replayExchangeActive = true);
    _startReplayDiscovery();
    _addLog('Looking for host...');
  }

  Future<void> _startReplayDiscovery() async {
    try {
      await Nearby().stopDiscovery();
      final a = await Nearby().startDiscovery(
        userName,
        strategy,
        onEndpointFound: (id, name, serviceId) {
          // Only connect to our lobby's collection or distribution
          if (name == 'COLLECT:$_lobbyName' || name == 'DISTRIBUTE:$_lobbyName') {
            _addLog('Found host: $name');
            Nearby().stopDiscovery();
            setState(() => _isDiscovering = false);
            Nearby().requestConnection(
              userName,
              id,
              onConnectionInitiated: _replayOnConnectionInit,
              onConnectionResult: (id, status) => _replayOnConnectionResult(id, status),
              onDisconnected: (id) => _replayOnDisconnected(id),
            );
          }
        },
        onEndpointLost: (_) {},
      );
      setState(() => _isDiscovering = a);
    } catch (e) {
      _addLog('Replay discovery failed: $e');
    }
  }

  Future<void> _startReplayAdvertising(String name) async {
    try {
      await Nearby().stopAdvertising();
      final a = await Nearby().startAdvertising(
        name,
        strategy,
        onConnectionInitiated: _replayOnConnectionInit,
        onConnectionResult: (id, status) => _replayOnConnectionResult(id, status),
        onDisconnected: (id) => _replayOnDisconnected(id),
      );
      setState(() => _replayAdvertising = a);
      _addLog('Replay advertising: $name');
    } catch (e) {
      _addLog('Replay advertising failed: $e');
    }
  }

  Future<void> _stopReplayAdvertising() async {
    await Nearby().stopAdvertising();
    setState(() => _replayAdvertising = false);
  }

  void _replayCheckReAdvertise() {
    if (!_replayAdvertising && (_collectingReplays || _distributingReplay)) {
      final phase = _collectingReplays ? 'COLLECT' : 'DISTRIBUTE';
      _startReplayAdvertising('$phase:$_lobbyName');
    }
  }

  Future<void> _saveReceivedOfflineReplayFile(Map<String, dynamic> json) async {
    try {
      final replayFile = ReplayFile.fromJson(json);
      await replayFile.saveReplayFile();
      if (_receivedMap != null) {
        await _receivedMap!.saveMapFile();
      }
      setState(() => _assembledReplayReceived = true);
      _addLog('Replay saved: ${replayFile.replayName}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Replay saved: ${replayFile.replayName}')),
        );
      }
    } catch (e) {
      _addLog('ERROR: Failed to save received replay: $e');
    }
  }

  // --------------------------------------------------------------------------
  // Pseudo-Host
  // --------------------------------------------------------------------------

  Future<void> _becomePseudoHost(String lobbyName) async {
    setState(() {
      _isPseudoHost = true;
      _lobbyName = lobbyName;
    });

    try {
      final a = await Nearby().startAdvertising(
        lobbyName,
        strategy,
        onConnectionInitiated: _onConnectionInit,
        onConnectionResult: (id, status) => _onConnectionResult(id, status),
        onDisconnected: (id) => _onDisconnected(id),
      );
      setState(() => _isAdvertising = a);
      _addLog("Pseudo-host advertising '$lobbyName': $a");
      _sendToHost(Cmd.pseudoConfirm(userName));
    } catch (e) {
      _addLog("Pseudo-host advertising failed: $e");
      _sendToHost(Cmd.pseudoFail(userName));
    }
  }

  /// Revert from pseudo-host back to a regular joiner.
  Future<void> _revertToJoiner() async {
    _addLog("Parent disconnected, reverting to joiner");

    _isDisconnectingAll = true;
    await Nearby().stopAdvertising();
    await Nearby().stopAllEndpoints();
    _isDisconnectingAll = false;

    setState(() {
      _isPseudoHost = false;
      _isAdvertising = false;
      _isDiscovering = false;
      _parentEndpointId = null;
      _lobbyName = '';
      endpointMap.clear();
      connectedNames.clear();
      discoveredEndpoints.clear();
      _localPendingEndpoints.clear();
      _players.clear();
      _inLobby = false;
      _pendingAcceptance = false;
    });

    // Restart discovery to find a new lobby
    _startDiscovery();
  }

  // --------------------------------------------------------------------------
  //  Capacity management
  // --------------------------------------------------------------------------

  void _checkStopAdvertising() {
    if (_childConnectionCount >= maxConnections && _isAdvertising) {
      _addLog('At capacity ($_childConnectionCount/$maxConnections), stopping advertising');
      _stopAdvertising();
    }
  }

  void _checkReAdvertise() {
    if (_childConnectionCount < maxConnections && !_isAdvertising && amHost) {
      _addLog('Slot freed, re-advertising');
      _startAdvertising();
    }
  }

  // --------------------------------------------------------------------------
  //  Advertising/Discovery
  // --------------------------------------------------------------------------

  Future<void> _startAdvertising() async {
    try {
      await Nearby().stopAdvertising();
      final a = await Nearby().startAdvertising(
        _lobbyName,
        strategy,
        onConnectionInitiated: _onConnectionInit,
        onConnectionResult: (id, status) => _onConnectionResult(id, status),
        onDisconnected: (id) => _onDisconnected(id),
      );
      setState(() => _isAdvertising = a);
      _addLog("Advertising '$_lobbyName'");
    } catch (e) {
      _addLog("Advertising failed: $e");
    }
  }

  Future<void> _stopAdvertising() async {
    await Nearby().stopAdvertising();
    setState(() => _isAdvertising = false);
  }

  Future<void> _startDiscovery() async {
    try {
      final a = await Nearby().startDiscovery(
        userName,
        strategy,
        onEndpointFound: (id, name, serviceId) {
          setState(() {
            // Remove any existing endpoint with the same lobby name,
            // only one device advertises per lobby at a time, so the
            // old one is stale (pseudo-host took over).
            discoveredEndpoints.removeWhere((_, ep) => ep.name == name);
            discoveredEndpoints[id] = DiscoveredEndpoint(
                id: id, name: name, serviceId: serviceId);
          });
        },
        onEndpointLost: (id) {
          setState(() => discoveredEndpoints.remove(id));
        },
      );
      setState(() => _isDiscovering = a);
      _addLog("Discovering lobbies…");
    } catch (e) {
      _addLog("Discovery failed: $e");
    }
  }

  Future<void> _stopDiscovery() async {
    await Nearby().stopDiscovery();
    setState(() {
      _isDiscovering = false;
      discoveredEndpoints.clear();
    });
  }

  /// User tapped a lobby in the list.
  void _joinLobby(DiscoveredEndpoint endpoint) {
    _addLog("Requesting to join '${endpoint.name}'…");
    Nearby().requestConnection(
      userName, // the advertiser sees this as our endpointName
      endpoint.id,
      onConnectionInitiated: _onConnectionInit,
      onConnectionResult: (id, status) => _onConnectionResult(id, status),
      onDisconnected: (id) => _onDisconnected(id),
    );
  }

  // --------------------------------------------------------------------------
  //  Connection lifecycle
  // --------------------------------------------------------------------------

  /// Both sides auto-accept.
  void _onConnectionInit(String id, ConnectionInfo info) {
    print('[$userName] onConnectionInit id=$id name=${info.endpointName}');

    setState(() {
      endpointMap[id] = info;
      // info.endpointName is the userName for joiners, or lobbyName for host
      connectedNames[id] = info.endpointName;
    });

    Nearby().acceptConnection(
      id,
      onPayLoadRecieved: (endpointId, payload) async {
        if (payload.type == PayloadType.BYTES && payload.bytes != null) {
          _onBytesReceived(endpointId, payload.bytes!);
        }
      },
      onPayloadTransferUpdate: (endpointId, update) {
        if (update.status == PayloadStatus.FAILURE) {
          print('Payload transfer failed from $endpointId');
        }
      },
    );
  }

  /// Once both sides have accepted, The channel is live.
  void _onConnectionResult(String id, Status status) {
    _addLog("Connection result $id: $status");

    if (status != Status.CONNECTED) {
      setState(() {
        endpointMap.remove(id);
        connectedNames.remove(id);
      });

      // Refresh discovery list
      if (!amHost) {
        setState(() => discoveredEndpoints.clear());
      }
      return;
    }

    // Exchange user and display names.
    _sendBytes(id, Cmd.username(userName, displayName));

    // Joiner successfully connected, stop discovering and clear the list
    if (!amHost) {
      _parentEndpointId = id;
      setState(() => _pendingAcceptance = true);
      _stopDiscovery();
      return;
    }

    // Check capacity locally, stop advertising if full
    _checkStopAdvertising();
  }


  void _onDisconnected(String id) {
    // If we're intentionally disconnecting everything, don't react.
    if (_isDisconnectingAll) return;

    final disconnectedName = connectedNames[id] ?? id;
    _addLog("Disconnected: $disconnectedName");

    // Check if this was a pending player at my node
    final wasPending = _localPendingEndpoints.containsKey(id);
    if (wasPending) {
      final info = _localPendingEndpoints.remove(id)!;
      if (isHost) {
        setState(() => _pendingGamePlayers
          .removeWhere((p) => p.userName == info.userName));
      } else {
        _sendToHost(Cmd.pendingDisconnect(info.userName));
      }
      _addLog('Pending player ${info.displayName} disconnected');
    }

    setState(() {
      endpointMap.remove(id);
      connectedNames.remove(id);
    });

    // Pseudo-host: check if it was our parent that disconnected
    if (_isPseudoHost && id == _parentEndpointId) {
      if (_gameStarted || _receivedMap != null) {
        _addLog("Parent disconnected (game active, ignoring)");
        setState(() {
          endpointMap.clear();
          connectedNames.clear();
        });
        return;
      }
      _revertToJoiner();
      return;
    }

    // Host: direct child disconnected 
    if (isHost && !wasPending) {
      if (_gameStarted || _receivedMap != null) {
        _addLog("Child disconnected (game active, ignoring)");
        return;
      }
      _hostHandleOwnDisconnect(disconnectedName);
      return;
    }

    // Pseudo-host: one of our game-accepted children disconnected 
    if (_isPseudoHost && !wasPending && id != _parentEndpointId) {
      // Tell the host so it can update the tree.
      _sendToHost(Cmd.reportDisconnect(userName, disconnectedName));
    }

    //  Joiner: lost connection to parent, restart discovery
    if (!amHost && id == _parentEndpointId) {
      _addLog("Lost connection to host, restarting discovery");
      setState(() {
        _parentEndpointId = null;
        _players.clear();
        _inLobby = false;
        _pendingAcceptance = false;
      });
      _startDiscovery();
      return;
    }

    _checkReAdvertise();
  }

  // --------------------------------------------------------------------------
  //  UI Builders
  // --------------------------------------------------------------------------

  Widget _buildGameTab(BuildContext context) {
    // Joiner: not yet connected or pending
    if (!isHost && !_inLobby && !_gameStarted) {
      if (_pendingAcceptance) {
        return _buildPendingView();
      }
      return _buildDiscoveryView();
    }

    if (_gameStarted) return _buildActiveGameTab(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        _buildLobbyTopSection(context),
        const SizedBox(height: 8),
        Expanded(
          child: DefaultTabController(
            length: isHost ? 4 : 3,
            child: Column(children: [
              TabBar(tabs: [
                const Tab(text: 'Rules'),
                const Tab(text: 'Players'),
                if (isHost) const Tab(text: 'Tree'),
                const Tab(text: 'Logs'),
              ]),
              Expanded(
                child: TabBarView(children: [
                  _buildLobbyRulesSubTab(),
                  _buildPlayersSubTab(),
                  if (isHost) _buildTopologySubTab(),
                  _buildLogsSubTab(),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildActiveGameTab(BuildContext context) {
    return Stack(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          _buildActiveTopSection(context),
          const SizedBox(height: 8),
          Expanded(
            child: DefaultTabController(
              length: 3,
              child: Column(children: [
                const TabBar(tabs: [
                  Tab(text: 'Rules'), 
                  Tab(text: 'Players'),
                  Tab(text: 'Logs'),
                ]),
                Expanded(
                  child: TabBarView(children: [
                    _buildRulesSubTab(), 
                    _buildPlayersSubTab(),
                    _buildLogsSubTab(),
                  ]),
                ),
              ]),
            ),
          ),
        ]),
      ),
      if (_gameFinished)
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confettiController,
            blastDirectionality: BlastDirectionality.explosive,
            shouldLoop: false,
            numberOfParticles: 15,
            maxBlastForce: 12,
            minBlastForce: 3,
            emissionFrequency: 0.03,
            gravity: 0.2,
          ),
        ),
    ]);
  }

  Widget _buildPendingView() {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Waiting for host to accept...'),
        ]),
      ),
    );
  }

  Widget _buildDiscoveryView() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isDiscovering && discoveredEndpoints.isEmpty)
            const Center(
              child: Column(children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Searching for lobbies…'),
              ]),
            ),
          if (discoveredEndpoints.isNotEmpty) ...[
            Text('Available Lobbies',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...discoveredEndpoints.values.map((ep) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.wifi_tethering),
                    title: Text(ep.name),
                    trailing: FilledButton(
                        onPressed: () => _joinLobby(ep),
                        child: const Text('Join')),
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildLobbyTopSection(BuildContext context) {
    return Column(children: [
      if (_lobbyName.isNotEmpty) ...[
        Text('Lobby',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        Text(_lobbyName,
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.bold, letterSpacing: 2)),
      ],
      const SizedBox(height: 8),
      Text(
          '${_players.length} player${_players.length == 1 ? '' : 's'} connected',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
      if (amHost) ...[
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(
            'Capacity ($_childConnectionCount/$maxConnections)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.cell_tower,
            size: 16,
            color: _isAdvertising
                ? Theme.of(context).colorScheme.primary
                : Colors.grey,
          ),
          const SizedBox(width: 4),
          Text(
            _isAdvertising ? 'Advertising' : 'Not Advertising',
            style: TextStyle(
              fontSize: 12,
              color: _isAdvertising
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey,
            ),
          ),
        ]),
        if (_isPseudoHost)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Pseudo-host',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary,
                    fontStyle: FontStyle.italic)),
          ),
      ],
      if (isHost) ...[
        const SizedBox(height: 16),
        if (_selectedMap == null && !_isStarting)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Select a map in the Map tab to start',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        if (!_players.any((p) => p.role == 'runner') && !_isStarting)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('At least one Runner is required to start',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        _isStarting
            ? const Row(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(strokeWidth: 2),
                SizedBox(width: 12),
                Text('Starting game...'),
              ])
            : SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start Game'),
                  onPressed: (_selectedMap == null ||
                          _faceOrder == null ||
                          !_players.any((p) => p.role == 'runner'))
                      ? null
                      : _hostStartGame,
                )),
      ],
    ]);
  }

  Widget _buildActiveTopSection(BuildContext context) {
if (_gameFinished) {
      return Column(children: [
        Text('Game Ended',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.amber.shade700, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        if (isHost) ...[
          if (!_collectingReplays && !_distributingReplay && _offlineAssembledReplayJson == null)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                icon: const Icon(Icons.download),
                label: const Text('Collect and Assemble Replay Data'),
                onPressed: _startCollecting,
              ),
            ),
          if (_collectingReplays && _collectedReplays.length + 1 < _players.length) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.send),
                label: const Text('Send Assembled Replay Now'),
                onPressed: _sendAssembledNow,
              ),
            ),
          ],
        ] else ...[
          if (!_replayExchangeActive && !_assembledReplayReceived)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                icon: const Icon(Icons.upload),
                label: const Text('Send Replay Data'),
                onPressed: _startReplayExchange,
              ),
            ),
        ],
      ]);
    }
    return Column(children: [
      Text('Game in progress',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.green, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Text('Role: ${_myRole == 'chaser' ? 'Chaser' : 'Runner'}',
          style: Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height: 12),
      HoldButton(
        label: 'Manual End Game (hold)',
        onComplete: _endGame,
        color: Theme.of(context).colorScheme.onPrimary,
        backgroundColor: Theme.of(context).colorScheme.primary,
        textColor: Theme.of(context).colorScheme.onPrimary,
        holdDuration: Duration(seconds: 2),
      ),
    ]);
  }

  Widget _buildLobbyRulesSubTab() {
    if (!isHost) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lock_outline, size: 48, color: Colors.grey),
          SizedBox(height: 12),
          Text('Rules will be visible when the game starts',
              style: TextStyle(color: Colors.grey)),
        ]),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Zone Closure', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(children: [
            const Text('Close a zone every '),
            SizedBox(
              width: 60,
              child: TextField(
                controller: _closureMinutesController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                onChanged: (v) {
                  final m = int.tryParse(v);
                  if (m != null && m > 0) _closureMinutes = m;
                },
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const Text(' minutes'),
          ]),
          const SizedBox(height: 20),
          Text('Grace Period', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(children: [
            const Text('Grace period: '),
            SizedBox(
              width: 60,
              child: TextField(
                controller: _gracePeriodController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                onChanged: (v) {
                  final s = int.tryParse(v);
                  if (s != null && s >= 0) _gracePeriodSeconds = s;
                },
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const Text(' seconds'),
          ]),
        ],
      ),
    );
  }

  Widget _buildRulesSubTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Zone Closure', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Text('Close a zone every: ${_activeClosureIntervalMs ~/ 60000} minutes'),
          const SizedBox(height: 20),
          Text('Grace Period', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Text('Grace period of: ${_activeGracePeriodMs ~/ 1000} seconds'),
        ],
      ),
    );
  }

  Widget _buildPendingCard(OfflinePendingPlayer pending) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Row(children: [
          Container(
            width: 4,
            height: 40,
            decoration: const BoxDecoration(
              color: Colors.orange,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(pending.displayName,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.orange)),
          ),
          TextButton(
            onPressed: () => _hostAcceptPlayer(pending.userName),
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Accept',
                style: TextStyle(color: Colors.green, fontSize: 13)),
          ),
          TextButton(
            onPressed: () => _hostRejectPlayer(pending.userName),
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Remove', style: TextStyle(color: Colors.red, fontSize: 13)),
          ),
        ]),
      ),
    );
  }

  Widget _buildPlayersSubTab() {
    final totalItems = _players.length + (isHost ? _pendingGamePlayers.length : 0);

    if (totalItems == 0) {
      return const Center(
          child: Text('No players yet', style: TextStyle(color: Colors.grey)));
    }

    return ListView.builder(
      controller: _playersScrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: totalItems,
      itemBuilder: (context, i) {
        if (i >= _players.length) {
          final pending = _pendingGamePlayers[i - _players.length];
          return _buildPendingCard(pending);
        }

        final player = _players[i];
        final colour = _playerColourMap.putIfAbsent(
          player.id,
          () => playerColours[_playerColourMap.length % playerColours.length],
        );

        return Card(
          margin: const EdgeInsets.only(bottom: 6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Container(
                width: 4,
                height: 40,
                decoration: BoxDecoration(
                  color: colour,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: player.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: player.nameColour,
                      ),
                    ),
                    TextSpan(
                      text: ' (${player.id.length > 8 ? player.id.substring(0, 8) : player.id})',
                      style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ]),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_gameStarted) ...[
                if (player.isHost)
                  Text('Host',
                      style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant))
                else if (player.role == 'chaser')
                  Text('Chaser',
                      style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(width: 16),
              ] else ...[
                Text(
                  player.isHost
                      ? 'Host'
                      : player.role == 'chaser'
                          ? 'Chaser'
                          : 'Runner',
                  style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                if (isHost && player.id != userName) ...[
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: () => _hostSwitchRole(player.id),
                    style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Switch',
                        style: TextStyle(color: Colors.blue, fontSize: 13)),
                  ),
                  TextButton(
                    onPressed: () => _hostKickPlayer(player.id),
                    style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Kick',
                        style: TextStyle(color: Colors.red, fontSize: 13)),
                  ),
                ] else
                  const SizedBox(width: 16),
              ],
            ]),
          ),
        );
      },
    );
  }

  Widget _buildLogsSubTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _log.length,
      itemBuilder: (_, i) => Text(_log[i],
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
    );
  }

  Widget _buildTopologySubTab() {
    if (_tree.isEmpty) {
      return const Center(
          child: Text('No connections', style: TextStyle(color: Colors.grey)));
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: _buildTopologyRows(userName, 0),
    );
  }

  List<Widget> _buildTopologyRows(String node, int depth) {
    final isPseudo = _pseudoHosts.contains(node);
    final isMe = node == userName;

    final playerData = _players.where((p) => p.id == node).firstOrNull;
    final displayLabel = playerData != null ? '${playerData.name} ($node)' : node;

    final String suffix;
    if (isMe) {
      suffix = ' - HOST';
    } else if (isPseudo) {
      suffix = ' - pseudo-host';
    } else {
      suffix = '';
    }

    final widgets = <Widget>[
      Padding(
        padding: EdgeInsets.only(left: depth * 20.0, top: 4, bottom: 4),
        child: Row(children: [
          Icon(
            isPseudo || isMe ? Icons.cell_tower : Icons.phone_android,
            size: 16,
            color: isPseudo || isMe
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
          const SizedBox(width: 8),
          Text('$displayLabel$suffix',
              style: TextStyle(
                  fontWeight: isMe ? FontWeight.bold : FontWeight.normal)),
        ]),
      ),
    ];

    for (final child in _tree[node] ?? <String>[]) {
      widgets.addAll(_buildTopologyRows(child, depth + 1));
    }

    return widgets;
  }

  Widget _buildMapTab(BuildContext context) {
    // During active game, show map viewer with caught button
    if (_gameStarted && _receivedMap != null) {
      final amRunner = _myRole == 'runner';
      final showCaughtButton = amRunner && !_inGracePeriod && !_gameFinished;
      return Stack(children: [
        GameDisplay(
          map: _receivedMap!,
          currentZoneNotifier: _displayCurrentZone,
          closedZonesNotifier: _displayClosedZones,
          players: _displayPlayers,
          next: _displayNextZone,
        ),
        if (amRunner && !_gameFinished)
          Positioned(
            left: 24,
            right: 24,
            bottom: 24,
            child: SafeArea(
              top: false,
              child: HoldButton(
                label: "I've been caught (hold)",
                enabled: showCaughtButton,
                onComplete: _onCaught,
                color: Theme.of(context).colorScheme.onPrimary,
                backgroundColor: Theme.of(context).colorScheme.primary,
                textColor: Theme.of(context).colorScheme.onPrimary,
                holdDuration: Duration(seconds: 2),
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              ),
            ),
          ),
      ]);
    }

    // During lobby, show map selector
    return MapSelector(
      canCreateMaps: false,
      selectedMapName: _selectedMap?.mapName,
      selectedMapId: _selectedMap?.id,
      onMapSelected: (map, faces) {
        setState(() {
          _selectedMap = map;
          _faceOrder = faces?.map<int>((f) => f.faceID as int).toList();
        });
        if (map != null) _addLog('Selected map: ${map.mapName}');
      },
    );
  }

  // --------------------------------------------------------------------------
  //  Build
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bool isConnected = 
      _gameStarted || endpointMap.isNotEmpty || (isHost && _isAdvertising);

    Widget? banner;
    if (_gameFinished) {
      final String bannerTitle = 'Game Ended';
      final String bannerSubtitle;
      final Color bannerColor;

      if (isHost) {
        if (_distributingReplay && _distributedTo.length >= _players.length - 1) {
          bannerSubtitle = 'Replay distributed to all players';
          bannerColor = Colors.green;
        } else if (_distributingReplay) {
          bannerSubtitle = 'Distributing replay... (${_distributedTo.length}/${_players.length - 1})';
          bannerColor = Colors.amber.shade700;
        } else if (_offlineAssembledReplayJson != null) {
          bannerSubtitle = 'Replay assembled, starting distribution...';
          bannerColor = Colors.amber.shade700;
        } else if (_collectingReplays) {
          bannerSubtitle = 'Collecting replays... (${_collectedReplays.length}/${_players.length})';
          bannerColor = Colors.blue;
        } else {
          bannerSubtitle = 'Replay ready to collect';
          bannerColor = Colors.amber.shade700;
        }
      } else {
        if (_assembledReplayReceived) {
          bannerSubtitle = 'Replay received and saved';
          bannerColor = Colors.green;
        } else if (_individualReplaySent) {
          bannerSubtitle = 'Replay sent, waiting for assembled replay...';
          bannerColor = Colors.blue;
        } else if (_replayExchangeActive) {
          bannerSubtitle = 'Looking for host...';
          bannerColor = Colors.blue;
        } else {
          bannerSubtitle = 'Ready to send replay';
          bannerColor = Colors.amber.shade700;
        }
      }

      banner = Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        color: bannerColor,
        child: Column(
          children: [
            Text(bannerTitle,
                style: const TextStyle(
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(bannerSubtitle,
                style: const TextStyle(color: Colors.white, fontSize: 14)),
          ],
        ),
      );
    } else if (_gameStarted && _inGracePeriod && _graceSecondsRemaining > 0) {
      banner = GameBanner(
        gameStarted: true,
        gameFinished: false,
        isHost: false,
        replaySubmitted: false,
        receivedReplaysCount: 0,
        totalPlayersCount: 0,
        inGracePeriod: true,
        graceSecondsRemaining: _graceSecondsRemaining,
        myRole: _myRole,
        pendingPlayersCount: 0,
        zoneClosePeriod: _closureMinutes,
        currentTime: _gameStartedAt != null ? DateTime.now().difference(_gameStartedAt!).inMilliseconds - _activeGracePeriodMs : null,
      );
    } else if (!_gameStarted && isHost && _pendingGamePlayers.isNotEmpty) {
      banner = GameBanner(
        gameStarted: false,
        gameFinished: false,
        isHost: true,
        replaySubmitted: false,
        receivedReplaysCount: 0,
        totalPlayersCount: 0,
        inGracePeriod: false,
        graceSecondsRemaining: 0,
        myRole: _myRole,
        pendingPlayersCount: _pendingGamePlayers.length,
        zoneClosePeriod: _closureMinutes,
        currentTime: _gameStartedAt != null ? DateTime.now().difference(_gameStartedAt!).inMilliseconds - _activeGracePeriodMs : null,
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldLeave = await _confirmLeave();
        if (shouldLeave && context.mounted) {
          if (_gameFinished || !_gameStarted) {
            await OfflineGameSession.clear();
          }
          if (context.mounted) {
            Navigator.popUntil(context, (route) => route.isFirst);
          }
        }
      },
      child: LobbyLayout(
        key: _lobbyKey,
        title: _gameFinished
            ? const Text('Game Ended')
            : _gameStarted
                ? Text.rich(TextSpan(children: [
                    TextSpan(text: '$displayName: ${_myRole == 'chaser' ? 'Chaser' : 'Runner'}'),
                  ]))
                : _inLobby
                    ? Text.rich(TextSpan(children: [
                        TextSpan(text: '$displayName: ${_myRole == 'chaser' ? 'Chaser' : 'Runner'}'),
                        if (isHost)
                          TextSpan(
                            text: ' (host)',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ]))
                    : Text(_lobbyName.isNotEmpty
                              ? 'Offline: $_lobbyName'
                              : 'Offline: Joining'),
        isConnected: isConnected,
        players: _players,
        chatMessages: _chatMessages,
        currentPlayerId: userName,
        playerColourMap: _playerColourMap,
        onSendChat: _sendChatMessage,
        gameTabBuilder: _buildGameTab,
        mapTabBuilder: (isHost || _gameStarted) ? _buildMapTab : null,
        banner: banner,
        gameStarted: _gameStarted,
        myRole: _myRole,
        chatEnabled: !_gameStarted,
        showChannelSelector: false,
        activeChannel: _activeChannel,
        onChannelChanged: (_) {},
      ),
    );
  }
}