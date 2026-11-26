# Purchase verification backend foundation

`verifyAndFulfillGemPurchase` is a Firebase Functions v2 callable. It is not
connected to the Flutter client, and `UnavailableGemPurchaseService` remains
the active implementation.

## Request contract

The callable requires a Firebase Authentication session and App Check. Its
request contains only:

```json
{"productId":"gems.small","purchaseToken":"<Google Play token>"}
```

The authenticated Firebase UID is authoritative. The caller cannot submit a
UID, a success flag, or a gem quantity. Product IDs and grants are defined in
`src/purchase_contract.js`; grants include the existing package bonuses.

The future Billing client must set Play Billing's obfuscated external account
ID to the lowercase SHA-256 hex digest of the authenticated Firebase UID. The
backend requires the same value in the Google-verified purchase response. This
prevents a token from being claimed by a different signed-in account.

## Durable records

- `gemPurchaseTransactions/{sha256(purchaseToken)}` is the global token
  uniqueness record. It stores the transaction ID, token hash, Firebase UID,
  product ID, state, verified/fulfilled/consumed timestamps, granted amount,
  attempt metadata, and a safe failure code. The raw purchase token is never
  written to Firestore or logs.
- `players/{uid}/economy/gems` stores the server-owned `paidBalance` separately
  from the existing local wallet. It is not currently read by Flutter.

The Firestore transaction writes the paid balance and
`fulfilled_pending_consumption` record atomically. Repeated verified requests
for a fulfilled token return the existing transaction and do not grant again.
The function then consumes the Play product. If consumption fails or its
response is interrupted, the durable fulfilled state remains and a retry
checks Play's consumption state before finishing the transaction record.

States are `pending`, `fulfilled_pending_consumption`, `fulfilled`, and
`rejected`. Only a Google-verified `PURCHASED` state may grant. `PENDING` is
recorded without a grant; a verified cancellation is terminally rejected.
Google API/configuration failures return an error and grant nothing, leaving a
later authenticated request free to retry verification.

## Required setup before deployment

1. Set `PLAY_PACKAGE_NAME` to the final Android application ID. The repository
   currently uses `com.example.orbit_dash`, which must be confirmed before
   creating Play products.
2. Enable Cloud Functions and billing for the Firebase project.
3. Enable the Google Play Developer API, link the Play Console app to the
   Google Cloud project, and grant the Functions runtime service account the
   minimum Play Console/API access needed to verify and consume one-time
   products. The function uses Application Default Credentials; no service
   account key is included.
4. Configure Firebase App Check for Android before invoking the callable.
5. Review deployed Firestore rules. This repository has no tracked Firestore
   rules, so deployment must not proceed until clients are confirmed unable to
   write `gemPurchaseTransactions` or `players/{uid}/economy/gems`.
6. Create Play products with IDs matching the server catalog and test the full
   flow using a licensed test account.

The Play API method used is `purchases.productsv2.getproductpurchasev2`; the
runtime identity must be authorized for the Android Publisher API. No
credentials or access are assumed to be configured by this repository.

## Current limits

- No Flutter Billing integration or checkout is enabled.
- The paid balance is not merged into the local GemWallet.
- A failed Play consume is recoverable by retrying this callable; no scheduled
  reconciler or RTDN handler is included in this foundation.
- Firestore rules are not created or replaced because the repository does not
  contain the current rules needed to preserve the existing player repository.
