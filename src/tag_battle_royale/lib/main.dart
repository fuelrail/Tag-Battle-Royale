import 'dart:math';

import 'package:flutter/material.dart';

import '/pages/offlinegamelobby.dart';
import '/pages/onlinegamelobby.dart';
import '/util/gamesession.dart';
import '/util/permissions.dart';
import '/pages/map_editor.dart';

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
  GameSessionData? _savedSession;
  String? _reconnectError;

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
      // Game was active
      Navigator.push(
        ctx,
        MaterialPageRoute(
          builder: (_) => OnlineConnectionScreen(
            role: _savedSession!.isHost
                ? ConnectionRole.host
                : ConnectionRole.join,
            playerName: _savedSession!.playerName,
            gameCode: _savedSession!.gameId,
            playerId: _savedSession!.playerId,
            isHostOverride: _savedSession!.isHost,
          ),
        ),
      // We create a saved session if they leave for if they'd like to reconnect again
      ).then((_) => _checkForSavedSession());
    }
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

            // Reconnect button
            if (_savedSession != null) ...[
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
                onPressed: () => _go(context, GameMode.online),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.cloud_off),
                label: const Text('Offline'),
                onPressed: () => _go(context, GameMode.offline),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.map),
                label: const Text('Map Editor'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MapEditor()),
                  );
                },
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