#!/bin/bash
set -euo pipefail
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLS_DIR="${1:-$SOURCE_DIR/deps}"
APP="${2:-$SOURCE_DIR/dist/Youtube Downloader.app}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Tools" "$SOURCE_DIR/.swift-cache"
swiftc -swift-version 5 -O -target arm64-apple-macosx13.0 -module-cache-path "$SOURCE_DIR/.swift-cache" "$SOURCE_DIR/Core.swift" "$SOURCE_DIR/App.swift" "$SOURCE_DIR/Views.swift" -o "$APP/Contents/MacOS/Youtube Downloader"
ditto "$TOOLS_DIR/yt-dlp-runtime" "$APP/Contents/Resources/Tools/yt-dlp-runtime"
for name in ffmpeg deno; do
    cp "$TOOLS_DIR/$name" "$APP/Contents/Resources/Tools/$name"
    chmod +x "$APP/Contents/Resources/Tools/$name"
done
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Youtube Downloader</string>
<key>CFBundleIdentifier</key><string>local.linkdrop.mac</string>
<key>CFBundleName</key><string>Youtube Downloader</string>
<key>CFBundleDisplayName</key><string>Youtube Downloader</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.6.0</string>
<key>CFBundleVersion</key><string>6</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSDownloadsFolderUsageDescription</key><string>Youtube Downloader saves videos and audio to your chosen folder.</string>
</dict></plist>
PLIST
if [ -f "$SOURCE_DIR/Assets/AppIcon.icns" ]; then cp "$SOURCE_DIR/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"; fi
if [ -f "$SOURCE_DIR/THIRD-PARTY.txt" ]; then cp "$SOURCE_DIR/THIRD-PARTY.txt" "$APP/Contents/Resources/"; fi
if [ -d "$TOOLS_DIR/Licenses" ]; then cp -R "$TOOLS_DIR/Licenses" "$APP/Contents/Resources/"; fi
codesign --force --sign - "$APP/Contents/MacOS/Youtube Downloader"
codesign --force --sign - "$APP"
printf 'Built %s\n' "$APP"
