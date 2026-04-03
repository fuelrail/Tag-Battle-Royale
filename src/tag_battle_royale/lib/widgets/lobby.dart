import 'package:flutter/material.dart';

import '/services/game_socket_service.dart';

const List<Color> _playerColours = [
  Colors.red,
  Colors.blue,
  Colors.green,
  Colors.orange,
  Colors.purple,
  Colors.teal,
  Colors.pink,
  Colors.indigo,
  Colors.amber,
  Colors.cyan,
];


class LobbyLayout extends StatefulWidget {
  const LobbyLayout({
    super.key,
    required this.title,
    required this.isConnected,
    required this.players,
    required this.chatMessages,
    required this.currentPlayerId,
    required this.playerColourMap,
    required this.onSendChat,
    required this.gameTabBuilder,
    this.mapTabBuilder,
  });

  final String title;
  final bool isConnected;
  final List<Map<String, String>> players;
  final List<ChatMessage> chatMessages;
  final String? currentPlayerId;
  final Map<String, Color> playerColourMap; // { playerId: Color }
  final void Function(String text) onSendChat;
  final Widget Function(BuildContext context) gameTabBuilder;
  final Widget Function(BuildContext context)? mapTabBuilder;

  @override
  State<LobbyLayout> createState() => LobbyLayoutState();
}

class LobbyLayoutState extends State<LobbyLayout> {
  int _currentTab = 2; // start on game tab
  int _lastMessageCount = 0;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  // When state changes this is called, check last message count with current,
  // if there is a difference, scroll chat to bottom
  @override
  void didUpdateWidget(LobbyLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.chatMessages.length > _lastMessageCount) {
      _lastMessageCount = widget.chatMessages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_chatScrollController.hasClients) {
          _chatScrollController.animateTo(
            _chatScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Color _getPlayerColour(String playerId) {
    return widget.playerColourMap.putIfAbsent(
      playerId,
      () => _playerColours[widget.playerColourMap.length % _playerColours.length],
    );
  }

  void _sendChat() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    widget.onSendChat(text);
    _chatController.clear();
  }

  @override
  void dispose() {
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  // --- Tab Builders ---

  Widget _buildDefaultMapTab() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.map_outlined, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text('Map', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildPlayersTab() {
    return Column(
      children: [
        // Player chips
        SizedBox(
          height: 64,
          child: widget.players.isEmpty
              ? const Center(
                  child: Text('No players yet', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  itemCount: widget.players.length,
                  itemBuilder: (_, i) {
                    final player = widget.players[i];
                    final colour = _getPlayerColour(player['id']!);
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Colour bar on the left
                            Container(
                              width: 4,
                              height: double.infinity,
                              decoration: BoxDecoration(
                                color: colour,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(8),
                                  bottomLeft: Radius.circular(8),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(player['name']!),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),

        const Divider(height: 1),

        // Chat messages
        Expanded(
          child: widget.chatMessages.isEmpty
              ? const Center(
                  child: Text('No messages yet',
                      style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  controller: _chatScrollController,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  itemCount: widget.chatMessages.length,
                  itemBuilder: (_, i) {
                    final msg = widget.chatMessages[i];
                    final colour = _getPlayerColour(msg.playerId);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: '${msg.playerName}: ',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: colour,
                              ),
                            ),
                            TextSpan(
                              text: msg.text,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),

        // Chat input box
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              top: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 0.5,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatController,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendChat(),
                  decoration: InputDecoration(
                    hintText: 'Message...',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _sendChat,
                icon: Icon(Icons.send,
                    color: Theme.of(context).colorScheme.primary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          // Connection status indicator
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Icon(
              widget.isConnected ? Icons.cloud_done : Icons.cloud_off,
              color: widget.isConnected ? Colors.green : Colors.red,
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentTab,
        children: [
          widget.mapTabBuilder?.call(context) ?? _buildDefaultMapTab(),
          _buildPlayersTab(),
          widget.gameTabBuilder(context),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        onDestinationSelected: (i) => setState(() => _currentTab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Players',
          ),
          NavigationDestination(
            icon: Icon(Icons.sports_esports_outlined),
            selectedIcon: Icon(Icons.sports_esports),
            label: 'Game',
          ),
        ],
      ),
    );
  }
}