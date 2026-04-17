import 'package:flutter/material.dart';

import '../util/player_data.dart';


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
    required this.currentTime,
    this.totalZones = 0,
    this.gameElapsedSeconds,
    required this.zoneClosePeriod,
    this.inBadZone = false,
    this.isOnline = true,
    this.replayFileAssembled = false,
    this.replayFileSentToServer = false,
    this.outOfZoneTimerEnabled = false,
    this.outOfZoneSecondsRemaining,
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
  final bool inBadZone;
  final bool isOnline;
  final int zoneClosePeriod;
  final int? currentTime;
  final int totalZones;
  final double? gameElapsedSeconds;

  final bool replayFileAssembled;
  final bool replayFileSentToServer;

  final bool outOfZoneTimerEnabled;
  final int? outOfZoneSecondsRemaining;

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
    final isRunner = myRole == 'runner';
    final duringGame = gameStarted && !inGracePeriod && !gameFinished;

    // Game finished banner
    if (gameFinished) {
      final finishMessage = finishReason == 'host_ended'
        ? 'Game ended by host'
        : finishReason == 'all_caught'
          ? 'All runners have been caught!'
          : 'Game ended';

      final String subtitle;
      final Color color;

      if (isHost) {
        if (replayFileSentToServer) {
          subtitle = 'Replay assembled and sent to server';
          color = Colors.green;
        } else if (replayFileAssembled) {
          subtitle = 'Sending replay to server...';
          color = Colors.amber.shade700;
        } else {
          subtitle = 'Waiting for replays... ($receivedReplaysCount/$totalPlayersCount)';
          color = Colors.amber.shade700;
        }
      } else {
        if (replayFileAssembled) {
          subtitle = 'Replay received and saved';
          color = Colors.green;
        } else if (replaySubmitted) {
          subtitle = 'Replay sent, waiting for assembled replay...';
          color = Colors.amber.shade700;
        } else {
          subtitle = 'Sending replay...';
          color = Colors.amber.shade700;
        }
      }

      return _banner(
        color: color,
        title: finishMessage,
        subtitle: subtitle,
      );
    }

    // Grace period banner
    if (gameStarted && inGracePeriod && graceSecondsRemaining > 0) {
      final minutes = graceSecondsRemaining ~/ 60;
      final seconds = graceSecondsRemaining % 60;
      final timeStr = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
      return _banner(
        color: isRunner ? Colors.blue : Colors.red,
        title: 'Grace Period: $timeStr',
        subtitle: isRunner ? 'Run!' : 'Stay in place!',
      );
    }

    // runner outside zone banner
    if(inBadZone && duringGame){
      if(isRunner){
        String subtitle = isOnline
            ? 'You are not in an open zone\nThe Chasers can now see you'
            : 'You are not in an open zone';

        if (outOfZoneTimerEnabled && outOfZoneSecondsRemaining != null) {
          final mins = outOfZoneSecondsRemaining! ~/ 60;
          final secs = outOfZoneSecondsRemaining! % 60;
          final timeStr = '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
          subtitle += '\nAuto-catch in: $timeStr';
        }

        return _banner(
          color: Colors.red,
          title: 'Turn Back!',
          subtitle: subtitle,
        );
      }
    }

    // time till next zone close
    if (duringGame && currentTime != null) {
      final totalPeriodSeconds = zoneClosePeriod * 60;
      final elapsedSeconds = currentTime! ~/ 1000;
      final remainingSeconds = totalPeriodSeconds - (elapsedSeconds % totalPeriodSeconds);
      final minutes = remainingSeconds ~/ 60;
      final seconds = remainingSeconds % 60;
      final timeStr = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

      return _banner(
        color: Colors.blue,
        title: 'Time till next zone closing:',
        subtitle: timeStr,
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
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
        ],
      ),
    );
  }
}