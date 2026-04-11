// ignore_for_file: avoid_print

import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';

import '../services/game_socket_service.dart'; 
import '../util/map_file_handler.dart';
import '../util/player_data.dart';
import '../main.dart';
import '../widgets/lobby.dart';
import '../widgets/map_selector.dart';

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

  // Build
  static String username(String userName, String displayName) =>
      '$_username$userName|$displayName';
  static String becomeHost(String lobby) => '$_becomeHost$lobby';
  static String reportChild(String parent, String child) =>
      '$_reportChild$parent:$child';
  static String reportDisconnect(String parent, String child) =>
      '$_reportDisconnect$parent:$child';
  static String relay(String from, String to, String inner) =>
      '$_relay$from:$to:$inner';
  static String chat(String playerName, String text) =>
      '$_chat$playerName:$text';
  static String playerList(List<Map<String, String>> players) {
    final entries = players.map((p) => '${p['id']}|${p['name']}').join(',');
    return '$_playerList$entries';
  }

  // Check
  static bool isUsername(String message) => message.startsWith(_username);
  static bool isBecomeHost(String message) => message.startsWith(_becomeHost);
  static bool isReportChild(String message) => message.startsWith(_reportChild);
  static bool isReportDisconnect(String message) => message.startsWith(_reportDisconnect);
  static bool isRelay(String message) => message.startsWith(_relay);
  static bool isChat(String message) => message.startsWith(_chat);
  static bool isPlayerList(String message) => message.startsWith(_playerList);

  // Parse
  static (String userName, String displayName) parseUsername(String message) {
    final payload = message.substring(_username.length);
    final parts = payload.split('|');
    return (parts[0], parts[1]);
  }

  static String parseBecomeHost(String message) => message.substring(_becomeHost.length);

  static (String parent, String child) parseReportChild(String message) {
    final p = message.substring(_reportChild.length).split(':');
    return (p[0], p[1]);
  }

  static (String parent, String child) parseReportDisconnect(String message) {
    final p = message.substring(_reportDisconnect.length).split(':');
    return (p[0], p[1]);
  }

  static (String sender, String target, String inner) parseRelay(String message) {
    final payload = message.substring(_relay.length);
    final i1 = payload.indexOf(':');
    final i2 = payload.indexOf(':', i1 + 1);
    return (payload.substring(0, i1), payload.substring(i1 + 1, i2), payload.substring(i2 + 1));
  }

  static (String playerName, String text) parseChat(String message) {
    final payload = message.substring(_chat.length);
    final i = payload.indexOf(':');
    return (payload.substring(0, i), payload.substring(i + 1));
  }

  static List<Map<String, String>> parsePlayerList(String message) {
    final payload = message.substring(_playerList.length);
    final list = <Map<String, String>>[];
    for (final entry in payload.split(',').where((s) => s.isNotEmpty)) {
      final parts = entry.split('|');
      list.add({'id': parts[0], 'name': parts[1]});
    }
    return list;
  }
}

class DiscoveredEndpoint {
  final String id;
  final String name;
  final String serviceId;
  DiscoveredEndpoint(
      {required this.id, required this.name, required this.serviceId});
}

// --------------------------------------------------------------------------
//  Offline Lobby Screen
// --------------------------------------------------------------------------

class OfflineConnectionScreen extends StatefulWidget {
  const OfflineConnectionScreen(
      {super.key, required this.role, required this.nickName, required this.lobbyName});
  final ConnectionRole role;
  final String nickName;
  final String lobbyName;

  @override
  State<OfflineConnectionScreen> createState() =>
      _OfflineConnectionScreenState();
}

class _OfflineConnectionScreenState extends State<OfflineConnectionScreen> {
  final String userName = 'User-${Random().nextInt(10000)}';
  late final String displayName; // nickName if provided, otherwise userName
  final Strategy strategy = Strategy.P2P_CLUSTER;
  final int maxConnections = 1;

  // Connected Endpoints
  Map<String, ConnectionInfo> endpointMap = {}; // { endpointId: ConnectionInfo }
  Map<String, String> connectedNames = {}; // { endpointId: userName }

  // Discovered Endpoints
  Map<String, DiscoveredEndpoint> discoveredEndpoints = {}; // { endpointId: DiscoveredEndpoint }

  bool _isAdvertising = false;
  bool _isDiscovering = false;
  bool _isPseudoHost = false; 
  late String _lobbyName;
  
  /// When true, _onDisconnected callbacks are blocked.
  bool _isDisconnectingAll = false;
  
  String? _parentEndpointId;

  bool get isHost => widget.role == ConnectionRole.host;
  bool get amHost => isHost || _isPseudoHost;

  // Topology (for host)
  final Map<String, List<String>> _tree = {}; // Tree structure
  final Set<String> _pseudoHosts = {}; // Set of userNames that are pseudoHosts already

  // Shared lobby data
  final List<Map<String, String>> _players = []; // [{ id: userName, name: displayName }]
  final Map<String, Color> _playerColourMap = {}; // { playerId: Color }
  final List<ChatMessage> _chatMessages = [];
  final List<String> _log = [];
  bool _showLogs = false; // toggle between connection info and logs in game tab

  MapFile? _selectedMap;
  List<int>? _faceOrder;       // ordered faceIDsr

  @override
  void initState() {
    super.initState();
    displayName = widget.nickName;
    _lobbyName = widget.lobbyName;
    if (isHost) {
      _tree[userName] = [];
      // Add self to player list
      _players.add({'id': userName, 'name': displayName});
      _startAdvertising();
    } else {
      _startDiscovery();
    }
  }
  
  @override
  void dispose() {
    _isDisconnectingAll = true;
    Nearby().stopAdvertising();
    Nearby().stopDiscovery();
    Nearby().stopAllEndpoints();
    super.dispose();
  }

  // Logs

  void _addLog(String message) {
    if (!mounted) return;
    setState(() {
      _log.insert(0,
          '${DateTime.now().toIso8601String().substring(11, 19)} $message');
      if (_log.length > 100) _log.removeLast();
    });
  }

  // --- Display Helpers ---

  /// Returns "displayName (userName)".
  /// If displayName equals userName, just shows userName.
String _displayForUser(String userName) {
    for (final player in _players) {
      if (player['id'] == userName && player['name'] != userName) {
        return '${player['name']} ($userName)';
      }
    }
    return userName;
  }

  // --- Player List ---

  /// Updates the local player list and floods the full list to the network.
  void _broadcastPlayerList() {
    // Ensure every node in the tree has an entry in _players
    for (final userName in _tree.keys) {
      if (!_players.any((player) => player['id'] == userName)) {
        _players.add({'id': userName, 'name': userName});
      }
    }
    // Remove any players no longer in the tree
    _players.removeWhere((p) => !_tree.containsKey(p['id']));

    final msg = Cmd.playerList(_players);
    _flood(msg);
    setState(() {});
  }

  // --- Chat ---

  void _sendChatMessage(String text) {
    if (text.isEmpty) return;
    final msg = Cmd.chat(displayName, text);
    _receiveChatMessage(displayName, text); 
    _flood(msg);
  }

  void _receiveChatMessage(String playerName, String text) {
    setState(() {
      //_chatMessages.add(ChatMessage(
      //  playerId: playerName,
      //  playerName: playerName,
      //  text: text,
      //  timestamp: DateTime.now().millisecondsSinceEpoch,
      //));
    });
  }

  // --- Message Sending ---

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

// --- Incoming Bytes ---

  void _onBytesReceived(String endpointId, Uint8List bytes) {
    final message = String.fromCharCodes(bytes);
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

    final bool forMe =
        to == userName || (to == Cmd.hostTarget && isHost);

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
      final (userName, displayName) = Cmd.parseUsername(message);
      if (fromEndpointId != null) {
        setState(() => connectedNames[fromEndpointId] = userName);
      }
      // Store their display name in the player list
      _players.removeWhere((player) => player['id'] == userName);
      _players.add({'id': userName, 'name': displayName});
      _addLog("${_displayForUser(userName)} connected");
      
    } else if (Cmd.isBecomeHost(message)) {
      final lobby = Cmd.parseBecomeHost(message);
      _addLog("Promoted to pseudo-host for '$lobby'");
      _becomePseudoHost(lobby);
      
    } else if (Cmd.isReportChild(message) && isHost) {
      final (parent, child) = Cmd.parseReportChild(message);
      _hostAddChild(parent, child);
      
    } else if (Cmd.isReportDisconnect(message) && isHost) {
      final (parent, child) = Cmd.parseReportDisconnect(message);
      _hostHandleDisconnect(parent, child);

    } else if (Cmd.isChat(message)) {
      final (playerName, text) = Cmd.parseChat(message);
      _receiveChatMessage(playerName, text);
      // Flood again to reach everyone in tree
      if (fromEndpointId != null) {
        _flood(message, excludeEndpointId: fromEndpointId);
      }

    } else if (Cmd.isPlayerList(message)) {
      final players = Cmd.parsePlayerList(message);
      setState(() {
        _players.clear();
        _players.addAll(players);
      });
      // Flood again to reach everyone in tree
      if (fromEndpointId != null) {
        _flood(message, excludeEndpointId: fromEndpointId);
      }
      
    } else {
      _addLog("msg: $message");
    }
  }

  // --- Host Topology ---

  void _hostAddChild(String parentName, String childName) {
    _tree.putIfAbsent(parentName, () => []);
    _tree[parentName]!.add(childName);
    _tree.putIfAbsent(childName, () => []);
    print('[$userName] topology add: $parentName -> $childName');
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

    print('[$userName] topology after disconnect: $_tree');
    print('[$userName] pseudoHosts after disconnect: $_pseudoHosts');
    _broadcastPlayerList();
    setState(() {});

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
      _addLog("Network is fully saturated, no promotion target.");
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

  // --- Pseudo-Host ---

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
    } catch (e) {
      _addLog("Pseudo-host advertising failed: $e");
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
      _players.clear();
    });

    // Restart discovery to find a new lobby
    _startDiscovery();
  }

  // --- Advertising ---

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

  // --- Discovery ---

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

  // --- Connection Life ---

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
    _addLog("Connection result ${_display(id)}: $status");

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
      _stopDiscovery();
      return;
    }

    // We use id in case something goes wrong
    final childName = connectedNames[id] ?? id;

    // Report new child to the real host, or record locally if I am the host
    if (isHost) {
      _hostAddChild(userName, childName);
    } else {
      _sendToHost(Cmd.reportChild(userName, childName));
    }

    // Check capacity locally, stop advertising if full
    final int childCount =
        _isPseudoHost ? endpointMap.length - 1 : endpointMap.length;

    if (childCount >= maxConnections) {
      _addLog("At capacity ($childCount/$maxConnections), stopping advertising");
      _stopAdvertising();
    }
  }

  void _onDisconnected(String id) {
    // If we're intentionally disconnecting everything, don't react.
    if (_isDisconnectingAll) return;

    final disconnectedName = connectedNames[id] ?? id;
    _addLog("Disconnected: ${_displayForUser(disconnectedName)}");

    setState(() {
      endpointMap.remove(id);
      connectedNames.remove(id);
    });

    // Pseudo-host: check if it was our parent that disconnected
    if (_isPseudoHost && id == _parentEndpointId) {
      _revertToJoiner();
      return;
    }

    // Host: direct child disconnected 
    if (isHost) {
      _hostHandleOwnDisconnect(disconnectedName);
      return;
    }

    // Pseudo-host: one of our children disconnected 
    if (_isPseudoHost) {
      // Tell the host so it can update the tree.
      _sendToHost(Cmd.reportDisconnect(userName, disconnectedName));

      // We now have a free child slot, re-advertise if we had stopped.
      final int childCount = endpointMap.length - 1; // minus parent
      if (childCount < maxConnections && !_isAdvertising) {
        _addLog("Slot freed, re-advertising '$_lobbyName'");
        _startAdvertising();
      }
      return;
    }

    //  Joiner: lost connection to parent, restart discovery
    if (!amHost && id == _parentEndpointId) {
      _addLog("Lost connection to host, restarting discovery");
      _parentEndpointId = null;
      _players.clear();
      _startDiscovery();
      return;
    }
  }

  // --- Helpers ---

  String _display(String endpointId) =>
      connectedNames[endpointId] ?? endpointId;

  void _showSnackbar(dynamic a) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(a.toString())));
  }

  // Tab Builders

  Widget _buildGameTab(BuildContext context) {
    String roleLabel;
    if (_isPseudoHost) {
      roleLabel = 'Pseudo-Host $displayName';
    } else if (isHost) {
      roleLabel = 'Host $displayName';
    } else {
      roleLabel = 'Joiner $displayName';
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Role and lobby info
          Center(
            child: Column(
              children: [
                Text(roleLabel,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                if (_lobbyName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _lobbyName,
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  '${_players.length} player${_players.length == 1 ? '' : 's'} in network',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Capacity display for hosts and pseudo-hosts
          if (amHost) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Capacity (${_isPseudoHost ? endpointMap.length - 1 : endpointMap.length}/$maxConnections)',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(width: 8),
                if (_isAdvertising)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cell_tower, size: 16,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 4),
                      Text('Advertising',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontSize: 13,
                          )),
                    ],
                  )
                else
                  Text('Not Advertising',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 13,
                      )),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // Discovered lobbies (joiner only)
          if (!amHost && discoveredEndpoints.isNotEmpty) ...[
            Text('Available Lobbies',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...discoveredEndpoints.values.map((ep) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.wifi_tethering),
                    title: Text(ep.name),
                    subtitle: Text(ep.id),
                    trailing: FilledButton(
                        onPressed: () => _joinLobby(ep),
                        child: const Text('Join')),
                  ),
                )),
            const SizedBox(height: 16),
          ],

          if (!amHost && _isDiscovering && discoveredEndpoints.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Center(
                  child: Column(children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Searching for lobbies…'),
              ])),
            ),

          // Start game button
          if (isHost) ...[
            SizedBox(
              height: 56,
              child: FilledButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start Game'),
                onPressed: () {
                  _addLog('Start game pressed');
                },
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Toggle between connection info and logs
          Row(
            children: [
              Text(
                _showLogs ? 'Log:' : (isHost ? 'Network Topology:' : 'Connected Devices:'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() => _showLogs = !_showLogs),
                icon: Icon(_showLogs ? Icons.device_hub : Icons.list_alt, size: 18),
                label: Text(_showLogs ? 'Connections' : 'Logs'),
              ),
            ],
          ),
          const SizedBox(height: 4),

          Expanded(
            child: _showLogs
                ? _buildLogView()
                : (isHost ? _buildTopologyWidget() : _buildConnectedDevicesWidget()),
          ),
        ],
      ),
    );
  }

  Widget _buildLogView() {
    return ListView.builder(
      itemCount: _log.length,
      itemBuilder: (_, i) => Text(
        _log[i],
        style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
      ),
    );
  }

  Widget _buildTopologyWidget() {
    if (_tree.isEmpty) {
      return const Center(
          child: Text('No connections', style: TextStyle(color: Colors.grey)));
    }
    return ListView(
      children: _buildTopologyRows(userName, 0),
    );
  }

  List<Widget> _buildTopologyRows(String node, int depth) {
    final isPseudo = _pseudoHosts.contains(node);
    final isMe = node == userName;
    // Show "nickname (userName)" in topology, with role
    final nameLabel = _displayForUser(node);
    final label = isMe ? '$nameLabel (HOST)' : (isPseudo ? '$nameLabel (pseudo)' : nameLabel);

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
          Text(label,
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

  Widget _buildConnectedDevicesWidget() {
    if (endpointMap.isEmpty) {
      return const Center(
          child: Text('No connections', style: TextStyle(color: Colors.grey)));
    }
    return ListView(
      children: endpointMap.keys.map((id) {
        final isParent = id == _parentEndpointId;
        final userName = connectedNames[id] ?? id;
        return ListTile(
          leading: Icon(isParent ? Icons.arrow_upward : Icons.phone_android),
          title: Text(_displayForUser(userName)),
          subtitle: Text(isParent ? '$id (parent)' : id),
        );
      }).toList(),
    );
  }

  Widget _buildMapTab(BuildContext context) {
    return MapSelector(
      canCreateMaps: false,
      selectedMapName: _selectedMap?.mapName,
      selectedMapId: _selectedMap?.id,
        onMapSelected: (map, faces) {
          setState(() {
            _selectedMap = map;
            if (faces != null) {
              _faceOrder = faces.map<int>((f) => f.faceID as int).toList();
            } else {
              _faceOrder = null;
            }
          });
          if (map != null) {
            _addLog('Selected map: ${map.mapName}');
          } else {
            _addLog('Map failed to select');
          };
        },
      );
    }

  @override
  Widget build(BuildContext context) {
    String title;
    if (_lobbyName.isNotEmpty) {
      title = 'Offline: $_lobbyName';
    } else if (amHost) {
      title = 'Offline: Host';
    } else {
      title = 'Offline: Joiner';
    }

    List<PlayerData> testing = [];

    return Container();

    //return LobbyLayout(
    //  title: title,
    //  isConnected: endpointMap.isNotEmpty || (isHost && _isAdvertising),
    //  players: testing,
    //  chatMessages: _chatMessages,
    //  currentPlayerId: userName,
    //  playerColourMap: _playerColourMap,
    //  onSendChat: _sendChatMessage,
    //  gameTabBuilder: _buildGameTab,
    //  mapTabBuilder: isHost ? _buildMapTab : null,
    //);
  }
}