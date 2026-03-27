import 'package:flutter/material.dart';

import '../services/game_socket_service.dart';
import '../services/location_service.dart';

// --------------------------------------------------------------------------
//  Online Game Screen: Where the game is played
// --------------------------------------------------------------------------

class OnlineGameScreen extends StatefulWidget {
  const OnlineGameScreen({
    super.key,
    required this.socket,
    required this.location,
    required this.gameId,
    required this.isHost,
  });

  // Passed from lobby or main
  final GameSocketService socket;
  final LocationService location;
  final String gameId;
  final bool isHost;

  @override
  State<OnlineGameScreen> createState() => _OnlineGameScreenState();
}

class _OnlineGameScreenState extends State<OnlineGameScreen> {
  GameSocketService get _socket => widget.socket;
  LocationService get _location => widget.location;

  final List<String> _log = [];
  final Map<String, PlayerLocationInfo> _playerLocations = {};
  String _connectionStatus = 'Connected';

  @override
  void initState() {
    super.initState();
    _setupCallbacks();
    _addLog('Game ${widget.gameId} in progress');
    _addLog('Role: ${widget.isHost ? "Host" : "Player"}');
  }

  void _setupCallbacks() {
    _socket.onConnected = () {
      if (!mounted) return;
      _location.notifySocketConnected();
      setState(() => _connectionStatus = 'Connected');
      _addLog('Reconnected to server');
    };

    _socket.onDisconnected = () {
      if (!mounted) return;
      _location.notifySocketDisconnected();
      setState(() => _connectionStatus = 'Reconnecting...');
      _addLog('Disconnected, reconnecting...');
    };

    _socket.onRejoined = (data) {
      if (!mounted) return;
      _addLog('Rejoined game');
    };

    _socket.onPlayerJoined = (data) {
      if (!mounted) return;
      _addLog('${data['playerName']} joined');
    };

    _socket.onPlayerLeft = (data) {
      if (!mounted) return;
      final id = data['playerId'];
      setState(() => _playerLocations.remove(id));
      _addLog('Player ${data['playerName'] ?? id} left');
    };

    _socket.onPlayerReconnected = (data) {
      if (!mounted) return;
      _addLog('${data['playerName']} reconnected');
    };

    _socket.onPlayerDisconnected = (data) {
      if (!mounted) return;
      _addLog('${data['playerName']} disconnected');
    };

    _socket.onLocationBroadcast = (players) {
      if (!mounted) return;
      setState(() {
        _playerLocations
          ..clear()
          ..addAll(players);
      });
      _addLog('Received broadcast with ${players.length} players');
    };

    _socket.onError = (event, message) {
      if (!mounted) return;
      _addLog('ERROR [$event]: $message');
    };

    _location.onLog = (msg) {
      if (!mounted) return;
      _addLog(msg);
    };
  }

  void _addLog(String message) {
    if (!mounted) return;
    setState(() {
      _log.insert(0,
          '${DateTime.now().toIso8601String().substring(11, 19)} $message');
      if (_log.length > 100) _log.removeLast();
    });
  }

  void _unhookCallbacks() {
    _location.onLog = null;
    _socket.onConnected = null;
    _socket.onDisconnected = null;
    _socket.onRejoined = null;
    _socket.onPlayerJoined = null;
    _socket.onPlayerLeft = null;
    _socket.onPlayerReconnected = null;
    _socket.onPlayerDisconnected = null;
    _socket.onLocationBroadcast = null;
    _socket.onError = null;
  }

  @override
  void dispose() {
    _unhookCallbacks();
    _location.dispose();
    _socket.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Prevent back button/gesture from leaving the game screen
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          // No back arrow
          automaticallyImplyLeading: false,
          title: Text('Game ${widget.gameId}'),
          actions: [
            // Connection status indicator
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Icon(
                _connectionStatus == 'Connected'
                    ? Icons.cloud_done
                    : Icons.cloud_off,
                color: _connectionStatus == 'Connected'
                    ? Colors.green
                    : Colors.orange,
              ),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Players
              if (_playerLocations.isNotEmpty) ...[
                Text('Players:', style: Theme.of(context).textTheme.titleMedium),
                ..._playerLocations.entries.map((e) {
                  final p = e.value;
                  final locText = p.isDisconnected
                      ? 'Disconnected ${(p.disconnectedAge! / 1000).round()}s ago'
                      : p.isStale
                          ? 'Last seen ${(p.locationAge! / 1000).round()}s ago'
                          : p.isUnknown
                              ? 'No location'
                              : '(${p.lat?.toStringAsFixed(5)}, ${p.lng?.toStringAsFixed(5)})';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '${p.playerName}: $locText',
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  );
                }),
                const SizedBox(height: 16),
              ],

              // Log
              Text('Log:', style: Theme.of(context).textTheme.titleMedium),
              Expanded(
                child: ListView.builder(
                  itemCount: _log.length,
                  itemBuilder: (_, i) => Text(
                    _log[i],
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}