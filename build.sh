#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/TouchPulse.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
BUILD_TMP="$ROOT/.build"

mkdir -p "$MACOS" "$RESOURCES" "$BUILD_TMP"

echo "🎨 Generating TouchPulse AppIcon.icns..."
clang -O2 -fobjc-arc -framework AppKit -framework QuartzCore "$ROOT/tools/make_icon.m" -o "$BUILD_TMP/make_icon"
"$BUILD_TMP/make_icon" "$BUILD_TMP/icon_1024.png"

ICONSET="$BUILD_TMP/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for sz in 16 32 128 256 512; do
    sips -z $sz $sz "$BUILD_TMP/icon_1024.png" --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
    sz2=$((sz * 2))
    sips -z $sz2 $sz2 "$BUILD_TMP/icon_1024.png" --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns"

echo "⚡️ Compiling TouchPulse native macOS binary..."
clang -O2 -fobjc-arc \
    -Wall -Wextra -Wno-unused-parameter -Wno-nullability-completeness \
    -mmacosx-version-min=12.0 \
    -I"$ROOT/src" \
    "$ROOT/src/TPTheme.m" \
    "$ROOT/src/TPAudioEngine.m" \
    "$ROOT/src/TPSystemMonitor.m" \
    "$ROOT/src/TPEngine.m" \
    "$ROOT/src/TPModesVisuals.m" \
    "$ROOT/src/TPModesChaos.m" \
    "$ROOT/src/TPModesArcade.m" \
    "$ROOT/src/TPModesTools.m" \
    "$ROOT/src/TPTouchBarController.m" \
    "$ROOT/src/TPControlCenterWindow.m" \
    "$ROOT/src/main.m" \
    -framework AppKit \
    -framework QuartzCore \
    -framework CoreGraphics \
    -framework AVFoundation \
    -framework CoreAudio \
    -framework AudioToolbox \
    -framework Accelerate \
    -framework IOKit \
    -o "$MACOS/TouchPulse"

echo "📦 Writing Info.plist..."
cat > "$CONTENTS/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>TouchPulse</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.touchpulse.mac</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>TouchPulse</string>
    <key>CFBundleDisplayName</key>
    <string>TouchPulse</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>TouchPulse optionally uses your microphone to power the live 36-band OLED Spectrum Pulse Touch Bar visualizer.</string>
</dict>
</plist>
EOF

echo "🔏 Ad-hoc code signing TouchPulse.app..."
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

rm -rf "$BUILD_TMP"
echo "✅ Build complete: $APP"
