# Logos Tower

Vertical jumper (Icy Tower–style) with the Logos λ. Jump rising platforms for height. **Login** is a browser Ed25519 persona. The **public leaderboard** is signed scores relayed to **logos.dev** over Waku (with a local mirror).

## Stack (Logos-first)

Mirrors the ForumerMobile / logos.dev patterns in this team’s workspace:

| Layer | Choice |
| --- | --- |
| App shell | Next.js (App Router) |
| Identity | Ed25519 persona in `localStorage` (`@noble/curves`) |
| Score integrity | BLAKE2b PoW + Ed25519 (`@noble/hashes`) |
| Network | `@waku/sdk` light node + `@libp2p/tcp` to logos.dev store/light-push peers |
| Content topic | `/logos-tower/1/scores/proto` on cluster `3` / shard `4` (`/waku/2/rs/3/4`) |

Browsers cannot dial the TCP logos.dev peers, so this process is the relay (same split as ForumerMobile phone → laptop relay).

## Run

```bash
npm install
npm run dev
```

Open [http://127.0.0.1:3000](http://127.0.0.1:3000).

1. **Login** — create a persona (optional alias).
2. **Play** — ← → / A D, Space to start; climb for height.
3. **Board** — after a fall, the run is signed in-browser and `POST /api/scores` verifies, mirrors locally, and light-pushes to logos.dev when reachable.

```bash
npm run build && npm start
npm run lint
```

## API

- `GET /api/scores` — public board (network + mirror)
- `POST /api/scores` — `{ wire: "<base64 signed envelope>" }`
- `GET /api/status` — logos.dev relay connectivity

## Brand

Muted slate-teal `#6A838B` + white λ (`public/logos-lambda.png`).

## Basecamp

**Catalog URL** (Package Repositories) — GitHub Releases, not raw branch:

```
https://github.com/uNexpectedR/logos-tower/releases/download/index/logos-repo.json
```

Install package **`logos_tower` `0.1.6`** (`darwin-arm64` / `linux-amd64`, category Social), then open **Logos Tower** from the Basecamp sidebar. Details and threat model: [BASECAMP.md](./BASECAMP.md).
