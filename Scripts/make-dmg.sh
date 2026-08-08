#!/usr/bin/env bash
# Builds a drag-to-Applications DMG from the signed .app.
set -euo pipefail

: "${APP_NAME:?}" "${VERSION:?}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/$APP_NAME.app"
DMG="$ROOT/dist/$APP_NAME.dmg"

[ -d "$APP" ] || { echo "missing $APP — run 'make sign' first" >&2; exit 1; }

echo "==> dmg"

# Assemble a staging folder holding the app plus an /Applications symlink, so the DMG
# window shows the familiar drag target.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  -fs HFS+ \
  "$DMG" >/dev/null

# Size it so the log line is informative.
SIZE="$(du -h "$DMG" | cut -f1 | tr -d ' ')"
echo "  packaged $APP_NAME $VERSION ($SIZE)"
