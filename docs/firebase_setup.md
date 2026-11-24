# Firebase setup for Orbit Dash

Orbit Dash uses Google Sign-In as its only supported authentication provider.
There are no guest, anonymous, Email/Password, or phone authentication flows.
Firebase initialization and sign-in failures leave gameplay available while
the identity service reports an unauthenticated or unavailable state.

## Firebase Console setup

1. Register the app in the Firebase project with the same Android package name
   as `applicationId` in `android/app/build.gradle.kts` (`com.example.orbit_dash`
   in this checkout).
2. In Firebase Authentication, enable **Google** as a sign-in provider.
3. In Firebase project settings, add SHA-1 and SHA-256 fingerprints for every
   Android signing certificate used for local debug, internal distribution,
   and release builds. Google Sign-In will fail on builds whose signing
   certificate is not registered.
4. Run `flutterfire configure` for the target platforms. Keep the generated
   `lib/firebase_options.dart` and Android `google-services.json` in sync with
   the registered app. Do not add Admin SDK service-account keys to Flutter.

## Android development

The Android Google Services Gradle plugin and `android/app/google-services.json`
are required. The generated JSON must include the Android package name and the
Web OAuth client ID used by Firebase/Google Sign-In. The app initializes the
current platform options before accessing Firebase Auth; the Google Sign-In
plugin initializes its singleton before opening the account chooser.

Run `flutter pub get`, then `flutter run` on an Android device or emulator with
a configured Google account and Google Play services. To verify the flow, launch
the app, select a Google account, and confirm Firebase Authentication records a
Google provider user. Canceling the chooser leaves the player unauthenticated
and allows sign-in to be retried. Automated identity tests use fakes and do not
contact Google or Firebase.

Google Sign-In also requires provider setup and platform-specific OAuth
configuration on any additional target. Android is the currently supported
testing target; do not assume the flow works on other targets without their
configuration and device testing.
