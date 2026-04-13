import 'package:flutter/material.dart';

class GameBanner extends StatelessWidget {
  const GameBanner({
    super.key,
    required this.gameStarted,
    required this.gameFinished,
    this.finishReason,
    required this.isHost,
    required this.replaySubmitted,
    required this.receivedReplaysCount,
    required this.totalPlayersCount,
    required this.inGracePeriod,
    required this.graceSecondsRemaining,
    required this.myRole,
    required this.pendingPlayersCount,
  });

  final bool gameStarted;
  final bool gameFinished;
  final String? finishReason;
  final bool isHost;
  final bool replaySubmitted;
  final int receivedReplaysCount;
  final int totalPlayersCount;
  final bool inGracePeriod;
  final int graceSecondsRemaining;
  final String myRole;
  final int pendingPlayersCount;

  @override
  Widget build(BuildContext context) {
    // Pending players banner (host only, lobby phase)
    if (isHost && !gameStarted && !gameFinished && pendingPlayersCount > 0) {
      final label = pendingPlayersCount == 1
        ? '1 Player Waiting to Join'
        : '$pendingPlayersCount Players Waiting to Join';
      return _banner(
        color: Colors.purple,
        title: label,
        subtitle: 'Accept in the player list',
      );
    }

    // Game finished banner
    if (gameFinished) {
      final String message;
      final Color color;

      if (isHost) {
        final allReceived = receivedReplaysCount >= totalPlayersCount;
        message = allReceived ? 'All Replays Received.' : 'Receiving Replays...';
        color = allReceived ? Colors.green : Colors.amber.shade700;
      } else {
        message = replaySubmitted ? 'Replay Sent.' : 'Sending Replay...';
        color = replaySubmitted ? Colors.green : Colors.amber.shade700;
      }

      final finishMessage = finishReason == 'host_ended'
        ? 'Game ended by host'
        : 'All runners have been caught!';

      return _banner(
        color: color,
        title: finishMessage,
        subtitle: message,
      );
    }

    // Grace period banner
    if (gameStarted && inGracePeriod && graceSecondsRemaining > 0) {
      final isRunner = myRole == 'runner';
      final minutes = graceSecondsRemaining ~/ 60;
      final seconds = graceSecondsRemaining % 60;
      final timeStr = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

      return _banner(
        color: isRunner ? Colors.blue : Colors.red,
        title: 'Grace Period: $timeStr',
        subtitle: isRunner ? 'Run!' : 'Stay in place!',
      );
    }

    return const SizedBox.shrink();
  }

  Widget _banner({
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      color: color,
      child: Column(
        children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(subtitle,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
        ],
      ),
    );
  }
}