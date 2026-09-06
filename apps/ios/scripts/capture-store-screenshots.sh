#!/bin/bash
# Regenerates docs/store/screenshots from a live simulator.
#
# Two things this script exists to prevent, both of which have silently shipped
# stale images before: zsh does not word-split an unquoted variable, so the
# device/screen lists are passed as explicit arguments; and `simctl io
# screenshot` can fail while leaving an older file in place, so every shot is
# verified to be newer than the run and retried once.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
OUT="$ROOT/docs/store/screenshots"
APP_ID="com.anishtalla.StringMap"
SCREENS=(home library play trace arrangements)

build() {
  xcodebuild -project "$ROOT/apps/ios/StringMap.xcodeproj" -scheme StringMap \
    -destination "platform=iOS Simulator,name=$1" -configuration Debug \
    build CODE_SIGNING_ALLOWED=NO >/dev/null 2>&1 || return 1
  find ~/Library/Developer/Xcode/DerivedData -name StringMap.app \
    -path "*Debug-iphonesimulator*" 2>/dev/null | head -1
}

capture() {
  local udid="$1" folder="$2" appearance="$3" app="$4"
  mkdir -p "$OUT/$folder"
  xcrun simctl ui "$udid" appearance "$appearance" >/dev/null
  for screen in "${SCREENS[@]}"; do
    local target="$OUT/$folder/$screen.png"
    local started; started=$(date +%s)
    for attempt in 1 2; do
      xcrun simctl terminate "$udid" "$APP_ID" >/dev/null 2>&1
      SIMCTL_CHILD_STRINGMAP_SEED_LIBRARY=1 \
      SIMCTL_CHILD_STRINGMAP_LOAD_DEMO=profile-contrast \
      SIMCTL_CHILD_STRINGMAP_SCREEN="$screen" \
        xcrun simctl launch "$udid" "$APP_ID" >/dev/null 2>&1
      sleep 9
      rm -f "$target"
      if xcrun simctl io "$udid" screenshot "$target" >/dev/null 2>&1 \
         && [ -s "$target" ] \
         && [ "$(stat -f %m "$target")" -ge "$started" ]; then
        echo "  ok   $folder/$screen.png"
        break
      fi
      echo "  retry $folder/$screen.png (attempt $attempt)"
      [ "$attempt" = 2 ] && { echo "  FAIL $folder/$screen.png"; return 1; }
    done
  done
}

run_device() {
  local udid="$1" name="$2" folder="$3"
  echo "== $name"
  xcrun simctl boot "$udid" >/dev/null 2>&1
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1
  local app; app="$(build "$name")" || { echo "  build failed"; return 1; }
  xcrun simctl install "$udid" "$app" >/dev/null
  capture "$udid" "$folder-light" light "$app"
  capture "$udid" "$folder-dark" dark "$app"
  xcrun simctl ui "$udid" appearance light >/dev/null
}

run_device "93B3DB1D-26B3-4544-AB05-9F5ACCEC7FCE" "iPhone 17 Pro Max" "iphone-6.9"
run_device "70AAC7F8-C7B2-4816-844B-D53CCECA8F7A" "iPad Pro 13-inch (M5)" "ipad-13"

echo
echo "Captured:"
find "$OUT" -name "*.png" -newermt "-40 minutes" | sort | sed "s|$OUT/|  |"
