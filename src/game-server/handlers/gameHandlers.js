const { sendChatHistory } = require("./chatHandlers");

// Emits per-socket payloads.
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

/// Check if all runners are caught. If so, finish the game.
function _checkGameOver(io, game) {
  if (game.status !== "active") return;
  if (game.getRemainingRunnerCount() > 0) return;

  game.finishGame("all_caught");

  io.to(game.id).emit("game:finished", {
    gameId: game.id,
    reason: "all_caught",
    finishedAt: game.finishedAt,
    players: game.getPlayerList(),
  });

  console.log(`[game:finished] Game ${game.id} finished, all runners caught`);
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

      // Add to pending
      game.addPendingPlayer(socket.id, playerName.trim());
      gameManager.addPendingPlayer(socket.id, normalizedId);

      console.log(`[game:join] "${playerName.trim()}" added to pending for game ${normalizedId} (${game.pendingPlayers.size} pending)`);

      // Tell the joining player they're pending
      callback({ ok: true, pending: true });

      // Notify the host
      const host = game.getPlayer(game.hostId);
      if (host && host.connected && host.socketId) {
        const hostSocket = io.sockets.sockets.get(host.socketId);
        if (hostSocket) {
          hostSocket.emit("player:pending", {
            socketId: socket.id,
            playerName: playerName.trim(),
            pendingPlayers: game.getPendingPlayerList(),
          });
        }
      }
    } catch (err) {
      emitError(socket, callback, "game:join", err.message);
    }
  });

  // Host accepts a pending player
  socket.on("player:accept", (data, callback) => {
    try {
      const playerInfo = gameManager.getPlayerBySocketId(socket.id);
      if (!playerInfo) {
        return emitError(socket, callback, "player:accept", "Not in a game");
      }

      const game = gameManager.getGame(playerInfo.gameId);
      if (!game) {
        return emitError(socket, callback, "player:accept", "Game not found");
      }

      if (playerInfo.id !== game.hostId) {
        return emitError(socket, callback, "player:accept", "Only the host can accept players");
      }

      const pendingSocketId = data?.socketId;
      if (!pendingSocketId) {
        return emitError(socket, callback, "player:accept", "Socket ID is required");
      }

      const pending = game.getPendingPlayer(pendingSocketId);
      if (!pending) {
        return emitError(socket, callback, "player:accept", "Pending player not found");
      }

      // Remove from pending
      game.removePendingPlayer(pendingSocketId);
      gameManager.removePendingPlayer(pendingSocketId);

      // Add as real player
      const player = gameManager.addPlayerToGame(game.id, pending.playerName, pendingSocketId);
      console.log(`[player:accept] "${player.name}" (${player.id}) accepted into game ${game.id}`);

      // Join the Socket.IO room
      const pendingSocket = io.sockets.sockets.get(pendingSocketId);
      if (pendingSocket) {
        pendingSocket.join(game.id);
        console.log(`[game:join] Socket ${pendingSocket} (${player.id}) joined room ${game.id}`);

        // Tell the accepted player they're in
        pendingSocket.emit("player:accepted", {
          game: game.toJSON(),
          playerId: player.id,
        });

      // Send existing chat history (lobby "all" messages because we know 
      // the game is in lobby phase)
        sendChatHistory(pendingSocket, game, ["all"]);
      }

      if (callback) callback({ ok: true });

      // Tell everyone in the game
      io.to(game.id).emit("player:joined", {
        playerId: player.id,
        playerName: player.name,
        players: game.getPlayerList(),
      });
      console.log(`[game:join] Notified room ${game.id} of new player "${player.name}" (${player.id})`);
    } catch (err) {
      emitError(socket, callback, "player:accept", err.message);
    }
  });

  // Host rejects a pending player
  socket.on("player:reject", (data, callback) => {
    try {
      const playerInfo = gameManager.getPlayerBySocketId(socket.id);
      if (!playerInfo) {
        return emitError(socket, callback, "player:reject", "Not in a game");
      }

      const game = gameManager.getGame(playerInfo.gameId);
      if (!game) {
        return emitError(socket, callback, "player:reject", "Game not found");
      }

      if (playerInfo.id !== game.hostId) {
        return emitError(socket, callback, "player:reject", "Only the host can reject players");
      }

      const pendingSocketId = data?.socketId;
      if (!pendingSocketId) {
        return emitError(socket, callback, "player:reject", "Socket ID is required");
      }

      const pending = game.getPendingPlayer(pendingSocketId);
      if (!pending) {
        return emitError(socket, callback, "player:reject", "Pending player not found");
      }

      // Remove from pending
      game.removePendingPlayer(pendingSocketId);
      gameManager.removePendingPlayer(pendingSocketId);

      console.log(`[player:reject] "${pending.playerName}" rejected from game ${game.id}`);

      // Notify the rejected player
      const pendingSocket = io.sockets.sockets.get(pendingSocketId);
      if (pendingSocket) {
        pendingSocket.emit("player:rejected", {
          reason: "Host rejected your join request",
        });
      }

      if (callback) callback({ ok: true });
    } catch (err) {
      emitError(socket, callback, "player:reject", err.message);
    }
  });

  socket.on("player:kick", (data, callback) => {
    const playerInfo = gameManager.getPlayerBySocketId(socket.id);
    if (!playerInfo) {
      return emitError(socket, callback, "player:kick", "Not in a game");
    }

    const game = gameManager.getGame(playerInfo.gameId);
    if (!game) {
      return emitError(socket, callback, "player:kick", "Game not found");
    }

    if (playerInfo.id !== game.hostId) {
      return emitError(socket, callback, "player:kick", "Only the host can kick players");
    }

    if (game.status === "finished") {
      return emitError(socket, callback, "player:kick", "Cannot kick players after game has ended");
    }

    const targetId = data?.playerId;
    if (!targetId) {
      return emitError(socket, callback, "player:kick", "Player ID is required");
    }

    if (targetId === game.hostId) {
      return emitError(socket, callback, "player:kick", "Cannot kick yourself");
    }

    const targetPlayer = game.getPlayer(targetId);
    if (!targetPlayer) {
      return emitError(socket, callback, "player:kick", "Player not found");
    }

    const targetName = targetPlayer.name;
    const targetSocketId = targetPlayer.socketId;
    const wasRunner = targetPlayer.role === "runner";

    // Remove from game
    gameManager.removePlayer(game.id, targetId);
    if (targetSocketId) {
      gameManager.socketToPlayer.delete(targetSocketId);
    }

    console.log(`[player:kick] "${targetName}" (${targetId}) kicked from game ${game.id}`);

    if (callback) callback({ ok: true });

    // Notify the kicked player
    if (targetSocketId) {
      const targetSocket = io.sockets.sockets.get(targetSocketId);
      if (targetSocket) {
        targetSocket.emit("player:kicked", {
          reason: "You have been kicked by the host",
        });
        targetSocket.leave(game.id);
      }
    }

    // Notify remaining players
    io.to(game.id).emit("player:left", {
      playerId: targetId,
      playerName: targetName,
      remainingPlayers: game.getPlayerList(),
    });

    // Check if last runner was kicked
    if (wasRunner && game.status === "active") {
      _checkGameOver(io, game);
    }

    // Check map confirmations if in starting phase
    if (game.allPlayersConfirmedMap() && game.status === "starting") {
      _finishStarting(io, game, gameManager);
    }
  });

  // Rejoin after a disconnection
  // The client sends their playerId and gameId that they stored from the
  // original join. The server finds their existing player record, updates
  // the socket, and puts them back in the room.
  socket.on("game:rejoin", (data, callback) => {
    try {
      const { gameId, playerId, hasMap, hasReplay } = data;
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

      // Send chat history
      const channels = ["all"];
      if (game.status !== "waiting") {
        channels.push(player.role);
      }
      sendChatHistory(socket, game, channels);

      if (game.mapData && !hasMap) {
        socket.emit("game:map", {
          map: game.mapData,
          faceOrder: game.faceOrder,
          closureIntervalMs: game.closureIntervalMs,
          gracePeriodMs: game.gracePeriodMs,
        });
        console.log(`[game:rejoin] Sent map data to reconnecting player "${player.name} (${player.id})"`);
      }

      // Send stored replays to rejoining host
      if (player.id === game.hostId && game.status === "finished") {
        const storedReplays = game.getStoredReplays();
        for (const { playerId: rpId, data: rpData } of storedReplays) {
          socket.emit("replay:received", { playerId: rpId, replay: rpData });
        }
        if (storedReplays.length > 0) {
          console.log(`[game:rejoin] Sent ${storedReplays.length} stored replays to rejoining host`);
        }
      }

      // Send assembled replay to reconnecting non-host player
      if (player.id !== game.hostId && game.assembledReplay && !hasReplay) {
        socket.emit("replay:file", { replayFile: game.assembledReplay });
        console.log(`[game:rejoin] Sent assembled replay to reconnecting player "${player.name}"`);
      }

      // Send pending players to reconnecting host
      if (player.id === game.hostId && game.pendingPlayers.size > 0) {
        socket.emit("player:pending", {
          pendingPlayers: game.getPendingPlayerList(),
        });
        console.log(`[game:rejoin] Sent ${game.pendingPlayers.size} pending players to reconnecting host`);
      }

      // Restart broadcasting if it was stopped due to all players disconnecting
      // and grace period is over
      if ((game.status === "active" || game.status === "finished") && !game._broadcastTimer && !game.inGracePeriod) {
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
        const pendingList = game.rejectAllPending();
        for (const pending of pendingList) {
          gameManager.removePendingPlayer(pending.socketId);
          const pendingSocket = io.sockets.sockets.get(pending.socketId);
          if (pendingSocket) {
            pendingSocket.emit("player:rejected", {
              reason: "Game disbanded by host",
            });
          }
        }

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

    const gracePeriodMs = data.gracePeriodMs;
    if (typeof gracePeriodMs !== "number" || gracePeriodMs < 0) {
      return emitError(socket, callback, "game:start", "Grace period is required");
    }

    //const runnerCount = Array.from(game.players.values()).filter(p => p.role === "runner").length;
    //if (runnerCount === 0) {
    //  return emitError(socket, callback, "game:start", "At least one runner is required to start");
    //}

    // Auto-reject all pending players
    const pendingList = game.rejectAllPending();
    for (const pending of pendingList) {
      gameManager.removePendingPlayer(pending.socketId);
      const pendingSocket = io.sockets.sockets.get(pending.socketId);
      if (pendingSocket) {
        pendingSocket.emit("player:rejected", {
          reason: "Game has started",
        });
      }
    }
    if (pendingList.length > 0) {
      console.log(`[game:start] Auto-rejected ${pendingList.length} pending players`);
    }

    console.log(`[game:start] Game ${game.id} starting with ${game.getConnectedPlayerCount()} connected players (triggered by socket ${socket.id})`);

    // Store map and enter starting phase
    game.mapData = mapData;
    game.faceOrder = faceOrder;
    game.closureIntervalMs = closureIntervalMs;
    game.gracePeriodMs = gracePeriodMs;
    game.mapConfirmations = new Set();
    game.status = "starting";

    // Broadcast map to all players in the room
    io.to(game.id).emit("game:map", {
      map: mapData,
      faceOrder: game.faceOrder,
      closureIntervalMs: game.closureIntervalMs,
      gracePeriodMs: game.gracePeriodMs,
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

  socket.on("player:role", (data, callback) => {
    const playerInfo = gameManager.getPlayerBySocketId(socket.id);
    if (!playerInfo) {
      return emitError(socket, callback, "player:role", "Not in a game");
    }

    const game = gameManager.getGame(playerInfo.gameId);
    if (!game) {
      return emitError(socket, callback, "player:role", "Game not found");
    }

    const { playerId, role } = data;
    if (!playerId || !["runner", "chaser"].includes(role)) {
      return emitError(socket, callback, "player:role", "Invalid playerId or role");
    }

    // Can't change host's role
    if (playerId === game.hostId) {
      return emitError(socket, callback, "player:role", "Cannot change the host's role");
    }

    // Non-host can only switch themselves from runner to chaser
    if (playerInfo.id !== game.hostId) {
      if (playerId !== playerInfo.id) {
        return emitError(socket, callback, "player:role", "You can only change your own role");
      }
      if (playerInfo.role !== "runner" || role !== "chaser") {
        return emitError(socket, callback, "player:role", "You can only switch from runner to chaser");
      }
    }

    const targetPlayer = game.getPlayer(playerId);
    if (!targetPlayer) {
      return emitError(socket, callback, "player:role", "Player not found");
    }

    const oldRole = targetPlayer.role;
    targetPlayer.role = role;

    // Track catch order when a runner becomes a chaser
    if (oldRole === "runner" && role === "chaser") {
      game.markCaught(playerId);
      console.log(`[player:role] ${targetPlayer.name} caught (#${targetPlayer.caughtOrder}) in game ${game.id}`);
    } else {
      targetPlayer.caughtOrder = null;
      targetPlayer.caughtAt = null;
      console.log(`[player:role] ${targetPlayer.name} role changed from ${oldRole} to ${role} in game ${game.id}`);
    }

    if (callback) callback({ ok: true });

    // Broadcast to all players in the game
    io.to(game.id).emit("player:role:updated", {
      playerId: targetPlayer.id,
      role: role,
    });

    // Send the new role's chat history to the player who switched
    if (oldRole !== role && game.status !== "waiting" && targetPlayer.connected) {
      sendChatHistory(io.sockets.sockets.get(targetPlayer.socketId), game, [role]);
    }

    // Check if all runners are caught
    _checkGameOver(io, game);
  });

  socket.on("game:reorderzones", (data, callback) => {
    const playerInfo = gameManager.getPlayerBySocketId(socket.id);
    if (!playerInfo) {
      return emitError(socket, callback, "game:reorderzones", "Not in a game");
    }

    const game = gameManager.getGame(playerInfo.gameId);
    if (!game) {
      return emitError(socket, callback, "game:reorderzones", "Game not found");
    }

    if (playerInfo.id !== game.hostId) {
      return emitError(socket, callback, "game:reorderzones", "Only the host can reorder zones");
    }

    if (game.status !== "active") {
      return emitError(socket, callback, "game:reorderzones", "Game is not active");
    }

    const newFaceOrder = data?.faceOrder;
    if (!Array.isArray(newFaceOrder) || newFaceOrder.length === 0) {
      return emitError(socket, callback, "game:reorderzones", "Face order is required");
    }

    // Validate same zones, just reordered
    const oldSorted = [...game.faceOrder].sort();
    const newSorted = [...newFaceOrder].sort();
    if (JSON.stringify(oldSorted) !== JSON.stringify(newSorted)) {
      return emitError(socket, callback, "game:reorderzones", "New face order must contain the same zones");
    }

    console.log(`[game:reorderzones] Host reordered zones in game ${game.id}: ${JSON.stringify(newFaceOrder)}`);
    game.faceOrder = newFaceOrder;

    if (callback) callback({ ok: true });

    // Broadcast to all players including host
    io.to(game.id).emit("game:zonesreordered", {
      faceOrder: newFaceOrder,
    });
  });

  socket.on("game:end", (_, callback) => {
    const playerInfo = gameManager.getPlayerBySocketId(socket.id);
    if (!playerInfo) {
      return emitError(socket, callback, "game:end", "Not in a game");
    }

    const game = gameManager.getGame(playerInfo.gameId);
    if (!game) {
      return emitError(socket, callback, "game:end", "Game not found");
    }

    if (playerInfo.id !== game.hostId) {
      return emitError(socket, callback, "game:end", "Only the host can end the game");
    }

    if (game.status !== "active") {
      return emitError(socket, callback, "game:end", "Game is not active");
    }

    console.log(`[game:end] Host ending game ${game.id}`);

    // Switch all remaining runners to chasers (without catch order)
    for (const [id, player] of game.players) {
      if (player.role === "runner") {
        player.role = "chaser";
        console.log(`[game:end] ${player.name} force-switched to chaser`);
      }
    }

    game.finishGame("host_ended");

    if (callback) callback({ ok: true });

    io.to(game.id).emit("game:finished", {
      gameId: game.id,
      reason: "host_ended",
      finishedAt: game.finishedAt,
      players: game.getPlayerList(),
    });

    console.log(`[game:end] Game ${game.id} finished, host ended`);
  });

  socket.on("replay:submit", (data, callback) => {
    const playerInfo = gameManager.getPlayerBySocketId(socket.id);
    if (!playerInfo) {
      return emitError(socket, callback, "replay:submit", "Not in a game");
    }

    const game = gameManager.getGame(playerInfo.gameId);
    if (!game) {
      return emitError(socket, callback, "replay:submit", "Game not found");
    }

    if (game.status !== "finished") {
      return emitError(socket, callback, "replay:submit", "Game is not finished");
    }

    const replayData = data?.replay;
    if (!replayData) {
      return emitError(socket, callback, "replay:submit", "Replay data is required");
    }

    // Store on the game
    game.storeReplay(playerInfo.id, replayData);
    console.log(`[replay:submit] "${playerInfo.name}" (${playerInfo.id}) submitted replay for game ${game.id} (${game.replays.size}/${game.getPlayerCount()} received)`);

    if (callback) callback({ ok: true });

    // Forward to host
    const host = game.getPlayer(game.hostId);
    if (host && host.connected && host.socketId) {
      const hostSocket = io.sockets.sockets.get(host.socketId);
      if (hostSocket) {
        hostSocket.emit("replay:received", {
          playerId: playerInfo.id,
          replay: replayData,
        });
        console.log(`[replay:submit] Forwarded replay from "${playerInfo.name}" to host`);
      }
    }
  });

  socket.on("replay:assembled", (data, callback) => {
    const playerInfo = gameManager.getPlayerBySocketId(socket.id);
    if (!playerInfo) {
      return emitError(socket, callback, "replay:assembled", "Not in a game");
    }

    const game = gameManager.getGame(playerInfo.gameId);
    if (!game) {
      return emitError(socket, callback, "replay:assembled", "Game not found");
    }

    if (playerInfo.id !== game.hostId) {
      return emitError(socket, callback, "replay:assembled", "Only the host can submit assembled replays");
    }

    if (game.status !== "finished") {
      return emitError(socket, callback, "replay:assembled", "Game is not finished");
    }

    const replayFileData = data?.replayFile;
    if (!replayFileData) {
      return emitError(socket, callback, "replay:assembled", "Replay file data is required");
    }

    game.assembledReplay = replayFileData;
    console.log(`[replay:assembled] Host submitted assembled replay for game ${game.id}`);

    if (callback) callback({ ok: true });

    // Broadcast to all non-host connected players
    for (const [id, player] of game.players) {
      if (id === game.hostId) continue;
      if (!player.connected || !player.socketId) continue;
      const playerSocket = io.sockets.sockets.get(player.socketId);
      if (playerSocket) {
        playerSocket.emit("replay:file", { replayFile: replayFileData });
      }
    }
    console.log(`[replay:assembled] Distributed assembled replay to players in game ${game.id}`);
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
  console.log(`[game:start] game: ${game.id} faceOrder: ${JSON.stringify(game.faceOrder)} closureIntervalMs: ${game.closureIntervalMs} grace period: ${game.gracePeriodMs / 1000}s`);
}

function emitError(socket, callback, event, message) {
  console.warn(`[${event}] ERROR for socket ${socket.id}: ${message}`);
  if (callback) callback({ ok: false, error: message });
  socket.emit("error", { event, message });
}

module.exports = { registerGameHandlers };
