// --- Real-time location updates between players ---
//
// Events received from the client:
//   location:update   { lat, lng, heading?, speed?, accuracy? }
//

const MIN_UPDATE_INTERVAL_MS = 500; // max amount of updates that can be sent by client

function registerLocationHandlers(io, socket, gameManager) {
  
  // Player sends their location
  socket.on("location:update", (data) => {
    const player = gameManager.getPlayerBySocketId(socket.id);
    if (!player) {
      console.log(`[location:update] Rejected — socket ${socket.id} not in a game`);
      return;
    }

    const game = gameManager.getGame(player.gameId);
    if (!game || game.status !== "active") {
      console.log(`[location:update] Rejected — game ${player.gameId} not active (status: ${game?.status})`);
      return;
    }

    // Rate limiting
    const now = Date.now();
    if (now - player.lastUpdateAt < MIN_UPDATE_INTERVAL_MS) {
      return; // Silently drop
    }

    if (typeof data.lat !== "number" || typeof data.lng !== "number") {
      console.log(`[location:update] Rejected — invalid lat/lng from "${player.name}" (${player.id})`);
      return socket.emit("error", {
        event: "location:update",
        message: "lat and lng are required numbers",
      });
    }

    if (data.lat < -90 || data.lat > 90 || data.lng < -180 || data.lng > 180) {
      console.log(`[location:update] Rejected — lat/lng out of range from "${player.name}" (${player.id}): ${data.lat}, ${data.lng}`);
      return socket.emit("error", {
        event: "location:update",
        message: "lat/lng out of range",
      });
    }

    // Update
    player.updateLocation(data);
    console.log(`[location:update] "${player.name}" (${player.id}) in game ${player.gameId}: ${data.lat.toFixed(5)}, ${data.lng.toFixed(5)}`);
  });
}

module.exports = { registerLocationHandlers };
