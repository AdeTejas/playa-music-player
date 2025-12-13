# Play Store release checklist (Playa)

This repo currently builds Android, but **Play Store upload requires**: a unique application id, a real release signing key, and compliance checks.

## 1) Set version
- Update `version:` in `pubspec.yaml` (format: `x.y.z+code`).
- Every upload must increment the `+code` value.

## 2) Set a real Application ID (required)
Current Android id is now `com.paxpiece.playa`.

You must pick a permanent id (e.g. `com.yourcompany.playa`) and update:
- `android/app/build.gradle.kts` → `defaultConfig.applicationId`
- Kotlin package paths:
  - `android/app/src/main/kotlin/.../MainActivity.kt` package declaration
  - any other `package com.paxpiece.playa` files
- Any hardcoded channel strings (e.g. MethodChannel names) that include the old id.

## 3) Configure release signing (required)
This repo supports a standard `android/key.properties` file.

## 3) Configure release signing (required)
This repo supports a standard `android/key.properties` file.

- Copy `android/key.properties.example` → `android/key.properties`
- Fill in your upload keystore values
- Do **not** commit the real `android/key.properties`

### a) Generating an upload keystore
Use the JDK `keytool` to create a durable upload key. For example:

```powershell
keytool -genkeypair -v -keystore ~/playa_upload_keystore.jks -alias upload -keyalg RSA -keysize 2048 -validity 9125
```

- Keep the keystore somewhere secure (e.g., a company vault).
- Update `android/key.properties` to point at that keystore and its passwords.
- Always use the same keystore for future Play Console uploads.

## 4) Validate permissions and Data Safety
- `READ_MEDIA_AUDIO` is used for library access.
- Ensure Play Console **Data safety** matches what the app does (local library access, network lyrics, etc.).
- Keep the privacy policy up to date in `PRIVACY_POLICY.md` and reference it in Play Console metadata (make sure it mentions the new `com.paxpiece.playa` identifier).

## 4b) Keep metadata synced

## 6) Upload and test
- Upload the AAB to Play Console **Internal testing** first.
- Smoke-test on Android 11–15 devices: library scan, playback, background notification, headset controls, external “open with”, etc.

## 7) CI verification
- This repo now auto-runs formatting, tests, and the release bundle via `.github/workflows/ci.yml`.
- Run the same checks locally before pushing:
  ```powershell
  dart format --set-exit-if-changed .
  flutter test
  flutter build appbundle --release
  ```
- You can also trigger the workflow manually with `gh workflow run ci.yml` (requires `gh` CLI and GitHub login).
flutter clean
flutter pub get
flutter test
flutter build appbundle --release
```

The output bundle:
- `build/app/outputs/bundle/release/app-release.aab`

## 6) Upload and test
- Upload the AAB to Play Console **Internal testing** first.
- Smoke-test on Android 11–15 devices: library scan, playback, background notification, headset controls, external “open with”, etc.
