#!/usr/bin/env bash
set -euo pipefail

ADDON="RoguePoison"
SUFFIX=""
case "${1:-}" in
    "") ;;
    --beta) SUFFIX="-beta" ;;
    *) echo "usage: bash release.sh [--beta]" >&2; exit 1 ;;
esac
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$ROOT/$ADDON"
cd "$ROOT"

if [ ! -d "$SRC" ]; then
    echo "error: expected addon directory at $SRC" >&2
    exit 1
fi

VERSION="$(grep -E '^## Version:' "$SRC/$ADDON.toc" | head -1 | sed -E 's/^## Version:[[:space:]]*//')"
if [ -z "$VERSION" ]; then
    echo "error: could not read '## Version' from $SRC/$ADDON.toc" >&2
    exit 1
fi

ZIP="$ADDON-v$VERSION$SUFFIX.zip"
STAGE="$(mktemp -d)"
DEST="$STAGE/$ADDON"
mkdir -p "$DEST"

rsync -a \
    --exclude '.git' \
    --exclude '.DS_Store' \
    --exclude '*.zip' \
    "$SRC/" "$DEST/"

rm -f "$ROOT/$ZIP"
( cd "$STAGE" && zip -r -q "$ROOT/$ZIP" "$ADDON" )
rm -rf "$STAGE"

echo "Created $ZIP (version $VERSION$SUFFIX)"
