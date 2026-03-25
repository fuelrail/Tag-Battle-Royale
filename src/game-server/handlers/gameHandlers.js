// --- Handles game events ---
//
// Events received from the client:
//   game:create   { playerName, config }
//   game:join     { gameId, playerName }
//   game:rejoin   { gameId, playerId }
//   game:leave    (no payload)
//   game:start    (no payload)
//
// Events given to client via callback:
//   game:create   { ok, game, playerId }
//   game:join     { ok, game, playerId }
//   game:rejoin   { ok, game, playerId }
//   game:leave    { ok }
//   game:start    { ok }
//
// Events emitted to players:
//   player:joined        { playerId, playerName, players }
//   player:left          { playerId, playerName, remainingPlayers }
//   player:reconnected   { playerId, playerName, players }
//   player:disconnected  { playerId, playerName, players }
//   game:started         { gameId, startedAt }
//   location:broadcast   { [playerId]: { status, location, ... } }
//   error                { event, message }
//

function registerGameHandlers(io, socket, gameManager) {
  
  // Create a new game
  socket.on("game:create", (data, callback) => {
    try {
      const { playerName, config } = data;
      if (!playerName?.trim()) {
        return emitError(socket, callback, "game:create", "Player name is required");
      }

      // Create the game
      const game = gameManager.createGame(config);
      console.log(`[game:create] Game ${game.id} created by socket ${socket.id}`);

      // Add the creator as the first player
      const player = gameManager.addPlayerToGame(game.id, playerName.trim(), socket.id);
      console.log(`[game:create] Player "${player.name}" (${player.id}) added to game ${game.id} (${game.getConnectedPlayerCount()} connected)`);

      // Join the Socket.IO room
      socket.join(game.id);
      console.log(`[game:create] Socket ${socket.id} (${player.id}) joined room ${game.id}`);

      callback({ ok: true, game: game.toJSON(), playerId: player.id });
    } catch (err) {
      emitError(socket, callback, "game:create", err.message);
    }
  });


  // Join game
  socket.on("game:join", (data, callback) => {
    try {
      const { gameId, playerName } = data;
      if (!playerName?.trim()) {
        return emitError(socket, callback, "game:join", "Player name is required");
      }
      if (!gameId?.trim()) {
        return emitError(socket, callback, "game:join", "Game ID is required");
      }

      const normalizedId = gameId.trim().toUpperCase();
      const game = gameManager.getGame(normalizedId);
      if (!game) {
        return emitError(socket, callback, "game:join", `Game "${normalizedId}" not found`);
      }

      // Don't allow fresh joins to active games, they must use game:rejoin
      if (game.status === "active") {
        return emitError(socket, callback, "game:join", `Game "${normalizedId}" has already started`);
      }

      // Add the player
      const player = gameManager.addPlayerToGame(normalizedId, playerName.trim(), socket.id);
      console.log(`[game:join] Player "${player.name}" (${player.id}) added to game ${normalizedId} (${game.getConnectedPlayerCount()} connected)`);

      // Join the Socket.IO room
      socket.join(normalizedId);
      console.log(`[game:join] Socket ${socket.id} (${player.id}) joined room ${normalizedId}`);

      // Tell the new player they're in
      callback({ ok: true, game: game.toJSON(), playerId: player.id });

      // Tell everyone else in the game
      socket.to(normalizedId).emit("player:joined", {
        playerId: player.id,
        playerName: player.name,
        players: game.getPlayerList(),
      });
      console.log(`[game:join] Notified room ${normalizedId} of new player "${player.name}" (${player.id})`);
    } catch (err) {
      emitError(socket, callback, "game:join", err.message);
    }
  });

  // Rejoin after a disconnection
  // The client sends their playerId and gameId that they stored from the
  // original join. The server finds their existing player record, updates
  // the socket, and puts them back in the room.
  socket.on("game:rejoin", (data, callback) => {
    try {
      const { gameId, playerId } = data;
      if (!gameId || !playerId) {
        return emitError(socket, callback, "game:rejoin", "gameId and playerId are required");
      }

      const normalizedId = gameId.trim().toUpperCase();
      console.log(`[game:rejoin] Socket ${socket.id} attempting to rejoin game ${normalizedId}`);

      const game = gameManager.getGame(normalizedId);
      if (!game) {
        console.log(`[game:rejoin] Reconnect failed, game ${gameId} not found`);
        return emitError(socket, callback, "game:rejoin", "Game no longer exists");
      }

      const player = gameManager.reconnectPlayer(normalizedId, playerId, socket.id);
      if (!player) {
        console.log(`[game:rejoin] Reconnect failed, player ${playerId} not in game ${gameId}`);
        return emitError(socket, callback, "game:rejoin", "Player not found");
      }

      // Rejoin the Socket.IO room
      socket.join(normalizedId);

      console.log(`[game:rejoin] Player "${player.name}" (${player.id}) reconnected to game ${normalizedId} (${game.getConnectedPlayerCount()} connected)`);

      // Tell the reconnected player they're back
      callback({ ok: true, game: game.toJSON(), playerId: player.id });

      // Restart broadcasting if it was stopped due to all players disconnecting
      if (game.status === "active" && !game._broadcasting) {
        game.startBroadcasting((gId, payload) => {
          const playerCount = Object.keys(payload).length;
          const activeCount = Object.values(payload).filter(p => p.status === "active").length;
          const staleCount = Object.values(payload).filter(p => p.status === "stale").length;
          const disconnectedCount = Object.values(payload).filter(p => p.status === "disconnected").length;
          console.log(`[broadcast] Game ${gId}: ${playerCount} players (${activeCount} active, ${staleCount} stale, ${disconnectedCount} disconnected)`);
          io.to(gId).emit("location:broadcast", payload);
        });
        console.log(`[game:rejoin] Restarted broadcast for game ${game.id}`);
      }

      // Notify everyone else
      socket.to(normalizedId).emit("player:reconnected", {
        playerId: player.id,
        playerName: player.name,
        players: game.getPlayerList(),
      });
      console.log(`[game:rejoin] Notified room ${normalizedId} that "${player.name}" (${player.id}) reconnected`);
    } catch (err) {
      emitError(socket, callback, "game:rejoin", err.message);
    }
  });

  // Leave current game
  // Unlike disconnect, this fully removes the player
  socket.on("game:leave", (_, callback) => {
    const player = gameManager.getPlayerBySocketId(socket.id);
    if (!player) {
      return emitError(socket, callback, "game:leave", "Not in a game");
    }

    const gameId = player.gameId;
    const playerName = player.name;
    const playerId = player.id;

    // Remove the player from the game
    gameManager.removePlayer(gameId, playerId);
    // Remove socket mapping
    gameManager.socketToPlayer.delete(socket.id);
    socket.leave(gameId);
    console.log(`[game:leave] Player "${playerName}" (${playerId}) left game ${gameId} (intentional)`);

    const game = gameManager.getGame(gameId);
    if (game) {
      // Notify remaining players
      io.to(gameId).emit("player:left", {
        playerId: playerId,
        playerName: playerName,
        remainingPlayers: game.getPlayerList(),
      });
      console.log(`[game:leave] Game ${gameId} now has ${game.getConnectedPlayerCount()} connected players`);

      // Do cleanup if the game is now empty
      gameManager.scheduleCleanupIfEmpty(gameId);
    }

    if (callback) callback({ ok: true });
  });


  // Start the game
  socket.on("game:start", (_, callback) => {
    const playerInfo = gameManager.getPlayerBySocketId(socket.id);
    if (!playerInfo) {
      return emitError(socket, callback, "game:start", "Not in a game");
    }

    const game = gameManager.getGame(playerInfo.gameId);
    if (!game) {
      return emitError(socket, callback, "game:start", "Game not found");
    }

    console.log(`[game:start] Game ${game.id} starting with ${game.getConnectedPlayerCount()} connected players (triggered by socket ${socket.id})`);

    // Start the game with the broadcast callback.
    // Every tick, this function is called and sends the
    // location payload to every player in the game room.
    game.start((gameId, payload) => {
      const playerCount = Object.keys(payload).length;
      const activeCount = Object.values(payload).filter(p => p.status === "active").length;
      const staleCount = Object.values(payload).filter(p => p.status === "stale").length;
      const disconnectedCount = Object.values(payload).filter(p => p.status === "disconnected").length;
      console.log(`[broadcast] Game ${gameId}: ${playerCount} players (${activeCount} active, ${staleCount} stale, ${disconnectedCount} disconnected)`);
      io.to(gameId).emit("location:broadcast", payload);
    });

    io.to(game.id).emit("game:started", {
      gameId: game.id,
      startedAt: game.startedAt,
    });
    console.log(`[game:start] Game ${game.id} started, broadcast tick running every ${game.broadcastIntervalMs}ms`);

    if (callback) callback({ ok: true });
  });
}


function emitError(socket, callback, event, message) {
  console.warn(`[${event}] ERROR for socket ${socket.id}: ${message}`);
  if (callback) callback({ ok: false, error: message });
  socket.emit("error", { event, message });
}

module.exports = { registerGameHandlers };
