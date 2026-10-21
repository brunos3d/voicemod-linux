#!/usr/bin/env bash
# Builds the vadshim DLL and packages the release bundle that install.sh
# downloads. The bundle contains this project's own files plus the prebuilt
# shim (our MIT-licensed binary). It never contains Voicemod or Proton code.
#
# Usage: scripts/make-release.sh [output-dir]
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
OUT="${1:-$ROOT/dist}"
NAME="voicemod-linux"

echo "==> Building the shim"
make -C "$ROOT/bridge/vadshim" clean all
[[ -f "$ROOT/bridge/vadshim/avrt.dll" ]] || { echo "shim build failed" >&2; exit 1; }

echo "==> Staging the bundle"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
dst="$stage/$NAME"
mkdir -p "$dst"

# Everything the installer needs at runtime, plus docs and the installer
# scripts themselves. The shim build output and VCS files are excluded.
cp -r "$ROOT/bin" "$ROOT/bridge" "$ROOT/share" "$dst/"
[[ -d "$ROOT/docs" ]] && cp -r "$ROOT/docs" "$dst/"
cp "$ROOT/install.sh" "$ROOT/uninstall.sh" "$dst/"
for f in README.md README.pt-BR.md LICENSE NOTICE CONTRIBUTING.md; do
    [[ -f "$ROOT/$f" ]] && cp "$ROOT/$f" "$dst/"
done
rm -rf "$dst/bridge/vadshim/build"

mkdir -p "$OUT"
tar -C "$stage" -czf "$OUT/$NAME.tar.gz" "$NAME"
( cd "$OUT" && sha256sum "$NAME.tar.gz" > "$NAME.tar.gz.sha256" )

echo "==> Done"
echo "    $OUT/$NAME.tar.gz"
echo "    $OUT/$NAME.tar.gz.sha256"
tar -tzf "$OUT/$NAME.tar.gz" | sed 's/^/      /'
