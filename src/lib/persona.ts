"use client";

import { publicKeyFromSeed, fingerprint } from "./score-codec";
import { fromHex, toHex } from "./bytes";

const KEY = "logos-tower-persona-v1";

export type Persona = {
  seed: string;
  alias: string;
};

export function readPersona(): Persona | null {
  if (typeof window === "undefined") return null;
  const raw = localStorage.getItem(KEY);
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw) as Persona;
    if (typeof parsed.seed !== "string" || !/^[0-9a-f]{64}$/.test(parsed.seed)) return null;
    return {
      seed: parsed.seed,
      alias: typeof parsed.alias === "string" ? parsed.alias.slice(0, 24) : "",
    };
  } catch {
    return null;
  }
}

export function writePersona(persona: Persona) {
  localStorage.setItem(KEY, JSON.stringify(persona));
}

export function clearPersona() {
  localStorage.removeItem(KEY);
}

export function freshSeed(): string {
  const seed = new Uint8Array(32);
  crypto.getRandomValues(seed);
  return toHex(seed);
}

export function createPersona(alias = ""): Persona {
  const persona = { seed: freshSeed(), alias: alias.trim().slice(0, 24) };
  writePersona(persona);
  return persona;
}

export function personaLabel(persona: Persona): string {
  const pk = publicKeyFromSeed(fromHex(persona.seed));
  const fp = fingerprint(pk);
  return persona.alias ? `${persona.alias} · ${fp}` : fp;
}

export function personaFingerprint(persona: Persona): string {
  return fingerprint(publicKeyFromSeed(fromHex(persona.seed)));
}
