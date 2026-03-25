// ignore_for_file: avoid_print

import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

import 'package:location/location.dart' as loc;
import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import 'main.dart'; // for ConnectionRole

// Commands
// 
// Direct (between adjacent nodes):
//   CMD:USERNAME:<userName>
//
// Relayed (wrapped in RELAY when non-adjacent):
//   CMD:BECOME_HOST:<lobbyName>
//   CMD:REPORT_CHILD:<parentUserName>:<childUserName>
//   CMD:REPORT_DISCONNECT:<parentUserName>:<childUserName>
//
// Relay wrapper:
//   CMD:RELAY:<senderUserName>:<targetUserName>:<innerMessage>
//   targetUserName can be "HOST" to address the host.

class Cmd {
  static const String _username = 'CMD:USERNAME:';
  static const String _becomeHost = 'CMD:BECOME_HOST:';
  static const String _reportChild = 'CMD:REPORT_CHILD:';
  static const String _reportDisconnect = 'CMD:REPORT_DISCONNECT:';
  static const String _relay = 'CMD:RELAY:';
  static const String hostTarget = 'HOST';

  // Build
  static String username(String name) => '$_username$name';
  static String becomeHost(String lobby) => '$_becomeHost$lobby';
  static String reportChild(String parent, String child) =>
      '$_reportChild$parent:$child';
  static String reportDisconnect(String parent, String child) =>
      '$_reportDisconnect$parent:$child';
  static String relay(String from, String to, String inner) =>
      '$_relay$from:$to:$inner';

  // Check
  static bool isUsername(String message) => message.startsWith(_username);
  static bool isBecomeHost(String message) => message.startsWith(_becomeHost);
  static bool isReportChild(String message) => message.startsWith(_reportChild);
  static bool isReportDisconnect(String message) => message.startsWith(_reportDisconnect);
  static bool isRelay(String message) => message.startsWith(_relay);

  // Parse
  static String parseUsername(String message) => message.substring(_username.length);
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
  final String nickName; // not implemented
  final String lobbyName;

  @override
  State<OfflineConnectionScreen> createState() =>
      _OfflineConnectionScreenState();
}

class _OfflineConnectionScreenState extends State<OfflineConnectionScreen> {
  final String userName = 'User-${Random().nextInt(10000)}';
  final Strategy strategy = Strategy.P2P_CLUSTER;
  final int maxConnections = 1; // needs testing to get the right number, but 3 is probably safe

  // Connected Endpoints
  Map<String, ConnectionInfo> endpointMap = {}; // { endpointId: ConnectionInfo }
  Map<String, String> connectedNames = {}; // { endpointId: userName }

  // Discovered Endpoints
  Map<String, DiscoveredEndpoint> discoveredEndpoints = {}; // { endpointId: DiscoveredEndpoint }

  bool _isActive = false; // advertising or discovering
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

  @override
  void initState() {
    super.initState();
    _lobbyName = widget.lobbyName;
    if (isHost) {
      _tree[userName] = [];
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

  // --- Permissions ---

  Future<bool> _ensurePermissions() async {
    try {
      if (await loc.Location.instance.hasPermission() ==
          loc.PermissionStatus.denied) {
        if (await loc.Location.instance.requestPermission() !=
            loc.PermissionStatus.granted) {
          throw Exception("Location permission not granted");
        }
      }
    } catch (e) {
      print('Location permission check threw: $e');
    }

    try {
      if (!await loc.Location.instance.serviceEnabled()) {
        if (!await loc.Location.instance.requestService()) {
          throw Exception("Location service not enabled");
        }
      }
    } catch (e) {
      _showSnackbar("Please enable location services");
      return false;
    }

    try {
      if (!await ph.Permission.bluetooth.request().isGranted ||
          !await ph.Permission.bluetoothAdvertise.request().isGranted ||
          !await ph.Permission.bluetoothConnect.request().isGranted ||
          !await ph.Permission.bluetoothScan.request().isGranted) {
        throw Exception("Bluetooth permissions not granted");
      }
    } catch (e) {
      _showSnackbar("Please enable bluetooth permissions");
      return false;
    }

    return true;
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
      final name = Cmd.parseUsername(message);
      if (fromEndpointId != null) {
        setState(() => connectedNames[fromEndpointId] = name);
      }
      _showSnackbar("$name connected");
      
    } else if (Cmd.isBecomeHost(message)) {
      final lobby = Cmd.parseBecomeHost(message);
      _showSnackbar("Promoted to pseudo-host for '$lobby'");
      _becomePseudoHost(lobby);
      
    } else if (Cmd.isReportChild(message) && isHost) {
      final (parent, child) = Cmd.parseReportChild(message);
      _hostAddChild(parent, child);
      
    } else if (Cmd.isReportDisconnect(message) && isHost) {
    final (parent, child) = Cmd.parseReportDisconnect(message);
    _hostHandleDisconnect(parent, child);
      
    } else {
      _showSnackbar("msg: $message");
    }
  }

  // --- Host Topology ---

  void _hostAddChild(String parentName, String childName) {
    _tree.putIfAbsent(parentName, () => []);
    _tree[parentName]!.add(childName);
    _tree.putIfAbsent(childName, () => []);
    print('[$userName] topology add: $parentName -> $childName');
    setState(() {}); // refresh topology UI

    // Check if the parent is now at capacity, if so, find next promotion target
    if (_tree[parentName]!.length >= maxConnections) {
      _pseudoHosts.add(parentName);
      _showSnackbar("$parentName is now full. Finding next promotion target…");

      final target = _findClosestNonPseudo();
      if (target == null) {
        _showSnackbar("Network is full, no promotion target.");
        return;
      }

      _showSnackbar("Promoting $target to pseudo-host");
      _pseudoHosts.add(target);
      _sendToDevice(target, Cmd.becomeHost(_lobbyName));
    }
  }

  /// Called by the host when a child disconnects from any node in the tree.
  void _hostHandleDisconnect(String parentName, String childName) {
    _showSnackbar("$childName disconnected from $parentName");

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
      if (!_isActive && isHost) {
        _showSnackbar("Host has capacity again, re-advertising");
        _restartAdvertising();
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
      _showSnackbar("Network is fully saturated, no promotion target.");
      return;
    }

    _showSnackbar("Promoting $target to pseudo-host (post-disconnect)");
    _pseudoHosts.add(target);
    _sendToDevice(target, Cmd.becomeHost(_lobbyName));
  }

  /// Breadth First Search to find the closest userName that is NOT in [_pseudoHosts].
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
      setState(() => _isActive = a);
      _showSnackbar("Pseudo-host advertising '$lobbyName': $a");
    } catch (e) {
      _showSnackbar("Pseudo-host advertising failed: $e");
    }
  }

  /// Revert from pseudo-host back to a regular joiner.
  Future<void> _revertToJoiner() async {
    _showSnackbar("Parent disconnected, reverting to joiner");

    _isDisconnectingAll = true;
    await Nearby().stopAdvertising();
    await Nearby().stopAllEndpoints();
    _isDisconnectingAll = false;

    setState(() {
      _isPseudoHost = false;
      _isActive = false;
      _parentEndpointId = null;
      _lobbyName = '';
      endpointMap.clear();
      connectedNames.clear();
      discoveredEndpoints.clear();
    });
  }

  // --- Advertising ---

  Future<void> _startAdvertising() async {
    if (!await _ensurePermissions()) return;
    _restartAdvertising();
  }

  Future<void> _restartAdvertising() async {
    try {
      await Nearby().stopAdvertising();
      final a = await Nearby().startAdvertising(
        _lobbyName,
        strategy,
        onConnectionInitiated: _onConnectionInit,
        onConnectionResult: (id, status) => _onConnectionResult(id, status),
        onDisconnected: (id) => _onDisconnected(id),
      );
      setState(() => _isActive = a);
      _showSnackbar("Advertising '$_lobbyName': $a");
    } catch (e) {
      _showSnackbar(e);
    }
  }

  Future<void> _stopAdvertising() async {
    await Nearby().stopAdvertising();
    setState(() => _isActive = false);
  }

  // --- Discovery ---

  Future<void> _startDiscovery() async {
    if (!await _ensurePermissions()) return;
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
      setState(() => _isActive = a);
      _showSnackbar("Discovering lobbies…");
    } catch (e) {
      _showSnackbar(e);
    }
  }

  Future<void> _stopDiscovery() async {
    await Nearby().stopDiscovery();
    setState(() {
      _isActive = false;
      discoveredEndpoints.clear();
    });
  }

  /// User tapped a lobby in the list.
  void _joinLobby(DiscoveredEndpoint endpoint) {
    _showSnackbar("Requesting to join '${endpoint.name}'…");
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
    _showSnackbar("Connection result ${_display(id)}: $status");

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

    // Exchange display names.
    _sendBytes(id, Cmd.username(userName));

    // Joiner successfully connected, stop discovering and clear the list
    if (!amHost) {
      _parentEndpointId = id;
      Nearby().stopDiscovery();
      setState(() {
        _isActive = false;
        discoveredEndpoints.clear();
      });
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

    // Check capacity locally, stop advertising if full.
    final int childCount =
        _isPseudoHost ? endpointMap.length - 1 : endpointMap.length;

    if (childCount >= maxConnections) {
      _showSnackbar("At capacity ($childCount/$maxConnections), stopping advertising");
      Nearby().stopAdvertising();
      setState(() => _isActive = false);
    }
  }

  void _onDisconnected(String id) {
    // If we're intentionally disconnecting everything, don't react.
    if (_isDisconnectingAll) return;

    final disconnectedName = connectedNames[id] ?? id;
    _showSnackbar("Disconnected: $disconnectedName");

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
      if (childCount < maxConnections && !_isActive) {
        _showSnackbar("Slot freed, re-advertising '$_lobbyName'");
        _restartAdvertising();
      }
      return;
    }
  }

  // --- Helpers ---

  String _display(String endpointId) =>
      connectedNames[endpointId] ?? endpointId;

  void _showSnackbar(dynamic a) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(a.toString())));
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    String roleLabel;
    if (_isPseudoHost) {
      roleLabel = 'Pseudo-Host';
    } else if (isHost) {
      roleLabel = 'Host';
    } else {
      roleLabel = 'Join';
    }

    return Scaffold(
      appBar: AppBar(title: Text('$roleLabel – $userName')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // Lobby banner
            if (_lobbyName.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Icon(Icons.meeting_room,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Lobby',
                                style:
                                    Theme.of(context).textTheme.labelMedium),
                            Text(_lobbyName,
                                style:
                                    Theme.of(context).textTheme.titleMedium),
                          ]),
                    ),
                  ]),
                ),
              ),

            if (_isPseudoHost)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Chip(
                  avatar: const Icon(Icons.cell_tower, size: 18),
                  label: const Text('Promoted to pseudo-host'),
                  backgroundColor:
                      Theme.of(context).colorScheme.tertiaryContainer,
                ),
              ),

            const SizedBox(height: 12),

            // Controls
            Text(
                amHost
                    ? (_isActive ? 'Advertising' : '')
                    : (_isActive ? 'Discovering' : 'Discovery'),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),

            if (!_isPseudoHost)
              Row(children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _isActive ||
                            (isHost && endpointMap.length >= maxConnections)
                        ? null
                        : (isHost ? _startAdvertising : _startDiscovery),
                    child:
                        Text('Start ${amHost ? "Advertising" : "Discovery"}'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isActive
                        ? (isHost ? _stopAdvertising : _stopDiscovery)
                        : null,
                    child:
                        Text('Stop ${amHost ? "Advertising" : "Discovery"}'),
                  ),
                ),
              ]),

            // Discovered lobbies (joiner only) 
            if (!amHost && discoveredEndpoints.isNotEmpty) ...[
              const SizedBox(height: 24),
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
            ],

            if (!amHost && _isActive && discoveredEndpoints.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Center(
                    child: Column(children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Searching for lobbies…'),
                ])),
              ),

            const SizedBox(height: 24),

            // Connected devices
            Text(
                'Connected: ${endpointMap.length}'
                '${amHost ? " (children: ${_isPseudoHost ? endpointMap.length - 1 : endpointMap.length}/$maxConnections)" : ""}',
                style: Theme.of(context).textTheme.titleMedium),
            if (endpointMap.isNotEmpty)
              ...endpointMap.keys.map((id) {
                final isParent = id == _parentEndpointId;
                return ListTile(
                  leading: Icon(isParent ? Icons.arrow_upward : Icons.phone_android),
                  title: Text(_display(id)),
                  subtitle: Text(isParent ? '$id (parent)' : id),
                );
              }),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.link_off),
              label: const Text('Disconnect All'),
              onPressed: () async {
                _isDisconnectingAll = true;
                await Nearby().stopAdvertising();
                await Nearby().stopDiscovery();
                await Nearby().stopAllEndpoints();
                _isDisconnectingAll = false;

                setState(() {
                  endpointMap.clear();
                  connectedNames.clear();
                  discoveredEndpoints.clear();
                  _isActive = false;
                  _isPseudoHost = false;
                  _parentEndpointId = null;
                  if (!isHost) _lobbyName = '';
                });
              },
            ),

            // Network topology (host only)
            if (isHost && _tree.isNotEmpty) ...[
              const Divider(height: 32),
              Text('Network Topology',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ..._buildTopologyView(userName, 0),
            ],
          ],
        ),
      ),
    );
  }

  /// Recursively build indented topology rows for the host's topology view.
  List<Widget> _buildTopologyView(String node, int depth) {
    final isPseudo = _pseudoHosts.contains(node);
    final isMe = node == userName;
    final label = isMe ? '$node (HOST)' : (isPseudo ? '$node (pseudo)' : node);

    final widgets = <Widget>[
      Padding(
        padding: EdgeInsets.only(left: depth * 20.0),
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
      widgets.addAll(_buildTopologyView(child, depth + 1));
    }

    return widgets;
  }
}