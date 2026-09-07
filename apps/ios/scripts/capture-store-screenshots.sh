#!/bin/bash
# Pass a dedicated, booted simulator UDID and iphone-6.9 or ipad-13.
# Uses actual public Release navigation, with no developer launch routes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
UDID="${1:?Pass a dedicated booted simulator UDID}"
DEVICE="${2:?Pass iphone-6.9 or ipad-13}"
RUN="$ROOT/artifacts/store-${DEVICE}-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$ROOT/artifacts"
cd "$ROOT"
xcrun simctl status_bar "$UDID" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
trap 'xcrun simctl status_bar "$UDID" clear >/dev/null 2>&1 || true' EXIT
xcodebuild -project apps/ios/StringMap.xcodeproj -scheme ReleaseValidation \
  -configuration Release -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$RUN-build" -resultBundlePath "$RUN.xcresult" \
  -only-testing:StringMapUITests/ReleaseTutorialUITests \
  CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES test > "$RUN.log" 2>&1
python3 scripts/export-store-screenshots.py "$RUN.xcresult" "$DEVICE"
echo "Review docs/store/screenshots/final/$DEVICE before uploading."
