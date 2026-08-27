# Level and Grid Authoring

## Production workflow

Level combat layouts are now authored through `LevelConfig` plus a grid board,
not by placing permanent Ally Ship instances in each level scene.

For a new level:

1. Duplicate an existing `LevelConfig` in `src/resources/levels/`.
2. Assign `res://src/levels/GridCombatLevel.tscn` to `level_scene`.
3. Enable `grid_combat_enabled`.
4. Assign a `GridPrototypeConfig` resource to `grid_board_config`.
5. Configure enemy type/count and the starting ship/Barrier inventories.
6. Set the minimum number of Ally Ships required to start.
7. Keep `show_in_level_select` enabled for player-facing levels.
8. Run the grid integration test before shipping.

## Board configuration

The board resource controls:

- columns and rows;
- world-space cell size;
- board origin;
- blocked cells.

The central planet footprint is represented by blocked cells. Additional blocked
cells can define map-specific lanes, hazards or unavailable construction areas.

Ally Ships use a two-cell footprint and can face any cardinal direction.
Barriers use one cell. Turrets do not consume board cells because they occupy the
two fixed mounts on an Ally Ship.

## Legacy level scenes

`Level1.tscn`, `Level2.tscn`, and their manually authored Ally Ships are retained
as legacy/reference maps. Player-facing Level 1 and Level 2 now load
`GridCombatLevel.tscn` through their `LevelConfig` resources.

Do not add permanent `Barrier` instances to the production grid scene. The grid
controller creates them from the level inventory during preparation.

## Internal test map

`GridPrototypeLevelConfig.tres` remains a hidden Level 0 used for direct testing.
It should keep `show_in_level_select = false` so it does not appear beside normal
campaign levels.
