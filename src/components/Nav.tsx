"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import { clearPersona, personaFingerprint, readPersona, type Persona } from "@/lib/persona";

export function Nav() {
  const path = usePathname();
  const [persona, setPersona] = useState<Persona | null>(null);

  useEffect(() => {
    setPersona(readPersona());
    const onStorage = () => setPersona(readPersona());
    window.addEventListener("storage", onStorage);
    window.addEventListener("lt-persona", onStorage);
    return () => {
      window.removeEventListener("storage", onStorage);
      window.removeEventListener("lt-persona", onStorage);
    };
  }, [path]);

  return (
    <header className="topbar">
      <Link href="/" className="brand">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/logos-lambda.png" alt="" width={32} height={32} />
        Logos Tower
      </Link>
      <nav className="nav">
        <Link href="/" aria-current={path === "/" ? "page" : undefined}>
          Play
        </Link>
        <Link href="/leaderboard" aria-current={path === "/leaderboard" ? "page" : undefined}>
          Board
        </Link>
        {persona ? (
          <>
            <Link href="/login" aria-current={path === "/login" ? "page" : undefined} title={personaFingerprint(persona)}>
              {persona.alias || personaFingerprint(persona)}
            </Link>
            <button
              type="button"
              onClick={() => {
                clearPersona();
                window.dispatchEvent(new Event("lt-persona"));
                setPersona(null);
              }}
            >
              Log out
            </button>
          </>
        ) : (
          <Link href="/login" aria-current={path === "/login" ? "page" : undefined}>
            Login
          </Link>
        )}
      </nav>
    </header>
  );
}
