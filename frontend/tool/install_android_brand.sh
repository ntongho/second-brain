#!/usr/bin/env bash
# Copy launcher icons + debug cleartext into a flutter create android/ tree.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/android_overlay/app/src"
DEST="${1:-$ROOT/android/app/src}"

if [[ ! -d "$DEST/main" ]]; then
  echo "No Android tree at $DEST"
  echo "Run from frontend/:  flutter create . --project-name second_brain --org app.secondbrain --platforms=android"
  echo "Then:  bash tool/install_android_brand.sh"
  exit 1
fi

mkdir -p "$DEST/main/res" "$DEST/debug"
cp -R "$SRC/main/res/." "$DEST/main/res/"
# Keep Flutter's debug manifest; only ensure cleartext if missing.
if [[ -f "$DEST/debug/AndroidManifest.xml" ]]; then
  if ! grep -q 'usesCleartextTraffic' "$DEST/debug/AndroidManifest.xml"; then
    echo "Add android:usesCleartextTraffic=\"true\" on <application> in android/app/src/debug/AndroidManifest.xml"
  fi
else
  cp "$SRC/debug/AndroidManifest.xml" "$DEST/debug/AndroidManifest.xml"
fi

echo "Android icons installed under $DEST/main/res"
echo "Uninstall the app from the phone once so the launcher cache drops the old Flutter icon."
