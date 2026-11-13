#!/bin/bash
# Cuts a release: builds the app, tags the commit, and publishes a GitHub release
# with SimMonitor.zip and install.sh attached.
# Usage: ./scripts/release.sh 1.0.0
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "error: $*" >&2; exit 1; }

VERSION="${1:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "usage: $0 <major.minor.patch>"
TAG="v$VERSION"

[[ "$(git branch --show-current)" == "main" ]] || fail "release from main"
[[ -z "$(git status --porcelain)" ]] || fail "the working tree has uncommitted changes"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && fail "$TAG already exists"

VERSION="$VERSION" ./scripts/build-app.sh
rm -f build/SimMonitor.zip
ditto -c -k --keepParent build/SimMonitor.app build/SimMonitor.zip

git tag -a "$TAG" -m "Sim Monitor $VERSION"
git push origin main "$TAG"

gh release create "$TAG" build/SimMonitor.zip scripts/install.sh \
    --title "Sim Monitor $VERSION" \
    --generate-notes \
    --notes 'Install or update, then look for the phone icon in the menu bar:

```sh
curl -fsSL https://github.com/flexaargo/sim-monitor/releases/latest/download/install.sh | bash
```

Requires macOS 26 and Xcode.'
