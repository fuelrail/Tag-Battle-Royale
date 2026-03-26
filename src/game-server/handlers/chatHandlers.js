// --- Handles chat messages within a game ---
//
// Events received from the client:
//   chat:send   { text }
//
// Events emitted to players:
//   chat:message   { playerId, playerName, text, timestamp }
//

function registerChatHandlers(io, socket, gameManager) {
  socket.on("chat:send", (data) => {
    const player = gameManager.getPlayerBySocketId(socket.id);
    if (!player) return;

    const game = gameManager.getGame(player.gameId);
    if (!game) return;

    const text = data?.text?.trim();
    if (!text) return;

    const message = {
      playerId: player.id,
      playerName: player.name,
      text: text,
      timestamp: Date.now(),
    };

    // Send to everyone in the room including the sender.
    // There is no storage for messages, this means new players will
    // not see old messages.
    io.to(player.gameId).emit("chat:message", message);
    console.log(`[chat:message] "${player.name}" in game ${player.gameId}: ${text}`);
  });
}

module.exports = { registerChatHandlers };