#!/bin/bash
# Builds "Remind Me.app" and copies it into /Applications.
# Re-run after changing RemindMe.swift. Your reminders are not affected.
set -e
cd "$(dirname "$0")"

APP="build/Remind Me.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/AppIcon.iconset

echo "Compiling..."
swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macos14.0 \
  RemindMe.swift -o "$APP/Contents/MacOS/RemindMe"
cp Info.plist "$APP/Contents/"

echo "Drawing icon..."
swift make_icon.swift build/icon.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon.png --out "build/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) build/icon.png --out "build/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

xattr -cr "$APP"
codesign --force -s - "$APP"

rm -rf "/Applications/Remind Me.app"
cp -R "$APP" /Applications/
echo "Done: /Applications/Remind Me.app"
