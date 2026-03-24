import 'dart:math';

import 'package:flutter/material.dart';

import 'offlinegamelobby.dart';
import 'onlinegamelobby.dart';
import 'location_permission.dart';

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
//  Screen 1: Choose Offline or Online mode
// --------------------------------------------------------------------------

class ModeSelectionScreen extends StatelessWidget {
  const ModeSelectionScreen({super.key});

  void _go(BuildContext ctx, GameMode mode) {
    Navigator.push(
      ctx,
      MaterialPageRoute(builder: (_) => RoleSelectionScreen(mode: mode)),
    );
  }

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
                    color: Theme.of(context).colorScheme.surfaceContainerHighest)),
            const SizedBox(height: 48),
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
    _nameCtrl.text = 'Player-${Random().nextInt(10000)}';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkLocationAndGo(BuildContext ctx, ConnectionRole role) async {
    if (!await checkLocationPermission(ctx)) return;
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
        ? 'Player-${Random().nextInt(1000)}'
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
        ? 'Player-${Random().nextInt(1000)}'
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

  @override
  Widget build(BuildContext context) {
    final modeLabel = isOnline ? 'Online' : 'Offline';

    return Scaffold(
      appBar: AppBar(title: Text('$modeLabel — Host or Join')),
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
                  labelText: 'Player Name',
                  border: OutlineInputBorder()),
            ),

            if (isOnline) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _codeCtrl,
                decoration: const InputDecoration(
                    labelText: 'Game Code (join only)',
                    border: OutlineInputBorder(),
                    helperText: 'Leave empty to create a new game'),
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
                onPressed: () => _checkLocationAndGo(context, ConnectionRole.host),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.search),
                label: const Text('Join'),
                onPressed: () => _checkLocationAndGo(context, ConnectionRole.join),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}