# Firebase security preparation

This document records repository evidence for a future Firestore rules review.
It is not a Firestore ruleset and does not establish the deployed Firebase
security state. No Firestore rules file or `.firebaserc` is tracked in this
checkout. Do not deploy a new ruleset based only on this document.

## Repository state and configuration

- `firebase.json` locally identifies project `orbit-dash-75426` through its
  FlutterFire metadata and configures Functions source as `functions`.
- `lib/firebase_options.dart` and `android/app/google-services.json` contain
  matching local Firebase project and Android app identifiers.
- `android/app/build.gradle.kts` sets both namespace and application ID to
  `com.example.orbit_dash`. Confirm the production package before Play setup.
- Functions use Node.js 22 in `functions/package.json`. The callable enforces
  App Check in code. This does not verify Console registration, deployed
  enforcement, or runtime service-account permissions.
- No Firebase deployment scripts, App Check Flutter dependency, or App Check
  initialization were found in the repository. `cloud_functions` is also not
  a Flutter dependency and the purchase callable is not called by the client.
- Firebase Console state, deployed Firestore rules, production App Check
  registration/enforcement, Play Console linkage, and deployed Function
  configuration cannot be verified from these repository files.

## Authentication and client data paths

The current Firebase identity provider signs in with Google credentials and
uses the Firebase Auth UID. Anonymous users are filtered out. The
`AuthenticatedPlayerRepository` takes its UID from the identity service; it
does not accept a UID from a UI caller. This describes the checked-in client,
not every version that may already be deployed.

The current Firestore data source uses these paths:

| Path | Observed client operations | Owner identity |
| --- | --- | --- |
| `players/{uid}` | Read profile; transactionally create if absent; transactionally update `displayName`, `photoUrl`, and `updatedAt` | UID supplied by `AuthenticatedPlayerRepository` |
| `players/{uid}/progress/data` | Read and decode progress | UID supplied by repository |
| `players/{uid}/inventory/data` | Read and decode inventory | UID supplied by repository |
| `players/{uid}/settings/data` | Read and merge-write settings | UID supplied by repository |

The checked-in Firestore data source has no progress or inventory write
operation. Those paths may have historical data or be written by another app
version; verify that before deciding to prohibit writes in deployed rules.
The profile create operation writes the full `PlayerProfile` map and its
update operation changes only display name, photo URL, and update timestamp.
Local gameplay wallet and progression persistence use local stores and do not
access these Firestore paths.

## Proposed rules policy for a later full ruleset

Once the deployed rules have been retrieved and reviewed in full, preserve
these narrow behaviors:

1. Allow a signed-in owner to read their own profile and use the current
   create/update operations. Validate that the profile's `uid` equals the
   document ID; restrict updates to the fields the profile update method
   changes and keep identity/schema/creation fields immutable.
2. Allow owner reads for the observed `progress/data`, `inventory/data`, and
   `settings/data` documents. Preserve owner writes to `settings/data`.
   Confirm whether progress or inventory writes are required by deployed app
   versions before defining their write policy.
3. Deny client read/write access to the full
   `gemPurchaseTransactions/{transactionId}` path.
4. Deny client read/write access to
   `players/{uid}/economy/gems`, including for the owner. The Admin SDK
   Function remains the writer of paid balance and purchase records.
5. Review every recursive wildcard and overlapping `allow` statement. Rules
   grants are additive, so a narrow deny cannot cancel a broader matching
   grant. Do not infer protection until the entire deployed ruleset has been
   checked for such grants.

Firestore rules are not changed here because there is no existing complete
ruleset to modify and the deployed rules are unknown. A standalone replacement
could remove access needed by existing clients or fail to revoke an existing
broad grant. Obtain the deployed rules and confirm legacy progress/inventory
write requirements before implementing and testing a complete rules change.

## App Check preparation

The Flutter project currently depends on `firebase_core`, `firebase_auth`, and
`cloud_firestore`, but not `firebase_app_check`. Firebase is initialized lazily
inside `createFirebasePlayerIdentityService`; App Check should be activated
immediately after `Firebase.initializeApp()` and before using protected Firebase
services. The repository has not activated it.

For Android production, Firebase's Flutter App Check guidance uses Play
Integrity. It requires registering the Android app in Firebase App Check and
configuring the Play Integrity API/linked project in Play Console. For local
emulator or development testing, the debug provider uses a separately
registered debug token; that token must remain private and must never ship in a
production build. Do not weaken the Function's `enforceAppCheck: true` setting
to accommodate development.

No App Check code was added: the plugin is absent from the installed project
dependencies, and Console registration/provider configuration has not been
verified. A future client change should add the FlutterFire plugin deliberately,
activate it in the shared Firebase initialization path, choose debug only for
development builds and Play Integrity for production Android builds, and
validate the resulting builds against registered test and production apps.

Firebase references:

- [App Check in Flutter](https://firebase.google.com/docs/app-check/flutter/default-providers)
- [Flutter debug provider](https://firebase.google.com/docs/app-check/flutter/debug-provider)
- [Play Integrity provider for Android](https://firebase.google.com/docs/app-check/android/play-integrity-provider)

## Deployment prerequisites

Before enabling purchases or deploying the purchase Function:

- Retrieve and review the complete deployed Firestore rules. Confirm no broad
  match grants access to the two server-owned paths and preserve verified
  player data operations.
- Configure and verify Android App Check registration, Play Integrity, and
  enforcement for the callable. Keep debug tokens out of releases.
- Finalize the Android application ID and configure `PLAY_PACKAGE_NAME` to the
  same value.
- Enable/link the Google Play Developer API and Play Console app, and grant the
  Function runtime identity only the permissions required to verify and
  consume products. Do not add service-account keys to the client.
- Verify deployed Firebase project, Functions source/runtime/parameters, and
  service-account configuration independently; local FlutterFire metadata is
  not evidence of deployed state.

No Firebase Console, Play Console, deployment, or live purchase operation was
performed as part of this preparation.
