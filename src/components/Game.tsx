"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { bytesToBase64, fromHex } from "@/lib/bytes";
import { signScore } from "@/lib/score-codec";
import { readPersona } from "@/lib/persona";

type Platform = { x: number; y: number; w: number };
type Phase = "ready" | "playing" | "over";

const W = 360;
const H = 640;
const GRAVITY = 0.42;
const JUMP = -11.2;
const MOVE = 0.55;
const FRICTION = 0.86;
const MAX_VX = 6.2;
const PLAYER = 36;

export function Game() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [phase, setPhase] = useState<Phase>("ready");
  const [height, setHeight] = useState(0);
  const [bestRun, setBestRun] = useState(0);
  const [submitState, setSubmitState] = useState<string | null>(null);
  const stateRef = useRef({
    phase: "ready" as Phase,
    px: W / 2 - PLAYER / 2,
    py: H - 120,
    vx: 0,
    vy: 0,
    cam: 0,
    maxHeight: 0,
    platforms: [] as Platform[],
    keys: { left: false, right: false },
    lambda: null as HTMLImageElement | null,
    submitted: false,
  });

  useEffect(() => {
    const img = new Image();
    img.src = "/logos-lambda.png";
    img.onload = () => {
      stateRef.current.lambda = img;
    };

    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    resetWorld(stateRef.current);

    const onKey = (e: KeyboardEvent, down: boolean) => {
      if (e.code === "ArrowLeft" || e.code === "KeyA") stateRef.current.keys.left = down;
      if (e.code === "ArrowRight" || e.code === "KeyD") stateRef.current.keys.right = down;
      if (down && (e.code === "Space" || e.code === "ArrowUp" || e.code === "KeyW")) {
        if (stateRef.current.phase === "ready") startGame();
        if (stateRef.current.phase === "over") restart();
      }
    };
    const down = (e: KeyboardEvent) => onKey(e, true);
    const up = (e: KeyboardEvent) => onKey(e, false);
    window.addEventListener("keydown", down);
    window.addEventListener("keyup", up);

    let raf = 0;
    const tick = () => {
      step(stateRef.current);
      draw(ctx, stateRef.current);
      setHeight(Math.floor(stateRef.current.maxHeight));
      if (stateRef.current.phase !== phase) setPhase(stateRef.current.phase);
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);

    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener("keydown", down);
      window.removeEventListener("keyup", up);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function startGame() {
    const s = stateRef.current;
    resetWorld(s);
    s.phase = "playing";
    s.vy = JUMP;
    s.submitted = false;
    setPhase("playing");
    setSubmitState(null);
  }

  function restart() {
    startGame();
  }

  async function submitScore() {
    const persona = readPersona();
    if (!persona) {
      setSubmitState("Log in with a persona to publish your height.");
      return;
    }
    if (stateRef.current.submitted) return;
    stateRef.current.submitted = true;
    setSubmitState("Signing…");
    try {
      const signed = await signScore({
        height: stateRef.current.maxHeight,
        seed: fromHex(persona.seed),
        alias: persona.alias,
        yieldEvery: 1024,
      });
      setSubmitState("Publishing…");
      const res = await fetch("/api/scores", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ wire: bytesToBase64(signed.wire) }),
      });
      const data = (await res.json()) as {
        error?: string;
        published?: boolean;
        publishError?: string;
        height?: number;
      };
      if (!res.ok) {
        setSubmitState(data.error ?? "Submit failed.");
        stateRef.current.submitted = false;
        return;
      }
      if (data.published) {
        setSubmitState(`Saved ${data.height} — on logos.dev.`);
      } else {
        setSubmitState(
          `Saved ${data.height} locally${data.publishError ? ` (${data.publishError})` : ""}.`,
        );
      }
    } catch (error) {
      stateRef.current.submitted = false;
      setSubmitState(error instanceof Error ? error.message : "Submit failed.");
    }
  }

  useEffect(() => {
    if (phase === "over") {
      setBestRun((b) => Math.max(b, height));
      void submitScore();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [phase]);

  return (
    <div className="stack" style={{ justifyItems: "center" }}>
      <div className="game-wrap">
        <div className="hud">
          <span>Height {height}</span>
          <span>Best {Math.max(bestRun, height)}</span>
        </div>
        <canvas ref={canvasRef} width={W} height={H} />
        {phase === "ready" && (
          <div className="overlay">
            <h1>Logos Tower</h1>
            <p>Jump the rising platforms. ← → or A D. Space to start.</p>
            <div className="actions">
              <button type="button" className="btn btn-solid" onClick={startGame}>
                Play
              </button>
            </div>
          </div>
        )}
        {phase === "over" && (
          <div className="overlay">
            <h2>Fell at {height}</h2>
            <p className="muted">{submitState ?? "…"}</p>
            <div className="actions">
              <button type="button" className="btn btn-solid" onClick={restart}>
                Again
              </button>
              <Link className="btn" href="/leaderboard">
                Board
              </Link>
              {!readPersona() && (
                <Link className="btn" href="/login">
                  Login
                </Link>
              )}
            </div>
          </div>
        )}
      </div>
      <p className="muted" style={{ textAlign: "center", maxWidth: 360 }}>
        Scores are signed by your browser persona and relayed to logos.dev.
      </p>
    </div>
  );
}

function resetWorld(s: {
  px: number;
  py: number;
  vx: number;
  vy: number;
  cam: number;
  maxHeight: number;
  platforms: Platform[];
}) {
  s.px = W / 2 - PLAYER / 2;
  s.py = H - 140;
  s.vx = 0;
  s.vy = 0;
  s.cam = 0;
  s.maxHeight = 0;
  s.platforms = [{ x: W / 2 - 50, y: H - 60, w: 100 }];
  let y = H - 140;
  for (let i = 0; i < 12; i++) {
    y -= 70 + Math.random() * 30;
    s.platforms.push(randomPlatform(y));
  }
}

function randomPlatform(y: number): Platform {
  const w = 70 + Math.random() * 50;
  const x = 16 + Math.random() * (W - w - 32);
  return { x, y, w };
}

function step(s: {
  phase: Phase;
  px: number;
  py: number;
  vx: number;
  vy: number;
  cam: number;
  maxHeight: number;
  platforms: Platform[];
  keys: { left: boolean; right: boolean };
}) {
  if (s.phase !== "playing") return;

  if (s.keys.left) s.vx -= MOVE;
  if (s.keys.right) s.vx += MOVE;
  s.vx *= FRICTION;
  s.vx = Math.max(-MAX_VX, Math.min(MAX_VX, s.vx));
  s.vy += GRAVITY;
  s.px += s.vx;
  s.py += s.vy;

  if (s.px < -PLAYER) s.px = W;
  if (s.px > W) s.px = -PLAYER;

  if (s.vy > 0) {
    for (const p of s.platforms) {
      const prevBottom = s.py - s.vy + PLAYER;
      const feet = s.py + PLAYER;
      if (prevBottom <= p.y && feet >= p.y && s.px + PLAYER > p.x && s.px < p.x + p.w) {
        s.py = p.y - PLAYER;
        s.vy = JUMP;
        break;
      }
    }
  }

  const worldY = s.cam + (H - s.py);
  s.maxHeight = Math.max(s.maxHeight, worldY / 10);

  const targetCam = Math.max(0, s.py - H * 0.45);
  if (targetCam < s.cam) {
    const dy = s.cam - targetCam;
    s.cam = targetCam;
    for (const p of s.platforms) p.y += dy;
    s.py += dy;
  }

  // Scroll/rise: slowly lift world so standing still still climbs pressure
  if (s.maxHeight > 20) {
    const rise = Math.min(1.1, 0.15 + s.maxHeight / 800);
    s.cam -= rise;
    for (const p of s.platforms) p.y += rise;
    s.py += rise;
  }

  s.platforms = s.platforms.filter((p) => p.y < H + 40);
  while (s.platforms.length < 14) {
    const top = Math.min(...s.platforms.map((p) => p.y));
    s.platforms.push(randomPlatform(top - (70 + Math.random() * 40)));
  }

  if (s.py > H + 40) {
    s.phase = "over";
  }
}

function draw(
  ctx: CanvasRenderingContext2D,
  s: {
    px: number;
    py: number;
    platforms: Platform[];
    lambda: HTMLImageElement | null;
    maxHeight: number;
  },
) {
  ctx.clearRect(0, 0, W, H);

  // subtle vertical bands
  ctx.fillStyle = "rgba(255,255,255,0.04)";
  for (let x = 0; x < W; x += 48) ctx.fillRect(x, 0, 1, H);

  for (const p of s.platforms) {
    const g = ctx.createLinearGradient(p.x, p.y, p.x, p.y + 10);
    g.addColorStop(0, "#f7fafb");
    g.addColorStop(1, "#c9d6da");
    ctx.fillStyle = g;
    roundRect(ctx, p.x, p.y, p.w, 10, 4);
    ctx.fill();
  }

  if (s.lambda) {
    ctx.drawImage(s.lambda, s.px - 4, s.py - 4, PLAYER + 8, PLAYER + 8);
  } else {
    ctx.fillStyle = "#fff";
    ctx.font = "28px Syne, sans-serif";
    ctx.fillText("λ", s.px + 8, s.py + 28);
  }
}

function roundRect(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  w: number,
  h: number,
  r: number,
) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}
