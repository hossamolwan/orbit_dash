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

These contracts do not implement cloud writes, revisions, conflict resolution,
local migration, or offline queues. Current local stores remain authoritative
for gameplay. Future sync work must add a recoverable migration path, preserve
invalid/unknown data for review, and define field-specific merge behavior
before writing to Firestore.
