// ignore_for_file: avoid_print

import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';

import '../util/player_data.dart';
import '../util/map_file_handler.dart';
import '../main.dart';
import '../widgets/lobby.dart';
import '../widgets/game_banner.dart';
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
  static const String _joinRequest = 'CMD:JOIN_REQUEST:';
  static const String _playerAccept = 'CMD:PLAYER_ACCEPT:';
  static const String _playerReject = 'CMD:PLAYER_REJECT:';
  static const String _roleUpdate = 'CMD:ROLE_UPDATE:';
  static const String _kick = 'CMD:KICK:';
  static const String _pseudoConfirm = 'CMD:PSEUDOHOST_CONFIRM:';
  static const String _pseudoFail = 'CMD:PSEUDOHOST_FAIL:';
  static const String _pendingDisconnect = 'CMD:PENDING_DISCONNECT:';

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
}

// --------------------------------------------------------------------------
//  Discovered endpoint
// --------------------------------------------------------------------------

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
  final String userName = 'User-${Random().nextInt(100000)}';
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

  // Map
  MapFile? _selectedMap;
  List<int>? _faceOrder; // ordered faceIDsr

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

  // --------------------------------------------------------------------------
  // Lifecycle
  // --------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
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
  
  @override
  void dispose() {
    _isDisconnectingAll = true;
    Nearby().stopAdvertising();
    Nearby().stopDiscovery();
    Nearby().stopAllEndpoints();
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

  // --------------------------------------------------------------------------
  // Incoming Bytes
  // --------------------------------------------------------------------------

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
      setState(() =>
          _pendingGamePlayers.removeWhere((p) => p.userName == joinerUser));
      _addLog('Pending player $joinerUser disconnected');
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
    // Mark host
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
      _revertToJoiner();
      return;
    }

    // Host: direct child disconnected 
    if (isHost && !wasPending) {
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
    if (!isHost && !_inLobby) {
      if (_pendingAcceptance) {
        return _buildPendingView();
      }
      return _buildDiscoveryView();
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        _buildTopSection(context),
        const SizedBox(height: 8),
        Expanded(
          child: DefaultTabController(
            length: isHost ? 3 : 2,
            child: Column(children: [
              TabBar(tabs: [
                const Tab(text: 'Players'),
                if (isHost) const Tab(text: 'Topology'),
                const Tab(text: 'Logs'),
              ]),
              Expanded(
                child: TabBarView(children: [
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

  Widget _buildTopSection(BuildContext context) {
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
            _isAdvertising ? Icons.cell_tower : Icons.cell_tower,
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
    ]);
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
        endpointMap.isNotEmpty || (isHost && _isAdvertising);

    return LobbyLayout(
      title: _inLobby
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
      mapTabBuilder: isHost ? _buildMapTab : null,
      banner: (isHost && _pendingGamePlayers.isNotEmpty)
        ? GameBanner(
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
          )
        : null,
      gameStarted: false,
      myRole: _myRole,
      showChannelSelector: false,
      activeChannel: _activeChannel,
      onChannelChanged: (_) {},
    );
  }
}