# StringMap 1.0 release finalization

Autonomous release preparation on September 6, 2026. The user asked to continue without unlocking the Mac. **Not ready to submit yet.** The public candidate contains 12 original lessons, 16 tutorial examples, and 18 original Free Practice exercises. Scanning and microphone listening are excluded from Release.

## Work completed

- Store description, review notes, privacy answers, and device/TestFlight checklist now match the offline tutorial release.
- Updated privacy, support, license and landing pages were published to GitHub Pages. All five live files match their checked-in HTML/CSS; see policy-deployment.json.
- Release archive builds for iOS with signing disabled. The binary audit verifies bundled content, no scanner/listener symbols, no camera/photo/microphone permissions, no recognition URL, and no collected-data declaration.
- ReleaseValidation runs the actual public UI; it does not use Debug lesson/score routes. It covers all twelve lessons, playback, pause, seeking, stepping, BPM changes, optional tab, both quiz outcomes, completion/next lesson, Free Practice, and the privacy document. All twelve lessons pass on iPhone 17 Pro Max and iPad Pro 13-inch. The final runs total eight passing UI test methods across the full-course, Home transport, light/dark, large-text, rotation and return-navigation checks. See [finalization-tests.json](finalization-tests.json) and [screenshot manifest](../store/screenshots/final/manifest.json).
- Screenshot inspection found a light-mode navigation contrast defect. Tutorial navigation now uses the actual cream/tobacco background and matching color scheme. iPad screenshot inspection verifies the corrected dark title on cream.
- Removed the duplicate alphaTab score title that overflowed after toggling tablature on iPhone; the title remains visible in native navigation. Changed the idle mini-player prompt to “Tap to open player” instead of a loading message before its renderer exists.
- Notation/tab switching checks, 3,108 free-practice bridge clock/seek checks, and all 16 tutorial MIDI/source-ID/PCM/notation comparisons pass.

## Remaining gates

- **Direct manual simulator interaction:** the desktop control tool reports the Mac is locked and cannot unlock it. Per the user’s instruction, continue without unlocking. Automated simulator interaction and screenshot inspection are separate evidence; neither is being labeled a completed manual click-through.
- **Apple signing/account:** automatic archive and distribution export both report “No Accounts” and no matching provisioning profile. A local Apple Development certificate exists for team S8DY583234, but this does not prove active paid membership or App Store distribution access. Recheck Xcode → Settings → Accounts after unlocking; sign in again if needed. No certificate or profile was fabricated.
- **App Store Connect:** app record, metadata/privacy/age-rating entry, account-holder declarations, review contact details, archive validation and TestFlight upload remain unverified. ExportOptions.plist prepares automatic App Store export; it does not upload or release.
- **Physical iPhone and iPad:** the known iPhone 14 Pro is unavailable to devicectl; no physical iPad is connected. Audible pitch/rhythm, speakers/headphones/Bluetooth, interruptions, VoiceOver, large text, memory and long sessions require the device exercise in device-testflight.md.
- **Seven-day TestFlight:** not started. This is the project’s release gate; no elapsed days or tester results are assumed.
- **Submission and public release:** remain separate final actions after the above checks pass.

## Reproduce builds

```sh
xcodebuild -project apps/ios/StringMap.xcodeproj -scheme StringMap -configuration Release -destination 'generic/platform=iOS' -archivePath artifacts/StringMap.xcarchive DEVELOPMENT_TEAM=S8DY583234 -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath artifacts/StringMap.xcarchive -exportPath artifacts/distribution -exportOptionsPlist apps/ios/ExportOptions.plist -allowProvisioningUpdates
python3 scripts/audit-offline-release.py artifacts/StringMap.xcarchive/Products/Applications/StringMap.app
```

Confirm an unused build number in App Store Connect before uploading. The current source is 1.0.0 (1); no remote build inventory could be verified while desktop account access is blocked. Do not treat the unsigned archive as distributable.

Use apps/ios/scripts/capture-store-screenshots.sh with a dedicated booted 6.9-inch iPhone or 13-inch iPad simulator. The exporter requires passing Release UI results, exact Apple screenshot dimensions and no alpha channel. Review the resulting images before uploading. The 14 native captures were inspected; the screenshot manifest records a recommended upload order, with the iPhone optional-tab capture retained as evidence because its tab staff falls below the captured viewport. Use the Play screenshot to show both notation and tab on iPhone.

Apple references checked September 6, 2026: [Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/), and [age rating](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/).
