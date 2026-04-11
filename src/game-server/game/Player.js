class Player {
  constructor(id, name, socketId, gameId) {
    this.id = id;
    this.name = name;
    this.socketId = socketId;
    this.gameId = gameId;
    this.role = "runner";
    this.zone = null; // faceID (int) if runner is in a zone, null otherwise
    this.location = null;
    this.lastUpdateAt = 0; // last location update time
    this.connectedAt = Date.now();
    this.revealed = false; // whether chasers can see this runner
    this.connected = true;
    this.disconnectedAt = null; // timestamp of last disconnect
    this.caughtOrder = null; // order in which this runner was caught, 1 = first caught
    this.caughtAt = null;    // timestamp when caught
  }

  updateLocation(data) {
    const now = Date.now();
    this.location = {
      x: data.x,
      y: data.y,
      timestamp: now,
    };
    this.zone = data.zone;
    this.revealed = data.revealed;
    this.lastUpdateAt = now;
  }

  /// Mark the player as disconnected but keep them in the game
  markDisconnected() {
    this.connected = false;
    this.disconnectedAt = Date.now();
    this.socketId = null;
  }

  /// Reconnect the player with a new socket
  reconnect(newSocketId) {
    this.connected = true;
    this.disconnectedAt = null;
    this.socketId = newSocketId;
  }

  toJSON() {
    return {
      id: this.id,
      name: this.name,
      role: this.role,
      connected: this.connected,
      location: this.location,
      connectedAt: this.connectedAt,
      caughtOrder: this.caughtOrder,
      caughtAt: this.caughtAt,
    };
  }
}

module.exports = { Player };
