import 'package:flutter/material.dart';

import '../util/player_data.dart';


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
    this.banner,
    this.gameStarted = false,
    this.myRole = 'runner',
    this.chatEnabled = true,
    this.showChannelSelector = true,
    required this.activeChannel,
    required this.onChannelChanged,
  });

  final Widget title;
  final bool isConnected;
  final List<PlayerData> players;
  final Map<String, List<ChatMessage>> chatMessages; // { channel: messages }
  final String? currentPlayerId;
  final Map<String, Color> playerColourMap; // { playerId: Color }
  final void Function(String text) onSendChat;
  final Widget Function(BuildContext context) gameTabBuilder;
  final Widget Function(BuildContext context)? mapTabBuilder;
  final Widget? banner;
  final bool gameStarted;
  final String myRole;
  final bool chatEnabled;
  final bool showChannelSelector;
  final String activeChannel;
  final void Function(String channel) onChannelChanged;

  @override
  State<LobbyLayout> createState() => LobbyLayoutState();
}

class LobbyLayoutState extends State<LobbyLayout> {
  int _currentTab = 2; // start on game tab
  int _lastMessageCount = 0;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  List<ChatMessage> get _activeMessages =>
      widget.chatMessages[widget.activeChannel] ?? [];

  void switchToGameTab() {
    setState(() => _currentTab = 2);
  }

  // When state changes this is called, check last message count with current,
  // if there is a difference, scroll chat to bottom
  @override
  void didUpdateWidget(LobbyLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newCount = _activeMessages.length;
    if (newCount > _lastMessageCount) {
      _lastMessageCount = newCount;
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
      () => playerColours[widget.playerColourMap.length % playerColours.length],
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

  Widget _buildChannelSelector() {
    final roleLabel = widget.myRole == 'chaser' ? 'Chaser' : 'Runner';
    final roleChannelEnabled = widget.gameStarted;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: _ChannelTab(
              label: 'All',
              selected: widget.activeChannel == 'all',
              enabled: true,
              onTap: () => widget.onChannelChanged('all'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ChannelTab(
              label: roleLabel,
              selected: widget.activeChannel == widget.myRole,
              enabled: roleChannelEnabled,
              onTap: roleChannelEnabled
                  ? () => widget.onChannelChanged(widget.myRole)
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatTab() {
    if (!widget.chatEnabled) {
      return const Center(
        child: Text('Chat not available in active game',
            style: TextStyle(color: Colors.grey)),
      );
    }

    final visiblePlayers = widget.activeChannel == 'all'
      ? widget.players
      : widget.players.where((p) => p.role == widget.activeChannel).toList();
    final messages = _activeMessages;

    return Column(
      children: [
        // Channel selector
        if (widget.showChannelSelector) _buildChannelSelector(),

        // Player chips
        SizedBox(
          height: 68,
          child: visiblePlayers.isEmpty
              ? const Center(
                  child: Text('No players yet', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  itemCount: visiblePlayers.length,
                  itemBuilder: (_, i) {
                    final player = visiblePlayers[i];
                    final colour = _getPlayerColour(player.id);
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
                              child: Text(
                                player.name,
                                style: TextStyle(
                                  color: player.connected ? player.nameColour : Colors.grey,
                                ),
                              ),
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
          child: messages.isEmpty
              ? const Center(
                  child: Text('No messages yet',
                      style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  controller: _chatScrollController,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  itemCount: messages.length,
                  itemBuilder: (_, i) {
                    final msg = messages[i];
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
                  enabled: widget.isConnected,
                  onSubmitted: widget.isConnected ? (_) => _sendChat() : null,
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
                onPressed: widget.isConnected ? _sendChat : null,
                icon: Icon(Icons.send,
                    color: widget.isConnected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFullscreenMap = _currentTab == 0 && widget.gameStarted == true;

    return Scaffold(
    extendBodyBehindAppBar: isFullscreenMap,
    extendBody: isFullscreenMap,
    resizeToAvoidBottomInset: true,
    appBar: AppBar(
      title: widget.title,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Icon(
            widget.isConnected ? Icons.cloud_done : Icons.cloud_off,
            color: widget.isConnected ? Colors.green : Colors.red,
          ),
        ),
      ],
    ),
    body: isFullscreenMap
    ? Stack(
        children: [
          Positioned.fill(
            child: widget.mapTabBuilder?.call(context) ?? _buildDefaultMapTab(),
          ),
          if (widget.banner != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + kToolbarHeight,
              left: 0,
              right: 0,
              child: widget.banner!,
            ),
        ],
      )
    : Column(
        children: [
          if (widget.banner != null) widget.banner!,
          Expanded(
            child: IndexedStack(
              index: _currentTab,
              children: [
                widget.mapTabBuilder?.call(context) ?? _buildDefaultMapTab(),
                _buildChatTab(),
                widget.gameTabBuilder(context),
              ],
            ),
          ),
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
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
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


// --- Channel tab button ---

class _ChannelTab extends StatelessWidget {
  const _ChannelTab({
    required this.label,
    required this.selected,
    required this.enabled,
    this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: !enabled
              ? Colors.grey.shade300
              : selected
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: !enabled
                  ? Colors.grey.shade500
                  : selected
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}