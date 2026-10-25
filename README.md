# PumpWatch

Petrol and diesel prices in Ireland, reported by drivers. Snap the price sign, the phone reads the price, everyone sees it on the map.

By VIP Tech · package `app.viptech.pumpwatch`

## Backend: Firebase
- Project: **PumpWatch** (`pumpwatch-4013d`), free Spark plan
- Firestore (europe-west2, London): `stations` and `reports`. Rules: `firestore.rules`
- Authentication: Anonymous (no login screen)
- App config: `lib/firebase_options.dart`

## Builds (GitHub Actions)
Every push to `main` builds:
- `pumpwatch-N.apk` – install on a phone to test
- `pumpwatch-N.aab` – upload to Google Play Console

They are attached to a GitHub release called "PumpWatch build N".

Release signing uses these repository secrets (Settings › Secrets and variables › Actions):
`PW_KEYSTORE_BASE64`, `PW_KEYSTORE_PASSWORD`, `PW_KEY_ALIAS`, `PW_KEY_PASSWORD`.
Without them the build is debug-signed, which is fine for testing but not for Google Play.

## Google Play
Listing text, data safety answers and content rating notes: `store/google-play-listing.md`.
Privacy policy page for viptech.app: `store/privacy-policy.html`.
