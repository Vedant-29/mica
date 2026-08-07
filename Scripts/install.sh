#!/usr/bin/env bash
# Installs the bundle to /Applications, replacing any running copy.
set -euo pipefail

: "${APP_NAME:?}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/dist/$APP_NAME.app"
DST="/Applications/$APP_NAME.app"

[ -d "$SRC" ] || { echo "missing $SRC" >&2; exit 1; }

echo "==> install"

if pgrep -x "$APP_NAME" > /dev/null; then
    # Quit rather than kill, so the running copy gets to run its restore path and put
    # the Dock, Do Not Disturb and any hidden apps back before it goes away.
    echo "  quitting running $APP_NAME"
    osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || pkill -x "$APP_NAME" || true
    for _ in $(seq 1 40); do
        pgrep -x "$APP_NAME" > /dev/null || break
        sleep 0.25
    done
    if pgrep -x "$APP_NAME" > /dev/null; then
        echo "  didn't quit in time; forcing (crash recovery will restore on next launch)"
        pkill -9 -x "$APP_NAME" || true
        sleep 0.5
    fi
fi

rm -rf "$DST"
ditto "$SRC" "$DST"
xattr -dr com.apple.quarantine "$DST" 2>/dev/null || true

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Support/lsregister

# Drop the staging copy before registering the installed one. Two bundles sharing a
# bundle identifier makes LaunchServices ambiguous about which is "the" app, and macOS
# then refuses notification authorization outright — the request comes back denied
# without ever prompting, which silently breaks the Remind-me trigger.
if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -u "$SRC" 2>/dev/null || true
fi
rm -rf "$SRC"

[ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$DST"

echo "  → $DST"
echo -n "  designated requirement: "
codesign -d -r- "$DST" 2>&1 | tail -1
