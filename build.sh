#!/usr/bin/env bash
# Builds "Google Suite.app" with nothing but the Command Line Tools: swiftc plus
# a hand-written Info.plist. No Xcode project, no SPM, no package downloads.
set -euo pipefail

APP_NAME="Google Suite"
BUNDLE_ID="com.saattrupdan.google-suite"
VERSION="0.1.0"
MIN_MACOS="13.0"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$ROOT/.build"
APP="$ROOT/$APP_NAME.app"
CLEAN=0
for arg in "$@"; do
  [[ "$arg" == "--clean" ]] && CLEAN=1
done

if (( CLEAN )); then
  echo "clean: removing $APP and $BUILD"
  rm -rf "$APP" "$BUILD"
fi

mkdir -p "$BUILD" "$APP/Contents/MacOS" "$APP/Contents/Resources"

# shellcheck disable=SC2046  # word-splitting the source list is intentional
swiftc \
  -swift-version 5 \
  -O \
  -target "arm64-apple-macosx$MIN_MACOS" \
  -framework AppKit -framework WebKit -framework UserNotifications -framework ServiceManagement \
  -o "$APP/Contents/MacOS/$APP_NAME" \
  $(find "$ROOT/Sources" -name '*.swift' | sort)

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
        <key>CFBundleName</key><string>$APP_NAME</string>
        <key>CFBundleDisplayName</key><string>$APP_NAME</string>
        <key>CFBundleExecutable</key><string>$APP_NAME</string>
        <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
        <key>CFBundlePackageType</key><string>APPL</string>
        <key>CFBundleShortVersionString</key><string>$VERSION</string>
        <key>CFBundleVersion</key><string>$VERSION</string>
        <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
        <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
        <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
        <key>NSHighResolutionCapable</key><true/>
        <key>NSHumanReadableCopyright</key><string>Personal tool. Not affiliated with Google.</string>
        <key>NSPrincipalClass</key><string>NSApplication</string>
        <key>NSSupportsAutomaticTermination</key><false/>
        <key>NSSupportsSuddenTermination</key><false/>
        <!-- Only used when openMeetInApp is true; join Meet in the browser otherwise. -->
        <key>NSCameraUsageDescription</key><string>Video for Google Meet calls opened inside this app.</string>
        <key>NSMicrophoneUsageDescription</key><string>Audio for Google Meet calls opened inside this app.</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"
[[ -f "$ROOT/README.md" ]] && cp "$ROOT/README.md" "$APP/Contents/Resources/README.md"

# Ad-hoc signature: an unsigned WebKit Networking process gets refused by the
# system, and Gatekeeper is stricter about that than about the signature being
# tied to a developer identity.
codesign --remove-signature "$APP" >/dev/null 2>&1 || true
codesign -s - --force --deep --timestamp=none "$APP"
codesign --verify --verbose=1 "$APP"

echo "built: $APP (adhoc-signed, $VERSION, min macOS $MIN_MACOS)"
