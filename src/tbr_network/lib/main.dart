import 'dart:math';

import 'package:flutter/material.dart';

import 'offlinegamelobby.dart';
import 'onlinegamescreen.dart';
import 'onlinegamelobby.dart';
import 'storage/gamesession.dart';
import 'permissions.dart';
import '/services/game_socket_service.dart';
import '/services/location_service.dart';

void main() => runApp(const MyApp());


enum GameMode { online, offline }
enum ConnectionRole { host, join }


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Game Lobby',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      home: const ModeSelectionScreen(),
    );
  }
}

// --------------------------------------------------------------------------
//  Screen 1: Reconnect, Offline, Online, Map Editor
// --------------------------------------------------------------------------

class ModeSelectionScreen extends StatefulWidget {
  const ModeSelectionScreen({super.key});

  @override
  State<ModeSelectionScreen> createState() => _ModeSelectionScreenState();
}

class _ModeSelectionScreenState extends State<ModeSelectionScreen> {
  static const String serverUrl = 'https://tag-battle-royale.fly.dev/';
  
  GameSessionData? _savedSession;
  bool _reconnecting = false;
  String? _reconnectError;

  // Socket/location for active game reconnection
  GameSocketService? _socket;
  LocationService? _location;

  @override
  void initState() {
    super.initState();
    _checkForSavedSession();
  }

  Future<void> _checkForSavedSession() async {
    final session = await GameSession.load();
    if (mounted) {
      setState(() {
        _savedSession = session;
        _reconnectError = null;
      });
    }
  }

  void _go(BuildContext ctx, GameMode mode) {
    Navigator.push(
      ctx,
      MaterialPageRoute(builder: (_) => RoleSelectionScreen(mode: mode)),
    ).then((_) => _checkForSavedSession());
  }

  // --- Reconnects ---

  Future<void> _reconnect(BuildContext ctx) async {
    // Could have lost the savedSession
    if (_savedSession == null) return;

    if (!await checkLocationPermission(ctx)) return;
    // We need to check if we are still on this screen because we could have left
    // due to the async await.
    if (!ctx.mounted) return;

    // If the game didn't start, we know we were not a host, because leaving an unstarted
    // game while host disbands it. Our details was not saved on the server, so just
    // join it again anew and move to lobby screen.
    if (!_savedSession!.gameStarted) {
      Navigator.push(
        ctx,
        MaterialPageRoute(
          builder: (_) => OnlineConnectionScreen(
            role: ConnectionRole.join,
            playerName: _savedSession!.playerName,
            gameCode: _savedSession!.gameId,
          ),
        ),
      ).then((_) => _checkForSavedSession());
    } else {
      // Connect via the same socket
      _startActiveReconnect();
    }
  }

  void _startActiveReconnect() {
    setState(() {
      _reconnecting = true;
      _reconnectError = null;
    });

    _socket = GameSocketService(serverUrl: serverUrl);
    _location = LocationService(gameSocketService: _socket!);

    _socket!.currentGameId = _savedSession!.gameId;
    _socket!.currentPlayerId = _savedSession!.playerId;

    _socket!.onRejoined = (data) {
      // This callback could be fired after the user leaves the screen
      // or during the timeout cleanup.
      if (!mounted || !_reconnecting) return;

      _location!.startTracking();

      // We pass a reference to our socket and then unhook and dispose it.
      // This way, if we dispose the game screen, it disposes its version
      // of the socket and avoids a bug where we double dispose.
      final socket = _socket!;
      final location = _location!;
      _socket!.onRejoined = null;
      _socket!.onError = null;
      _socket = null;
      _location = null;

      setState(() => _reconnecting = false);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OnlineGameScreen(
            socket: socket,
            location: location,
            gameId: _savedSession!.gameId,
            isHost: _savedSession!.isHost,
          ),
        ),
      // We create a saved session if they leave for if they'd like to reconnect again
      ).then((_) => _checkForSavedSession());
    };

    _socket!.onError = (event, message) {
      if (!mounted || !_reconnecting) return;
      if (event == 'game:rejoin' || event == 'connection') {
        GameSession.clear();
        _cleanupReconnect();
        setState(() {
          _reconnecting = false;
          _reconnectError = 'Could not reconnect, game may no longer exist';
          _savedSession = null;
        });
      }
    };

    _socket!.connect();

    // Timeout
    Future.delayed(const Duration(seconds: 15), () {
      if (mounted && _reconnecting) {
        GameSession.clear();
        _cleanupReconnect();
        setState(() {
          _reconnecting = false;
          _reconnectError = 'Connection timed out';
          _savedSession = null;
        });
      }
    });
  }

  void _cleanupReconnect() {
    _socket?.onRejoined = null;
    _socket?.onError = null;
    _location?.dispose();
    _socket?.disconnect();
    _socket = null;
    _location = null;
  }


  @override
  void dispose() {
    _cleanupReconnect();
    super.dispose();
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Tag Battle Royale',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text('Choose your connection mode',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 48),

            // Reconnect error message
            if (_reconnectError != null) ...[
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Icon(Icons.error_outline,
                        color: Theme.of(context).colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_reconnectError!)),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Reconnecting spinner
            if (_reconnecting) ...[
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(children: [
                    CircularProgressIndicator(strokeWidth: 2),
                    SizedBox(width: 16),
                    Text('Reconnecting...'),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Reconnect button
            if (_savedSession != null && !_reconnecting) ...[
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: Text('Reconnect to ${_savedSession!.gameId}'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => _reconnect(context),
                ),
              ),
              const SizedBox(height: 8),
              // Go away
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () async {
                    await GameSession.clear();
                    _checkForSavedSession();
                  },
                  child: const Text('Dismiss'),
                ),
              ),
              const SizedBox(height: 16),
            ],

            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                icon: const Icon(Icons.cloud),
                label: const Text('Online'),
                onPressed: _reconnecting ? null : () => _go(context, GameMode.online),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.cloud_off),
                label: const Text('Offline'),
                onPressed: _reconnecting ? null : () => _go(context, GameMode.offline),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------------
//  Screen 2: Host or Join a game
// --------------------------------------------------------------------------

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key, required this.mode});
  final GameMode mode;

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  final _lobbyCtrl = 'Game-${Random().nextInt(10000)}';
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  bool get isOnline => widget.mode == GameMode.online;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  // --- Lobby Push ---

  Future<void> _checkPermissionsAndGo(BuildContext ctx, ConnectionRole role) async {
    if (isOnline) {
      if (!await checkLocationPermission(ctx)) return;
    } else {
      if (!await checkOfflinePermissions(ctx)) return;
    }
    // We need to check if we are still on this screen because we could have left
    // due to the async await.
    if (!ctx.mounted) return;

    if (role == ConnectionRole.host) {
      _goHost(ctx);
    } else {
      _goJoin(ctx);
    }
  }

  void _goHost(BuildContext ctx) {
    final name = _nameCtrl.text.trim().isEmpty
        ? 'Player'
        : _nameCtrl.text.trim();
    if (isOnline) {
      Navigator.push(
        ctx,
        MaterialPageRoute(
          builder: (_) => OnlineConnectionScreen(
            role: ConnectionRole.host,
            playerName: name,
          ),
        ),
      );
    } else {
      final lobby = _lobbyCtrl.trim();
      Navigator.push(
        ctx,
        MaterialPageRoute(
          builder: (_) => OfflineConnectionScreen(
              role: ConnectionRole.host, 
              nickName: name,
              lobbyName: lobby),
        ),
      );
    }
  }

  void _goJoin(BuildContext ctx) {
    final name = _nameCtrl.text.trim().isEmpty
        ? 'Player'
        : _nameCtrl.text.trim();
    if (isOnline) {
      final code = _codeCtrl.text.trim().toUpperCase();
      Navigator.push(
        ctx,
        MaterialPageRoute(
          builder: (_) => OnlineConnectionScreen(
            role: ConnectionRole.join,
            playerName: name,
            gameCode: code.isNotEmpty ? code : null,
          ),
        ),
      );
    } else {
      Navigator.push(
        ctx,
        MaterialPageRoute(
          builder: (_) => OfflineConnectionScreen(
              role: ConnectionRole.join, 
              nickName: name,
              lobbyName: ''),
        ),
      );
    }
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final modeLabel = isOnline ? 'Online' : 'Offline';

    return Scaffold(
      appBar: AppBar(title: Text('$modeLabel - Host or Join')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(
              isOnline ? Icons.cloud : Icons.wifi_off,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('$modeLabel Mode',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 24),

            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                  labelText: 'User Name',
                  border: OutlineInputBorder()),
            ),

            if (isOnline) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _codeCtrl,
                decoration: const InputDecoration(
                    labelText: 'Game Code (join only)',
                    border: OutlineInputBorder()),
                textCapitalization: TextCapitalization.characters,
                maxLength: 6,
              ),
            ],

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                icon: const Icon(Icons.cell_tower),
                label: const Text('Host'),
                onPressed: () => _checkPermissionsAndGo(context, ConnectionRole.host),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.search),
                label: const Text('Join'),
                onPressed: () => _checkPermissionsAndGo(context, ConnectionRole.join),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}