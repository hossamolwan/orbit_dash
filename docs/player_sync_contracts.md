# Player sync contracts and local mappings

This milestone defines version 1 sync data contracts and read-only projections
from the existing local stores. It does not read or write Firestore and does
not perform migration or synchronization.

## Progress v1

| Field | Meaning and source of truth | Validation | Missing behavior |
| --- | --- | --- | --- |
| `highScore` | Highest Survival score. The local mapper takes the maximum of the existing survival-best preference and `PlayerStatisticsStore.bestRun` so either existing copy is preserved. | Integer from 0 through `LocalDataValidation.maxPersistedCounter`. | Missing document is reported as missing; explicit new-player defaults use 0. |
| `runsStarted` | Survival runs started, from `PlayerStatisticsStore.runsStarted`; it is not a completed-run count. | Integer from 0 through the shared counter maximum. | Missing document is reported as missing; explicit default is 0. |
| `losses` | Collision losses from `PlayerStatisticsStore.losses`. | Integer in the shared counter range. | Missing document is reported as missing; explicit default is 0. |
| `shieldAbsorptions` | Shield-absorbed collisions from `PlayerStatisticsStore.shieldAbsorptions`. | Integer in the shared counter range. | Missing document is reported as missing; explicit default is 0. |
| `maxOrbit` | Highest orbit count reached from `PlayerStatisticsStore.maxOrbit`. | Integer from 2 through 5. | Missing document is reported as missing; explicit default is 2. |

The high score is a projection because the current app has two persisted
representations. This mapper reconciles them with `max`; it does not rewrite or
delete either local key. `level`, `xp`, `totalXp`, `totalDistance`, completed
stages, achievements, and daily challenge progress are excluded. The first
four are unused by runtime gameplay; completed stages are retained legacy
statistics rather than active progression; achievements and daily challenges
have separate semantics and contracts that are not part of this milestone.

## Inventory v1

`ownedItemIds` is a sorted, unique set of catalog IDs. The four baseline
cosmetics are always included as owned: `ship.defaultSkin`,
`orbit.defaultOrbit`, `core.defaultCore`, and `trail.classic`.

`equipped` independently represents `ship`, `orbit`, `core`, and `trail`.
Each ID must exist in the corresponding current catalog and in
`ownedItemIds`. Current IDs are preserved, including the existing canonical
aliases `orbit.void` and `core.void`. Unknown IDs, duplicate ownership entries,
wrong-slot IDs, missing defaults, and unowned equipped items produce explicit
validation issues; they are not silently dropped or replaced by defaults.

The local inventory mapper projects cosmetic IDs from `GemWallet.purchasedItemIds`
and equipment from `SkinStore`/`AppearanceStore`. It validates the projected
IDs and never returns wallet balance, purchase prices/history, daily reward
ledgers, or payment data. It does not mutate those stores. This projection is
not proof of a real-money entitlement.

## Decode behavior and limitations

Both contracts use `schemaVersion: 1`. Decoding returns one of `missing`,
`valid`, or `invalid`, retaining path-specific validation issues for invalid
documents. Missing documents are not converted to defaults. Callers may choose
the explicit `defaults()` value for a new player after making that decision.
Only fields in schema v1 are accepted; a future schema version requires an
explicit contract update.

## Cloud write foundation (Milestone 2)

`PlayerSyncRepository` exposes explicit load and save methods for the
authenticated account's Progress and Inventory contracts. The Firestore data
source stores each contract in its existing domain document:

- `players/{uid}/progress/data`
- `players/{uid}/inventory/data`

The canonical contract and its revision are stored in a nested `sync` envelope
(`sync.revision`, `sync.payload`). This keeps the strict contract fields
separate from legacy fields already present in each document. Writes use a
Firestore transaction and `SetOptions(merge: true)` on only the `sync` field;
they do not replace the domain document or touch the other domain, Settings,
Profile, or sibling collections. Inventory payloads contain only canonical
cosmetic IDs/equipment and never wallet balance or purchase records.

The repository captures the authenticated UID when constructed and does not
accept a UID in its public sync methods. The caller first loads a sync snapshot
and passes its domain-specific revision as `expectedRevision`. New or legacy
documents without a `sync` envelope have revision 0. A successful transaction
increments the selected domain's revision. If the stored revision differs,
the write fails with `staleRevision`; there is no application-level retry of
that stale payload. Firestore may rerun a transaction callback on contention,
and each callback attempt rereads and checks `expectedRevision`. Progress and
Inventory revisions are independent. If the expected revision matches and
the canonical payload is unchanged, the operation succeeds as a no-op and
returns the current revision without issuing a write. Existing malformed sync
envelopes or payloads are rejected without replacement.

Invalid payloads, invalid expected revisions, stale revisions, malformed
stored data, Firestore permission denials, and other service failures have
distinct backend-neutral write failure codes. No Firebase exception details
are exposed through the sync write API.
Existing legacy `loadProgress`/`loadInventory` behavior remains unchanged; the
new sync snapshot methods read only the nested canonical envelope.

This is an explicit cloud persistence capability only. No automatic sync,
gameplay-triggered writes, local migration, offline queue, retry policy,
conflict resolution, entitlement verification, or Firestore Rules changes are
included. Local stores remain authoritative for gameplay, and sync writes do
not mutate them. The expected-revision mechanism prevents concurrent stale
domain writes only when callers use a freshly loaded snapshot; it does not
reconcile divergent local and cloud values or make local ownership proof of
purchase entitlement.
