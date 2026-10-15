# Basecamp install — Logos Tower

## Catalog URL

Use the GitHub Releases catalog (not a raw branch URL):

```
https://github.com/uNexpectedR/logos-tower/releases/download/index/logos-repo.json
```

`indexUrl` in that file points at:

```
https://github.com/uNexpectedR/logos-tower/releases/download/index/index.json
```

## Install steps

1. Open **Logos Basecamp** (desktop — macOS Apple Silicon or Linux x86_64).
2. **Settings → Package Repositories** (or Package Manager → Add repository).
3. If you previously added a raw.githubusercontent.com catalog URL, remove it.
4. Paste the Releases catalog URL above → **Add**.
5. Refresh / reopen **Package Manager** (or Package Monitor).
6. Find **Logos Tower** (`logos_tower`) under **Social** → **Install**.
7. Open **Logos Tower** from the sidebar (Apps).

| | |
| --- | --- |
| Package id | `logos_tower` |
| Version | `0.1.11` |
| Variants | `darwin-arm64`, `linux-amd64` |
| Category | `social` |
| Release | https://github.com/uNexpectedR/logos-tower/releases/tag/logos_tower-v0.1.11 |

**macOS note:** Apple Silicon Basecamp expects `darwin-arm64`. Intel Mac (`darwin-amd64`) is not in this release yet.

After install, play from the Basecamp sidebar app **Logos Tower** (no separate play URL — it is an in-shell UI module).

## Threat model (brief)

- **Persona seed** lives in this Basecamp profile (`QSettings` org `logos` / app `logos_tower`). It never leaves the device except as public key + signatures on score envelopes. Clearing the persona wipes the seed from settings.
- **Scores are not trusted as bare integers.** Submit path builds a canonical JSON envelope, mines **BLAKE2b PoW** (12 leading zero bits), **Ed25519-signs** `canonical ‖ nonce`, and **verifies the signature before** updating the board.
- **Board** keeps best height per public key on-device. Cross-device/public logos.dev sync remains available via the web relay app in this repo; the Basecamp package verifies locally.
- **Open source:** module sources under `module/`, vendored Monocypher for crypto. Index lists `sha256` + manifest `rootHash` for download verification.

## Build from source

```bash
cd module
nix build '.#lgx-portable' --out-link ../result-lgx
```
