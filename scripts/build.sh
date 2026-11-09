#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# CLIPPER_UNIVERSAL=1: build arm64 + x86_64 and merge them (used for GitHub releases).
# CLIPPER_DIST=dir: output directory (default dist).
BIN=.build/release/MacSelectionClipper
if [[ "${CLIPPER_UNIVERSAL:-0}" == 1 ]]; then
    for arch in arm64 x86_64; do swift build -c release --product MacSelectionClipper --triple "$arch-apple-macosx13.0"; done
    BIN=.build/universal/MacSelectionClipper; mkdir -p .build/universal
    lipo -create -output "$BIN" .build/arm64-apple-macosx/release/MacSelectionClipper .build/x86_64-apple-macosx/release/MacSelectionClipper
else
    swift build -c release --product MacSelectionClipper
fi
APP="$PWD/${CLIPPER_DIST:-dist}/Mac Selection Clipper.app"
# Prefer the stable local identity (scripts/create-signing-identity.sh) so macOS keeps the
# Accessibility permission across rebuilds; fall back to an ad-hoc signature.
LOCAL_IDENTITY="Mac Selection Clipper Local Signing"
if [[ -z "${CLIPPER_SIGN_IDENTITY:-}" ]] && security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$LOCAL_IDENTITY\""; then
    CLIPPER_SIGN_IDENTITY="$LOCAL_IDENTITY"
fi
IDENTITY="${CLIPPER_SIGN_IDENTITY:--}"
INPUT_HASH="$(shasum -a 256 "$BIN" scripts/build.sh | shasum -a 256 | cut -d ' ' -f 1) $IDENTITY $APP"
if [[ -f .build/clipper-bundle-input && -d "$APP" && "$(cat .build/clipper-bundle-input)" == "$INPUT_HASH" ]] && codesign --verify --strict "$APP" 2>/dev/null; then
    echo "Unchanged bundle retained (no re-signing): $APP"
    exit 0
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacSelectionClipper"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Mac Selection Clipper</string>
<key>CFBundleDisplayName</key><string>Mac Selection Clipper</string>
<key>CFBundleIdentifier</key><string>io.github.mylszd.MacSelectionClipper</string>
<key>CFBundleExecutable</key><string>MacSelectionClipper</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Default is an ad-hoc LOCAL signature, not Developer ID distribution/notarization.
# An existing development identity can be chosen explicitly for stable local TCC identity.
codesign --force --sign "$IDENTITY" --identifier io.github.mylszd.MacSelectionClipper "$APP"
codesign --verify --strict "$APP"
printf '%s\n' "$INPUT_HASH" > .build/clipper-bundle-input
echo "$APP"
