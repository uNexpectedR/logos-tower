#!/usr/bin/env bash
# Run on the target OS (macOS Apple Silicon → darwin-arm64, Linux x86_64 → linux-amd64).
set -euo pipefail
cd "$(dirname "$0")/../module"
git add -A
nix build '.#lgx-portable' --out-link ../result-lgx-portable --fallback
file="$(find -L ../result-lgx-portable -name '*.lgx' | head -n1)"
echo "Built: $file"
lgx manifest "$file" || true
