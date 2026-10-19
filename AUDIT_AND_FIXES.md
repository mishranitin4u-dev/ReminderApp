# Daily Reminder V2.2 — Audit and Fixes

## Changes made

1. **Dart type correction:** monthly reminder date clamping now converts the result to `int` before passing it to `TZDateTime`.
2. **Preference save correction:** Easy Mode persistence now awaits `SharedPreferences.setBool` inside a `Future<void>` method.
3. **Alarm sound handling:** Default, Gentle, and Urgent use separate Android notification channels. Android channel sound settings are fixed when a channel is first created, so reusing one channel could cause all three options to play the same sound.
4. **Caregiver SMS launch:** added an Android `<queries>` entry for SMS `SENDTO` intents so `canLaunchUrl` can discover a compatible messaging app on Android versions that enforce package visibility.
5. **Cloud build workflow:** the workflow now generates missing Android/Gradle scaffolding and restores the app-specific manifest and WAV sounds afterward. It confirms the APK exists before uploading it and uses the new artifact name `Daily-Reminder-V2.2-Fixed-APK`.
6. **Cleanup:** removed an unused Dart import.

## Validation performed here

- Android manifest parsed as valid XML.
- `pubspec.yaml` and GitHub Actions workflow parsed as valid YAML.
- Confirmed both bundled WAV files exist and are non-empty.
- Checked both monthly date clamp expressions now return integers.

## Not yet verified

This environment does not have Flutter or Dart installed, so I could not run `flutter analyze` or build an APK locally. The corrected package must complete its GitHub Actions build before the APK can be called build-verified. After installation, notification permission, exact-alarm access, reboot behavior, sound channels, recurrence, voice input, and SMS composer behavior should be tested on a physical Android phone.


Build Fix 3: Removed the flutter_timezone dependency that failed Kotlin compilation. Reminder timezone is explicitly set to Asia/Kolkata for the initial India-focused release. The workflow no longer modifies plugin Kotlin files.
