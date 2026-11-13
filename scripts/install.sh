#!/bin/bash
# Downloads a released SimMonitor.app, puts it in /Applications and launches it.
# Installs the latest release, or the one named by SIM_MONITOR_VERSION (e.g. 1.0.0).
set -euo pipefail

REPO="flexaargo/sim-monitor"
ASSET="SimMonitor.zip"
DEST="/Applications/SimMonitor.app"
VERSION="${SIM_MONITOR_VERSION:-}"
VERSION="${VERSION#v}"

fail() { echo "error: $*" >&2; exit 1; }

[[ "$(uname)" == "Darwin" ]] || fail "Sim Monitor only runs on macOS."
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
(( MAJOR >= 26 )) || fail "Sim Monitor needs macOS 26 or later (this is $(sw_vers -productVersion))."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [[ -n "$VERSION" ]]; then
    URL="https://github.com/$REPO/releases/download/v$VERSION/$ASSET"
else
    URL="https://github.com/$REPO/releases/latest/download/$ASSET"
fi

echo "Downloading Sim Monitor ${VERSION:-(latest)}..."
if ! curl -fsSL "$URL" -o "$TMP/$ASSET" 2>/dev/null; then
    # Fall back to the GitHub CLI, which downloads with your login.
    command -v gh >/dev/null || fail "could not download $URL"
    gh release download ${VERSION:+"v$VERSION"} --repo "$REPO" --pattern "$ASSET" --dir "$TMP" \
        || fail "could not download $ASSET from $REPO"
fi

ditto -x -k "$TMP/$ASSET" "$TMP"
[[ -d "$TMP/SimMonitor.app" ]] || fail "the download did not contain SimMonitor.app"

pkill -x SimMonitor 2>/dev/null || true
rm -rf "$DEST"
ditto "$TMP/SimMonitor.app" "$DEST"
open "$DEST"

INSTALLED="$(defaults read "$DEST/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)"
echo "Installed Sim Monitor $INSTALLED to $DEST. Look for the phone icon in the menu bar."
