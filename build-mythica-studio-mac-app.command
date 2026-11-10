#!/bin/bash
# Builds the Mythica Studio Mac app and installs it in Applications. Double-click to run (about 30 seconds).
# Needs only Apple's free Command Line Tools. Safe to run again any time (rebuilds and replaces).
cd "$(dirname "$0")" || exit 1
HERE="$(pwd)"
LOG="$HERE/build-log.txt"; : > "$LOG"
say(){ echo "▸ $*"; echo "$*" >> "$LOG"; }
fail(){ echo; echo "✖ $*"; echo "FAILED: $*" >> "$LOG"; echo; read -r -p "Press Return to close…" _; exit 1; }

if ! xcrun --find swiftc >/dev/null 2>&1; then
  say "Apple's Command Line Tools are needed (free, one time). Opening the installer…"
  xcode-select --install >/dev/null 2>&1
  fail "Click Install in the window that just opened. When it finishes, double-click this file again."
fi

BUILD="$HERE/build"; APP="$BUILD/Mythica Studio.app"
rm -rf "$BUILD"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
say "Compiling…"
xcrun swiftc -parse-as-library -O -target "$(uname -m)-apple-macos12.3" -o "$APP/Contents/MacOS/MythicaStudio" \
  "$HERE/mac/mythica-studio-mac-main.swift" "$HERE/mac/mythica-studio-mac-bridge.swift" \
  -framework Cocoa -framework WebKit -framework Photos -framework AVFoundation -framework QuickLookThumbnailing -framework ImageIO >>"$LOG" 2>&1 \
  || fail "Compile failed. Look in build-log.txt in this folder."
cp "$HERE/app/mythica-studio.html" "$HERE/app/mythica-studio-seed.js" "$APP/Contents/Resources/"
[ -f "$HERE/mac/mythica-studio-icon.icns" ] && cp "$HERE/mac/mythica-studio-icon.icns" "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Mythica Studio</string>
  <key>CFBundleDisplayName</key><string>Mythica Studio</string>
  <key>CFBundleIdentifier</key><string>com.intothemythica.mythica-studio</string>
  <key>CFBundleExecutable</key><string>MythicaStudio</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>12.3</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.lifestyle</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPhotoLibraryUsageDescription</key><string>Mythica Studio shows your photos and videos in your story timeline. Nothing is copied or changed.</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP" >>"$LOG" 2>&1 || say "(codesign warning, continuing)"

DEST="/Applications"; [ -w "$DEST" ] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }
osascript -e 'tell application id "com.intothemythica.mythica-studio" to quit' >/dev/null 2>&1; sleep 1
rm -rf "$DEST/Mythica Studio.app"
ditto "$APP" "$DEST/Mythica Studio.app" || fail "Couldn't copy into $DEST."
say "Installed: $DEST/Mythica Studio.app"
open "$DEST/Mythica Studio.app"
echo; echo "✓ Done! Mythica Studio is open. Drag it from $DEST to your Dock."
echo "OK" >> "$LOG"
sleep 3
