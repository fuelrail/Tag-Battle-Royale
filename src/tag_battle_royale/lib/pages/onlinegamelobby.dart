import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'package:tag_battle_royale/widgets/game_display.dart';

import '../services/game_socket_service.dart';
import '../services/location_service.dart';
import '../util/map_file_handler.dart';
import '../util/gamesession.dart';
import '../util/player_data.dart';
import '../util/player.dart';
import '../util/replay/replay.dart';
import '../util/replay/replay_file_handler.dart';
import '../widgets/lobby.dart';
import '../widgets/hold_button.dart';
import '../widgets/map_selector.dart';
import '../widgets/game_banner.dart';

import '../main.dart'; 

// --------------------------------------------------------------------------
//  Online Game Screen
// --------------------------------------------------------------------------

class OnlineConnectionScreen extends StatefulWidget {
  const OnlineConnectionScreen({
    super.key,
    required this.role,
    required this.playerName,
    this.gameCode,
    this.playerId,
    this.isHostOverride,
    this.resumeSession,
  });

  final ConnectionRole role;
  final String playerName;
  final String? gameCode;
  final String? playerId;
  final bool? isHostOverride;
  final GameSessionData? resumeSession;

  @override
  State<OnlineConnectionScreen> createState() => _OnlineConnectionScreenState();
}

class _OnlineConnectionScreenState extends State<OnlineConnectionScreen> {
  static const String serverUrl = 'https://tag-battle-royale.fly.dev/';

  GameSocketService? _socket;
  LocationService? _location;
  late ConfettiController _confettiController;
  final GlobalKey<LobbyLayoutState> _lobbyKey = GlobalKey<LobbyLayoutState>();

  // Connection
  String _status = 'Disconnected';
  String? _gameId;
  String? _hostId;
  bool _pendingAcceptance = false;

  // Players
  final List<PlayerData> _players = [];
  final List<PendingPlayer> _pendingPlayers = [];
  final Map<String, Color> _playerColourMap = {};
  final ScrollController _playersScrollController = ScrollController();
  final List<String> _log = [];

  final Players _displayPlayers = Players();
  final ValueNotifier<int?> _displayCurrentZone = ValueNotifier(null);
  final ValueNotifier<Set<int>> _displayClosedZones = ValueNotifier({});
  final ValueNotifier<int?> _displayNextZone = ValueNotifier(null);

  // Chat
  final Map<String, List<ChatMessage>> _chatMessages = {
    'all': [],
    'runner': [],
    'chaser': [],
  };
  String _activeChannel = 'all';

  // Map
  MapFile? _selectedMap; // host only
  bool _isStarting = false;
  MapFile? _receivedMap;
  List<int>? _faceOrder;
  int _closureMinutes = 15;
  int _gracePeriodSeconds = 90;
  final TextEditingController _closureMinutesController =
      TextEditingController(text: '15');
  final TextEditingController _gracePeriodController =
      TextEditingController(text: '90');

  // Game state
  bool _gameStarted = false;
  bool _gameFinished = false;
  String? _finishReason; // "all_caught" or "host_ended"
  DateTime? _gameStartedAt;
  List<int> _activeFaceOrder = [];
  int _activeClosureIntervalMs = 15 * 60 * 1000;
  int _activeGracePeriodMs = 90 * 1000;
  final Map<String, PlayerLocationInfo> _playerLocations = {};

  // Grace period
  Timer? _graceTimer;
  int _graceSecondsRemaining = 0;

  // Replay
  Replay? _replay;
  bool _replaySubmitted = false;
  Timer? _replayRetryTimer;
  final Map<String, Map<String, dynamic>> _receivedReplays = {}; // { playerId: replayJson }
  bool _replayFileAssembled = false;
  bool _replayFileSentToServer = false;
  Map<String, dynamic>? _assembledReplayJson;

  // --- Get properties ---

  bool get isHost => widget.isHostOverride ?? (widget.role == ConnectionRole.host);
  bool get _isReconnecting => widget.playerId != null;

  String get _myRole {
    return _findPlayer(_socket?.currentPlayerId)?.role ?? 'runner';
  }

  bool get _inGracePeriod {
    if (_gameStartedAt == null || _activeGracePeriodMs <= 0) return false;
    return DateTime.now().difference(_gameStartedAt!).inMilliseconds < _activeGracePeriodMs;
  }

  Set<int> get _closedZones {
    if (_gameStartedAt == null || _activeFaceOrder.isEmpty) return {};
    final elapsed = DateTime.now().difference(_gameStartedAt!).inMilliseconds - _activeGracePeriodMs;
    if (elapsed <= 0) return {};

    final zones = _activeFaceOrder.take(elapsed ~/ _activeClosureIntervalMs).toSet();
    if(_displayClosedZones.value.length!= zones.length){
      _displayClosedZones.value = zones;
      if(zones.length != _activeFaceOrder.length){
        _displayNextZone.value = _activeFaceOrder[zones.length];
      }else{_displayNextZone.value = null;}
    }
    return zones;
  }

  /// Find a player by ID.
  PlayerData? _findPlayer(String? id) {
    if (id == null) return null;
    return _players.where((p) => p.id == id).firstOrNull;
  }

  // --- Lifecycle ---

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    _socket = GameSocketService(serverUrl: serverUrl);
    _location = LocationService(gameSocketService: _socket!);
    _location!.onLog = (msg) => _addLog(msg);

    _setupCallbacks();

    // If reconnecting to an active game, set before connecting
    if (_isReconnecting) {
      _socket!.currentGameId = widget.gameCode;
      _socket!.currentPlayerId = widget.playerId;
      _gameId = widget.gameCode;
    }

    if (widget.resumeSession != null && widget.resumeSession!.gameStarted) {
      _initFromSession(widget.resumeSession!);
    }

    _socket!.connect();

    _addLog('Online mode: ${_isReconnecting ? "reconnecting" : isHost ? "hosting" : "joining"}');
    _addLog('Player: ${widget.playerName}');
    if (widget.gameCode != null) _addLog('Game code: ${widget.gameCode}');

    // Timeout if we can't connect within 15 seconds
    Future.delayed(const Duration(seconds: 15), () {
      if (mounted && _status == 'Disconnected') {
        // If reconnecting, pop after showing the error
        if (_isReconnecting) {
          _showSnackbarAndLeave('Connection timed out');
        } else {
          setState(() => _status = 'Error');
          _addLog('Connection timed out');
        }
      }
    });
  }

  void _initFromSession(GameSessionData session) {
    _gameId = session.gameId;
    _gameStarted = true;
    _gameStartedAt = session.gameStartedAt != null
        ? DateTime.fromMillisecondsSinceEpoch(session.gameStartedAt!)
        : null;

    // Restore config
    _activeFaceOrder = session.faceOrder ?? [];
    _activeClosureIntervalMs = session.closureIntervalMs ?? 15 * 60 * 1000;
    _activeGracePeriodMs = session.gracePeriodMs ?? 90 * 1000;

    // Restore map
    if (session.mapJson != null) {
      try {
        _receivedMap = MapFile.fromJson(session.mapJson!);
        _location?.map = _receivedMap;
        _socket!.hasMap = true;
      } catch (e) {
        _addLog('Failed to restore map: $e');
      }
    }

    // Restore players
    if (session.players != null) {
      for (final p in session.players!) {
        _players.add(PlayerData(
          id: p['id'] ?? '',
          name: p['name'] ?? '',
          role: p['role'] ?? 'runner',
          isHost: p['isHost'] == true,
          connected: p['connected'] ?? true,
          caughtOrder: p['caughtOrder'],
        ));
      }
      _hostId = _players.where((p) => p.isHost).firstOrNull?.id;
      _setUpDisplay();
    }

    // Restore replay
    if (session.replayJson != null && _gameStartedAt != null) {
      try {
        final restored = Replay.fromJson(session.replayJson!);
        final oldPositions = restored.positions;
        final me = _findPlayer(_socket?.currentPlayerId);
        _replay = Replay(
          playerID: me?.id ?? session.playerId,
          playerName: me?.name ?? session.playerName,
          colour: me?.nameColour ?? Colors.black,
          gameStartedAt: _gameStartedAt,
        );
        _replay!.positions.addAll(oldPositions);
        _addLog('Restored replay with ${oldPositions.length} frames');
      } catch (e) {
        _addLog('Failed to restore replay: $e');
      }
    }

    // Set role from session
    _updateLocationRole();
    _location?.getClosedZones = () => _closedZones;
    _location?.updateCurrentZone = _updateCurrentZone;
    _location?.updatePlayerPosition = _updatePlayerPosition;

    // Set up frame recording with persistence
    _location?.onFrameRecorded = (position, zone, role) {
      _replay?.add(position, zone: zone, role: role);
      _persistReplay();
    };

    _startGraceCountdown();
    if (_receivedMap != null) _location?.startTracking();

    _addLog('Resumed from saved session (connecting in background...)');
  }

  @override
  void dispose() {
    _unhookCallbacks();
    _graceTimer?.cancel();
    _replayRetryTimer?.cancel();
    _confettiController.dispose();
    // Only fully leave if the game hasn't started (lobby phase).
    // If the game has started, just disconnect the socket, the server
    // will mark us as disconnected so we can reconnect.
    if (!_gameStarted && _socket?.currentGameId != null) {
      _socket?.leaveGame();
    }
    _location?.dispose();
    _socket?.disconnect();
    _playersScrollController.dispose();
    _closureMinutesController.dispose();
    _gracePeriodController.dispose();
    super.dispose();
  }

  // --- Grace period timer ---

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

  void _updateCurrentZone(int? id){
    if(id != _displayCurrentZone.value){
      _displayCurrentZone.value = id;
    }
  }

  void _updatePlayerColour(String playerID, Color colour){
    final player = _displayPlayers.getById(playerID);
    player?.updateColour(colour);
  }

  void _updatePlayerPosition(Offset? pos){;
    if(_socket!.currentPlayerId == null){return;}
    _displayPlayers.updatePlayerPosition(_socket!.currentPlayerId!, pos);
    _displayPlayers.update();
  }
  
  void _setUpDisplay(){
    for(final player in _players){
      final p = Player(id: player.id,name: player.name,colour:player.nameColour);
      _displayPlayers.addPlayer(p);
    }
  }
  // --- Replay ---

  void _startReplay() {
    final me = _findPlayer(_socket?.currentPlayerId);
    if (me == null || _gameStartedAt == null) return;

    _replay = Replay(
      playerID: me.id,
      playerName: me.name,
      colour: me.nameColour,
      gameStartedAt: _gameStartedAt,
    );

    _location?.onFrameRecorded = (position, zone, role) {
      _replay?.add(position, zone: zone, role: role);
      _persistReplay();
    };

    _addLog('Replay recording started');
  }

  void _saveMap() async {
    _addLog("trying to save map");
    if(_receivedMap == null){return;}
    final alreadyHaveMap = await getMapByID(_receivedMap!.id) != null;
    if(!alreadyHaveMap){
      try{
        _receivedMap!.saveMapFile();
        _addLog("Map saved ${_receivedMap!.mapName}");
      } catch (e){
        _addLog("Couldn't save map -> $e");
      }
    } else{_addLog("Map already saved Locally");}
  }
  
  Future<void> _persistReplay() async {
    if (_replay == null) return;
    try {
      await GameSession.updateReplay(_replay!.toJson());
    } catch (e) {
      print('Failed to persist replay: $e');
    }
  }

  void _saveFullSession() {
    if (_socket?.currentGameId == null || _socket?.currentPlayerId == null) return;
    GameSession.save(
      gameId: _socket!.currentGameId!,
      playerId: _socket!.currentPlayerId!,
      playerName: widget.playerName,
      isHost: isHost,
      gameStarted: _gameStarted,
      role: _myRole,
      gameStartedAt: _gameStartedAt?.millisecondsSinceEpoch,
      faceOrder: _activeFaceOrder.isNotEmpty ? _activeFaceOrder : null,
      closureIntervalMs: _activeClosureIntervalMs,
      gracePeriodMs: _activeGracePeriodMs,
      mapJson: _receivedMap?.toJson(),
      replayJson: _replay?.toJson(),
      players: _players.map((p) => {
        'id': p.id,
        'name': p.name,
        'role': p.role,
        'isHost': p.isHost,
        'connected': p.connected,
        'caughtOrder': p.caughtOrder,
      }).toList(),
    );
  }

  Future<void> _restoreOrStartReplay() async {
    final session = await GameSession.load();
    if (session?.replayJson != null && _gameStartedAt != null) {
      try {
        final restored = Replay.fromJson(session!.replayJson!);
        final oldPositions = restored.positions;
        final me = _findPlayer(_socket?.currentPlayerId);
        _replay = Replay(
          playerID: me?.id ?? _socket!.currentPlayerId!,
          playerName: me?.name ?? widget.playerName,
          colour: me?.nameColour ?? Colors.black,
          gameStartedAt: _gameStartedAt,
        );
        _replay!.positions.addAll(oldPositions);
        _addLog('Restored replay with ${oldPositions.length} frames');

        _location?.onFrameRecorded = (position, zone, role) {
          _replay?.add(position, zone: zone, role: role);
          _persistReplay();
        };
      } catch (e) {
        _addLog('Failed to restore replay: $e');
        _startReplay();
      }
    } else {
      _startReplay();
    }
  }

  void _submitReplay() {
    if (_replay == null || _replaySubmitted) return;

    _addLog('Submitting replay (${_replay!.positions.length} frames)...');

    _socket?.submitReplay(_replay!.toJson(), onResult: (success) {
      if (!mounted) return;
      if (success) {
        _replaySubmitted = true;
        _replayRetryTimer?.cancel();
        setState(() {});
        _addLog('Replay submitted successfully');
      } else {
        _addLog('Replay submission failed, retrying in 5s...');
        _scheduleReplayRetry();
      }
    });
  }

  void _scheduleReplayRetry() {
    _replayRetryTimer?.cancel();
    _replayRetryTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && !_replaySubmitted) {
        _submitReplay();
      }
    });
  }

  Future<void> _assembleReplay() async {
    if (_receivedMap == null) {
      _addLog('ERROR: No map data for replay assembly');
      return;
    }
    if (_replayFileAssembled) return;
    _addLog("Saving map ...");
    _saveMap();

    // Compute zone closings from game config
    final Map<int, double> zoneClosings = {};
    for (int i = 0; i < _activeFaceOrder.length; i++) {
      final closingTimeMs = _activeGracePeriodMs + ((i + 1) * _activeClosureIntervalMs);
      zoneClosings[_activeFaceOrder[i]] = closingTimeMs / 1000.0;
    }

    // Collect all replays (including our own)
    final List<Replay> replays = [];
    for (final entry in _receivedReplays.entries) {
      try {
        replays.add(Replay.fromJson(entry.value));
      } catch (e) {
        _addLog('WARNING: Failed to assemble replay from ${entry.key}: $e');
      }
    }
    // Add our own replay if not already received from server
    if (_replay != null && !_receivedReplays.containsKey(_socket?.currentPlayerId)) {
      replays.add(_replay!);
    }

    _addLog('Assembling replay with ${replays.length} player(s)...');

    try {
      await _receivedMap!.saveMapFile();
      _addLog('Map saved: ${_receivedMap!.mapName}');
      final replayFile = await ReplayFile.create(
        map: _receivedMap!,
        replays: replays,
        zoneClosings: zoneClosings,
      );
      await replayFile.saveReplayFile();
      _assembledReplayJson = replayFile.toJson();
      _addLog('Replay saved: ${replayFile.replayName}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Replay saved: ${replayFile.replayName}')),
        );
      }

      setState(() => _replayFileAssembled = true);

      // Auto send to server
      _sendAssembledReplayToServer();
    } catch (e) {
      _addLog('ERROR: Failed to save replay: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save replay')),
        );
      }
    }
  }

  void _sendAssembledReplayToServer() {
    if (_assembledReplayJson == null || _replayFileSentToServer) return;
    if (_socket == null || !_socket!.isConnected) {
      _addLog('Not connected, will send assembled replay when reconnected');
      return;
    }
    _addLog('Sending assembled replay to server...');
    _socket!.submitAssembledReplay(_assembledReplayJson!);
    setState(() => _replayFileSentToServer = true);
    _addLog('Assembled replay sent to server');
  }

  Future<void> _saveReceivedReplayFile(Map<String, dynamic> json) async {
    try {
      final replayFile = ReplayFile.fromJson(json);
      await replayFile.saveReplayFile();
      // Save the map so the replay can be viewed
      if (_receivedMap != null) {
        await _receivedMap!.saveMapFile();
      }
      setState(() => _replayFileAssembled = true);
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

  // --- Game finished ---

  void _onGameFinished(Map<String, dynamic> data) {
    final reason = data['reason']?.toString() ?? 'unknown';
    final serverPlayers = data['players'] as List?;

    setState(() {
      _gameFinished = true;
      _finishReason = reason;
      if (serverPlayers != null) _updatePlayerList(serverPlayers);
    });

    _addLog('Game finished: $reason');
    _confettiController.play();

    _submitReplay();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lobbyKey.currentState?.switchToGameTab();
    });
  }

  // --- Callbacks ---

  void _setupCallbacks() {
    _socket!.onConnected = () {
      // This check is technically unnecessary because we decided to remove
      // our callbacks on dispose, however there's no downside to removing it,
      // as it is a simple security check
      if (!mounted) return;
      setState(() => _status = 'Connected');
      _addLog('Connected to server');

      // If reconnecting, the socket will auto-rejoin via _attemptRejoin.
      // If fresh connect and no game yet, create or join.
      if (!_isReconnecting && _socket!.currentGameId == null && !_pendingAcceptance) {
        if (isHost) {
          _socket!.createGame(widget.playerName);
        } else if (widget.gameCode != null) {
          _socket!.joinGame(widget.gameCode!, widget.playerName);
        }
      }

      // Notify location service if game is active
      if (_gameStarted) _location?.notifySocketConnected();

      if (_gameFinished && !_replaySubmitted) _submitReplay();

      if (_gameFinished && _replayFileAssembled && !_replayFileSentToServer) {
        _sendAssembledReplayToServer();
      }
    };

    _socket!.onDisconnected = () {
      if (!mounted) return;
      setState(() => _status = 'Reconnecting...');
      _addLog('Disconnected from server, attempting to reconnect');

      if (_gameStarted) _location?.notifySocketDisconnected();
    };

    _socket!.onGameCreated = (data) {
      if (!mounted) return;
      setState(() {
        _gameId = data['game']['id'];
        _hostId = data['game']['hostId']?.toString();
        _updatePlayerList(data['game']['players']);
      });
      _addLog('Game created: $_gameId (you are ${data['playerId']})');
      // Host doesn't save session during lobby, leaving disbands the game
    };

    _socket!.onGameJoined = (data) {
      if (!mounted) return;
      if (data['pending'] == true) {
        setState(() => _pendingAcceptance = true);
        _addLog('Waiting for host to accept...');
        return;
      }

      // Direct join (shouldn't happen)
      setState(() {
        _pendingAcceptance = false;
        _gameId = data['game']['id'];
        _hostId = data['game']['hostId']?.toString();
        _updatePlayerList(data['game']['players']);
      });
      _addLog('Joined game: $_gameId');
      // Save session so joiners can reconnect to lobby if they disconnect
      _saveFullSession();
    };

    _socket!.onPlayerAccepted = (data) {
      if (!mounted) return;
      setState(() {
        _pendingAcceptance = false;
        _gameId = data['game']?['id'];
        _hostId = data['game']?['hostId']?.toString();
        _updatePlayerList(data['game']?['players'] ?? []);
      });
      _socket!.currentGameId = _gameId;
      _socket!.currentPlayerId = data['playerId']?.toString();
      _addLog('Accepted into game: $_gameId');
      _saveFullSession();
    };

    _socket!.onPlayerRejected = (data) {
      if (!mounted) return;
      final reason = data['reason']?.toString() ?? 'Join request rejected';
      _addLog('Rejected: $reason');
      _showSnackbarAndLeave(reason);
    };

    _socket!.onPlayerPending = (data) {
      if (!mounted) return;
      _updatePendingList(data['pendingPlayers'] as List?);
      final name = data['playerName']?.toString();
      if (name != null) _addLog('$name wants to join');
    };

    _socket!.onPlayerPendingLeft = (data) {
      if (!mounted) return;
      _updatePendingList(data['pendingPlayers'] as List?);
      final name = data['playerName']?.toString();
      if (name != null) _addLog('Pending player $name disconnected');
    };

    _socket!.onPlayerKicked = (data) {
      if (!mounted) return;
      final reason = data['reason']?.toString() ?? 'You have been kicked';
      
      _addLog('Kicked: $reason');
      GameSession.clear();
      _showSnackbarAndLeave(reason);
    };

    _socket!.onRejoined = (data) async {
      if (!mounted) return;

      setState(() {
        _gameId = data['game']?['id'] ?? _gameId;
        _hostId = data['game']?['hostId']?.toString() ?? _hostId;
        _gameStarted = true;
        _gameStartedAt = DateTime.fromMillisecondsSinceEpoch(data['game']?['startedAt']);
        if (data['game']?['status'] == 'finished') {
          _gameFinished = true;
          _finishReason = data['game']?['finishReason'];
        }
        if (data['game']?['players'] != null) _updatePlayerList(data['game']['players']);
      });
      _addLog('Rejoined game: $_gameId');

      _saveFullSession();

      _updateLocationRole();
      _location?.getClosedZones = () => _closedZones;
      _location?.updateCurrentZone = _updateCurrentZone;
      _location?.updatePlayerPosition = _updatePlayerPosition;

      // Tracking will start when the map arrives
      if (!_gameFinished) {
        _startGraceCountdown();
        if (_replay == null) await _restoreOrStartReplay();

      } else {
        // Restore replay from session and submit
        if (_replay == null) await _restoreOrStartReplay();
        if (!_replaySubmitted) _submitReplay();
      }
    };

    _socket!.onPlayerJoined = (data) {
      if (!mounted) return;
      setState(() => _updatePlayerList(data['players']));
      if (_gameStarted) _saveFullSession();
      _addLog('${data['playerName']} joined');
    };

    _socket!.onPlayerLeft = (data) {
      if (!mounted) return;
      setState(() {
        _updatePlayerList(data['remainingPlayers']);
        _playerLocations.remove(data['playerId']);
      });
      _addLog('Player ${data['playerName'] ?? data['playerId']} left');
    };

    _socket!.onPlayerReconnected = (data) {
      if (!mounted) return;
      setState(() => _updatePlayerList(data['players']));
      if (_gameStarted) _saveFullSession();
      _addLog('${data['playerName']} reconnected');
    };

    _socket!.onPlayerDisconnected = (data) {
      if (!mounted) return;
      setState(() => _updatePlayerList(data['players']));
      if (_gameStarted) _saveFullSession();
      _addLog('${data['playerName']} disconnected');
    };

    _socket!.onGameStarted = (data) {
      if (!mounted) return;
      
      setState(() {
        _isStarting = false;
        _gameStarted = true;
        _gameStartedAt = DateTime.fromMillisecondsSinceEpoch(data['startedAt']);
        _pendingPlayers.clear();
      });
      _addLog('Game started!');

      if (isHost) {
        _receivedMap = _selectedMap;
        _location?.map = _selectedMap;
        _socket!.hasMap = true;
      }

      // Save session for reconnection
      _saveFullSession();

      // Set role and start tracking
      _updateLocationRole();
      _location?.getClosedZones = () => _closedZones;
      _location?.updateCurrentZone = _updateCurrentZone;
      _location?.updatePlayerPosition = _updatePlayerPosition;
      _startGraceCountdown();
      _startReplay();
      if (_location?.map != null) _location?.startTracking();
    };

    _socket!.onGameFinished = (data) {
      if (!mounted) return;
      _onGameFinished(data);
    };

    _socket!.onChatMessage = (message) {
      if (!mounted) return;
      setState(() {
        final channel = message.channel;
        _chatMessages[channel] ??= [];
        _chatMessages[channel]!.add(message);
      });
    };

    _socket!.onChatHistory = (channel, messages) {
      if (!mounted) return;
      setState(() => _chatMessages[channel] = messages);
      _addLog('Received ${messages.length} $channel chat messages');
    };

    _socket!.onMapData = (data) {
      if (!mounted) return;
      try {
        _receivedMap = MapFile.fromJson(data['map'] as Map<String, dynamic>);
        _activeFaceOrder = List<int>.from(data['faceOrder']);
        _displayNextZone.value = _activeFaceOrder[0];
        _activeClosureIntervalMs = data['closureIntervalMs'];
        _activeGracePeriodMs = data['gracePeriodMs'];

        _location?.map = _receivedMap;
        _socket!.hasMap = true;

        if (_gameStarted && !_location!.isTracking) {
          _updateLocationRole();
          _location?.getClosedZones = () => _closedZones;
          _location?.updateCurrentZone = _updateCurrentZone;
          _location?.updatePlayerPosition = _updatePlayerPosition;
          _location?.startTracking();
        }

        // Only confirm during the starting phase (not on rejoin)
        if (!_gameStarted) {
          _socket!.confirmMapReceived();
          _addLog('Map received and confirmed');
          _addLog('Face order: ${_activeFaceOrder.toString()} zones, '
            'closure interval: ${_activeClosureIntervalMs ~/ 1000}s, '
            'grace period: ${_activeGracePeriodMs ~/ 1000}s');
          // Save session for host and joiners for active game
          _saveFullSession();
        } else {
          _addLog('Map received');
          _saveFullSession();
          _addLog('Face order: ${_activeFaceOrder.length} zones, '
            'closure interval: ${_activeClosureIntervalMs ~/ 1000}s, '
            'grace period: ${_activeGracePeriodMs ~/ 1000}s');
        }
        setState(() {}); // Rebuild to show map tab
      } catch (e) {
        _addLog('ERROR: Failed to deserialize map: $e');
      }
    };
  
    _socket!.onLocationBroadcast = (players) {
      if (!mounted) return;
      _addLog('Broadcast: ${players.entries.map((e) {
        final p = e.value;
        final pos = p.x != null
          ? '(${p.x!.toStringAsFixed(1)}, ${p.y!.toStringAsFixed(1)})'
          : 'no pos';
          // update user position display
          final point = p.status=="active" 
          ? ui.Offset(p.x!,p.y!) 
          : null;
          _displayPlayers.updatePlayerPosition(p.playerId, point);
          

        return '${p.playerName}(${p.role}) $pos ${p.status}';
      }).join(', ')}');
      _displayPlayers.update();
      setState(() {
        _playerLocations
          ..clear()
          ..addAll(players);
      });
    };

    _socket!.onZonesReordered = (data) {
      if (!mounted) return;
      final newOrder = List<int>.from(data['faceOrder']);
      setState(() => _activeFaceOrder = newOrder);

      // Update the next zone display
      final closedCount = _closedZones.length;
      if (closedCount < _activeFaceOrder.length) {
        _displayNextZone.value = _activeFaceOrder[closedCount];
      } else {
        _displayNextZone.value = null;
      }

      _addLog('Zone order updated: ${_activeFaceOrder.toString()}');
      if (_gameStarted) _saveFullSession();
    };

    _socket!.onPlayerRoleUpdated = (data) {
      if (!mounted) return;
      final playerId = data['playerId']?.toString();
      final role = data['role']?.toString();
      
      if (playerId == null || role == null) return;
      setState(() {
        final player = _findPlayer(playerId);
        if (player == null){return;}
        player.role = role;
        _updatePlayerColour(playerId, player.nameColour);
      });
      _addLog('${_findPlayer(playerId)?.name ?? playerId} is now $role');

      // If this player's role changed, update LocationService
      if (playerId == _socket?.currentPlayerId) {
        _updateLocationRole();
        GameSession.updateRole(role);
        if (role == 'chaser') {
          setState(() {
            _chatMessages['runner'] = [];
            if (_activeChannel == 'runner') _activeChannel = 'chaser';
          });
        }
      }
    };

    _socket!.onReplayReceived = (data) {
      if (!mounted) return;
      final playerId = data['playerId']?.toString();
      final replayData = data['replay'] as Map<String, dynamic>?;
      if (playerId == null || replayData == null) return;

      setState(() => _receivedReplays[playerId] = replayData);

      final playerName = replayData['playerName'] ?? playerId;
      final frameCount = (replayData['positions'] as List?)?.length ?? 0;
      _addLog('Replay received from $playerName ($frameCount frames) '
        '[${_receivedReplays.length}/${_players.length}]');

      // Auto assemble if all replays received
      if (isHost && _receivedReplays.length >= _players.length && !_replayFileAssembled) {
        _assembleReplay();
      }
    };

    _socket!.onReplayFileReceived = (data) {
      if (!mounted) return;
      final replayFileJson = data['replayFile'] as Map<String, dynamic>?;
      if (replayFileJson == null) return;

      _addLog('Received assembled replay file from server');
      _saveReceivedReplayFile(replayFileJson);
    };

    _socket!.onGameDisbanded = (data) {
      if (!mounted) return;
      GameSession.clear();
      _showSnackbarAndLeave(data['reason']?.toString() ?? 'Game disbanded');
    };

    _socket!.onError = (event, message) {
      if (!mounted) return;
      _addLog('ERROR [$event]: $message');

      if (event == 'connection' || event == 'game:create' || event == 'game:join') {
        setState(() => _status = 'Error');
      }
      if (event == 'game:start') setState(() => _isStarting = false);
      if (event == 'game:rejoin') {
        GameSession.clear();
        _showSnackbarAndLeave('Could not reconnect, game may no longer exist');
      }
    };
  }

  void _unhookCallbacks() {
    _location?.onLog = null;
    _location?.onFrameRecorded = null;
    _socket?.onConnected = null;
    _socket?.onDisconnected = null;
    _socket?.onGameCreated = null;
    _socket?.onGameJoined = null;
    _socket?.onPlayerAccepted = null;
    _socket?.onPlayerRejected = null;
    _socket?.onPlayerPending = null;
    _socket?.onPlayerPendingLeft = null;
    _socket?.onPlayerKicked = null;
    _socket?.onRejoined = null;
    _socket?.onPlayerJoined = null;
    _socket?.onPlayerLeft = null;
    _socket?.onPlayerReconnected = null;
    _socket?.onPlayerDisconnected = null;
    _socket?.onGameStarted = null;
    _socket?.onGameFinished = null;
    _socket?.onLocationBroadcast = null;
    _socket?.onChatMessage = null;
    _socket?.onChatHistory = null;
    _socket?.onMapData = null;
    _socket?.onPlayerRoleUpdated = null;
    _socket?.onReplayReceived = null;
    _socket?.onReplayFileReceived = null;
    _socket?.onGameDisbanded = null;
    _socket?.onZonesReordered = null;
    _socket?.onError = null;
  }

  // --- Player list ---

  void _updatePlayerList(List players) {
    // Preserve existing roles across updates
    final existingRoles = {for (final p in _players) p.id: p.role};
    final existingCaughtOrder = {for (final p in _players) p.id: p.caughtOrder};

    _players.clear();
    for (final player in players) {
      final id = player['id']?.toString() ?? '';
      final name = player['name']?.toString() ?? 'Unknown';
      // Use server role if present, then preserved role, then default
      final role = player['role']?.toString() ?? existingRoles[id] ?? 'runner';
      final caughtOrder = player['caughtOrder'] ?? existingCaughtOrder[id];
      _players.add(PlayerData(
        id: id,
        name: name,
        role: role,
        isHost: id == _hostId,
        connected: player['connected'] ?? true,
        caughtOrder: caughtOrder,
      ));
    }
    _setUpDisplay();
  }

  void _updatePendingList(List? pendingList) {
    setState(() {
      _pendingPlayers.clear();
      if (pendingList != null) {
        for (final p in pendingList) {
          final map = Map<String, dynamic>.from(p);
          final socketId = map['socketId']?.toString() ?? '';
          final playerName = map['playerName']?.toString() ?? 'Unknown';
          _pendingPlayers.add(PendingPlayer(
            socketId: socketId,
            playerName: playerName,
          ));
        }
      }
    });
  }

  Future<void> _kickPlayer(String playerId) async {
    final player = _findPlayer(playerId);
    if (player == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kick player?'),
        content: Text('Are you sure you want to kick ${player.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kick'),
           ),
        ],
      ),
    );
    if (confirmed == true) _socket?.kickPlayer(playerId);
  }

  void _updateLocationRole() {
    _location?.role = _myRole;
  }

  // --- Role switching ---

  void _switchRole(String playerId) {
    if (playerId == _hostId) return;

    // Self-switches (caught button) skip confirmation popup
    if (playerId == _socket?.currentPlayerId) {
      _doRoleSwitch(playerId);
      return;
    }

    if (_gameStarted) {
      _confirmRoleSwitch(playerId);
    } else {
      _doRoleSwitch(playerId);
    }
  }

  Future<void> _confirmRoleSwitch(String playerId) async {
    final player = _findPlayer(playerId);
    if (player == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Switch role?'),
        content: Text(
          'The game is in progress. Are you sure you want to switch '
          '${player.name} to ${player.role == 'runner' ? 'chaser' : 'runner'}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Switch'),
          ),
        ],
      ),
    );

    if (confirmed == true) _doRoleSwitch(playerId);
  }

  void _doRoleSwitch(String playerId) {
    final player = _findPlayer(playerId);
    if (player == null) return;

    setState(() => player.role = player.role == 'runner' ? 'chaser' : 'runner');

    _socket?.switchPlayerRole(playerId, player.role);
    if (playerId == _socket?.currentPlayerId) {
      _updateLocationRole();
      GameSession.updateRole(player.role);
    }
  }

  // --- End game ---

  Future<void> _hostEndGame() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End game?'),
        content: const Text('This will end the game for all players.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('End Game')),
        ],
      ),
    );
    if (confirmed == true) _socket?.endGame();
  }

  // --- Helpers ---

  void _addLog(String message) {
    if (!mounted) return;
    print('${DateTime.now().toIso8601String().substring(11, 19)} $message');
    setState(() {
      _log.insert(0, '${DateTime.now().toIso8601String().substring(11, 19)} $message');
      if (_log.length > 100) _log.removeLast();
    });
  }

  void _showSnackbarAndLeave(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  /// Show a confirmation box when leaving a game.
  Future<bool> _confirmLeave() async {
    final String title;
    final String content;

    if (_gameFinished) {
      if (isHost) {
        if (_replayFileSentToServer) {
          // Host has sent assembled replay, just leave
          return true;
        }
        title = 'Leave game?';
        content = _replayFileAssembled
            ? 'The assembled replay has not been sent to the server yet.'
            : "This game's replay has not been generated.";
      } else {
        if (_replayFileAssembled) {
          // Non-host received and saved replay, just leave
          return true; 
        }
        if (_replaySubmitted) {
          title = 'Leave game?';
          content = 'You have not received the assembled replay yet.';
        } else {
          title = 'Leave game?';
          content = 'Your replay has not been sent.';
        }
      }
    } else if (_gameStarted) {
      title = 'Leave game?';
      content = 'You will be marked as disconnected. You can reconnect later from the main menu.';
    } else if (isHost) {
      title = 'Disband game?';
      content = 'Leaving will disband the game for all players. Are you sure?';
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
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // --------------------------------------------------------------------------
  //  Ui Builders
  // --------------------------------------------------------------------------

  // --- Sub Tab Builders for Game Tab ---

  Widget _buildRulesSubTab() {
    // Non-host can't see rules until game starts
    if (!isHost && !_gameStarted) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text('Rules will be visible when the game starts',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    // Active game, show rules as plain text
    if (_gameStarted) {
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

    // Lobby, editable fields for host
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Zone Closure', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
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
            ],
          ),
          const SizedBox(height: 20),
          Text('Grace Period', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
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
            ],
          ),
        ],
      ),
    );
  }

  // --- Players sub-tab ---

  Widget _buildPlayersSubTab() {
    if (_players.isEmpty && _pendingPlayers.isEmpty) {
      return const Center(
          child: Text('No players yet', style: TextStyle(color: Colors.grey)));
    }
    if (_gameFinished) return _buildFinishedPlayerList();
    return _buildActivePlayerList();
  }

  Widget _buildFinishedPlayerList() {
    final sorted = List<PlayerData>.from(_players)
      ..sort((a, b) {
        // Players with caughtOrder come first, sorted descending
        if (a.caughtOrder != null && b.caughtOrder != null) {
          return b.caughtOrder!.compareTo(a.caughtOrder!);
        }
        if (a.caughtOrder != null) return -1; // a was caught, b wasn't
        if (b.caughtOrder != null) return 1;  // b was caught, a wasn't
        return 0; // both original chasers
      });

    String placeLabel(int index) {
      if (sorted[index].caughtOrder == null) return '';
      final place = index + 1;
      if (place == 1) return '1st';
      if (place == 2) return '2nd';
      if (place == 3) return '3rd';
      return '${place}th';
    }

    return Scrollbar(
      thumbVisibility: true,
      controller: _playersScrollController,
      child: ListView.builder(
        controller: _playersScrollController,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: sorted.length,
        itemBuilder: (context, i) {
          final player = sorted[i];
          final colour = _playerColourMap.putIfAbsent(
            player.id,
            () => playerColours[_playerColourMap.length % playerColours.length],
          );
          final place = placeLabel(i);

            return Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  children: [
                    // Place label
                    SizedBox(
                      width: 40,
                      child: Center(
                        child: Text(
                          place,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: place == '1st' ? Colors.amber.shade700 : Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
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
                      child: Text(
                        player.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: player.connected ? player.nameColour : Colors.grey,
                        ),
                      ),
                    ),
                    Text(
                      player.caughtOrder != null ? 'Caught' : 'Chaser',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }

  // Normal (non-finished game) player list
  Widget _buildActivePlayerList() {
    final totalPlayers = _players.length + (isHost ? _pendingPlayers.length : 0);

    return Scrollbar(
      thumbVisibility: true,
      controller: _playersScrollController,
      child: ListView.builder(
        controller: _playersScrollController,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: totalPlayers,
        itemBuilder: (context, i) {
          // Pending players
          if (i >= _players.length) {
            final pending = _pendingPlayers[i - _players.length];
            return _buildPendingPlayerCard(pending);
          }

          final player = _players[i];
          final colour = _playerColourMap.putIfAbsent(
            player.id,
            () => playerColours[_playerColourMap.length % playerColours.length],
          );
          final shortId = player.id.length > 8
            ? player.id.substring(0, 8)
            : player.id;

          return Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  // Colour bar
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
                  // Player name and ID
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: player.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: player.connected ? player.nameColour : Colors.grey,
                            ),
                          ),
                          TextSpan(
                            text: ' ($shortId)',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (!player.connected)
                            const TextSpan(
                              text: '  disconnected',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                        ],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Role label
                  Text(
                    player.isHost
                        ? 'Host'
                        : player.role == 'chaser'
                            ? 'Chaser'
                            : 'Runner',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  // Switch button (host user only, not on the host player card)
                  if (isHost && !player.isHost && !_gameFinished) ...[
                    const SizedBox(width: 4),
                    TextButton(
                      onPressed: () => _switchRole(player.id),
                      style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Switch',
                        style: TextStyle(color: Colors.blue, fontSize: 13),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _kickPlayer(player.id),
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
              ),
            ),
          );
        },
      ),
    );
  }

  void _selectNextZone(ui.Offset point) async {
    print("hello");
    if (_inGracePeriod || !_gameStarted || _gameFinished) return;
    if (_receivedMap == null) return;
    if (!isHost) return;

    final graph = _receivedMap!.graph;
    final face = graph.pointInFace(point);
    if (face == null) return;

    // Don't allow selecting an already closed zone
    if (_closedZones.contains(face.faceID)) return;

    final bool? shouldBeNext = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Next Zone"),
          content: const Text("This zone will close next?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Yes"),
            ),
          ],
        );
      },
    );
    if (shouldBeNext != true) return;

    // Build new order, keep closed zones in place, insert selected next, then the rest
    final closedCount = _closedZones.length;
    final closedPart = _activeFaceOrder.take(closedCount).toList();
    final remainingOpen = _activeFaceOrder.skip(closedCount).where((f) => f != face.faceID).toList();
    final newZoneOrder = [...closedPart, face.faceID, ...remainingOpen];

    _addLog('Reordering zones: next to close = zone ${face.faceID}');

    _socket?.reorderZones(newZoneOrder);

    print("oldzones $_activeFaceOrder");
    print("new zones $newZoneOrder");
  }

  Widget _buildPendingPlayerCard(PendingPlayer pending) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Row(children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.orange,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              pending.playerName,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Colors.orange,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() => _pendingPlayers.removeWhere((p) => p.socketId == pending.socketId));
              _socket?.acceptPlayer(pending.socketId);
            },
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Accept',
                style: TextStyle(color: Colors.green, fontSize: 13)),
          ),
          TextButton(
            onPressed: () {
              setState(() => _pendingPlayers.removeWhere((p) => p.socketId == pending.socketId));
              _socket?.rejectPlayer(pending.socketId);
            },
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Remove',
                style: TextStyle(color: Colors.red, fontSize: 13)),
          ),
        ]),
      ),
    );
  }

  // --- Logs sub-tab ---

  Widget _buildLogsSubTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _log.length,
      itemBuilder: (_, i) => Text(
        _log[i],
        style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
      ),
    );
  }

  // --- Game Tab Builder ---

  Widget _buildGameTab(BuildContext context) {
    // If not connected, don't display game tab
    if (_pendingAcceptance) {
      return _buildPendingView(context);
    }

    if (!_gameStarted &&
        (_status == 'Disconnected' ||
            _status == 'Reconnecting...' ||
            _status == 'Error' ||
            _gameId == null)) {
      return _buildLoadingView(context);
    }

    return Stack(
      children: [
        Column(
          children: [
            _buildTopSection(context),
            Expanded(
              child: DefaultTabController(
                length: 3,
                initialIndex: 1,
                child: Column(
                  children: [
                    const TabBar(tabs: [
                      Tab(text: 'Rules'),
                      Tab(text: 'Players'),
                      Tab(text: 'Logs'),
                      ]
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildRulesSubTab(),
                          _buildPlayersSubTab(),
                          _buildLogsSubTab(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        // Confetti overlay
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
      ],
    );
  }

  Widget _buildPendingView(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          const Text('Waiting for host to accept...'),
          const SizedBox(height: 8),
          Text(
            _status == 'Connected' ? 'Connected' : _status,
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ]),
      ),
    );
  }

  Widget _buildLoadingView(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Status/actions
          if (_status == 'Disconnected' || _status == 'Reconnecting...')
            const Center(child: CircularProgressIndicator())
          else if (_status == 'Error')
            Center(
              child: Column(
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  const Text('Failed to connect to server'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
                    child: const Text('Go Back'),
                  ),
                ],
              ),
            )
          else if (_gameId == null)
            const Center(
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Setting up game…'),
                ],
              ),
            ),
          const Spacer(),
        ],
      ),
    );
  }

  // --- Top section ---

  Widget _buildTopSection(BuildContext context) {
    if (_gameFinished) return _buildFinishedTopSection(context);
    if (_gameStarted) return _buildActiveTopSection(context);
    return _buildLobbyTopSection(context);
  }

  Widget _buildFinishedTopSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          Text(
            'Game Ended',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.amber.shade700, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text('Code: $_gameId',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          if (isHost) ...[
            const SizedBox(height: 4),
            Text('Replays received: ${_receivedReplays.length}/${_players.length}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            if (!_replayFileAssembled) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  icon: const Icon(Icons.build),
                  label: Text('Assemble Replay (${_receivedReplays.length}/${_players.length})'),
                  onPressed: _assembleReplay,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

    Widget _buildActiveTopSection(BuildContext context) {
      final disconnected = _players.where((p) => !p.connected).length;
      final countText = '${_players.length} player${_players.length == 1 ? '' : 's'}';
      final disconnectedText = disconnected > 0 ? ', $disconnected disconnected' : '';
      
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          children: [
            Text(
              'Game in progress',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Code: $_gameId',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              '$countText$disconnectedText',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            if (isHost) ...[
              const SizedBox(height: 12),
              HoldButton(
                label: 'Manual End Game (hold)',
                onComplete: _hostEndGame,
                color: Theme.of(context).colorScheme.onPrimary,
                backgroundColor: Theme.of(context).colorScheme.primary,
                textColor: Theme.of(context).colorScheme.onPrimary,
                holdDuration: Duration(seconds: 2),
              ),
            ],
          ],
        ),
      );
    }

Widget _buildLobbyTopSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          // Game code
          Text('Game Code',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(
            _gameId!,
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_players.length} player${_players.length == 1 ? '' : 's'} connected',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),

          // Select a map
          if (isHost && _selectedMap == null && !_isStarting)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Select a map in the Map tab to start',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),

          // One Runner required
          if (isHost && !_players.any((p) => p.role == 'runner') && !_isStarting)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'At least one Runner is required to start',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),

          // Start / waiting
          if (isHost)
            _isStarting
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(strokeWidth: 2),
                        SizedBox(width: 12),
                        Text('Starting game...'),
                      ],
                    ),
                  )
                : SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start Game'),
                      onPressed: (_selectedMap == null || _faceOrder == null) //!_players.any((p) => p.role == 'runner'))
                          ? null
                          : () {
                              setState(() => _isStarting = true);
                              _socket!.startGame(
                                _selectedMap!.toJson(),
                                faceOrder: _faceOrder!,
                                closureIntervalMs: _closureMinutes * 60 * 1000,
                                gracePeriodMs: _gracePeriodSeconds * 1000,
                              );
                              _addLog('Starting game, sending map to players…');
                            },
                    ),
                  )
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(strokeWidth: 2),
                  SizedBox(width: 12),
                  Text('Waiting for host to start…'),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // --- Map tab ---

  Widget _buildMapTab(BuildContext context) {
    // During lobby, host selects a map
    if (!_gameStarted) {
      return MapSelector(
        canCreateMaps: true,
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

    // During active game, show map viewer
    if (_receivedMap != null) {
      final amRunner = _myRole == 'runner';
      final showCaughtButton = amRunner && !_inGracePeriod && !_gameFinished;
      return Stack(
        children: [
          GameDisplay(
            map: _receivedMap!,
            closedZonesNotifier: _displayClosedZones,
            currentZoneNotifier: _displayCurrentZone,
            players: _displayPlayers,
            next: _displayNextZone,
            onTapScene: _selectNextZone,
          ),
          if (amRunner)
            Positioned(
              left: 24,
              right: 24,
              bottom: 24,
              child: SafeArea(
                top: false,
                child: HoldButton(
                  label: "I've been caught (hold)",
                  enabled: showCaughtButton,
                  onComplete: () {
                    final myId = _socket?.currentPlayerId;
                    if (myId != null) _switchRole(myId);
                  },
                  color: Theme.of(context).colorScheme.onPrimary,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  textColor: Theme.of(context).colorScheme.onPrimary,
                  holdDuration: Duration(seconds: 2),
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                ),
              ),
            ),
        ],
      );
    }

    return const Center(child: Text('Waiting for map data...'));
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    // Determine if banner should show
    final showBanner = !_pendingAcceptance && (_gameId != null || _gameStarted || _gameFinished);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldLeave = await _confirmLeave();
        if (shouldLeave && context.mounted) {
          Navigator.popUntil(context, (route) => route.isFirst);
        }
      },
      child: LobbyLayout(
        key: _lobbyKey,
        title: _pendingAcceptance
          ? const Text('Joining...')
          : _gameFinished
            ? const Text('Game Ended')
            : _gameStarted
                ? Text.rich(TextSpan(children: [
                    TextSpan(text: '${widget.playerName}: ${_myRole == 'chaser' ? 'Chaser' : 'Runner'}'),
                    if (isHost)
                      TextSpan(
                        text: ' (host)',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ]))
                : _gameId != null
                    ? Text('Lobby: $_gameId')
                    : const Text('Connecting...'),
        isConnected: _status == 'Connected',
        players: _players,
        chatMessages: _chatMessages,
        currentPlayerId: _socket?.currentPlayerId,
        playerColourMap: _playerColourMap,
        onSendChat: (text) => _socket?.sendChat(text, channel: _activeChannel),
        gameTabBuilder: _buildGameTab,
        mapTabBuilder: (isHost || _gameStarted) ? _buildMapTab : null, // host gets map tab in lobby
        banner: showBanner
          ? GameBanner(
              gameStarted: _gameStarted,
              gameFinished: _gameFinished,
              finishReason: _finishReason,
              isHost: isHost,
              replaySubmitted: _replaySubmitted,
              receivedReplaysCount: _receivedReplays.length,
              totalPlayersCount: _players.length,
              inGracePeriod: _inGracePeriod,
              graceSecondsRemaining: _graceSecondsRemaining,
              myRole: _myRole,
              pendingPlayersCount: _pendingPlayers.length,
              replayFileAssembled: _replayFileAssembled,
              replayFileSentToServer: _replayFileSentToServer,
            )
          : null,
        gameStarted: _gameStarted,
        myRole: _myRole,
        activeChannel: _activeChannel,
        onChannelChanged: (channel) => setState(() => _activeChannel = channel),
      ),
    );
  }
}