/**
 * Logos-style signed score envelopes for Logos Tower.
 * Pattern mirrors ForumerMobile: Ed25519 persona + BLAKE2b PoW + Waku wire.
 *
 * canonical = JSON of every field except nonce, sig, id (sorted keys, no whitespace)
 * work      = BLAKE2b-256(canonical || nonce) has >= powBits leading zero bits
 * sig       = Ed25519 over canonical || nonce
 * id        = hex(BLAKE2b-128(canonical || nonce || sig))
 * wire      = {"env":"<envelope json>","t":"score","v":1}
 */

import { ed25519 } from "@noble/curves/ed25519.js";
import { blake2b } from "@noble/hashes/blake2.js";
import { concat, fromHex, toHex, utf8 } from "./bytes";

export const CONTENT_TOPIC = "/logos-tower/1/scores/proto";
export const CLUSTER_ID = 3;
export const SHARD_ID = 4;
export const PUBSUB_TOPIC = "/waku/2/rs/3/4";
export const POW_BITS = 12;
export const MAX_HEIGHT = 1_000_000;
export const MAX_FUTURE_MS = 10 * 60 * 1000;
export const MAX_PAST_MS = 24 * 60 * 60 * 1000;
const NONCE_BYTES = 8;
const CROCKFORD = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

export class ScoreError extends Error {
  status: number;
  constructor(message: string, status = 400) {
    super(message);
    this.name = "ScoreError";
    this.status = status;
  }
}

export type ScoreEnvelope = {
  version: number;
  height: number;
  alias: string;
  timestampMs: number;
  publicKey: Uint8Array;
  powBits: number;
  nonce: Uint8Array;
  signature: Uint8Array;
  id: string;
};

export type BoardEntry = {
  id: string;
  height: number;
  alias: string;
  author: string;
  publicKeyHex: string;
  timestampMs: number;
};

export function publicKeyFromSeed(seed: Uint8Array): Uint8Array {
  if (seed.length !== 32) throw new ScoreError("A persona seed is 32 bytes.");
  return ed25519.getPublicKey(seed);
}

export function fingerprint(publicKey: Uint8Array): string {
  const hash = blake2b(publicKey, { dkLen: 16 });
  let bits = BigInt(0);
  for (let i = 0; i < 5; i++) bits = (bits << BigInt(8)) | BigInt(hash[i] ?? 0);
  let out = "lt:";
  for (let i = 7; i >= 0; i--) {
    out += CROCKFORD[Number((bits >> BigInt(i * 5)) & BigInt(0x1f))];
    if (i === 4) out += "-";
  }
  return out;
}

export function authorDisplay(publicKey: Uint8Array, alias: string): string {
  const fp = fingerprint(publicKey);
  const clean = alias.trim().slice(0, 24);
  return clean ? `${clean} · ${fp}` : fp;
}

function dumpString(value: string): string {
  let out = '"';
  for (const ch of value) {
    const code = ch.codePointAt(0) ?? 0;
    if (code === 0x08) out += "\\b";
    else if (code === 0x09) out += "\\t";
    else if (code === 0x0a) out += "\\n";
    else if (code === 0x0c) out += "\\f";
    else if (code === 0x0d) out += "\\r";
    else if (code === 0x22) out += '\\"';
    else if (code === 0x5c) out += "\\\\";
    else if (code <= 0x1f) out += `\\u${code.toString(16).padStart(4, "0")}`;
    else out += ch;
  }
  return `${out}"`;
}

function canonicalJson(env: Omit<ScoreEnvelope, "nonce" | "signature" | "id">): string {
  return (
    `{` +
    `"alias":${dumpString(env.alias)},` +
    `"height":${env.height},` +
    `"powBits":${env.powBits},` +
    `"publicKey":${dumpString(toHex(env.publicKey))},` +
    `"timestampMs":${env.timestampMs},` +
    `"version":${env.version}` +
    `}`
  );
}

function leadingZeroBits(hash: Uint8Array): number {
  let bits = 0;
  for (const byte of hash) {
    if (byte === 0) {
      bits += 8;
      continue;
    }
    let v = byte;
    while ((v & 0x80) === 0) {
      bits += 1;
      v <<= 1;
    }
    break;
  }
  return bits;
}

function incrementNonce(nonce: Uint8Array) {
  for (let i = nonce.length - 1; i >= 0; i--) {
    nonce[i] = (nonce[i]! + 1) & 0xff;
    if (nonce[i] !== 0) return;
  }
}

function envelopeJson(env: ScoreEnvelope): string {
  return JSON.stringify({
    alias: env.alias,
    height: env.height,
    id: env.id,
    nonce: toHex(env.nonce),
    powBits: env.powBits,
    publicKey: toHex(env.publicKey),
    signature: toHex(env.signature),
    timestampMs: env.timestampMs,
    version: env.version,
  });
}

export function encodeWire(env: ScoreEnvelope): Uint8Array {
  return utf8(JSON.stringify({ env: envelopeJson(env), t: "score", v: 1 }));
}

export function parseWire(bytes: Uint8Array): ScoreEnvelope {
  let parsed: unknown;
  try {
    parsed = JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    throw new ScoreError("Score wire is not JSON.");
  }
  if (!parsed || typeof parsed !== "object") throw new ScoreError("Score wire is empty.");
  const root = parsed as Record<string, unknown>;
  if (root.t !== "score" || root.v !== 1 || typeof root.env !== "string") {
    throw new ScoreError("Score wire shape is wrong.");
  }
  let envRaw: unknown;
  try {
    envRaw = JSON.parse(root.env);
  } catch {
    throw new ScoreError("Score envelope is not JSON.");
  }
  if (!envRaw || typeof envRaw !== "object") throw new ScoreError("Score envelope is empty.");
  const e = envRaw as Record<string, unknown>;
  if (e.version !== 1) throw new ScoreError("Unknown score version.");
  if (typeof e.height !== "number" || !Number.isFinite(e.height)) {
    throw new ScoreError("Height missing.");
  }
  if (typeof e.timestampMs !== "number" || typeof e.powBits !== "number") {
    throw new ScoreError("Score fields missing.");
  }
  if (typeof e.publicKey !== "string" || typeof e.nonce !== "string" || typeof e.signature !== "string" || typeof e.id !== "string") {
    throw new ScoreError("Score crypto fields missing.");
  }
  return {
    version: 1,
    height: Math.floor(e.height),
    alias: typeof e.alias === "string" ? e.alias.slice(0, 24) : "",
    timestampMs: e.timestampMs,
    publicKey: fromHex(e.publicKey),
    powBits: e.powBits,
    nonce: fromHex(e.nonce),
    signature: fromHex(e.signature),
    id: e.id.toLowerCase(),
  };
}

export function verifyScore(env: ScoreEnvelope, nowMs = Date.now()): void {
  if (env.height < 0 || env.height > MAX_HEIGHT) throw new ScoreError("Height out of range.");
  if (env.publicKey.length !== 32) throw new ScoreError("Bad public key.");
  if (env.nonce.length !== NONCE_BYTES) throw new ScoreError("Bad nonce.");
  if (env.signature.length !== 64) throw new ScoreError("Bad signature.");
  if (env.powBits < 0 || env.powBits > 24) throw new ScoreError("Bad proof-of-work.");
  if (env.timestampMs > nowMs + MAX_FUTURE_MS) throw new ScoreError("Score timestamp too far ahead.");
  if (env.timestampMs < nowMs - MAX_PAST_MS) throw new ScoreError("Score is too old.");

  const canonical = utf8(
    canonicalJson({
      version: env.version,
      height: env.height,
      alias: env.alias,
      timestampMs: env.timestampMs,
      publicKey: env.publicKey,
      powBits: env.powBits,
    }),
  );
  const work = blake2b(concat(canonical, env.nonce), { dkLen: 32 });
  if (leadingZeroBits(work) < env.powBits) throw new ScoreError("Proof-of-work failed.");
  const signed = concat(canonical, env.nonce);
  if (!ed25519.verify(env.signature, signed, env.publicKey, { zip215: false })) {
    throw new ScoreError("Signature failed.");
  }
  const id = toHex(blake2b(concat(signed, env.signature), { dkLen: 16 }));
  if (id !== env.id) throw new ScoreError("Score id mismatch.");
}

export type SignScoreInput = {
  height: number;
  seed: Uint8Array;
  alias?: string;
  timestampMs?: number;
  powBits?: number;
  yieldEvery?: number;
};

export async function signScore(input: SignScoreInput): Promise<{
  envelope: ScoreEnvelope;
  wire: Uint8Array;
  author: string;
}> {
  const height = Math.floor(input.height);
  if (!Number.isFinite(height) || height < 0 || height > MAX_HEIGHT) {
    throw new ScoreError("Invalid height.");
  }
  const alias = (input.alias ?? "").trim().slice(0, 24);
  const powBits = input.powBits ?? POW_BITS;
  const publicKey = publicKeyFromSeed(input.seed);
  const nonce = new Uint8Array(NONCE_BYTES);
  crypto.getRandomValues(nonce);
  const timestampMs = input.timestampMs ?? Date.now();

  const draft: ScoreEnvelope = {
    version: 1,
    height,
    alias,
    timestampMs,
    publicKey,
    powBits,
    nonce,
    signature: new Uint8Array(64),
    id: "",
  };

  const canonical = utf8(
    canonicalJson({
      version: draft.version,
      height: draft.height,
      alias: draft.alias,
      timestampMs: draft.timestampMs,
      publicKey: draft.publicKey,
      powBits: draft.powBits,
    }),
  );

  const yieldEvery = input.yieldEvery ?? 2048;
  let tried = 0;
  while (leadingZeroBits(blake2b(concat(canonical, draft.nonce), { dkLen: 32 })) < powBits) {
    incrementNonce(draft.nonce);
    tried += 1;
    if (tried > 4_000_000) throw new ScoreError("Proof-of-work took too long.");
    if (yieldEvery > 0 && tried % yieldEvery === 0) {
      await new Promise((r) => setTimeout(r, 0));
    }
  }

  const signed = concat(canonical, draft.nonce);
  draft.signature = ed25519.sign(signed, input.seed);
  draft.id = toHex(blake2b(concat(signed, draft.signature), { dkLen: 16 }));
  verifyScore(draft);
  return {
    envelope: draft,
    wire: encodeWire(draft),
    author: authorDisplay(draft.publicKey, draft.alias),
  };
}

export function toBoardEntry(env: ScoreEnvelope): BoardEntry {
  return {
    id: env.id,
    height: env.height,
    alias: env.alias,
    author: authorDisplay(env.publicKey, env.alias),
    publicKeyHex: toHex(env.publicKey),
    timestampMs: env.timestampMs,
  };
}
