// --- Handles game events ---
//
// Events received from the client:
//   game:create         { playerName, config }
//   game:join           { gameId, playerName }
//   game:rejoin         { gameId, playerId, hasMap }
//   game:leave          (no payload)
//   game:start          { map, faceOrder, closureIntervalMs }
//   game:map:received   (no payload)
//   player:role         { playerId, role }
//
// Events given to client via callback:
//   game:create   { ok, game, playerId }
//   game:join     { ok, game, playerId }
//   game:rejoin   { ok, game, playerId }
//   game:leave    { ok }
//   game:start    { ok }
//   player:role   { ok }
//
// Events emitted to players:
//   player:joined          { playerId, playerName, players }
//   player:left            { playerId, playerName, remainingPlayers }
//   player:reconnected     { playerId, playerName, players }
//   player:disconnected    { playerId, playerName, players }
//   player:role:updated    { playerId, role }
//   game:map               { map, faceOrder, closureIntervalMs }
//   game:started           { gameId, startedAt }
//   game:disbanded         { reason }
//   location:broadcast     (per-socket filtered payload)
//   error                  { event, message }
//

// Emits per-socket payloads.
// perPlayerPayloads is { socketId: filteredPayload }
function makeBroadcastCallback(io, game) {
  return (gId, perPlayerPayloads) => {
    // Log status counts from the actual player list
    const players = Array.from(game.players.values());
    const activeCount = players.filter(p => p.connected && p.location && (Date.now() - p.location.timestamp) <= game.staleThresholdMs).length;
    const staleCount = players.filter(p => p.connected && p.location && (Date.now() - p.location.timestamp) > game.staleThresholdMs).length;
    const unknownCount = players.filter(p => p.connected && !p.location).length;
    const disconnectedCount = players.filter(p => !p.connected).length;
    console.log(`[broadcast] Game ${gId}: ${players.length} players (${activeCount} active, ${staleCount} stale, ${unknownCount} unknown, ${disconnectedCount} disconnected)`);

    for (const [socketId, payload] of Object.entries(perPlayerPayloads)) {
      io.to(socketId).emit("location:broadcast", payload);
    }
  };
}


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

      // Host is always a chaser
      player.role = "chaser";
      game.hostId = player.id;
      console.log(`[game:create] Player "${player.name}" (${player.id}) added as host/chaser to game ${game.id} (${game.getConnectedPlayerCount()} connected)`);

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

      // Don't allow fresh joins to active or starting games
      if (game.status !== "waiting") {
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
      const { gameId, playerId, hasMap } = data;
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

      if (game.mapData && !hasMap) {
        socket.emit("game:map", {
          map: game.mapData,
          faceOrder: game.faceOrder,
          closureIntervalMs: game.closureIntervalMs,
        });
        console.log(`[game:rejoin] Sent map data to reconnecting player "${player.name} (${player.id})"`);
      }

      // Restart broadcasting if it was stopped due to all players disconnecting
      if (game.status === "active" && !game._broadcastTimer) {
        game.startBroadcasting(makeBroadcastCallback(io, game));
        console.log(`[game:rejoin] Restarted broadcast for game ${game.id}`);
      }

      // Re-check map confirmations if we're in starting phase
      if (game.status === "starting") {
        game.mapConfirmations.add(player.id);
        console.log(`[game:rejoin] Auto-confirmed map for reconnecting player "${player.name}" (${game.mapConfirmations.size}/${game.getConnectedPlayerCount()})`);
        if (game.allPlayersConfirmedMap()) {
          _finishStarting(io, game, gameManager);
        }
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
  // Unlike a disconnect, this fully removes the player
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
      if (game.status === "waiting" && playerId === game.hostId) {
        // Host left during lobby, disband
        io.to(gameId).emit("game:disbanded", { reason: "Host left the game" });
        gameManager.removeGame(gameId);
        console.log(`[game:leave] Game ${gameId} disbanded (host left)`);
      } else {
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
    }

    if (callback) callback({ ok: true });
  });


  // Start the game
  // 1. Host sends game:start with map data
  // 2. Server stores map and broadcasts game:map to all players
  // 3. Each player confirms with game:map:received
  // 4. Once all connected players confirmed, game actually starts
  socket.on("game:start", (data, callback) => {
    const playerInfo = gameManager.getPlayerBySocketId(socket.id);
    if (!playerInfo) {
      return emitError(socket, callback, "game:start", "Not in a game");
    }

    const game = gameManager.getGame(playerInfo.gameId);
    if (!game) {
      return emitError(socket, callback, "game:start", "Game not found");
    }

    const mapData = data?.map;
    if (!mapData) {
      return emitError(socket, callback, "game:start", "Map data is required");
    }

    const faceOrder = data.faceOrder;
    if (!Array.isArray(faceOrder) || faceOrder.length === 0) {
      return emitError(socket, callback, "game:start", "Face order is required");
    }

    const closureIntervalMs = data.closureIntervalMs;
    if (typeof closureIntervalMs !== "number" || closureIntervalMs <= 0) {
      return emitError(socket, callback, "game:start", "Closure interval is required");
    }

    console.log(`[game:start] Game ${game.id} starting with ${game.getConnectedPlayerCount()} connected players (triggered by socket ${socket.id})`);

    // Store map and enter starting phase
    game.mapData = mapData;
    game.faceOrder = faceOrder;
    game.closureIntervalMs = closureIntervalMs;
    game.mapConfirmations = new Set();
    game.status = "starting";

    // Broadcast map to all players in the room
    io.to(game.id).emit("game:map", {
      map: mapData,
      faceOrder: game.faceOrder,
      closureIntervalMs: game.closureIntervalMs,
    });
    console.log(`[game:start] Map sent to all players in game ${game.id}, waiting for confirmations`);

    if (callback) callback({ ok: true });
  });

  socket.on("game:map:received", () => {
    const playerInfo = gameManager.getPlayerBySocketId(socket.id);
    if (!playerInfo) return;

    const game = gameManager.getGame(playerInfo.gameId);
    if (!game || game.status !== "starting") return;

    game.mapConfirmations.add(playerInfo.id);
    console.log(`[game:map:received] Player "${playerInfo.name}" confirmed (${game.mapConfirmations.size}/${game.getConnectedPlayerCount()})`);

    if (game.allPlayersConfirmedMap()) {
      _finishStarting(io, game, gameManager);
    }
  });

  // Roles
  socket.on("player:role", (data, callback) => {
    const playerInfo = gameManager.getPlayerBySocketId(socket.id);
    if (!playerInfo) {
      return emitError(socket, callback, "player:role", "Not in a game");
    }

    const game = gameManager.getGame(playerInfo.gameId);
    if (!game) {
      return emitError(socket, callback, "player:role", "Game not found");
    }

    // Only host can switch roles
    if (playerInfo.id !== game.hostId) {
      return emitError(socket, callback, "player:role", "Only the host can switch roles");
    }

    const { playerId, role } = data;
    if (!playerId || !["runner", "chaser"].includes(role)) {
      return emitError(socket, callback, "player:role", "Invalid playerId or role");
    }

    // Can't change host's role
    if (playerId === game.hostId) {
      return emitError(socket, callback, "player:role", "Cannot change the host's role");
    }

    const targetPlayer = game.getPlayer(playerId);
    if (!targetPlayer) {
      return emitError(socket, callback, "player:role", "Player not found");
    }

    targetPlayer.role = role;
    console.log(`[player:role] ${targetPlayer.name} (${targetPlayer.id}) role changed to ${role} in game ${game.id}`);

    if (callback) callback({ ok: true });

    // Broadcast to all players in the game
    io.to(game.id).emit("player:role:updated", {
      playerId: targetPlayer.id,
      role: role,
    });
  });

  // Re-check map confirmations if a player disconnects during starting phase
  // Uses process.nextTick so the main disconnect handler in server.js
  // removes/marks the player first, then we re-check remaining players.
  socket.on("disconnect", () => {
    const playerInfo = gameManager.getPlayerBySocketId(socket.id);
    if (!playerInfo) return;

    const game = gameManager.getGame(playerInfo.gameId);
    if (!game || game.status !== "starting") return;

    process.nextTick(() => {
      if (game.status === "starting" && game.allPlayersConfirmedMap()) {
        console.log(`[game:start] Player disconnected during starting phase, all remaining confirmed`);
        _finishStarting(io, game, gameManager);
      }
    });
  });
}

// Called when all players have confirmed map receipt. Starts the game
// and begins the location broadcast tick.
function _finishStarting(io, game, gameManager) {
  console.log(`[game:start] All players confirmed map, starting game ${game.id}`);

    // Start the game with the broadcast callback.
    // Every tick, this function is called and sends the
    // location payload to every player in the game room.
  game.start(makeBroadcastCallback(io, game));

  io.to(game.id).emit("game:started", {
    gameId: game.id,
    startedAt: game.startedAt,
  });
  console.log(`[game:start] Game ${game.id} started, broadcast tick running every ${game.broadcastIntervalMs}ms`);
  console.log(`[game:start] game: ${game.id} faceOrder: ${JSON.stringify(game.faceOrder)} closureIntervalMs: ${game.closureIntervalMs}`);
}

function emitError(socket, callback, event, message) {
  console.warn(`[${event}] ERROR for socket ${socket.id}: ${message}`);
  if (callback) callback({ ok: false, error: message });
  socket.emit("error", { event, message });
}

module.exports = { registerGameHandlers };
