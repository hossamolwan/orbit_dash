# Economy and Shop Review

## 1. Executive Summary

Orbit Dash currently has a working **local soft-currency economy**. Gameplay and
daily rewards credit an account-scoped `GemWallet`; cosmetic purchases deduct
gems and record item ownership together in the wallet's saved JSON state.
Equipped cosmetics are saved separately and checked against wallet ownership
when stores load.

The Gem Shop is not a working real-money checkout. Its production entry point
uses `UnavailableGemPurchaseService`, and every package action reports that
purchases are unavailable without changing the wallet. A Firebase Functions
callable provides a Google Play verification and server-side grant foundation,
but there is no Flutter Billing or callable integration, and its paid balance
is not merged into the local wallet.

The local write ordering is generally sound for this single-client game: wallet
operations serialize within a wallet instance, validate balance bounds, write
the combined balance/ownership state before updating memory, and reject repeat
item purchases. The main practical findings are limited shop feedback when
local writes fail, a buy-then-equip two-tap flow, and the lack of a path from the
cosmetic shop to the unavailable real-money shop. Local wallet values are not
server-authoritative and must not be treated as a secure monetary balance.

**Final verdict: Approved with Notes.** Local earned-gem cosmetics are
implemented and have focused tests. Real-money gem purchasing remains
unavailable as indicated in the UI and must not be represented as integrated.

## 2. Current Economy Architecture

- [lib/gem_wallet.dart](../lib/gem_wallet.dart) owns spendable gems, purchased
  item IDs, daily reward idempotency data, and recent pickup deduplication.
  State is serialized as one versioned JSON value under a player-scoped
  `SharedPreferences` key.
- [lib/main.dart](../lib/main.dart) creates one wallet per `OrbitGamePage`
  using the current session player ID. Gameplay pickups and daily challenge
  claims credit it; cosmetic shop handlers spend from it.
- [lib/skins.dart](../lib/skins.dart) defines the cosmetic catalogs and stores
  equipped ship, orbit, core, and trail selections separately from ownership.
- [lib/gem_shop.dart](../lib/gem_shop.dart) defines display packages and a
  service boundary. Its shipped implementation always reports unavailable.
- [functions/src/index.js](../functions/src/index.js) and
  [functions/src/purchase_contract.js](../functions/src/purchase_contract.js)
  implement a separate purchase verification and server grant foundation.
  [functions/README.md](../functions/README.md) explicitly says that it is not
  connected to Flutter.

The four cosmetic catalogs contain ship, orbit, core, and trail items with
stable IDs and gem prices. Each catalog includes a zero-price default item and
priced cosmetic choices. The UI passes catalog prices to wallet spending and
renders those same prices.

## 3. GemWallet Analysis

### Initialization and persistence

`GemWallet.load` reads the account-scoped `orbit_dash_gem_wallet_v1` value.
Missing or undecodable state initializes to zero balance and empty ledgers and
ownership, then writes version 3. Versions 1 and 2 are decoded and migrated to
version 3. Balance and purchase records are checked for type and bounds; a
negative balance, balance above `maxBalance`, malformed reward ledger, or
invalid purchase entry is rejected by the decoder.

The app runs `LocalDataPreflight` before loading feature stores. If the wallet
domain is invalid, it attempts to quarantine the raw wallet value and fails the
feature-store load instead of entering normal gameplay with a reset wallet.
This is an app startup safeguard; a direct standalone `GemWallet.load` call
with undecodable data treats it as absent and writes an empty state.

### Credits, spending, and consistency

- `creditPickupOnce` rejects blank IDs, nonpositive amounts, and overflow. Its
  pickup deduplication set is in memory only, intentionally scoped to a run
  session and capped at 256 recent IDs.
- `creditDailyRewardOnce` persists date/challenge IDs, with bounded retention
  for 30 dates and 128 claims per date, and commits the reward with the new
  balance in one wallet-state write.
- `purchase` rejects blank IDs, nonpositive or over-limit prices, insufficient
  balance, and already-owned IDs. It writes the debited balance and new
  ownership map together before changing in-memory values.
- `_serialize` chains actions within a `GemWallet` instance, preventing two
  concurrent operations through that instance from spending the same balance
  twice. Failed writes throw before the in-memory balance/ownership is
  committed. Tests in `test/progression_stores_test.dart` cover purchase
  deduplication and persistence failure; wallet reward ledger tests are in
  `test/gem_wallet_daily_reward_test.dart`.

The checked-in app constructs one wallet for the game page, so the serialization
guard applies to its normal UI path. There is no server lock or server-owned
authority for this local wallet. Multiple independent `GemWallet` instances
are not coordinated by the per-instance `_tail`; the current app path does not
show concurrent independent wallets being used for purchases.

### Integrity boundary

The implementation prevents ordinary UI overspending and negative balances,
but `SharedPreferences` and client code are user-controlled storage. Local
balances and item IDs can be modified by a device owner or altered client.
`GemWallet.purchase` accepts an item ID and price from its caller and validates
basic bounds and ownership, not a server-owned catalog or price. The UI passes
the catalog price, but that is not a security boundary. This is acceptable only
for the current local earned-gem economy; it is not sufficient authority for
paid currency or purchases.

## 4. Shop & Pricing Analysis

### Cosmetic shop

`_skinsContent` in `lib/main.dart` presents four horizontally selectable
categories. Each item shows rarity, description, price, and one of `EQUIPPED`,
`OWNED - EQUIP`, `BUY - N GEMS`, or `NEED N MORE`. Items that are unaffordable
are disabled. The catalog and wallet use the same `price` field for each
cosmetic, so the reviewed UI-to-spend path has no price mismatch.

Ship, orbit, core, and trail purchase handlers call `GemWallet.purchase` with
the catalog's `itemId` and `price`. Repeated purchase attempts are blocked by
wallet ownership and by `_purchaseInProgress` guards. There is no purchase
confirmation dialog. After buying an item, the player must select it again to
equip it; purchase and equip are separate actions and separate persistence
writes.

### Gem packages

`lib/gem_shop.dart` defines four packages with hard-coded display price
metadata and total gems including bonuses. The server catalog grants the same
totals: 500, 1,300, 2,850, and 7,200 gems. However, those values are not fetched
from Google Play, and the `$` display strings are static metadata rather than
localized store prices.

`GemShopDialog` shows package totals, optional bonus amounts, and the display
price. Package rows can be selected, but selection does not affect which
package action can be invoked. Every action is labelled `NOT AVAILABLE`; the
button invokes the service, which returns unavailable. The UI reports that
purchases are coming soon and explicitly says the Gem balance has not changed.
There is no insufficient-balance flow here because this shop is for real-money
packages, not spending gems.

## 5. Cosmetics & Ownership Analysis

The wallet's `purchases` map is the ownership record: each item ID maps to the
price paid. Ship IDs use `ship.<enum name>`, trail IDs use `trail.<enum name>`,
and orbit/core identity extensions preserve the special `orbit.void` and
`core.void` IDs. All purchase and selection handlers resolve catalog entries
before acting.

`SkinStore` persists the equipped ship separately. `AppearanceStore` persists
orbit, core, and trail selections under separate account-scoped keys. On load,
each store checks the selected ID against the wallet's purchased item IDs and
falls back to its default if no longer owned or if the stored value is invalid.
Default cosmetics are selectable without wallet ownership. This keeps equipped
state from granting ownership by itself.

Ownership and balance are committed together for cosmetic purchase. Equipped
selection is then persisted in a separate operation only when the player
chooses the owned item. If that selection write fails, ownership remains
persisted and the current/default selection remains; the error is logged but
not shown in the UI. The code does not automatically equip an item on purchase.

The cosmetic shop supports preview dialogs and clearly labels a preview as
non-purchasing/non-equipping. The debug-only cosmetic test mode is gated by
`kDebugMode` and changes preview/equipped visuals without wallet purchase.

## 6. Purchase Flow Analysis

### Cosmetic gem purchase path

1. The player taps a cosmetic row. The UI disables it when the displayed
   wallet balance is below the catalog price.
2. The handler checks current ownership and `_purchaseInProgress`, then calls
   `GemWallet.purchase(itemId, price)`.
3. The wallet re-reads saved state, serializes the operation, checks duplicate
   ownership and available balance, then writes the new balance and ownership
   together.
4. Only after the write succeeds does the wallet update memory. The caller
   rebuilds the shop, showing `OWNED - EQUIP`.
5. Equipping requires a second tap and writes the selected cosmetic through
   `SkinStore` or `AppearanceStore`; the UI refreshes after the save succeeds.

There is no success dialog, but the ownership indicator is the success signal.
On a persistence exception the balance/ownership are not committed in memory.
The handler catches and logs the error; no user-facing failure message appears.
For the ship handler, a `false` result (including insufficient balance or
duplicate state) does not show an error. The appearance handlers likewise do
not inspect the boolean result. The normal UI guards make insufficient balance
non-actionable and purchase-in-progress prevents normal repeated taps, but a
late storage conflict or write failure can still leave the player with no
visible explanation.

### Real-money package path

The displayed package action calls `GemPurchaseService.purchase`. The dialog
has a pending spinner and disables package and close controls while the call
is in progress. The currently injected service is the default unavailable
service. It never modifies wallet balance, and no successful status exists in
the current `GemPurchaseStatus` enum. Thus the path currently stops at
unavailable feedback; price validation, Google Play checkout, server
verification invocation, paid-balance refresh, and client-side grant display
are not connected.

## 7. Firebase & Backend Integration Status

### Existing functionality

- Firebase Auth and Firestore are Flutter dependencies, and the Firebase
  Functions source is configured in `firebase.json`.
- `verifyAndFulfillGemPurchase` is implemented as a Firebase Functions v2
  callable requiring Firebase Auth and App Check.
- The contract accepts only a known product ID and purchase token. The server
  uses the authenticated UID, verifies Google Play product/account/state,
  hashes the token for a unique transaction record, and atomically records a
  server-owned paid balance plus a `fulfilled_pending_consumption` transaction
  before consuming the Play item. Retries use the durable transaction state.
- Server package grant totals match the totals displayed in `gemPackages`.

### Missing integration and compatibility limits

- [pubspec.yaml](../pubspec.yaml) has no `in_app_purchase` or
  `cloud_functions` Flutter dependency.
- `lib/main.dart::_openGemShop` constructs `GemShopDialog` without a service,
  so the unavailable default is used. No code invokes the callable.
- The server writes `players/{uid}/economy/gems.paidBalance`; the Flutter
  `GemWallet` neither reads nor merges that field. The server balance and local
  earned balance are separate economies today.
- The future client must reconcile the server's granted quantity and
  `fulfilled_pending_consumption` result, handle pending/unavailable/error
  states, bind the Play account to the Firebase UID as documented, and refresh
  the correct balance. Those behaviors cannot be verified because there is no
  Billing client integration.
- Product IDs and grant totals are aligned, but the current static display
  prices do not establish Play product configuration or localized pricing.
  Firebase/Play Console setup, deployment, App Check configuration, and remote
  runtime state were not verified in this read-only repository review.

There is no present code conflict because the server paid balance is not
connected to the local wallet. Future integration will need an explicit
authority and display model so a client-controlled earned balance cannot
overwrite or impersonate the server-verified paid balance.

## 8. UX Findings

- Cosmetic affordability and ownership are visible directly on each item;
  the player can preview before purchase, and equipped status is explicit.
- Cosmetic purchase has no confirmation step and no visible processing state.
  `_purchaseInProgress` blocks duplicate handler calls, but the button itself
  remains visually available during the operation.
- A successful cosmetic purchase changes the item to `OWNED - EQUIP`; a
  second tap is needed to equip. This is coherent with the separate states but
  is not explained in a confirmation message.
- Persistence failures and failed equip saves are only sent to `debugPrint`.
  Players may see the unchanged shop state without knowing why the action
  failed.
- The cosmetic shop has no direct `GET GEMS` action. The main menu has one,
  but navigating back to the menu is required when the player cannot afford a
  cosmetic.
- Gem package prices are static dollar strings. The unavailable state is
  explicit and the balance is not falsely credited, but the selectable
  highlight may suggest a checkout selection even though all package buttons
  remain `NOT AVAILABLE`.

## 9. Issues & Risks

### Critical

None identified.

### High

None identified for currently enabled local soft-currency functionality.
Paid gem checkout is not enabled, as the UI and service indicate.

### Medium

None identified as a current loss, duplicate deduction, negative balance, or
ownership corruption in the normal single-wallet app path.

### Low

1. **Local cosmetic purchase failures have no player-facing explanation.**
   `lib/main.dart::_purchaseSkin`, `_selectOrbitSkin`, `_selectCoreSkin`, and
   `_selectTrailSkin` catch persistence exceptions and only log them; several
   handlers also ignore `GemWallet.purchase`'s `false` result. A failed save
   leaves the item unaffordable/unowned as before, but the player receives no
   reason. Regression coverage should include the visible failure state if a
   user-facing message is later added.
2. **Cosmetics require a separate purchase and equip tap.** The first tap
   purchases through `GemWallet.purchase`; only a later tap runs the selection
   store. This is consistent with the current UI labels but adds a step and is
   not called out after purchase. This is an observation, not a correctness
   failure.
3. **The cosmetic shop does not link directly to gem acquisition.** The only
   `GET GEMS` entry point is on the main menu; unaffordable cosmetic rows are
   disabled and tell the player the shortfall, but do not offer navigation to
   that entry point.

### Informational

1. **Local wallet is not a trusted paid balance.** `lib/gem_wallet.dart`
   stores client-editable `SharedPreferences` state and accepts the supplied
   item ID/price at its method boundary. UI catalog values provide ordinary
   validation only. Do not use this wallet as proof of payment or entitlements.
2. **Google Play checkout remains an unconnected foundation.** The callable
   and server ledger are implemented, but no Flutter Billing plugin, callable
   invocation, or paid-balance merge is present. Real-money package purchase
   cannot currently complete from the app.
3. **The package display price is static metadata.** `lib/gem_shop.dart`
   uses hard-coded USD strings instead of store-provided localized prices.
   This has no transaction effect while checkout is unavailable.

## 10. Recommended Next Steps

1. Before enabling paid products, connect a Flutter Billing client to the
   existing callable and define how server-verified paid gems are presented
   alongside local earned gems. Keep the callable authoritative for paid
   grants; do not credit a local balance from a client-reported success.
2. Use store-provided localized product details for displayed prices and
   explicitly handle pending, verified, fulfilled-pending-consumption, and
   failure outcomes in the eventual purchase UI.
3. Improve player-facing feedback for failed local cosmetic purchase/equip
   persistence and consider a direct route from the cosmetic shop to gem
   acquisition. Preserve the existing ownership and balance transaction
   semantics.
4. Keep the current local cosmetic economy as local-only unless and until a
   product requirement calls for server-authoritative soft currency. No
   backend redesign is required by this audit.

## 11. Final Verdict

**Approved with Notes.** The local earned-gem and cosmetic shop path has
consistent UI/catalog prices, bounded wallet validation, same-write balance
deduction plus ownership recording, per-wallet operation serialization, and
ownership-checked equipped state. The primary note is architectural: all of
that economy is local and user-modifiable. Real-money purchase support is a
backend foundation only; the in-app package flow intentionally reports
unavailable and has no client integration. The low-severity UX gaps above do
not block the current local-only shop, but they should be considered before
broader availability or paid checkout is enabled.
