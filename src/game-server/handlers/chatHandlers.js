// --- Handles chat messages within a game ---
//
// Events received from the client:
//   chat:send   { text, channel }    channel: "all", "runner", or "chaser"
//
// Events emitted to players:
//   chat:message   { playerId, playerName, text, timestamp, channel }
//   chat:history   { channel, messages }
//

const VALID_CHANNELS = ["all", "runner", "chaser"];

function registerChatHandlers(io, socket, gameManager) {
  socket.on("chat:send", (data) => {
    const player = gameManager.getPlayerBySocketId(socket.id);
    if (!player) {
      return socket.emit("error", { event: "chat:send", message: "Invalid game" });
    }


    const game = gameManager.getGame(player.gameId);
    if (!game) {
      return socket.emit("error", { event: "chat:send", message: "Invalid game" });
    }

    const text = data?.text?.trim();
    if (!text) {
      return socket.emit("error", { event: "chat:send", message: "Invalid message" });
    }

    const channel = data?.channel;
    if (!channel || !VALID_CHANNELS.includes(channel)) {
      return socket.emit("error", { event: "chat:send", message: "Invalid channel" });
    }

    if (channel === "runner" && player.role !== "runner") {
      return socket.emit("error", { event: "chat:send", message: "You are not a runner" });
    }
    if (channel === "chaser" && player.role !== "chaser") {
      return socket.emit("error", { event: "chat:send", message: "You are not a chaser" });
    }

    if (game.status === "waiting" && channel !== "all") {
      return socket.emit("error", { event: "chat:send", message: "Only 'all' chat is available in lobby" });
    }

    const message = {
      playerId: player.id,
      playerName: player.name,
      text: text,
      timestamp: Date.now(),
      channel: channel,
    };

    game.addChatMessage(channel, message);

    console.log(`[chat] "${player.name}" (${player.id}) in game ${player.gameId} [${channel}]: ${text}`);

    // Broadcast to appropriate players
    if (channel === "all") {
      io.to(game.id).emit("chat:message", message);
    } else {
      // Send only to players with the matching role (also to sending player)
      for (const [id, p] of game.players) {
        if (p.connected && p.role === channel) {
          io.to(p.socketId).emit("chat:message", message);
        }
      }
    }
  });
}

/// Send chat history for given channels to a socket.
/// Called from gameHandlers on join/rejoin.
function sendChatHistory(socket, game, channels) {
  for (const channel of channels) {
    const messages = game.getChatHistory(channel);
    if (messages.length > 0) {
      socket.emit("chat:history", {
        channel: channel,
        messages: messages,
      });
      console.log(`[chat] Sent ${messages.length} ${channel} messages to socket ${socket.id}`);
    }
  }
}

module.exports = { registerChatHandlers, sendChatHistory };