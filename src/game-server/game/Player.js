class Player {
  constructor(id, name, socketId, gameId) {
    this.id = id;
    this.name = name;
    this.socketId = socketId;
    this.gameId = gameId;
    this.role = "runner";
    this.location = null;
    this.lastUpdateAt = 0; // last location update time
    this.connectedAt = Date.now();
    this.connected = true;
    this.disconnectedAt = null; // timestamp of last disconnect
  }

  updateLocation(locationData) {
    this.location = {
      lat: locationData.lat,
      lng: locationData.lng,
      heading: locationData.heading ?? null,
      speed: locationData.speed ?? null,
      accuracy: locationData.accuracy ?? null,
      timestamp: Date.now(),
    };
    this.lastUpdateAt = Date.now();
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
    };
  }
}

module.exports = { Player };
