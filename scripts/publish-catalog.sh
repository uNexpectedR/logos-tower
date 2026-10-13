#!/usr/bin/env bash
# Rebuild catalog/index.json from a local multi-variant .lgx (local helper).
# Production catalogs come from .github/workflows/rebuild-index.yml.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LGX="${1:?path to multi-variant .lgx}"
OWNER="${OWNER:-uNexpectedR}"
REPO="${REPO:-logos-tower}"

if ! command -v lgx >/dev/null 2>&1; then
  for p in /nix/store/*/bin/lgx; do
    [[ -x "$p" ]] || continue
    export PATH="$(dirname "$p"):$PATH"
    break
  done
fi
command -v lgx >/dev/null || { echo "error: lgx required on PATH"; exit 1; }

export ROOT LGX OWNER REPO
python3 - <<'PY'
import hashlib, json, os, subprocess
from datetime import datetime, timezone
from pathlib import Path

root = Path(os.environ["ROOT"])
lgx = Path(os.environ["LGX"])
owner = os.environ["OWNER"]
repo = os.environ["REPO"]

manifest = json.loads(subprocess.check_output(["lgx", "manifest", "--json", str(lgx)]))
version = manifest["version"]
tag = f"logos_tower-v{version}"
asset = f"logos_tower-{version}.lgx"
url = f"https://github.com/{owner}/{repo}/releases/download/{tag}/{asset}"
raw = lgx.read_bytes()
now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

entry = {
    "releasedAt": now,
    "publisherRef": tag,
    "url": url,
    "urls": [url],
    "size": len(raw),
    "sha256": hashlib.sha256(raw).hexdigest(),
    "rootHash": manifest["hashes"]["root"],
    "manifest": manifest,
}

index = {
    "schemaVersion": 2,
    "repositoryName": "logos-tower",
    "generatedAt": now,
    "packages": [{"name": manifest["name"], "versions": [entry]}],
}

out = root / "catalog" / "index.json"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(index, indent=2) + "\n")

repo_card = root / "logos-repo.json"
data = json.loads(repo_card.read_text())
data["indexUrl"] = f"https://github.com/{owner}/{repo}/releases/download/index/index.json"
data["description"] = "Logos Tower for Basecamp — install logos_tower (vertical jumper)."
repo_card.write_text(json.dumps(data, indent=2) + "\n")

print("wrote", out)
print("variants", sorted((manifest.get("main") or {}).keys()))
print("category", manifest.get("category"))
print("url", url)
print("logos-repo indexUrl", data["indexUrl"])
PY
