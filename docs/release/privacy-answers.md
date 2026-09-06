# App Store privacy answers — prepared, not submitted

The former “Data Not Collected” answer no longer describes the hosted scan design. The app privacy manifest now includes these categories for app functionality, with tracking disabled. Conservatively mark the records linked to the app-specific device key: having no customer account does not remove that association.

| Category | Actual use | Retention |
| --- | --- | --- |
| Photos or Videos | User-approved cropped page, asynchronous recognition | Working files deleted at terminal state; startup deletes crash remnants |
| Other User Content | Recognized MusicXML and job source title | Unclaimed results expire within one hour after processing; client requests deletion on receipt |
| Device ID | App Attest public key, receipt, assertion counter, owned-job association | 90 days after last use; sessions one hour |
| Other Data Types | Hashed IP address and abuse-limit buckets | Address bucket one hour; scan limit up to one day |

No advertising, cross-app tracking, analytics, account registration, or ATT permission prompt. No microphone or audio recording. Saved source images and practice history remain local. Contact/support handling and the hosting provider’s final traffic/logging settings must be reconciled against the live service before these answers are entered into App Store Connect.

Apple defines collection to include off-device data retained beyond servicing the request in real time and requires functionality-related collection to be disclosed: https://developer.apple.com/app-store/app-privacy-details/ . The one-hour asynchronous result retention and 90-day key storage must therefore not be described as zero collection.

The native policy is bundled for offline access. Matching [privacy](https://anishtalla27.github.io/StringMap/privacy.html), [support](https://anishtalla27.github.io/StringMap/support.html), and [license](https://anishtalla27.github.io/StringMap/licenses.html) pages were published and returned HTTP 200 with matching content hashes; see `policy-deployment.json`. The user confirmed `stringmap.support@gmail.com` as the support contact. Email delivery has not been tested.
