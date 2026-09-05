#!/usr/bin/env bash
# Installs the built bundle into /Applications and registers it with
# LaunchServices so Spotlight, the Dock and `open -a` all find it.
set -euo pipefail

APP_NAME="Google Suite"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$ROOT/$APP_NAME.app"
DEST="/Applications/$APP_NAME.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

[[ -d "$SRC" ]] || { echo "not built yet: run ./build.sh" >&2; exit 1; }

if [[ -e "$DEST" ]] && [[ ! -w "/Applications" ]]; then
  echo "need permission to write to /Applications" >&2; exit 1
fi

rsync -a --delete "$SRC/" "$DEST/"
# Drop any stale saved state so the new build does not inherit an old window.
rm -rf "$HOME/Library/Saved Application State/com.saattrupdan.google-suite.savedState" 2>/dev/null || true
[[ -x "$LSREGISTER" ]] && "$LSREGISTER" -f "$DEST"

echo "installed: $DEST"
echo "launch:    open -a '$APP_NAME'   (or: bin/gcal)"
