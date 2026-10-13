# Basecamp install — Logos Tower

## Catalog URL

```
https://raw.githubusercontent.com/uNexpectedR/logos-tower/cursor/logos-tower-558f/logos-repo.json
```

## Install steps

1. Open **Logos Basecamp** (desktop).
2. **Settings → Package Repositories** (or Package Manager → Add repository).
3. Paste the catalog URL above → **Add**.
4. Open **Package Manager**, find **Logos Tower** (`logos_tower`).
5. **Install** → load/open from the sidebar (Apps).

| | |
| --- | --- |
| Package id | `logos_tower` |
| Version | `0.1.0` |
| Variant | `linux-amd64` |
| Release | https://github.com/uNexpectedR/logos-tower/releases/tag/logos_tower-v0.1.0 |

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
