import { promises as fs } from "fs";
import path from "path";
import type { BoardEntry } from "./score-codec";

const FILE = path.join(process.cwd(), "data", "scores.json");
const TOP = 50;

async function ensure() {
  await fs.mkdir(path.dirname(FILE), { recursive: true });
}

export async function readMirror(): Promise<BoardEntry[]> {
  await ensure();
  try {
    const raw = await fs.readFile(FILE, "utf8");
    const parsed = JSON.parse(raw) as BoardEntry[];
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

export async function writeMirror(entries: BoardEntry[]) {
  await ensure();
  const tmp = `${FILE}.${process.pid}.tmp`;
  await fs.writeFile(tmp, JSON.stringify(entries, null, 2), "utf8");
  await fs.rename(tmp, FILE);
}

/** Keep best score per persona public key. */
export function mergeBoard(existing: BoardEntry[], incoming: BoardEntry[]): BoardEntry[] {
  const byKey = new Map<string, BoardEntry>();
  for (const e of [...existing, ...incoming]) {
    const cur = byKey.get(e.publicKeyHex);
    if (!cur || e.height > cur.height || (e.height === cur.height && e.timestampMs < cur.timestampMs)) {
      byKey.set(e.publicKeyHex, e);
    }
  }
  return [...byKey.values()]
    .sort((a, b) => b.height - a.height || a.timestampMs - b.timestampMs)
    .slice(0, TOP);
}

export async function mirrorScore(entry: BoardEntry): Promise<BoardEntry[]> {
  const next = mergeBoard(await readMirror(), [entry]);
  await writeMirror(next);
  return next;
}
