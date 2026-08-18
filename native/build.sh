#!/bin/bash
# Build Gena.app — a native macOS wrapper for the Gena planner.
# Requires only Xcode Command Line Tools (swiftc, iconutil) — no downloads, no money.
# Usage:  cd native && ./build.sh   →   produces Gena.app (drag it to /Applications)
set -e
cd "$(dirname "$0")"

APP="Gena.app"
BIN="Contents/MacOS/Gena"

echo "› Cleaning old build…"
rm -rf "$APP" Gena.iconset Gena.icns

echo "› Compiling native binary (Swift + WebKit)…"
swiftc -O Gena.swift -o gena-bin -framework Cocoa -framework WebKit

echo "› Assembling app bundle…"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mv gena-bin "$APP/$BIN"

echo "› Generating app icon…"
# The icon comes from the same PNG the web app installs with, so the mark has one source of truth.
# Regenerate that with tools/make-icons.py if the mark ever changes.
SRC=""
for p in ./icon-512.png ../icon-512.png ../../gena-public/icon-512.png; do
  [ -f "$p" ] && SRC="$p" && break
done
if [ -n "$SRC" ]; then
  mkdir -p Gena.iconset
  sips -z 16   16   "$SRC" --out Gena.iconset/icon_16x16.png      >/dev/null
  sips -z 32   32   "$SRC" --out Gena.iconset/icon_16x16@2x.png   >/dev/null
  sips -z 32   32   "$SRC" --out Gena.iconset/icon_32x32.png      >/dev/null
  sips -z 64   64   "$SRC" --out Gena.iconset/icon_32x32@2x.png   >/dev/null
  sips -z 128  128  "$SRC" --out Gena.iconset/icon_128x128.png    >/dev/null
  sips -z 256  256  "$SRC" --out Gena.iconset/icon_128x128@2x.png >/dev/null
  sips -z 256  256  "$SRC" --out Gena.iconset/icon_256x256.png    >/dev/null
  sips -z 512  512  "$SRC" --out Gena.iconset/icon_256x256@2x.png >/dev/null
  sips -z 512  512  "$SRC" --out Gena.iconset/icon_512x512.png    >/dev/null
  cp "$SRC" Gena.iconset/icon_512x512@2x.png
  iconutil -c icns Gena.iconset -o "$APP/Contents/Resources/Gena.icns"
  rm -rf Gena.iconset
  ICON_LINE="<key>CFBundleIconFile</key><string>Gena</string>"
else
  echo "  (icon-512.png not found — app will use the default icon)"
  ICON_LINE=""
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Gena</string>
  <key>CFBundleDisplayName</key><string>Gena</string>
  <key>CFBundleExecutable</key><string>Gena</string>
  <key>CFBundleIdentifier</key><string>com.mintaymisgano.gena</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Mintay Misgano · PolyForm Noncommercial</string>
  ${ICON_LINE}
</dict>
</plist>
PLIST

# Ad-hoc sign so macOS runs a locally built, unsigned app cleanly.
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo ""
echo "✓ Built $APP"
echo "  Move it to Applications:   mv \"$APP\" /Applications/"
echo "  Then open it from Launchpad or Spotlight like any other app."
