const { v4: uuidv4 } = require("uuid");
const { Game } = require("./Game");
const { Player } = require("./Player");

class GameManager {
  constructor() {
    this.games = new Map(); // { gameId: Game }
    this.socketToPlayer = new Map(); // { socketId: { playerId, gameId } }
  }

  // Games
  createGame(config = {}) {
    const gameId = this.generateGameCode();
    const game = new Game(gameId, config);
    this.games.set(gameId, game);
    console.log(`[GameManager] Game created: ${gameId}`);
    return game;
  }

  getGame(gameId) {
    return this.games.get(gameId) || null;
  }

  removeGame(gameId) {
    const game = this.games.get(gameId);
    if (game) {
      // Stop the broadcast timer so it doesn't keep ticking on a dead game
      game.stopBroadcasting();
      // If the game was active, mark it finished
      if (game.status === "active") {
        game.finish();
      }
      console.log(`[GameManager] Game ${gameId} removed (was ${game.status})`);
    }
    this.games.delete(gameId);
  }

  getActiveGameCount() {
    return this.games.size;
  }

  // Players
  addPlayerToGame(gameId, playerName, socketId) {
    const game = this.games.get(gameId);
    if (!game) throw new Error("Game not found");

    const playerId = uuidv4();
    const player = new Player(playerId, playerName, socketId, gameId);
    game.addPlayer(player);

    this.socketToPlayer.set(socketId, { playerId, gameId });

    console.log(`[GameManager] ${playerName} (${playerId}) joined game ${gameId}`);
    return player;
  }

  // Disconnection, mark player as disconnected
  disconnectPlayer(socketId) {
    const mapping = this.socketToPlayer.get(socketId);
    if (!mapping) return null;

    const game = this.games.get(mapping.gameId);
    if (game) {
      const player = game.getPlayer(mapping.playerId);
      if (player) {
        player.markDisconnected();
        console.log(`[GameManager] Player "${player.name}" (${mapping.playerId}) marked disconnected in game ${mapping.gameId}`);
      }
    }

    // Remove socket mapping — player stays in the game
    this.socketToPlayer.delete(socketId);
    return mapping;
  }

  // Reconnection, restore the disconnected player with a new socket
  // Returns the player if reconnection succeeds, null if not found
  reconnectPlayer(gameId, playerId, newSocketId) {
    const game = this.games.get(gameId);
    if (!game) {
      console.log(`[GameManager] Reconnect failed, game ${gameId} not found`);
      return null;
    }

    const player = game.getPlayer(playerId);
    if (!player) {
      console.log(`[GameManager] Reconnect failed, player ${playerId} not in game ${gameId}`);
      return null;
    }

    player.reconnect(newSocketId);
    this.socketToPlayer.set(newSocketId, { playerId, gameId });
    console.log(`[GameManager] Player "${player.name}" (${playerId}) reconnected to game ${gameId} with socket ${newSocketId}`);
    return player;
  }

  // Fully remove a player
  removePlayer(gameId, playerId) {
    const game = this.games.get(gameId);
    if (game) {
      game.removePlayer(playerId);
    }
  }

  getPlayerBySocketId(socketId) {
    const mapping = this.socketToPlayer.get(socketId);
    if (!mapping) return null;

    const game = this.games.get(mapping.gameId);
    if (!game) return null;

    return game.getPlayer(mapping.playerId);
  }


  // Helpers
  // Generate a game code
  generateGameCode() {
    const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; 
    let code;
    do {
      code = "";
      for (let i = 0; i < 6; i++) {
        code += chars[Math.floor(Math.random() * chars.length)];
      }
    } while (this.games.has(code)); // the code is unique

    return code;
  }

  scheduleCleanupIfEmpty(gameId, delayMs = 30000) {
    const game = this.games.get(gameId);
    if (!game) return;

    if (game.getConnectedPlayerCount() === 0) {
      game.stopBroadcasting();
      console.log(`[GameManager] Game ${gameId} has no connected players, scheduling removal in ${delayMs / 1000}s`);
      setTimeout(() => {
        const g = this.games.get(gameId);
        if (g && g.getConnectedPlayerCount() === 0) {
          this.removeGame(gameId);
          console.log(`[GameManager] Game ${gameId} removed`);
        } else {
          console.log(`[GameManager] Game ${gameId} cleanup skipped, players reconnected`);
        }
      }, delayMs);
    }
  }
}

module.exports = { GameManager };
