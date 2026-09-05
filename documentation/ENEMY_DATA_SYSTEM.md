# Enemy Data System

## Status

Development plan, point 1: implemented.

This layer defines shared enemy archetypes and weighted spawn-roster entries. It does not change the current spawner or instantiate runtime enemies. The future `EnemyWorld` will consume these Resources without creating one `Node3D` per enemy.

## Files

- `res://src/resources/enemy_data.gd`: shared definition of an enemy archetype.
- `res://src/resources/enemy_spawn_entry.gd`: weighted reference used by a level roster.
- `res://src/resources/enemies/`: initial enemy archetype assets.
- `res://tests/enemy_data_validation_test.tscn`: validation test suite.

## EnemyData contract

`EnemyData` is the Godot equivalent of a data asset. One Resource is shared by every runtime enemy of the same archetype. It contains authoring data only:

- Stable `enemy_id`.
- Display name and description.
- Behavior family.
- Shared `VisualAsset3D` profile; legacy scene/scale remain as compatibility fallback.
- HP, damage, attack interval, and collision radius.
- Movement and rotation speeds.
- Credit reward.

The visual prefab is loaded once by the batched renderer to extract meshes and materials. It is never instantiated once per mass enemy. See [3D asset standard](ASSET_3D_PIPELINE.md).

## Initial archetypes

| ID | Behavior | Visual source |
| --- | --- | --- |
| `asteroid_small` | `ASTEROID` | normalized prefab wrapping `meteoro_small.FBX` |
| `asteroid_medium` | `ASTEROID` | normalized prefab wrapping `meteoro_medium.FBX` |
| `asteroid_large` | `ASTEROID` | normalized prefab wrapping `meteoro_big.FBX` |
| `barrier_attack_ship` | `BARRIER_ATTACKER` | `enemy_spaceship_3d.tscn` through `VisualAsset3D` |

The initial numbers preserve the current gameplay values where they already exist. They are balance defaults, not a permanent simulation layout.

## EnemySpawnEntry contract

An `EnemySpawnEntry` connects an `EnemyData` Resource to a positive `spawn_weight`. A future `LevelConfig.enemy_roster` will contain these entries.

Example weights:

| Enemy | Weight | Expected share |
| --- | ---: | ---: |
| Small asteroid | 60 | 60% |
| Medium asteroid | 25 | 25% |
| Large asteroid | 10 | 10% |
| Barrier attack ship | 5 | 5% |

Weights are relative and do not need to add up to 100.

## Validation rules

`EnemyData.validate_catalog()` reports:

- Empty catalog entries.
- Values that are not `EnemyData` Resources.
- Empty IDs, names, or visual prototypes.
- Duplicate enemy IDs.
- Invalid HP, radius, scale, movement, combat, or reward values.

`EnemySpawnEntry.validate_roster()` reports:

- Empty roster entries.
- Values that are not `EnemySpawnEntry` Resources.
- Missing enemy references.
- Non-finite, zero, or negative spawn weights.
- Repeated enemy IDs in the same roster.

Validation returns every discovered error instead of stopping at the first one, so editor tooling can present a complete correction list.

## Ownership rules

- `EnemyData` describes what an enemy archetype is.
- `EnemySpawnEntry` describes its relative probability in one level.
- `LevelConfig` will own the roster and spawn-rate settings.
- `MassEnemySpawner` will schedule spawn commands.
- `EnemyWorld` will own runtime state and GPU buffers.

No runtime position, current HP, target, timer, or state-machine state belongs inside `EnemyData`.

## Test command

```powershell
& 'E:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --path 'E:\GODOT\vearthIncThreat' 'res://tests/enemy_data_validation_test.tscn'
```

## Integration status

Development points 2 and 3 are now implemented. `LevelConfig` contains:

- `total_enemies`.
- `enemies_per_spawn_point`.
- `spawn_interval_seconds`.
- `enemy_roster: Array[EnemySpawnEntry]`.

The new `MassEnemySpawner` consumes these fields and submits compact spawn requests to the step-4 `EnemyWorld`. See [Mass Enemy Spawner](MASS_ENEMY_SPAWNER.md), [EnemyWorld](ENEMY_WORLD.md), and the [development checklist](ENEMY_DEVELOPMENT_PLAN.md).

The current `actor_type` remains untouched until the new mass-enemy path is integrated and tested.
