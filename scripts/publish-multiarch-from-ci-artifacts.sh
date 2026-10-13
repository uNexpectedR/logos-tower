#!/usr/bin/env bash
# Merge per-platform .lgx files and publish release + index (run on any host with gh+lgx+nix).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINUX_LGX="${1:?linux .lgx}"
DARWIN_LGX="${2:?darwin-arm64 .lgx}"
VERSION=$(lgx manifest --json "$DARWIN_LGX" | python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])')
OUT="$ROOT/dist/logos_tower-${VERSION}.lgx"
mkdir -p "$ROOT/dist"
lgx merge "$LINUX_LGX" "$DARWIN_LGX" -o "$OUT" -y
lgx verify "$OUT"
lgx manifest "$OUT"
TAG="logos_tower-v${VERSION}"
gh release delete "$TAG" -R uNexpectedR/logos-tower -y 2>/dev/null || true
git tag -f "$TAG" && git push -f origin "$TAG" || true
gh release create "$TAG" "$OUT" -R uNexpectedR/logos-tower --title "$TAG" --notes "Multi-arch logos_tower ${VERSION} (darwin-arm64 + linux-amd64)"
# rebuild index via index.py if present
