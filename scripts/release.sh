#!/bin/bash
# Cuts a release: builds, signs and notarizes the app, tags the commit, and publishes a GitHub release
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

# Notarization credentials, saved once with:
#   xcrun notarytool store-credentials sim-monitor-notary --apple-id <id> --team-id <team>
PROFILE="${NOTARY_PROFILE:-sim-monitor-notary}"
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
    || fail "no notarytool keychain profile named '$PROFILE'"

VERSION="$VERSION" ./scripts/build-app.sh
codesign -dvv build/SimMonitor.app 2>&1 | grep -q "Authority=Developer ID Application" \
    || fail "the app is not signed with a Developer ID certificate"

# Notarize, staple the ticket so it verifies offline, then zip the stapled app.
ZIP="build/SimMonitor.zip"
rm -f "$ZIP"
ditto -c -k --keepParent build/SimMonitor.app "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple build/SimMonitor.app
rm -f "$ZIP"
ditto -c -k --keepParent build/SimMonitor.app "$ZIP"
spctl --assess --type execute build/SimMonitor.app || fail "Gatekeeper rejected the app"

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
