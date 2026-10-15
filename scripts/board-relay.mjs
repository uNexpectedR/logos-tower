#!/usr/bin/env node
/**
 * Tiny logos.dev Waku relay for Basecamp clients.
 * GET  /board  → verified public scores (store query + local merge)
 * POST /scores → { wire: "<base64>" } verify + light-push
 * GET  /health → { ok, relay }
 */
import { createServer } from "node:http";
import { base64ToBytes, bytesToBase64 } from "../src/lib/bytes.ts";
import {
  ScoreError,
  parseWire,
  toBoardEntry,
  verifyScore,
} from "../src/lib/score-codec.ts";
import { mergeBoard, mirrorScore, readMirror, writeMirror } from "../src/lib/score-store.ts";
import { fetchNetworkScores, publishScoreWire } from "../src/lib/waku-relay.ts";

const PORT = Number(process.env.PORT || 8787);

function send(res, status, body) {
  const data = JSON.stringify(body);
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "GET,POST,OPTIONS",
    "access-control-allow-headers": "content-type",
    "cache-control": "no-store",
  });
  res.end(data);
}

async function readBoard() {
  const local = await readMirror();
  try {
    const network = await fetchNetworkScores();
    const merged = mergeBoard(local, network);
    await writeMirror(merged);
    return { scores: merged.slice(0, 50), source: "network+mirror" };
  } catch (error) {
    return {
      scores: local.slice(0, 50),
      source: "mirror",
      networkError: error instanceof Error ? error.message : "network unavailable",
    };
  }
}

const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url || "/", `http://127.0.0.1:${PORT}`);
    if (req.method === "OPTIONS") {
      send(res, 204, {});
      return;
    }
    if (req.method === "GET" && url.pathname === "/health") {
      send(res, 200, { ok: true, service: "logos-tower-board-relay" });
      return;
    }
    if (req.method === "GET" && (url.pathname === "/board" || url.pathname === "/api/scores")) {
      send(res, 200, await readBoard());
      return;
    }
    if (req.method === "POST" && (url.pathname === "/scores" || url.pathname === "/api/scores")) {
      const chunks = [];
      for await (const c of req) chunks.push(c);
      const raw = Buffer.concat(chunks).toString("utf8");
      let body;
      try {
        body = JSON.parse(raw || "{}");
      } catch {
        send(res, 400, { error: "JSON body required." });
        return;
      }
      if (!body?.wire || typeof body.wire !== "string") {
        send(res, 400, { error: "Signed score wire required (base64)." });
        return;
      }
      const wireBytes = base64ToBytes(body.wire);
      const env = parseWire(wireBytes);
      verifyScore(env);
      const entry = toBoardEntry(env);
      await mirrorScore(entry);
      let published = false;
      let publishError;
      try {
        await publishScoreWire(wireBytes);
        published = true;
      } catch (error) {
        publishError = error instanceof ScoreError ? error.message : "Could not reach logos.dev.";
      }
      const board = await readBoard();
      send(res, 200, {
        ok: true,
        height: entry.height,
        author: entry.author,
        published,
        publishError,
        wire: bytesToBase64(wireBytes),
        scores: board.scores,
        source: board.source,
      });
      return;
    }
    send(res, 404, { error: "not found" });
  } catch (error) {
    if (error instanceof ScoreError) {
      send(res, error.status || 400, { error: error.message });
      return;
    }
    console.error(error);
    send(res, 500, { error: "relay error" });
  }
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`board-relay listening on http://127.0.0.1:${PORT}`);
});
