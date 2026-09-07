# Hosted recognition components

HOMR, copyright Christian Liebhardt and contributors, is licensed under AGPL-3.0. Its complete license is in `COPYING.homr`; the pinned upstream revision is `457e7c6518a10ba755db2e60883419e56c4d7369` at https://github.com/liebharc/homr.

StringMap's `recognizer.py` adapter and `score_quality.py` additions are provided under AGPL-3.0-or-later, without warranty. This notice applies to these hosted recognition components, not to the separate native iOS application.

Each service build creates and serves `/recognizer-source.tar.gz`, containing the pinned upstream source, the adapter, and build and model-download instructions. Preserve this source offer and license notices when deploying or modifying the recognition service. The iOS Settings screen links to the running service's source offer.

The `oemer` adapter and its patches are retained solely to reproduce the previous failed benchmark; production no longer installs or invokes oemer. Audiveris and Zeus are separate evaluation tools and are not included in the production image.
