# Daily Reminder – Version 2.2

## New in Version 2.2
### 1. Custom Alarm Sounds
- Default
- Gentle (bundled WAV tone)
- Urgent (bundled WAV tone)

### 2. Medicine Details
For Medicine reminders:
- Medicine name
- Dosage, e.g. 1 tablet / 5 ml
- Before Food / After Food / With Food
- Notes

### 3. Voice-Created Reminders
Tap the microphone on Add Reminder and speak the reminder title.
Android microphone permission is required.

Example:
"Take BP medicine"

The recognized speech is inserted into the reminder title. Natural-language parsing
of date/time is planned for a future AI release.

### 4. Caregiver / Family Alert
Add a caregiver name and mobile number in Settings.
When the user marks a reminder as "I MISSED THIS", the app:
- records a local caregiver alert notification
- opens the phone's SMS composer with a pre-filled alert message when supported

The user confirms the SMS in the messaging application. Fully automatic SMS delivery
is intentionally not implemented because Android/Google Play policies and carrier
permissions may restrict it. Automatic remote caregiver alerts should use a backend
service (Firebase/AWS/etc.) in a future production release.

## Setup
1. Install Flutter and Android Studio.
2. Create a Flutter project:
   flutter create daily_reminder
3. Replace:
   - pubspec.yaml
   - lib/main.dart
   - android/app/src/main/AndroidManifest.xml
   - android/app/src/main/res/raw/gentle.wav
   - android/app/src/main/res/raw/urgent.wav
4. Run:
   flutter pub get
   flutter run

## Permissions
Allow:
- Notifications
- Alarms & reminders / exact alarms where requested
- Microphone for voice reminder creation

## Suggested Version 2.3
- Natural-language AI reminders: "Remind me to take medicine tomorrow at 8 AM"
- Automatic missed-reminder detection after a grace period
- Firebase/AWS caregiver push notifications
- Medication adherence report
- BP and blood sugar logging
- Family dashboard
