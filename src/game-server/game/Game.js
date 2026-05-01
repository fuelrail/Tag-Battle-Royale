class Game {
  constructor(id, config = {}) {
    this.id = id;
    this.hostId = null;
    this.players = new Map(); // { playerId: Player }
    this.pendingPlayers = new Map(); // { socketId: { socketId, playerName } }
    this.status = "waiting"; // waiting or starting or active or finished
    this.createdAt = Date.now();
    this.startedAt = null;
    this.finishedAt = null;
    this.finishReason = null; // "all_caught" or "host_ended"
    this.maxPlayers = 10;
    this.metadata = config.metadata || {};

    // Broadcast  
    this.broadcastIntervalMs = 5000;
    this.staleThresholdMs = 15000; // no update = stale
    this._broadcastTimer = null;
    this._broadcastCallback = null; // set by GameManager when game starts
    this._graceTimer = null;

    // Map transfer
    this.mapData = null;
    this.mapConfirmations = new Set(); // playerIds that confirmed receival

    // Zone closure
    this.faceOrder = []; // ordered list of faceIDs
    this.closureIntervalMs = null;
    this.gracePeriodMs = null;
    this.outOfZoneTimerEnabled = false;
    this.outOfZoneTimerMs = null;

    // Chat history per channel
    this.chatHistory = {
      all: [],
      runner: [],
      chaser: [],
    };

    this._catchCounter = 0;

    // Replay storage: { playerId: replayJson }
    this.replays = new Map();
    this.assembledReplay = null;
  }

  // --- Players ---

  addPlayer(player) {
    if (this.getConnectedPlayerCount() >= this.maxPlayers) {
      throw new Error("Game is full");
    }
    if (this.status === "finished") {
      throw new Error("Game has ended");
    }
    this.players.set(player.id, player);
  }

  removePlayer(playerId) {
    this.players.delete(playerId);
  }

  getPlayer(playerId) {
    return this.players.get(playerId);
  }

  getPlayerByName(name) {
    for (const player of this.players.values()) {
      if (player.name === name) return player;
    }
    return null;
  }

  getPlayerCount() {
    return this.players.size;
  }

  getConnectedPlayerCount() {
    let count = 0;
    for (const player of this.players.values()) {
      if (player.connected) count++;
    }
    return count;
  }

  getPlayerList() {
    return Array.from(this.players.values()).map((p) => p.toJSON());
  }

  // --- Pending players ---

  addPendingPlayer(socketId, playerName) {
    this.pendingPlayers.set(socketId, { socketId, playerName });
  }

  removePendingPlayer(socketId) {
    this.pendingPlayers.delete(socketId);
  }

  getPendingPlayer(socketId) {
    return this.pendingPlayers.get(socketId);
  }

  getPendingPlayerList() {
    return Array.from(this.pendingPlayers.values());
  }

  rejectAllPending() {
    const pending = this.getPendingPlayerList();
    this.pendingPlayers.clear();
    return pending;
  }

  // --- Catch tracking ---

  /// Mark a player as caught. Returns the catch order number.
  markCaught(playerId) {
    const player = this.getPlayer(playerId);
    if (!player) return null;
    this._catchCounter++;
    player.caughtOrder = this._catchCounter;
    player.caughtAt = Date.now();
    return this._catchCounter;
  }

  /// Returns the number of remaining runners.
  getRemainingRunnerCount() {
    let count = 0;
    for (const player of this.players.values()) {
      if (player.role === "runner") count++;
    }
    return count;
  }

  // --- Replays ---

  storeReplay(playerId, replayData) {
    this.replays.set(playerId, replayData);
  }

  getStoredReplays() {
    return Array.from(this.replays.entries()).map(([playerId, data]) => ({
      playerId,
      data,
    }));
  }

  // --- Chat ---

  addChatMessage(channel, message) {
    if (this.chatHistory[channel]) {
      this.chatHistory[channel].push(message);
    }
  }

  getChatHistory(channel) {
    return this.chatHistory[channel] || [];
  }

  // --- Map transfer ---
  //
  // Check if all connected players have confirmed receiving the map.
  // Called after each game:map:received and after a player disconnects
  // during the starting phase.
  allPlayersConfirmedMap() {
    for (const [id, player] of this.players) {
      if (player.connected && !this.mapConfirmations.has(id)) {
        return false;
      }
    }
    return true;
  }

  // --- Grace period ---

  inGracePeriod() {
    if (!this.startedAt || !this.gracePeriodMs || this.gracePeriodMs <= 0) return false;
    return (Date.now() - this.startedAt) < this.gracePeriodMs;
  }

  // --- Locations for broadcasting ---
  //
  // Builds the payload that gets sent to a player each tick.
  // Each player entry includes a status property where:
  //   "active"  = location received within staleThresholdMs
  //   "stale"   = connected but no recent location (GPS lost, backgrounded, etc.)
  //   "unknown" = never sent a location
  //   "disconnected" = player's socket dropped, may reconnect
  _buildPlayerEntry(id, player) {
    const now = Date.now();

    // Disconnected players, still include them so clients can show their state
    if (!player.connected) {
      return {
        playerId: id,
        playerName: player.name,
        role: player.role,
        status: "disconnected",
        location: player.location, // last known location, may be null
        disconnectedAge: now - player.disconnectedAt,
      };
    }

    if (!player.location) {
      return {
        playerId: id,
        playerName: player.name,
        role: player.role,
        status: "unknown",
        location: null,
      };
    }

    const age = now - player.location.timestamp;
    const isStale = age > this.staleThresholdMs;

    return {
      playerId: id,
      playerName: player.name,
      role: player.role,
      status: isStale ? "stale" : "active",
      location: {
        x: player.location.x,
        y: player.location.y,
        timestamp: player.location.timestamp,
      },
      locationAge: age,
    };
  }

  getEachPlayerBroadcast() {
    // Build entries for every player
    const allEntries = {};
    for (const [id, player] of this.players) {
      allEntries[id] = this._buildPlayerEntry(id, player);
    }

    const result = {}; // { socketId: { playerId: entry, ... } }

    for (const [id, player] of this.players) {
      if (!player.connected) continue;

      if (player.role === "runner") {
        continue;
      }

      // Chasers see other chasers and runners not in a zone (excluding themselves)
      const filtered = {};
      for (const [otherId, otherPlayer] of this.players) {
        if (otherId === id) continue; // skip self

        if (otherPlayer.role === "chaser") {
          filtered[otherId] = allEntries[otherId];
        } else if (otherPlayer.role === "runner" && otherPlayer.revealed) {
          filtered[otherId] = allEntries[otherId];
        }
      }

      result[player.socketId] = filtered;
    }

    return result;
  }

  // --- Broadcasting ---

  startBroadcasting(callback) {
    this._broadcastCallback = callback;

    this._broadcastTimer = setInterval(() => {
      if (this._broadcastCallback) {
        const perPlayer = this.getEachPlayerBroadcast();
        this._broadcastCallback(this.id, perPlayer);
      }
    }, 
      this.broadcastIntervalMs
    );
  }

  stopBroadcasting() {
    if (this._graceTimer) {
      clearTimeout(this._graceTimer);
      this._graceTimer = null;
    }
    if (this._broadcastTimer) {
      clearInterval(this._broadcastTimer);
      this._broadcastTimer = null;
    }
    this._broadcastCallback = null;
  }

  // --- Game life ---

  start(broadcastCallback) {
    this.status = "active";
    this.startedAt = Date.now();

    // Delay broadcasting until grace period is over
    if (this.gracePeriodMs && this.gracePeriodMs > 0) {
      console.log(`[Game] Grace period: ${this.gracePeriodMs / 1000}s, broadcasting delayed`);
      this._graceTimer = setTimeout(() => {
        this._graceTimer = null;
        console.log(`[Game] Grace period over for game ${this.id}, starting broadcasts`);
        this.startBroadcasting(broadcastCallback);
      }, this.gracePeriodMs);
    } else {
      this.startBroadcasting(broadcastCallback);
    }
  }

  /// Finish the game but keep broadcasting so players can find each other.
  finishGame(reason) {
    this.status = "finished";
    this.finishedAt = Date.now();
    this.finishReason = reason;
    // Don't stop broadcasting, all players are chasers now and
    // can use the map to find each other.
  }

  /// Removes the game entirely.
  finish() {
    this.status = "finished";
    this.finishedAt = Date.now();
    this.stopBroadcasting();
  }

  toJSON() {
    return {
      id: this.id,
      hostId: this.hostId,
      status: this.status,
      playerCount: this.getConnectedPlayerCount(),
      maxPlayers: this.maxPlayers,
      players: this.getPlayerList(),
      createdAt: this.createdAt,
      startedAt: this.startedAt,
      finishedAt: this.finishedAt,
      finishReason: this.finishReason,
      metadata: this.metadata,
    };
  }
}

module.exports = { Game };
