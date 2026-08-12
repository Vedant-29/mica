#!/usr/bin/env bash
# Cuts a release: bump VERSION, commit, tag, push. CI does the rest.
#
# The tag is the trigger and VERSION is the source of truth; the release workflow
# refuses to build if they disagree, so this script is the only place the two are
# set and it always sets them together.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'EOF'
usage: Scripts/release.sh <major|minor|patch|X.Y.Z>

  patch   0.1.0 -> 0.1.1   bug fixes only
  minor   0.1.0 -> 0.2.0   new features, no breaking config changes
  major   0.1.0 -> 1.0.0   breaking change to settings or bundle identity
EOF
  exit 1
}

[ $# -eq 1 ] || usage
BUMP="$1"

CURRENT="$(cat VERSION)"
IFS='.' read -r MA MI PA <<<"$CURRENT"

case "$BUMP" in
  major) NEXT="$((MA + 1)).0.0" ;;
  minor) NEXT="$MA.$((MI + 1)).0" ;;
  patch) NEXT="$MA.$MI.$((PA + 1))" ;;
  [0-9]*.[0-9]*.[0-9]*) NEXT="$BUMP" ;;
  *) usage ;;
esac

# A dirty tree would put unrelated work in the release commit, and the tag would
# then point at a tree nobody reviewed.
if [ -n "$(git status --porcelain)" ]; then
  echo "working tree is dirty — commit or stash first" >&2
  exit 1
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "$BRANCH" != "main" ]; then
  echo "releases are cut from main, not $BRANCH" >&2
  exit 1
fi

if git rev-parse "v$NEXT" >/dev/null 2>&1; then
  echo "tag v$NEXT already exists" >&2
  exit 1
fi

echo "==> $CURRENT -> $NEXT"
swift test

printf '%s\n' "$NEXT" > VERSION
git add VERSION
git commit -m "release: v$NEXT"
git tag -a "v$NEXT" -m "v$NEXT"

echo "==> pushing"
git push origin main
git push origin "v$NEXT"

cat <<EOF

Tagged v$NEXT and pushed. GitHub Actions is now building the DMG.

  watch:    gh run watch --repo Vedant-29/mica
  release:  https://github.com/Vedant-29/mica/releases/tag/v$NEXT

The website's download button needs no change — it points at
/releases/latest/download/Mica.dmg and will serve this build once the
release publishes.
EOF
