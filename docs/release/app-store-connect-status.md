# App Store Connect submission

## Current status — September 7, 2026, 3:17 PM EDT

StringMap 1.0.0 (5) submitted successfully; Apple shows **Waiting for Review**. Submission ID: 889a503b-ffb6-40da-a94a-8629bfc0b741. The account holder saved the affirmative third-party content rights declaration before submission. Manual release remains selected; approval will not automatically publish the app. EU trader status still requires the account holder's answer, and elapsed TestFlight qualification remains incomplete. The user explicitly requested expedited submission. No elapsed testing success is implied.

Status page: https://appstoreconnect.apple.com/apps/6809277270/distribution/reviewsubmissions/details/889a503b-ffb6-40da-a94a-8629bfc0b741

The following notes are historical preparation milestones, superseded by the status above.

Historical status: verified September 6, 2026 in the signed-in account.

**September 7 live update:** Build 5 uploaded at 2:57 PM EDT, processed, and saved in the 1.0.0 draft. Internal TestFlight group StringMap Release Testing contains build 5 and one invited account-holder tester; What to Test instructions saved. Description, promotional text and review notes now cover 20 songs/40 arrangements, 24 tutorials and 18 exercises. Replaced both screenshot sets with seven current images each. Country availability saved for all 175 countries/regions on release. Manual release remains selected. Apple Add for Review check reports missing Content Rights Information as the sole blocking item. Awaiting user confirmation of that declaration and EU trader status. No App Review submission or public release has occurred; elapsed TestFlight exercise is not complete.

Current screenshot order: iPhone melody, chords, chord-shape tutorial, Learn, first notes, Free Practice player, Songbook library. iPad Learn, first notes, Songbook chords, melody, library, chord-shape tutorial, Free Practice player. Uploads are unaltered Release captures from docs/store/screenshots/songbook plus tutorial-expansion (iPhone and iPad Learn) and final (remaining iPad tutorial/exercise screens).

- Created StringMap, Apple ID `6809277270`, bundle ID `com.anishtalla.StringMap`, SKU `stringmap-ios-001`, iOS, English (U.S.).
- Version `1.0.0` is **Prepare for Submission**. Build 1 uploaded, processed in TestFlight (Ready to Submit), and saved in the release draft; no App Review submission or public release.
- Saved description, promotional text, keywords, support and marketing URLs, copyright, and review notes from `docs/store/metadata.md`.
- Saved **Manually release this version** and disabled **Sign-in required**.
- Account holder supplied the required review phone number and saved the contact details; verified Save disabled and validation errors cleared. Private contact details are not copied into this repository.
- Saved subtitle `Learn notes. Find your frets.`, Music primary category and Education secondary category.
- Completed the age-rating questionnaire: all listed content/capability answers No/None, no Kids category or age override. Apple calculated **4+**; saved the questionnaire.
- Account holder confirmed privacy publication; verified Apple's “Published ... by Anish Talla” status and **Data Not Collected** label with the correct privacy policy URL.
- Saved free pricing: United States base price $0.00, zero-price equivalents across 175 countries/regions. This price takes effect only when the app is released. Country availability itself remains unconfigured.
- Disabled Apple silicon Mac and Vision Pro availability to match the iPhone/iPad release scope.
- Uploaded six native 1320 × 2868 iPhone screenshots and seven native 2064 × 2752 iPad screenshots after the account holder enabled Chrome file access. Media Manager showed 6/10 and 7/10 respectively. Both sets persisted after navigation. Asynchronous upload changed the order: iPhone 04,03,01,06,02,07; iPad 05,03,04,06,01,07,02. Optional ordering polish remains; the manifest recommendation is not the observed order.
- Verified paid Apple Developer Program membership for team `S8DY583234`, Individual, renewal September 6, 2027. Selected this team in Xcode and persisted it in project configuration.
- After the account holder restarted the iPhone and signed into Xcode again, the physical device connected and automatic signing created its provisioning profile. The Release app was installed and launched successfully on iPhone 14 Pro, iOS 26.6.1.
- Signed archive and App Store export succeeded. Export uses Cloud Managed Apple Distribution, correct team/application identifiers, and `get-task-allow=false`. Exported package signature verification and offline-content audit pass; see `signed-build.json`.
- **Apple validation passed** in Xcode Organizer for version 1.0.0 (1): “Your app successfully passed all validation checks.” This is archive validation, not App Review approval.
- Physical-device public tutorial UI testing passed: one full-course test covering all 12 lessons, zero failures, iPhone 14 Pro / iOS 26.6.1. Audible/device-route qualification remains incomplete.
- Saved concrete What to Test instructions for build 1. No tester groups or invitations were added; the seven-day exercise has not begun.
- Country availability, content rights, trader declaration, complete device testing and TestFlight exercise remain incomplete.

Draft: https://appstoreconnect.apple.com/apps/6809277270/distribution/ios/version/inflight

Earlier account/device failures are resolved. Successful build logs: `artifacts/finalization-physical-build.log`, `artifacts/finalization-provisioned-archive.log`, and `artifacts/finalization-distribution-export.log`. Physical test log: `artifacts/finalization-physical-tutorial.log`.
