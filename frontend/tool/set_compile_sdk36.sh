#!/usr/bin/env bash
# file_picker + flutter_plugin_android_lifecycle need compileSdk 36.
# Does not change minSdk (Android 10 phones still install).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_KTS="$ROOT/android/app/build.gradle.kts"
APP_GROOVY="$ROOT/android/app/build.gradle"
ROOT_KTS="$ROOT/android/build.gradle.kts"
ROOT_GROOVY="$ROOT/android/build.gradle"

if [[ ! -d "$ROOT/android" ]]; then
  echo "No android/ tree. Run: flutter create . --project-name second_brain --org app.secondbrain --platforms=android"
  exit 1
fi

patch_app() {
  local f="$1"
  python3 - "$f" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
t = p.read_text()
orig = t
t = t.replace("compileSdk = flutter.compileSdkVersion", "compileSdk = 36")
t = t.replace("compileSdk flutter.compileSdkVersion", "compileSdk 36")
if t == orig and "compileSdk = 36" not in t and "compileSdk 36" not in t:
    sys.exit("Could not find compileSdk in " + str(p))
p.write_text(t)
print("updated", p)
PY
}

if [[ -f "$APP_KTS" ]]; then
  patch_app "$APP_KTS"
elif [[ -f "$APP_GROOVY" ]]; then
  patch_app "$APP_GROOVY"
else
  echo "Missing android/app/build.gradle(.kts)"
  exit 1
fi

FORCE='
subprojects {
    afterEvaluate { project ->
        if (project.hasProperty("android")) {
            project.android {
                compileSdkVersion 36
            }
        }
    }
}
'

if [[ -f "$ROOT_GROOVY" ]]; then
  if ! grep -q "compileSdkVersion 36" "$ROOT_GROOVY"; then
    printf "%s\n" "$FORCE" >> "$ROOT_GROOVY"
    echo "updated $ROOT_GROOVY"
  fi
elif [[ -f "$ROOT_KTS" ]]; then
  if ! grep -q "compileSdkVersion(36)" "$ROOT_KTS"; then
    cat >> "$ROOT_KTS" <<'KTS'

subprojects {
    afterEvaluate {
        extensions.findByName("android")?.let {
            val ext = it as com.android.build.gradle.BaseExtension
            ext.compileSdkVersion(36)
        }
    }
}
KTS
    echo "updated $ROOT_KTS"
  fi
fi

echo "compileSdk 36 set. minSdk unchanged."
