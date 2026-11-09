#!/bin/bash
# Builds the downloadable release zip: universal (arm64 + x86_64), ad-hoc signed, not notarized.
# Ad-hoc rather than a local certificate: it is the signature macOS reliably accepts for
# Accessibility on other people's Macs (the cost: users re-grant the permission after updating).
# Output: dist-release/MacSelectionClipper-<version>.zip and its .sha256. Does not touch dist/.
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf dist-release
CLIPPER_UNIVERSAL=1 CLIPPER_DIST=dist-release CLIPPER_SIGN_IDENTITY=- ./scripts/build.sh
APP="dist-release/Mac Selection Clipper.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
lipo -info "$APP/Contents/MacOS/MacSelectionClipper"
ZIP="dist-release/MacSelectionClipper-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
(cd dist-release && shasum -a 256 "$(basename "$ZIP")" | tee "$(basename "$ZIP").sha256")
