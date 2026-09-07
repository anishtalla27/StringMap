# App Store Connect preparation

Verified September 6, 2026 in the signed-in account.

- Created StringMap, Apple ID `6809277270`, bundle ID `com.anishtalla.StringMap`, SKU `stringmap-ios-001`, iOS, English (U.S.).
- Version `1.0.0` is **Prepare for Submission**. No build uploaded or submitted.
- Saved description, promotional text, keywords, support and marketing URLs, copyright, and review notes from `docs/store/metadata.md`.
- Saved **Manually release this version** and disabled **Sign-in required**.
- Account holder supplied the required review phone number and saved the contact details; verified Save disabled and validation errors cleared. Private contact details are not copied into this repository.
- Saved subtitle `Learn notes. Find your frets.`, Music primary category and Education secondary category.
- Completed the age-rating questionnaire: all listed content/capability answers No/None, no Kids category or age override. Apple calculated **4+**; saved the questionnaire.
- Account holder confirmed privacy publication; verified Apple's “Published ... by Anish Talla” status and **Data Not Collected** label with the correct privacy policy URL.
- Saved free pricing: United States base price $0.00, zero-price equivalents across 175 countries/regions. This price takes effect only when the app is released. Country availability itself remains unconfigured.
- Disabled Apple silicon Mac and Vision Pro availability to match the iPhone/iPad release scope.
- Uploaded six native 1320 × 2868 iPhone screenshots and seven native 2064 × 2752 iPad screenshots in the recommended manifest order after the account holder enabled Chrome file access. Media Manager showed 6/10 and 7/10 respectively. Recheck persistence/processing and order before submission.
- Verified paid Apple Developer Program membership for team `S8DY583234`, Individual, renewal September 6, 2027. Selected this team in Xcode and persisted it in project configuration.
- Xcode now reaches Apple's provisioning service but reports the team has no devices from which to generate an iOS App Development profile. Account holder must connect/unlock/trust an iPhone for provisioning and physical testing. No signed archive yet.
- Country availability, content rights, trader declaration, signing/validation, device testing and TestFlight remain incomplete.

Draft: https://appstoreconnect.apple.com/apps/6809277270/distribution/ios/version/inflight

The earlier command-line archive failed with “No Accounts” and missing provisioning profile; see `artifacts/finalization-unlocked-archive.log`. The newer Xcode UI evidence above narrows the provisioning blocker to a missing registered device. Command-line signing must still be revalidated after device registration.
