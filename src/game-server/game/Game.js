class Game {
  constructor(id, config = {}) {
    this.id = id;
    this.players = new Map(); // { playerId: Player }
    this.status = "waiting"; // waiting or active or finished
    this.createdAt = Date.now();
    this.maxPlayers = config.maxPlayers || 10;
    this.metadata = config.metadata || {};

    // Broadcast config 
    this.broadcastIntervalMs = config.broadcastIntervalMs || 4000;
    this.staleThresholdMs = config.staleThresholdMs || 12000; // no update = stale
    this._broadcastTimer = null;
    this._broadcastCallback = null; // set by GameManager when game starts
  }

  // Players
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

  /// Find a player by name — used for reconnection
  getPlayerByName(name) {
    for (const player of this.players.values()) {
      if (player.name === name) return player;
    }
    return null;
  }

  /// Total players including disconnected
  getPlayerCount() {
    return this.players.size;
  }

  /// Only connected players
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

  // --- Locations for broadcasting ---
  //
  // Builds the payload that gets sent to players each tick.
  // Each player entry includes a status property where:
  //   "active"  = location received within staleThresholdMs
  //   "stale"   = connected but no recent location (GPS lost, backgrounded, etc.)
  //   "unknown" = never sent a location
  //   "disconnected" = player's socket dropped, may reconnect
  getLocationBroadcast() {
    const now = Date.now();
    const players = {};

    for (const [id, player] of this.players) {
      // Disconnected players, still include them so clients can show their state
      if (!player.connected) {
        players[id] = {
          playerId: id,
          playerName: player.name,
          status: "disconnected",
          location: player.location,
          disconnectedAge: now - player.disconnectedAt,
        };
        continue;
      }

      if (!player.location) {
        players[id] = {
          playerId: id,
          playerName: player.name,
          status: "unknown",
          location: null,
        };
      } else {
        const age = now - player.location.timestamp;
        const isStale = age > this.staleThresholdMs;

        players[id] = {
          playerId: id,
          playerName: player.name,
          status: isStale ? "stale" : "active",
          location: {
            lat: player.location.lat,
            lng: player.location.lng,
            heading: player.location.heading,
            speed: player.location.speed,
            accuracy: player.location.accuracy,
            timestamp: player.location.timestamp,
          },
          // Last known location age in ms, used for "last seen X seconds ago"
          locationAge: age,
        };
      }
    }

    return players;
  }

  // Broadcasting
  startBroadcasting(callback) {
    this._broadcastCallback = callback;

    this._broadcastTimer = setInterval(() => {
      if (this._broadcastCallback) {
        const payload = this.getLocationBroadcast();
        this._broadcastCallback(this.id, payload);
      }
    }, 
      this.broadcastIntervalMs
    );
  }

  stopBroadcasting() {
    if (this._broadcastTimer) {
      clearInterval(this._broadcastTimer);
      this._broadcastTimer = null;
    }
    this._broadcastCallback = null;
  }

  // Game life
  start(broadcastCallback) {
    this.status = "active";
    this.startedAt = Date.now();
    this.startBroadcasting(broadcastCallback);
  }

  finish() {
    this.status = "finished";
    this.finishedAt = Date.now();
    this.stopBroadcasting();
  }

  toJSON() {
    return {
      id: this.id,
      status: this.status,
      playerCount: this.getConnectedPlayerCount(),
      maxPlayers: this.maxPlayers,
      players: this.getPlayerList(),
      createdAt: this.createdAt,
      metadata: this.metadata,
    };
  }
}

module.exports = { Game };
