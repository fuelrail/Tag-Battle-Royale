const express = require("express");

// --- REST calls ---
//
//  GET    /api/games/:id      — Get game info (check if it exists before joining)
//  GET    /api/games          — List active games, should change to not started*
function gameRoutes(gameManager) {
  const router = express.Router();

  // GET specific game details
  router.get("/:id", (req, res) => {
    const game = gameManager.getGame(req.params.id.toUpperCase());
    if (!game) {
      return res.status(404).json({ ok: false, error: "Game not found" });
    }
    res.json({ ok: true, game: game.toJSON() });
  });

  // GET all active game details
  router.get("/", (_req, res) => {
    const games = [];
    for (const [_id, game] of gameManager.games) {
      if (game.status !== "finished") { // should change to not started
        games.push(game.toJSON());
      }
    }
    res.json({ ok: true, games });
  });

  return router;
}

module.exports = gameRoutes;
