# App Store privacy answers — offline first release

Prepared for StringMap 1.0 with 12 lessons and 18 original exercises. Not yet entered in App Store Connect.

Select **Data Not Collected** and **No tracking** for this release. The distributed app contains no scanner, hosted recognition client, microphone listener, analytics, advertising, or customer account. Tutorial progress, saved songs, and preferences remain on device and may be included in the user's Apple device backups.

The loopback web view serves bundled notation and audio on the device. It is not a remote music-processing service. Fixed support/privacy links open GitHub Pages; voluntary support emails and website traffic are explained in the privacy policy. No camera, photo-library, microphone or App Attest purpose/entitlement is part of Release.

Required-reason API declarations are separate from collected-data answers: the app declares local UserDefaults; ZIPFoundation includes its dependency manifest. Inspect these in the final signed archive, not just source.

Run `python3 scripts/audit-offline-release.py PATH/TO/StringMap.app` on the archived application and validate through Xcode/App Store Connect before submission. Revisit these answers before shipping any future network processing or listening feature. Historical hosted-scanner privacy answers do not apply to this build.

Apple references: https://developer.apple.com/app-store/app-privacy-details/ and https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
