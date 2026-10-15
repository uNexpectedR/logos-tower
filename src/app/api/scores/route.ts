import { NextResponse } from "next/server";
import { base64ToBytes, bytesToBase64 } from "@/lib/bytes";
import {
  ScoreError,
  parseWire,
  toBoardEntry,
  verifyScore,
} from "@/lib/score-codec";
import { mergeBoard, mirrorScore, readMirror, writeMirror } from "@/lib/score-store";
import { fetchNetworkScores, publishScoreWire } from "@/lib/waku-relay";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET() {
  const local = await readMirror();
  let network: Awaited<ReturnType<typeof fetchNetworkScores>> = [];
  let source: "network+mirror" | "mirror" = "mirror";
  let networkError: string | undefined;

  try {
    network = await fetchNetworkScores();
    source = "network+mirror";
    const merged = mergeBoard(local, network);
    await writeMirror(merged);
    return NextResponse.json({
      scores: merged.slice(0, 25).map((s, i) => ({
        rank: i + 1,
        author: s.author,
        height: s.height,
        timestampMs: s.timestampMs,
      })),
      source,
    });
  } catch (error) {
    networkError = error instanceof Error ? error.message : "network unavailable";
    return NextResponse.json({
      scores: local.slice(0, 25).map((s, i) => ({
        rank: i + 1,
        author: s.author,
        height: s.height,
        timestampMs: s.timestampMs,
      })),
      source,
      networkError,
    });
  }
}

export async function POST(req: Request) {
  try {
    const body = (await req.json().catch(() => null)) as {
      wire?: string;
    } | null;
    if (!body?.wire || typeof body.wire !== "string") {
      return NextResponse.json(
        { error: "Signed score wire required (base64)." },
        { status: 400 },
      );
    }

    const wireBytes = base64ToBytes(body.wire);
    const env = parseWire(wireBytes);
    verifyScore(env);
    const entry = toBoardEntry(env);

    // Always mirror verified scores so the board works offline.
    await mirrorScore(entry);

    let published = false;
    let publishError: string | undefined;
    try {
      await publishScoreWire(wireBytes);
      published = true;
    } catch (error) {
      publishError = error instanceof ScoreError ? error.message : "Could not reach logos.dev.";
    }

    return NextResponse.json({
      ok: true,
      height: entry.height,
      author: entry.author,
      published,
      publishError,
      wire: bytesToBase64(wireBytes),
    });
  } catch (error) {
    if (error instanceof ScoreError) {
      return NextResponse.json({ error: error.message }, { status: error.status });
    }
    console.error(error);
    return NextResponse.json({ error: "Score submit failed." }, { status: 500 });
  }
}
