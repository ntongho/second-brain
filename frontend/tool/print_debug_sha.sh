#!/usr/bin/env bash
# Debug keystore SHA-1 for Google Cloud → Android OAuth client.
set -euo pipefail
KS="${HOME}/.android/debug.keystore"
if [[ ! -f "$KS" ]]; then
  echo "No debug keystore at $KS — run the app once on a device first."
  exit 1
fi
keytool -list -v -keystore "$KS" -alias androiddebugkey -storepass android -keypass android 2>/dev/null \
  | grep -E 'SHA1:|SHA-1:' | head -n 1
echo
echo "Package name is applicationId in android/app/build.gradle.kts (or build.gradle)."
echo "Google Cloud: create an Android OAuth client with that package + this SHA-1."
echo "Keep using the existing Web client ID as GOOGLE_CLIENT_ID (serverClientId)."
