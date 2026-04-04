const express = require("express");
const http = require("http");
const { Server } = require("socket.io");
const cors = require("cors");
const { GameManager } = require("./game/GameManager");
const { registerGameHandlers } = require("./handlers/gameHandlers");
const { registerLocationHandlers } = require("./handlers/locationHandlers");
const { registerChatHandlers } = require("./handlers/chatHandlers");
const gameRoutes = require("./routes/gameRoutes");

const PORT = process.env.PORT || 3000;
const CORS_ORIGIN = process.env.CORS_ORIGIN || "*";

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: CORS_ORIGIN,
    methods: ["GET", "POST"],
  },
  pingInterval: 10000, // how often to ping clients (ms)
  pingTimeout: 5000, // how long to wait for pong before disconnect
  maxHttpBufferSize: 6e6, // 6mb limit
});

app.use(cors());
app.use(express.json());

// Game Manager
const gameManager = new GameManager();

// Rest Routes for simple API calls
app.use("/api/games", gameRoutes(gameManager));

app.get("/health", (_req, res) => {
  res.json({
    status: "ok",
    uptime: process.uptime(),
    activeGames: gameManager.getActiveGameCount(),
    connectedPlayers: io.engine.clientsCount,
  });
});

// --- Socket.IO connections ---
//
io.on("connection", (socket) => {
  console.log(`[connect] Client connected: (${socket.id}) (total: ${io.engine.clientsCount})`);

  // Register all event handlers for this socket
  registerGameHandlers(io, socket, gameManager);
  registerLocationHandlers(io, socket, gameManager);
  registerChatHandlers(io, socket, gameManager);

  // --- Disconnect ---
  //
  socket.on("disconnect", (reason) => {
    const player = gameManager.getPlayerBySocketId(socket.id);
    if (player) {
      const gameId = player.gameId;
      const game = gameManager.getGame(gameId);

      if (game && game.status === "waiting") {
        // Lobby phase, fully remove the player, they can rejoin fresh
        gameManager.removePlayer(gameId, player.id);
        gameManager.socketToPlayer.delete(socket.id);
        console.log(`[disconnect] Client: (${socket.id}) Reason: (${reason}) PlayerName: (${player.name}) PlayerId: (${player.id}) "fully removed from lobby game" (${gameId})`);

        if (player.id === game.hostId) {
          // Host left during lobby, disband
          io.to(gameId).emit("game:disbanded", { reason: "Host left the game" });
          gameManager.removeGame(gameId);
          console.log(`[disconnect] Game ${gameId} disbanded (host left)`);
        } else {
          io.to(gameId).emit("player:left", {
            playerId: player.id,
            playerName: player.name,
            remainingPlayers: game.getPlayerList(),
          });
        
          // If no connected players remain, schedule game cleanup
          gameManager.scheduleCleanupIfEmpty(gameId);
        }

      } else if (game) {
        // Active game, mark disconnected, let them reconnect with same identity
        gameManager.disconnectPlayer(socket.id);
        console.log(`[disconnect]  Client: (${socket.id}) Reason: (${reason}) PlayerName: (${player.name}) PlayerId: (${player.id}) "marked disconnected in active game" (${gameId})`);

        io.to(gameId).emit("player:disconnected", {
          playerId: player.id,
          playerName: player.name,
          players: game.getPlayerList(),
        });

        // Stop broadcasting if no connected players remain
        if (game.getConnectedPlayerCount() === 0) {
          game.stopBroadcasting();
          console.log(`[disconnect] Game (${gameId}) broadcast stopped, no connected players`);
        }

        // If no connected players remain, schedule game cleanup
        gameManager.scheduleCleanupIfEmpty(gameId);
      }

    } else {
      console.log(`[disconnect] Client (${socket.id}) was not in any game`);
    }

    const adjustment = (reason === "client namespace disconnect" || reason === "server namespace disconnect") ? 1 : 0;
    console.log(`[disconnect] Remaining connections: ${io.engine.clientsCount - adjustment}`);
  });
});

// Start the server
server.listen(PORT, '0.0.0.0', () => {
  console.log(`\nGame server running on port ${PORT}`);
  console.log(`   REST API:    http://localhost:${PORT}/api/games`);
  console.log(`   Health:      http://localhost:${PORT}/health`);
  console.log(`   WebSocket:   ws://localhost:${PORT}\n`);
});
