import 'package:flutter_test/flutter_test.dart';
import 'package:tag_battle_royale/util/offline_game_session.dart';
import 'package:tag_battle_royale/util/gamesession.dart';

void main() {
  // --------------------------------------------------------------------------
  //  OfflineGameSession
  // --------------------------------------------------------------------------

  group('OfflineGameSession', () {
    test('round-trip preserves all fields', () {
      final session = OfflineGameSession(
        playerName: 'User-12345',
        displayName: 'CoolFox',
        isHost: true,
        role: 'chaser',
        gameStarted: true,
        gameStartedAt: 1700000000000,
        lobbyName: 'Game-42',
        faceOrder: [3, 1, 4, 1, 5],
        closureIntervalMs: 600000,
        gracePeriodMs: 60000,
        players: [
          {'id': 'User-12345', 'name': 'CoolFox', 'role': 'chaser', 'isHost': true},
          {'id': 'User-67890', 'name': 'FastBear', 'role': 'runner', 'isHost': false},
        ],
        gameFinished: true,
        finalElapsedSeconds: 543.21,
        outOfZoneTimerEnabled: true,
        outOfZoneTimerMs: 180000,
        outOfZoneRemainingMs: 45000,
        inBadZone: true,
      );

      final restored = OfflineGameSession.fromJson(session.toJson());

      expect(restored.playerName, 'User-12345');
      expect(restored.displayName, 'CoolFox');
      expect(restored.isHost, true);
      expect(restored.role, 'chaser');
      expect(restored.gameStartedAt, 1700000000000);
      expect(restored.faceOrder, [3, 1, 4, 1, 5]);
      expect(restored.players.length, 2);
      expect(restored.players[1]['role'], 'runner');
      expect(restored.finalElapsedSeconds, 543.21);
      expect(restored.outOfZoneRemainingMs, 45000);
      expect(restored.inBadZone, true);
    });

    test('empty JSON uses defaults', () {
      final restored = OfflineGameSession.fromJson({});

      expect(restored.playerName, '');
      expect(restored.role, 'runner');
      expect(restored.gameStarted, false);
      expect(restored.faceOrder, isEmpty);
      expect(restored.closureIntervalMs, 900000);
      expect(restored.gracePeriodMs, 90000);
      expect(restored.players, isEmpty);
      expect(restored.outOfZoneTimerEnabled, false);
      expect(restored.inBadZone, false);
    });
  });

  // --------------------------------------------------------------------------
  //  GameSessionData (Online)
  // --------------------------------------------------------------------------

  group('GameSessionData', () {
    test('round-trip preserves all fields', () {
      final json = {
        'gameId': 'ABC123',
        'playerId': 'p-001',
        'playerName': 'CoolFox',
        'isHost': true,
        'gameStarted': true,
        'role': 'chaser',
        'gameStartedAt': 1700000000000,
        'faceOrder': [3, 1, 4],
        'closureIntervalMs': 600000,
        'gracePeriodMs': 60000,
        'replaySubmitted': true,
        'replayFileAssembled': true,
        'replayFileSentToServer': false,
        'players': [
          {'id': 'p-001', 'name': 'CoolFox', 'role': 'chaser', 'connected': true},
          {'id': 'p-002', 'name': 'FastBear', 'role': 'runner', 'connected': false},
        ],
        'gameFinished': true,
        'finishReason': 'all_caught',
        'finalElapsedSeconds': 543.21,
        'outOfZoneTimerEnabled': true,
        'outOfZoneTimerMs': 180000,
        'outOfZoneRemainingMs': 45000,
        'inBadZone': true,
      };

      final session = GameSessionData.fromJson(json);

      expect(session.gameId, 'ABC123');
      expect(session.playerId, 'p-001');
      expect(session.isHost, true);
      expect(session.faceOrder, [3, 1, 4]);
      expect(session.players!.length, 2);
      expect(session.players![1]['connected'], false);
      expect(session.finishReason, 'all_caught');
      expect(session.finalElapsedSeconds, 543.21);
      expect(session.replayFileSentToServer, false);
      expect(session.outOfZoneRemainingMs, 45000);
      expect(session.inBadZone, true);
    });

    test('empty JSON uses defaults', () {
      final session = GameSessionData.fromJson({});

      expect(session.gameId, '');
      expect(session.playerId, '');
      expect(session.isHost, false);
      expect(session.gameStarted, false);
      expect(session.role, isNull);
      expect(session.faceOrder, isNull);
      expect(session.players, isNull);
      expect(session.gameFinished, isNull);
      expect(session.inBadZone, isNull);
    });
  });
}