# StringMap release checklist

StringMap is not being submitted by this repository change. Complete this list before the first TestFlight build.

## Product gates

- [ ] Confirm the release scope remains the reliable monophonic MusicXML practice flow.
- [ ] Decide whether chords, polyphony, tuplets, and arbitrary durations are release blockers or clearly disclose them in App Store copy.
- [ ] Keep camera/Photos/PDF scanning hidden until a licensed OMR service, confidence model, page-order handling, and correction review are real. When enabled, add camera and photo-library usage descriptions and test denial flows on hardware.
- [ ] Run the end-to-end checklist in `apps/ios/README.md` with all four bundled studies and representative exported MusicXML from MuseScore, Finale, and Dorico.

## Device and quality validation

- [ ] Run on at least one physical iPhone and one iPad; verify Files import, audio output, silent-mode expectations, headphones, interruptions, background/foreground, memory pressure, rotation, Dynamic Type, VoiceOver, light mode, and dark mode.
- [ ] Confirm alphaTab playback begins only after a user action and recovers after an audio interruption.
- [ ] Verify cold launch, a large saved score, profile switching, tuning/capo/transposition, manual locks, loop resume, and offline launch with Instruments and MetricKit where available.
- [ ] Complete a crash-free TestFlight soak with representative devices and OS versions.
- [ ] Re-run `swift test`, `xcodebuild test`, `npm test`, `npm run typecheck`, and `npm run build` from a clean checkout.

## Signing and App Store Connect

- [ ] Confirm the final Apple Developer team and register `com.anishtalla.StringMap`.
- [ ] Create the App Store Connect app record; confirm that the display name is available.
- [ ] Replace development signing with the intended distribution configuration and archive a Release build.
- [ ] Increment `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` for every submitted build.
- [ ] Validate the archive in Xcode Organizer before upload; resolve all analyzer and App Store validation warnings.
- [ ] Complete export-compliance questions. The current target declares no non-exempt encryption and has no custom cryptography.
- [ ] Choose supported countries, price, age rating, copyright, support URL, privacy-policy URL, category, and release strategy.

## Store assets and review material

- [ ] Commission/finalize the production app icon and review it at all rendered sizes.
- [ ] Capture current iPhone and iPad screenshots for every required App Store size in light and dark mode.
- [ ] Write accurate name, subtitle, description, keywords, promotional text, and release notes without claiming OMR, AI tutoring, chord support, or recognition accuracy.
- [ ] Provide App Review notes describing local MusicXML import, offline alphaTab playback, the loopback-only renderer resource server, and steps to load the bundled demos.
- [ ] Add a public support page and privacy policy even though the current app collects no data.

## Privacy, licenses, and security

- [ ] Re-run Xcode's privacy report on the Release archive and verify `PrivacyInfo.xcprivacy` is at the app-bundle root.
- [ ] Confirm App Store privacy answers remain “Data Not Collected” unless features or dependencies change.
- [ ] Re-audit every runtime dependency and include current notices. alphaTab is MPL-2.0; its license and modified-source obligations must remain satisfied.
- [ ] Verify no development endpoints, API keys, analytics SDKs, sample user data, or unpublished copyrighted scores are in the archive.
- [ ] Confirm the local resource server still binds only to `127.0.0.1`, exposes only the allowlist, and accepts no writes.

## Deferred OMR-specific requirements

- [ ] Select an OMR architecture and complete license/compliance review; homr and Audiveris are AGPL-3.0 and are not currently embedded.
- [ ] Add explicit upload consent, retention/deletion behavior, privacy disclosures, unavailable-service handling, confidence thresholds, multi-page ordering, rotation/crop correction, and a note/measure review editor.
- [ ] Add `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` only when those user flows exist and their copy accurately describes use.
