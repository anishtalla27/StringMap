# StringMap 1.0 release finalization

> The new 24-lesson build-4 candidate passes autonomous verification and is signed, exported and installed; physical audio qualification remains pending. See [tutorial-expansion.md](tutorial-expansion.md). The build-1 upload and 12-lesson evidence below remain historical and do not qualify the replacement binary.

**Current status: not ready to submit.** Build 1 has a user-reported silent-switch audio defect. Build 2 introduced a reproduced playback freeze. Source build 3 removes competing native audio activation and passes the physical tutorial clock/resume regression. Device silent-mode audible confirmation is pending. Build 1 must be replaced before submission.

**Build 1 evidence:** Version 1.0.0 (1) is signed, passed Apple validation, uploaded and processed in TestFlight, and saved in the App Store draft. The full-course automated UI test passed on the connected physical iPhone. See [current App Store status](app-store-connect-status.md) and [signed build evidence](signed-build.json). Apple validation is not App Review approval.

The public candidate contains 12 original lessons, 16 tutorial examples, and 18 original Free Practice exercises. Scanning and microphone listening are excluded from Release.

## Work completed

- Store description, review notes, privacy answers, and device/TestFlight checklist now match the offline tutorial release.
- Updated privacy, support, license and landing pages were published to GitHub Pages. All five live files match their checked-in HTML/CSS; see policy-deployment.json.
- Signed Release archive and App Store distribution export succeed. The binary audit verifies bundled content, no scanner/listener symbols, no camera/photo/microphone permissions, no recognition URL, and no collected-data declaration.
- ReleaseValidation runs the actual public UI; it does not use Debug lesson/score routes. It covers all twelve lessons, playback, pause, seeking, stepping, BPM changes, optional tab, both quiz outcomes, completion/next lesson, Free Practice, and the privacy document. All twelve lessons pass on iPhone 17 Pro Max and iPad Pro 13-inch. The final runs total eight passing UI test methods across the full-course, Home transport, light/dark, large-text, rotation and return-navigation checks. See [finalization-tests.json](finalization-tests.json) and [screenshot manifest](../store/screenshots/final/manifest.json).
- Screenshot inspection found a light-mode navigation contrast defect. Tutorial navigation now uses the actual cream/tobacco background and matching color scheme. iPad screenshot inspection verifies the corrected dark title on cream.
- Removed the duplicate alphaTab score title that overflowed after toggling tablature on iPhone; the title remains visible in native navigation. Changed the idle mini-player prompt to “Tap to open player” instead of a loading message before its renderer exists.
- Notation/tab switching checks, 3,108 free-practice bridge clock/seek checks, and all 16 tutorial MIDI/source-ID/PCM/notation comparisons pass.

## Remaining gates

- **Manual interaction and physical audio:** automated simulator and physical iPhone results are verified separately from manual click-throughs and audible checks. Human pitch/rhythm checks, headphones/Bluetooth, interruptions, VoiceOver and long sessions remain. A physical iPad has not been qualified. Follow [device-testflight.md](device-testflight.md).
- **App Store declarations:** country availability, content rights and DSA trader status remain unconfigured. Account-holder decisions are still needed. Metadata, privacy, age rating, free pricing, screenshot uploads, review contact, signing, validation and build upload are complete.
- **Seven-day TestFlight:** build processed and testing instructions saved; no tester invitations or elapsed testing days are assumed. This is the project's release gate, not an Apple-mandated minimum.
- **Submission and public release:** remain separate final actions after the checks pass.

## Reproduce builds

```sh
xcodebuild -project apps/ios/StringMap.xcodeproj -scheme StringMap -configuration Release -destination 'generic/platform=iOS' -archivePath artifacts/StringMap.xcarchive DEVELOPMENT_TEAM=S8DY583234 -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath artifacts/StringMap.xcarchive -exportPath artifacts/distribution -exportOptionsPlist apps/ios/ExportOptions.plist -allowProvisioningUpdates
python3 scripts/audit-offline-release.py artifacts/StringMap.xcarchive/Products/Applications/StringMap.app
```

Build 1.0.0 (1) is already uploaded. Increment the build number for any replacement upload. The current signed archive is artifacts/StringMap-1.0.0-provisioned.xcarchive; its exported IPA is artifacts/finalization-distribution/StringMap.ipa.

Use apps/ios/scripts/capture-store-screenshots.sh with a dedicated booted 6.9-inch iPhone or 13-inch iPad simulator. The exporter requires passing Release UI results, exact Apple screenshot dimensions and no alpha channel. Review the resulting images before uploading. The 14 native captures were inspected; the screenshot manifest records a recommended upload order, with the iPhone optional-tab capture retained as evidence because its tab staff falls below the captured viewport. Use the Play screenshot to show both notation and tab on iPhone.

Apple references checked September 6, 2026: [Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/), and [age rating](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/).
