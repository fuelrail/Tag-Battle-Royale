import 'dart:math';

import 'package:flutter/material.dart';
import 'package:unique_names_generator/unique_names_generator.dart';

import '/pages/offlinegamelobby.dart';
import '/pages/onlinegamelobby.dart';
import '/util/gamesession.dart';
import '/util/permissions.dart';
import '/util/offline_game_session.dart';
import '/pages/map_editor.dart';
import '/pages/replay_page.dart';

void main() => runApp(const MyApp());


enum GameMode { online, offline }
enum ConnectionRole { host, join }

String generateRandomName() {
  String name;
  do {
    final generator = UniqueNamesGenerator(
      config: Config(
        dictionaries: [adjectives, animals],
        separator: '',
        style: Style.capital,
        length: 2,
      ),
    );
    name = generator.generate();
  } while (name.length > 12);
  return name;
}


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Game Lobby',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: const ColorScheme(
          brightness: Brightness.light,
          primary: Color.fromARGB(255, 235, 127, 26),
          onPrimary: Color.fromARGB(255, 255, 255, 255),
          secondary: Color.fromARGB(255, 255, 219, 172),
          onSecondary: Color.fromARGB(255, 255, 167, 35),
          error: Color.fromARGB(255, 248, 94, 33),
          onError: Colors.white,
          surface: Colors.white,
          onSurface: Colors.black,
          outline: Color.fromARGB(255, 235, 127, 26),
        ),
        inputDecorationTheme: InputDecorationTheme(
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Color.fromARGB(255, 235, 127, 26)),
          ),
          focusedBorder: OutlineInputBorder(
            
            borderSide: BorderSide(color: Color.fromARGB(255, 235, 127, 26), width: 2),
          ),
        ),
      ),
      
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
  OfflineGameSession? _savedOfflineSession;
  String? _reconnectError;

  @override
  void initState() {
    super.initState();
    _checkForSavedSession();
  }

  Future<void> _checkForSavedSession() async {
    final session = await GameSession.load();
    final offlineSession = await OfflineGameSession.load();
    if (mounted) {
      setState(() {
        _savedSession = session;
        _savedOfflineSession = offlineSession;
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

  Future<void> _resumeOffline(BuildContext ctx) async {
    if (_savedOfflineSession == null) return;
    if (!await checkLocationPermission(ctx)) return;
    if (!ctx.mounted) return;

    Navigator.push(
      ctx,
      MaterialPageRoute(
        builder: (_) => OfflineConnectionScreen(
          role: _savedOfflineSession!.isHost
              ? ConnectionRole.host
              : ConnectionRole.join,
          nickName: _savedOfflineSession!.displayName,
          lobbyName: '',
          resumeSession: _savedOfflineSession,
        ),
      ),
    ).then((_) => _checkForSavedSession());
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body:  Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.fromARGB(255, 250, 168, 45),
            Color.fromARGB(255, 250, 144, 45),
            
          ],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Tag Battle Royale',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                ),
              ),
            const SizedBox(height: 8),
            Text('Choose your connection mode',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.white)),
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
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => _reconnect(context),
                ),
              ),
              const SizedBox(height: 8),
              // Go away
              //Align(
              //  alignment: Alignment.centerRight,
              //  child: TextButton(
              //    onPressed: () async {
              //      await GameSession.clear();
              //      _checkForSavedSession();
              //    },
              //    child: const Text('Dismiss'),
              //  ),
              //),
              //const SizedBox(height: 16),
            ],
            if (_savedOfflineSession != null) ...[
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Resume Offline Game'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => _resumeOffline(context),
                ),
              ),
              const SizedBox(height: 16),
            ],
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.onPrimary,
                  foregroundColor: Theme.of(context).colorScheme.primary,
                ),
                icon: const Icon(Icons.cloud),
                label: const Text('Online'),
                onPressed: () => _go(context, GameMode.online),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.onPrimary,
                  foregroundColor: Theme.of(context).colorScheme.primary,
                ),
                icon: const Icon(Icons.bluetooth),
                label: const Text('Offline'),
                onPressed: () => _go(context, GameMode.offline),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
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
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
                icon: const Icon(Icons.location_history),
                label: const Text('Game Replays'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ReplayPage()),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
      )
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
  final _nameCtrl = TextEditingController(text: generateRandomName());
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
        ? generateRandomName()
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
        ? generateRandomName()
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
      appBar: AppBar(
        title: Text('$modeLabel - Host or Join',
          style: Theme.of(context).textTheme.titleLarge),
        iconTheme: IconThemeData(
          color: Theme.of(context).colorScheme.primary,
        ),
        ),
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
              maxLength: 12,
              decoration: InputDecoration(
                labelStyle: Theme.of(context).textTheme.bodyMedium,
                  labelText: 'User Name',
                  ),
            ),

            if (isOnline) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _codeCtrl,
                decoration: InputDecoration(
                    labelStyle: Theme.of(context).textTheme.bodyMedium,
                    labelText: 'Game Code (join only)',
                    counterText: ""
                    ),
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