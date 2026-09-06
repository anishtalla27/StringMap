# StringMap release gates

Status: **NOT READY FOR APP STORE SUBMISSION**. See [release evidence](docs/release/evidence.md) for current results and blockers. Passing unit tests does not complete the release gates.

- [x] Preserve the existing working tree and design before implementation.
- [x] Add polyphonic guitar score/fingering support, source identities, review/correction, source-image persistence, and migration coverage.
- [x] Import compressed MusicXML with bounded archive handling; verify actual Files import, relaunch and library playback on iPhone/iPad simulators.
- [x] Add bounded owned recognition jobs, App Attest verification, cancellation, expiry, and crash cleanup; security tests use a test CA/fake process.
- [x] Publish matching HTTPS privacy/support/license pages and verify their bytes.
- [x] Reject missing recognition URL, policy URLs, or signing team in Release builds.
- [ ] Finish the actual recognizer benchmark with at least 100 qualified images, real camera photographs, genuine handwriting, independently checked references, and documented provenance.
- [x] Match all 148 controlled printed images (5,120 note events and 800 chord onsets) and reject five unsupported inputs.
- [ ] Reach release targets on independently qualified clean print and actual usable-camera inputs; report handwriting separately. Controlled generated variants do not close this gate.
- [ ] Demonstrate useful handwriting recognition and practical correction before advertising it.
- [ ] Verify all supported results equal their references after corrections in the real app.
- [ ] Finish every iPhone/iPad Simulator screen and control manually, including Photos selection and all failure/recovery paths.
- [ ] Finish physical camera, audible playback/routes/interruption/backgrounding, VoiceOver/large text, rotation, memory and long-session testing.
- [x] Build/test the Linux recognition container, validate the corresponding-source offer, and exercise real process cancellation/crash cleanup.
- [x] User approved up to $20/month hosting and subscribed to Railway Hobby; spending controls are recorded.
- [ ] Validate real Apple attestation/receipts, deploy HTTPS, and verify hosted retention/monitoring.
- [x] Replace the ambiguous SoundFont with a documented CC0 bank and replace the incompatible legacy OMR runtime; test guitar/chord/metronome synthesis.
- [ ] Finish the overall dependency and distribution license review.
- [x] User confirmed `stringmap.support@gmail.com` as the support contact.
- [ ] Reconcile App Store privacy answers with the deployed provider.
- [ ] Verify support mailbox delivery; no test email has been sent.
- [ ] Configure Apple signing, produce a signed Release archive, and validate it for distribution.
- [ ] Refresh verified screenshots and publish only tested listing claims.
- [ ] Complete seven days of TestFlight on representative physical iPhone/iPad devices with no release blockers.
- [ ] Obtain the separate final authorization for App Store submission and public release.
