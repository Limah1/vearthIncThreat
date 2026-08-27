# Grid Combat

## Production status

The approved grid-combat prototype is now the production preparation flow for
Level 1 and Level 2. Both level resources load
`res://src/levels/GridCombatLevel.tscn`, preserve their own enemy counts, and
configure their own placement inventories.

The old Level 0 resource remains available for direct tests but has
`show_in_level_select = false`, so it is no longer displayed in the player-facing
level selector.

## Player flow

Every grid-enabled level follows:

```text
PREPARATION -> PLAYING -> END_SESSION
```

During preparation:

- choose an Ally Ship, Barrier, or unlocked turret from the footer;
- the preview follows the cursor and snaps to the board;
- Ally Ships occupy two adjacent cells;
- Barriers occupy one cell and have 10 HP;
- the four central planet cells reject placement;
- occupied or out-of-board footprints reject placement;
- press `A` or `D` to rotate the active ship preview;
- click a placed ship and use `A` or `D` to rotate it after placement;
- rotation is rejected when the new two-cell footprint is blocked;
- right-click cancels placement or clears selection;
- Reset returns placed actors and turrets to their inventories;
- Start Wave remains disabled until the configured minimum ship count is met.

When Start Wave is pressed, placement UI is hidden, the production spawner is
released, player click damage is enabled, and the normal combat loop runs.
Eliminating the configured enemy total banks run credits and opens the normal
balance summary.

## Per-level configuration

`LevelConfig` exposes:

| Property | Purpose |
|---|---|
| `grid_combat_enabled` | enables mandatory grid preparation |
| `grid_board_config` | board dimensions, cell size, origin and blocked cells |
| `starting_ally_ships` | two-cell ship inventory |
| `starting_defense_blocks` | one-cell Barrier inventory |
| `minimum_ally_ships_to_start` | required placed ships before the wave |
| `show_in_level_select` | hides internal/test levels from players |

Inventory values are also included in the Balance Editor's `Levels` worksheet.
The importer rejects configurations where required ships exceed starting ships.

Current production values:

| Level | Enemies | Ally Ships | Barriers |
|---|---:|---:|---:|
| Level 1 | 200 | 4 | 3 |
| Level 2 | 450 | 5 | 4 |

## Runtime contracts

Grid combat reuses the production systems rather than simulating them:

- `Spawner` and the selected `LevelConfig` control the wave;
- `Barrier` supplies Ally Ship health, collision, avoidance and turret mounts;
- `PreparationController` owns turret placement and cone editing;
- `GridDefenseBlock` uses the production damage-team and avoidance contracts;
- `GameManager` owns credits, eliminated threats, unlock progression and states;
- asteroid movement continues to use the production obstacle spatial hash.

The grid board stores occupancy in dictionaries. It does not create one node per
cell. Grid lines are drawn through one `ImmediateMesh`, while blocked cells and
the active footprint use lightweight overlays.

## Main files

```text
src/levels/GridCombatLevel.tscn
src/prototypes/grid_combat/GridCombatPrototype.tscn
src/prototypes/grid_combat/grid_combat_controller.gd
src/prototypes/grid_combat/grid_board.gd
src/prototypes/grid_combat/grid_defense_block.gd
src/prototypes/grid_combat/resources/GridPrototypeConfig.tres
src/resources/level_config.gd
tests/grid_combat_prototype_test.gd
```

The `prototypes` directory name is retained for asset compatibility. The scene
loaded by player levels is the production wrapper in `src/levels`.

## Test

```powershell
& 'E:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --path 'E:\GODOT\vearthIncThreat' 'res://tests/grid_combat_prototype_test.tscn'
```

The integration test covers production LevelConfig selection, per-level
inventory, preparation spawn gating, two-cell occupancy, post-placement
rotation, destructible Barriers, Start Wave handoff, enemy spawning, completion
and credit banking.
