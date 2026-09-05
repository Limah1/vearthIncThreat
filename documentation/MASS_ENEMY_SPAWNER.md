# Mass Enemy Spawner

## Status

Development plan, points 2 and 3: implemented as a parallel path.

The existing Node-based `Spawner` remains active for the current game. The mass path is connected to `EnemyWorld` (point 4) in `res://src/prototypes/mass_enemies/MassEnemyFoundation.tscn`. See [the development checklist](ENEMY_DEVELOPMENT_PLAN.md) for current status.

## LevelConfig fields

```gdscript
total_enemies: int
enemies_per_spawn_point: int
spawn_interval_seconds: float
enemy_roster: Array[EnemySpawnEntry]
```

- `total_enemies` is the total number of spawn commands for the entire level.
- `enemies_per_spawn_point` is emitted by every point during one cycle.
- `spawn_interval_seconds` is the duration between cycles.
- `enemy_roster` is the weighted list of allowed enemy archetypes.

The theoretical spawn rate is:

```text
spawn points × enemies per spawn point ÷ interval seconds
```

Example: 40 points × 2 enemies ÷ 1 second = 80 enemies per second.

`actor_type` remains under the `Legacy Spawner` inspector group. It is ignored by `MassEnemySpawner` and can be removed after the old runtime path is retired.

## Runtime contract

`MassEnemySpawner` discovers live `Node2D` markers in the `spawn_point` group at wave start, scoped to `spawn_root` (or its parent subtree). Auto-start is deferred until sibling nodes have entered the tree. A `SpawnerPoint` registers itself automatically; generated legacy points already use the same group. `set_spawn_points()` accepts an explicit ordered list for tests and custom setups.

The spawner emits:

```gdscript
spawn_requested(enemy: EnemyData, world_position: Vector3, sequence: int)
```

With `enemy_world` assigned, the spawner registers the catalog once, calls `EnemyWorld.request_spawn()` and counts only accepted allocations. The signal is then an observation of an accepted spawn; do not connect it to another allocator or the same enemy would spawn twice. Without a world, the spawner can still run as a request-only scheduler for unit tests.

When capacity is exhausted, the current cycle cursor and remaining requests stay pending. Recycling world slots allows spawning to resume. World or point removal aborts the wave with `configuration_rejected`, never a success notification.

The first cycle occurs after one full `spawn_interval_seconds`. Every complete cycle visits each point and emits `enemies_per_spawn_point` requests. The final partial cycle stops exactly at `total_enemies`.

## Frame-drop handling

Elapsed time is accumulated. If one frame crosses multiple intervals, the spawner catches up through multiple cycles. `max_catch_up_cycles_per_frame` limits cycles and `max_spawn_commands_per_frame` (default 1024) limits requests, including within one large cycle. Unprocessed elapsed time and partial-cycle progress stay queued. Under sustained overload the schedule runs behind its nominal rate rather than silently dropping requests.

This prevents both lost spawn time and a large one-frame spike after a stall.

## Weighted selection

Every request independently selects one valid roster entry using relative weights. Weights do not need to add up to 100. `random_seed = 0` randomizes a run; any nonzero seed gives a repeatable sequence for tests and deterministic debugging.

Counts, interval, roster membership and weights are captured at wave start. Restart explicitly to apply Inspector changes. A repeated `start_spawning()` is idempotent; `stop_spawning()` / `resume_spawning()` preserve progress. `reset_spawning()` clears scheduler state only, so reset the world separately when restarting a populated wave. Game preparation/pause and SceneTree pause do not accumulate spawn time, including when using `advance_spawning()` manually. Standalone demos can disable `respect_game_state`.

## Validation and failure behavior

Starting is rejected when:

- `level_config` is missing.
- No SpawnPoint exists.
- Spawn values are invalid.
- The roster is empty or invalid (including the referenced EnemyData, non-finite numeric values and unpacked visual Resources).
- Enemy IDs repeat in the roster.

All errors are emitted through `configuration_rejected` and logged as warnings. No partial spawning begins from an invalid configuration.

## Current level resources

The three existing LevelConfig assets now contain a valid mass roster with the small asteroid at weight 1. Their legacy `actor_type` behavior is unchanged.

## Tests

The test suite covers:

- Spawn-rate calculation.
- SpawnPoint group registration.
- Per-point batch size.
- Interval timing.
- Exact total limit.
- Single completion event.
- Frame-drop catch-up and queued elapsed time.
- Invalid configuration rejection.
- Weighted roster selection.

```powershell
& 'E:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --path 'E:\GODOT\vearthIncThreat' 'res://tests/mass_enemy_spawner_test.tscn'
```

## Next development point

Point 4 is implemented in `EnemyWorld`. Point 5 adds MultiMesh rendering and measures actual rendered performance; the foundation tests alone do not establish a frame-rate target.
