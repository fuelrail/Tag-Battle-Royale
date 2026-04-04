// --- Real-time location updates between players ---
//
// Events received from the client:
//   location:update   { x, y, zone? }
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

    if (typeof data.x !== "number" || typeof data.y !== "number") {
      console.log(`[location:update] Rejected — invalid x/y from "${player.name}" (${player.id})`);
      return socket.emit("error", {
        event: "location:update",
        message: "x and y are required numbers",
      });
    }

    // Update
    player.updateLocation(data);
    console.log(`[location:update] "${player.name}" (${player.id}) in game ${player.gameId}: (${data.x.toFixed(1)}, ${data.y.toFixed(1)})${data.zone != null ? ` zone=${data.zone}` : ''}`);
  });
}

module.exports = { registerLocationHandlers };
