#!/usr/bin/env bash
# Rebuild catalog/index.json for a published .lgx on GitHub Releases.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?version e.g. 0.1.0}"
LGX="${2:?path to .lgx}"
OWNER="${OWNER:-uNexpectedR}"
REPO="${REPO:-logos-tower}"
TAG="logos_tower-v${VERSION}"
ASSET="logos_tower-${VERSION}.lgx"

sha256=$(sha256sum "$LGX" | awk '{print $1}')
size=$(wc -c <"$LGX" | tr -d ' ')

# rootHash: sha256 of the lgx is used as a content digest for verification when
# trustedSigners is empty (HTTPS + index hash). Catalog clients verify download
# against sha256 + rootHash from the index entry.
rootHash="$sha256"

mkdir -p "$ROOT/catalog"
generatedAt=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
url="https://github.com/${OWNER}/${REPO}/releases/download/${TAG}/${ASSET}"

cat >"$ROOT/catalog/index.json" <<EOF
{
  "schemaVersion": 2,
  "repositoryName": "logos-tower",
  "generatedAt": "${generatedAt}",
  "packages": [
    {
      "name": "logos_tower",
      "versions": [
        {
          "releasedAt": "${generatedAt}",
          "publisherRef": "${TAG}",
          "url": "${url}",
          "size": ${size},
          "sha256": "${sha256}",
          "rootHash": "${rootHash}",
          "manifest": {
            "name": "logos_tower",
            "display_name": "Logos Tower",
            "version": "${VERSION}",
            "type": "ui_qml",
            "category": "games",
            "description": "Vertical jumper with the Logos λ. Ed25519 persona + signed height scores.",
            "icon": "assets/icon.png",
            "view": "qml/Main.qml",
            "dependencies": [],
            "main": {
              "linux-amd64": "logos_tower_plugin.so"
            }
          }
        }
      ]
    }
  ]
}
EOF

# Point logos-repo indexUrl at raw branch file (updated in-repo).
python3 - <<PY
import json
from pathlib import Path
p = Path("$ROOT/logos-repo.json")
data = json.loads(p.read_text())
data["indexUrl"] = f"https://raw.githubusercontent.com/{OWNER}/{REPO}/cursor/logos-tower-558f/catalog/index.json"
data["description"] = "Logos Tower for Basecamp — install logos_tower from this catalog."
p.write_text(json.dumps(data, indent=2) + "\n")
print("wrote", p)
print("index", Path("$ROOT/catalog/index.json"))
print("sha256", "$sha256")
print("url", "$url")
PY
