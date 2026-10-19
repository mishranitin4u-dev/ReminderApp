# Daily Reminder Version 2.2 – Cloud APK Builder

This package includes the Daily Reminder source code and a GitHub Actions workflow
that builds an Android APK in the cloud. You do NOT need to install Flutter or
Android Studio on your computer.

## Quick steps

1. Download and extract this ZIP.
2. Create a free GitHub account if you do not already have one.
3. Go to https://github.com/new and create a new empty repository, for example:
   daily-reminder-app
4. Upload ALL files from the extracted `daily_reminder_v22` folder into that
   repository. Make sure the `.github/workflows/build-apk.yml` file is included.
5. Open the repository and select the **Actions** tab.
6. Open **Build Daily Reminder APK**.
7. Click **Run workflow**.
8. Wait for the build to finish.
9. Open the completed workflow run.
10. Under **Artifacts**, download `Daily-Reminder-V2.2-Fixed-APK`.
11. Extract the downloaded artifact. It contains `app-release.apk`.
12. Copy the APK to your Android phone and tap it to install.
13. If Android asks, allow your browser/file manager to install unknown apps.

## Fixes included in this package

- Corrected monthly date clamping to use integer values.
- Corrected the Easy Mode preference save method.
- Separated default, gentle and urgent Android notification channels so Android can apply each channel's sound.
- Added Android package visibility for opening the SMS composer.
- Updated the GitHub Actions workflow to preserve the custom manifest and bundled WAV sounds when generating Android build files.

## Important

- The APK produced this way is unsigned for Google Play publishing, but it is
  suitable for direct testing/installation on your own Android device.
- Voice input, notifications, microphone and exact alarm permissions will be
  requested by the app/device as needed.
- GitHub Actions runs the Android/Flutter build in the cloud, so no local
  Flutter or Android Studio installation is required.

## Security note

Do not upload private signing keys to the repository. For a future Play Store
release, create a separate signing configuration and store signing secrets in
GitHub Actions secrets.
