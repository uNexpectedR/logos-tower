"use client";

import { useEffect, useState } from "react";
import Link from "next/link";

type Row = {
  rank: number;
  author: string;
  height: number;
  timestampMs: number;
};

type Status = {
  state: string;
  detail: string;
};

export default function LeaderboardPage() {
  const [rows, setRows] = useState<Row[]>([]);
  const [source, setSource] = useState<string>("");
  const [networkError, setNetworkError] = useState<string | undefined>();
  const [status, setStatus] = useState<Status | null>(null);
  const [loading, setLoading] = useState(true);

  async function load() {
    setLoading(true);
    try {
      const [board, st] = await Promise.all([
        fetch("/api/scores").then((r) => r.json()),
        fetch("/api/status").then((r) => r.json()).catch(() => null),
      ]);
      setRows(board.scores ?? []);
      setSource(board.source ?? "");
      setNetworkError(board.networkError);
      if (st) setStatus(st);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void load();
  }, []);

  return (
    <div className="board stack">
      <div>
        <h1 className="page-title">Leaderboard</h1>
        <p className="muted">
          Public board of best signed heights. Network: logos.dev Waku topic{" "}
          <code>/logos-tower/1/scores/proto</code>. Local mirror keeps the board readable offline.
        </p>
      </div>

      <div className="actions" style={{ justifyContent: "flex-start" }}>
        <button type="button" className="btn btn-solid" onClick={() => void load()}>
          Refresh
        </button>
        <Link className="btn" href="/">
          Play
        </Link>
      </div>

      {status && (
        <p className="muted">
          Relay {status.state}: {status.detail}
          {source ? ` · source ${source}` : ""}
          {networkError ? ` · ${networkError}` : ""}
        </p>
      )}

      {loading ? (
        <p className="muted">Loading…</p>
      ) : rows.length === 0 ? (
        <p className="muted">No scores yet. Login, play, and publish a height.</p>
      ) : (
        <ol>
          {rows.map((row) => (
            <li key={`${row.rank}-${row.author}-${row.height}`}>
              <span className="rank">{row.rank}</span>
              <span>{row.author}</span>
              <span className="height">{row.height}</span>
            </li>
          ))}
        </ol>
      )}
    </div>
  );
}
