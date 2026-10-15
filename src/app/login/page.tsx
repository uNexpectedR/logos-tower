"use client";

import { useEffect, useState } from "react";
import {
  clearPersona,
  createPersona,
  personaFingerprint,
  readPersona,
  writePersona,
  type Persona,
} from "@/lib/persona";

export default function LoginPage() {
  const [persona, setPersona] = useState<Persona | null>(null);
  const [alias, setAlias] = useState("");
  const [note, setNote] = useState<string | null>(null);

  useEffect(() => {
    const p = readPersona();
    setPersona(p);
    if (p) setAlias(p.alias);
  }, []);

  function refresh(p: Persona | null) {
    setPersona(p);
    window.dispatchEvent(new Event("lt-persona"));
  }

  return (
    <div className="panel stack" style={{ maxWidth: 420, margin: "0 auto" }}>
      <div>
        <h1 className="page-title">Login</h1>
        <p className="muted">
          Logos-style persona: an Ed25519 key stays in this browser. Scores are signed here and
          relayed to logos.dev — same idea as ForumerMobile, no password server.
        </p>
      </div>

      {persona ? (
        <div className="stack">
          <div>
            <div className="muted">Persona</div>
            <div style={{ fontFamily: "var(--font-display)", fontSize: "1.15rem" }}>
              {personaFingerprint(persona)}
            </div>
          </div>
          <label className="field">
            <span>Display alias (optional)</span>
            <input
              value={alias}
              maxLength={24}
              placeholder="name on the board"
              onChange={(e) => setAlias(e.target.value)}
            />
          </label>
          <div className="actions" style={{ justifyContent: "flex-start" }}>
            <button
              type="button"
              className="btn btn-solid"
              onClick={() => {
                const next = { ...persona, alias: alias.trim().slice(0, 24) };
                writePersona(next);
                refresh(next);
                setNote("Alias saved.");
              }}
            >
              Save
            </button>
            <button
              type="button"
              className="btn"
              onClick={() => {
                const next = createPersona(alias);
                refresh(next);
                setNote("New persona created. Old scores stay under the previous key.");
              }}
            >
              New persona
            </button>
            <button
              type="button"
              className="btn"
              onClick={() => {
                clearPersona();
                refresh(null);
                setAlias("");
                setNote("Logged out. Clearing site data also removes the key.");
              }}
            >
              Log out
            </button>
          </div>
        </div>
      ) : (
        <div className="stack">
          <label className="field">
            <span>Display alias (optional)</span>
            <input
              value={alias}
              maxLength={24}
              placeholder="name on the board"
              onChange={(e) => setAlias(e.target.value)}
            />
          </label>
          <div className="actions" style={{ justifyContent: "flex-start" }}>
            <button
              type="button"
              className="btn btn-solid"
              onClick={() => {
                const next = createPersona(alias);
                refresh(next);
                setNote("Persona ready. Play, then your height can be published.");
              }}
            >
              Create persona
            </button>
          </div>
        </div>
      )}

      {note && <p className="muted">{note}</p>}
    </div>
  );
}
