# Temporary Firestore rules status

## Current rules

The rules provided for the current development configuration are:

```text
rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if request.time < timestamp.date(2026, 12, 25);
    }
  }
}
```

These rules permit any client read or write to any Firestore document until
December 25, 2026. They are intentionally permissive for active development
and are temporary.

## Repository and deployment status

This checkout contains no `firestore.rules` file, and `firebase.json` does not
declare a Firestore rules file. Therefore, the repository cannot confirm that
the supplied rules match a local rules configuration. Repository files also do
not establish the rules currently deployed in Firebase; deployed rules must be
checked separately.

## Security implications and future milestone

While these rules are active, clients can read and write all Firestore
documents, including data belonging to other users and data that should be
server-controlled. This can expose, alter, or delete data and should not be
treated as a production security policy. The date condition expires access
through this ruleset after December 25, 2026, unless the rules are changed.

Production-ready rules will be designed in a future milestone after the main
game features and backend functionality are complete. At that time, the rules
must reflect the implemented application, verified Firestore access patterns,
data ownership, and server/client responsibilities. The future work will
reassess the architecture and implemented features, identify required access,
protect server-owned data, economy, purchases, and transactions, and test
restrictive rules against legitimate gameplay before deployment. No future
rules design or implementation is part of this status document.
