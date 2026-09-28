#!/bin/bash
# Builds Audio6.app (native Apple Silicon) into ./build
# The app icon (Resources/Icon.icon from Icon Composer) needs Xcode 26+ (actool).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/Audio6.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Audio6 "$APP/Contents/MacOS/Audio6"

# Compile the Icon Composer icon into Assets.car + Icon.icns
if [ -d Resources/Icon.icon ]; then
    xcrun actool Resources/Icon.icon \
        --compile "$APP/Contents/Resources" \
        --output-partial-info-plist build/icon-partial.plist \
        --app-icon Icon \
        --include-all-app-icons \
        --platform macosx \
        --target-device mac \
        --minimum-deployment-target 13.0 \
        --output-format human-readable-text --errors --warnings
else
    echo "No Resources/Icon.icon found - building without an app icon"
fi

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Audio6</string>
    <key>CFBundleIdentifier</key><string>local.audio6</string>
    <key>CFBundleName</key><string>Audio6</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleIconName</key><string>Icon</string>
    <key>CFBundleIconFile</key><string>Icon</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
touch "$APP"   # nudge Finder to pick up the new icon
echo "Built $APP - drag it to /Applications"
