#!/usr/bin/env bash
# Assembles the built binary into a proper .app bundle.
set -euo pipefail

: "${APP_NAME:?}" "${BUNDLE_ID:?}" "${VERSION:?}" "${BUILD_NUM:?}" "${MIN_MACOS:?}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/$APP_NAME.app"
BIN="$ROOT/.build/release/$APP_NAME"

[ -x "$BIN" ] || { echo "missing built binary: $BIN" >&2; exit 1; }
[ -f "$ROOT/Resources/AppIcon.icns" ] || { echo "missing Resources/AppIcon.icns — run 'make icon'" >&2; exit 1; }

echo "==> bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# SwiftPM emits a resource bundle per dependency that ships resources; they have to sit
# alongside the executable or Bundle.module lookups fail at runtime.
for resource_bundle in "$ROOT"/.build/release/*.bundle; do
    [ -e "$resource_bundle" ] && cp -R "$resource_bundle" "$APP/Contents/Resources/"
done

sed -e "s|@APP_NAME@|$APP_NAME|g" \
    -e "s|@BUNDLE_ID@|$BUNDLE_ID|g" \
    -e "s|@VERSION@|$VERSION|g" \
    -e "s|@BUILD_NUM@|$BUILD_NUM|g" \
    -e "s|@MIN_MACOS@|$MIN_MACOS|g" \
    "$ROOT/Resources/Info.plist.in" > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" > /dev/null

# Anything linked outside the system would have to be embedded and re-signed; catching
# it here beats discovering it as a dyld failure on a machine without the build tree.
if otool -L "$APP/Contents/MacOS/$APP_NAME" | tail -n +2 \
     | grep -vE '/usr/lib/|/System/Library/' | grep -q .; then
    echo "unembedded dynamic dependencies:" >&2
    otool -L "$APP/Contents/MacOS/$APP_NAME" >&2
    exit 1
fi

echo "  → $APP ($VERSION build $BUILD_NUM)"
