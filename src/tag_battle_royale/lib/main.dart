import 'dart:math';

import 'package:flutter/material.dart';
import 'package:unique_names_generator/unique_names_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '/pages/offlinegamelobby.dart';
import '/pages/onlinegamelobby.dart';
import '/util/gamesession.dart';
import '/util/permissions.dart';
import '/util/offline_game_session.dart';
import '/pages/map_editor.dart';
import '/pages/replay_page.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  await WakelockPlus.enable();

  runApp(const MyApp());
}

enum GameMode { online, offline }
enum ConnectionRole { host, join }

const String defaultServerUrl = 'https://tag-battle-royale.fly.dev/';
const String _serverUrlPrefsKey = 'custom_server_url';

Future<String> getServerUrl() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_serverUrlPrefsKey) ?? defaultServerUrl;
}

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
            resumeSession: _savedSession,
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
      body: Stack(
        children: [
          Container(
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
        ),
        Positioned(
          top: 48,
          left: 16,
          child: IconButton(
            icon: const Icon(Icons.help_outline),
            color: Colors.white,
            iconSize: 32,
            onPressed: () {
              Navigator.of(context).push(
                PageRouteBuilder(
                  opaque: false,
                  barrierColor: Colors.black.withValues(alpha: .55),
                  pageBuilder: (_, __, ___) => const AppTutorialOverlay(),
                ),
              );
            },
          ),
        ),
      ],
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
  final _nameCtrl = TextEditingController(text: generateRandomName());
  final _codeCtrl = TextEditingController();
  int _iconTapCount = 0;

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

  // --- Server URL config ---

  Future<void> _showServerUrlDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getString(_serverUrlPrefsKey) ?? defaultServerUrl;
    final controller = TextEditingController(text: current);

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Server URL'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'URL',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await prefs.remove(_serverUrlPrefsKey);
              controller.text = defaultServerUrl;
            },
            child: const Text('Reset'),
          ),
          FilledButton(
            onPressed: () async {
              final url = controller.text.trim();
              if (url.isEmpty || url == defaultServerUrl) {
                await prefs.remove(_serverUrlPrefsKey);
              } else {
                await prefs.setString(_serverUrlPrefsKey, url);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
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
            GestureDetector(
              onTap: isOnline ? () {
                _iconTapCount++;
                if (_iconTapCount >= 5) {
                  _iconTapCount = 0;
                  _showServerUrlDialog();
                }
              } : null,
              child: Icon(
                isOnline ? Icons.cloud : Icons.wifi_off,
                size: 56,
                color: Theme.of(context).colorScheme.primary,
              ),
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
                    labelText: 'Game Code (required for join)',
                    ),
                textCapitalization: TextCapitalization.characters,
                maxLength: 6,
                onChanged: (_) => setState(() {}),
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
                onPressed: isOnline && _codeCtrl.text.trim().length < 6
                  ? null
                  : () => _checkPermissionsAndGo(context, ConnectionRole.join),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class AppTutorialOverlay extends StatelessWidget {
  const AppTutorialOverlay({super.key});

  final List<_TutorialSectionData> _sections = const [
    _TutorialSectionData(
      title: 'Welcome to Tag Battle Royale',
      text:
          'Tag Battle Royale is designed to organise large scale games of tag.',
    ),
   _TutorialSectionData(
    title: 'Home Page',
    text:
        'The Home Page lets you navigate to:\nOnline Mode\nOffline Mode\nThe Map Editor\nThe Replay Viewer\nIf you leave an unfinished game, a reconnect button will appear here.',
    imagePath: 'assets/tutorial/Homepage.jpg',
  ),

  _TutorialSectionData(
    title: 'Map Editor',
    text:
        'The Map Editor is used to create the map to play on. First, choose the real world location where the game will be played, then capture the map image.',
    imagePath: 'assets/tutorial/google_maps.jpg',
  ),

  _TutorialSectionData(
    title: 'Drawing Zones',
    text:
        'After capturing the map, draw lines on the image to divide it into zones. These zones are used during the game to restrict the runners. You can name the map and name each zone before saving. You can also delete zones',
    imagePath: 'assets/tutorial/map_editor_tools.jpg',
  ),

  _TutorialSectionData(
    title: 'Online Mode',
    text:
        'Online Mode uses an internet connection and our server. The host creates the lobby and players join using the code generated. Online Mode keeps players connected during the game and automatically saves a replay when the game ends.',
  ),

  _TutorialSectionData(
    title: 'Offline Mode',
    text:
        'Offline Mode lets nearby players connect directly to each other. It does not use the online server. Players disconnect during active play, so positions are not shared live and the host will preorder the zone closings. At the end, players reconnect to the host so the replay can be saved.',
  ),

  _TutorialSectionData(
    title: 'Lobby Map Tab',
    text:
        'The Map tab is where the host selects the map for the game. The host can also choose the order that zones will close. In Online Mode, the host can create a new map from this tab.',
    imagePath: 'assets/tutorial/onlineMaps.jpg',
  ),

  _TutorialSectionData(
    title: 'Zone Closing Order',
    text:
        'Zones close during the game based on the order chosen by the host. This controls which areas become unsafe first. In Online Mode, the host can also change the next zone dynamically during the game by selecting a different zone.',
  ),

  _TutorialSectionData(
    title: 'Lobby Chat Tab',
    text:
        'The Chat tab lets players communicate. Before the game starts, players can use the all chat. During the game, runners and chasers also get separate team chats.',
    imagePath: 'assets/tutorial/chat.jpg',
  ),

  _TutorialSectionData(
    title: 'Lobby Game Tab',
    text:
        'The Game tab is where the host manages the lobby. The host can accept incoming players, kick players, change game settings and start the game.',
    imagePath: 'assets/tutorial/accpet_player.jpg',
  ),

  _TutorialSectionData(
    title: 'Game Settings',
    text:
        'The host can adjust the main rules before starting. These include the grace period before tagging begins, how often zones close, and other gameplay options that control how the match runs.',
  ),

  _TutorialSectionData(
    title: 'Starting the Game',
    text:
        'When the host starts the game, players enter the starting phase. The grace period gives players time to spread out before active tagging begins.',
  ),

  _TutorialSectionData(
    title: 'During the Game',
    text:
        'Players move around the real world area shown on the map. Runners try to avoid chasers and stay inside open zones. Chasers try to tag runners. Closed zones will show runners to the chasers or convert them into a chaser.',
    imagePath: 'assets/tutorial/during_game.jpg',
  ),

  _TutorialSectionData(
    title: 'Player Visibility',
    text:
        'In Online Mode, the map can show player positions. Chasers can see other chasers and players who are not in an open zone. This helps enforce the zone rules during play.',
  ),

  _TutorialSectionData(
    title: 'Ending the Game',
    text:
        'In Online Mode, the game can be ended by the host and the replay is saved automatically. In Offline Mode, each player ends the game on their own device, then reconnects to the host to combine and save the replay.',
  ),

  _TutorialSectionData(
    title: 'Replay Viewer',
    text:
        'The Replay Viewer lets you watch saved games. You can play or pause the replay, scrub through time, show or hide selected players, toggle nameplates, minimise the controls and delete old replays.',
    imagePath: 'assets/tutorial/replay_cont.jpg',
  ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.95),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Column(
                      children: [
                        Text(
                          'How to Play',
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.headlineSmall?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),

                        const SizedBox(height: 24),

                        for (final section in _sections) ...[
                          _TutorialSection(section: section),
                          const SizedBox(height: 32),
                        ],

                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Got it'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TutorialSection extends StatelessWidget {
  const _TutorialSection({
    required this.section,
  });

  final _TutorialSectionData section;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          section.title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
        ),

        const SizedBox(height: 8),

        Text(
          section.text,
          textAlign: TextAlign.left,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        if(section.imagePath != null)
          Image.asset(
            section.imagePath!,
            fit: BoxFit.contain,
          ),
      ],
    );
  }
}

class _TutorialSectionData {
  final String title;
  final String text;
  final String? imagePath;

  const _TutorialSectionData({
    required this.title,
    required this.text,
    this.imagePath,
  });
}