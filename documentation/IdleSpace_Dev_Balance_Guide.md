# Development & Balance Guide - VearthIncThreat (Godot 4)

This document unifies the **Developer Guide (Godot 4 & GDScript)** and the **Upgrades & Sizing Balance Guide**, serving as a reference manual for expanding code features and calibrating mathematical parameters in the game.

---

## PART 1: DEVELOPER GUIDE (GODOT 4 / GDSCRIPT)

The project leverages Godot 4's lightweight scripting combined with custom autoload managers and dynamic resource definitions.

### 1. Object Pooling (`BaseMasterPool` & `Node3D` Instances)
To maximize CPU performance and minimize memory fragmentation, dynamic gameplay nodes (such as Space Garbage, Asteroids, Enemy Spaceships, Debris, and Projectiles) **MUST NEVER** be created using `instantiate()` directly during gameplay loops or destroyed with `queue_free()`.
* **Borrowing**: Call the relevant master pool's `borrow_instance()` or public spawn method.
* **Returning**: Call the relevant master pool's `return_to_pool(instance)` or call the entity's `die()` / recycle method.
* **Coding Protocol**:
  - `on_pool_activate(spawn_pos_3d, ...)`: Reset physical parameters, health, visibility, timers, and manager registrations.
  - `on_pool_deactivate()`: Stop movement, clear visual markers, unregister manager/grid/collision membership, and hide visuals.
  - `_manager_move(delta)`: Keep active movement in `GameManager`'s centralized dispatcher.
  - `_manager_collision()`: Keep collision sweeps separate from movement; use lower frequency where gameplay allows.
  - `take_damage(amount)`: Apply damage, use pooled Label3D feedback, and trigger `die()` if health falls below zero.

### 2. High-count runtime rules
The project targets hundreds of active objects. Keep per-entity work bounded:
* Use `GameManager` movement/collision registration instead of one `_physics_process()` callback per threat.
* Use the incremental spatial grid for nearby-target queries; update cells only when entities cross boundaries.
* Use `MultiMeshRenderer` for repeated garbage, debris, and projectile visuals.
* Avoid per-hit logging, per-frame scene-tree searches, dynamic popup/tween allocation, and per-ship pathfinding queries.
* Keep glow, shadows, and material emission disabled unless a measured visual requirement justifies their GPU cost.

### 3. Level data assets
Create one `LevelConfig` resource per playable level under `res://src/resources/levels/`. Set `level_number`, `level_name`, `icon`, `level_scene` (a full playable scene copied from the first-level world, with planet, spawners, pools, camera, UI, and an `AllyShips` node for manually placed barriers), one `actor_type` (`small_asteroid`, `medium_asteroid`, `large_asteroid`, `enemy`, or `garbage`), and `total_enemies`. All configured actors spawn in one pass at random spawn points when the wave starts. Example first level: `small_asteroid`, total `500`. The upgrade screen's `SELECT LEVEL` button discovers these resources, shows icon/type/total, and starts the selected config.

### 4. Workflow for Adding New Game Content

#### A. Adding a New Upgrade Resource
1. In the FileSystem, create a new Resource (`.tres`) in [res://src/resources/upgrades/](file:///e:/GODOT/vearthIncThreat/src/resources/upgrades/).
2. Select `UpgradeData` as the script class.
3. Configure the inspector parameters:
   - `upgrade_id`: Unique identifier (e.g. `DA_MyNewUpgrade_T0`).
   - `upgrade_name`: Display title in the tooltip.
   - `description`: Explanatory tooltip text.
   - `category`: Select one of the supported category enums (e.g. `ClickDamage`, `DebrisAmount`, `PlanetHealth`).
   - `base_cost`: The credit price to purchase.
   - `max_level`: Maximum level limit.
   - `value_increment`: Multiplier increase per level.
   - `internal_level`: Step multiplier scaling.
   - `is_percentage`: Set to `true` for compound exponential scaling, or `false` for linear.
4. **Linking nodes**: In the parent upgrade resource, add your new upgrade's ID to its `unlocks` list. The skill tree connection lines and unlocks will be generated dynamically!

#### B. Adding a New Spawner or Path Point
1. Open the active scene `main.tscn`.
2. Locate the relevant `SpawnPath` under `GarbageCircleSpawner` or `AsteoidsCircleSpawner` in `main.tscn`.
3. Select `SpawnPath` and add points to the path to modify the spawning ring.
4. If you want to configure spawners, they will automatically spawn along the Path2D points during startup.

---

## PART 2: UPGRADES BALANCE & MATHEMATICS

### 1. Unified Multiplier Formula
The system starts with a **Base Multiplier of `1.0` (100%)**.
Upgrades accumulate additively inside categories:
$$\text{FinalMultiplier} = 1.0 + \sum (\text{IndividualUpgradeMultiplier} - 1.0)$$

This design prevents compounding multipliers from making individual upgrades excessively overpowered. The multiplier for a specific upgrade is computed in `calculate_multiplier(level)` based on its level:

* **Linear Progressions (`is_percentage = false`)**:
  $$\text{Multiplier} = 1.0 + (\text{value_increment} \times \text{level} \times \text{internal_level})$$
  *Example*: `value_increment = 0.5`, `internal_level = 1.0`:
  - Level 1 = +0.5 multiplier (150% total)
  - Level 2 = +1.0 multiplier (200% total)

* **Exponential / Compound Progressions (`is_percentage = true`)**:
  $$\text{Multiplier} = (1.0 + \text{value_increment})^{(\text{level} \times \text{internal_level})}$$
  *Example*: `value_increment = 0.2`, `internal_level = 1.0`:
  - Level 1 = +0.2 multiplier (120% total)
  - Level 2 = +0.44 multiplier (144% total)

---

### 2. Suggested Tuning Settings

| Upgrade Category | Sizing / Scale Mode | Sug. Increment (`value_increment`) | Tuning Rationale |
| :--- | :---: | :---: | :--- |
| **Click Damage** (`ClickDamage`) | Compound test | `2.0` (`x3`) | Temporary test tuning: base click damage `3`, each purchased ClickDamage level multiplies total by `3`. |
| **Auto Clicker Rate** (`AutoClickRate`) | Compound (Rec.) | `0.10 - 0.15` | Capped at a minimum click interval of **0.05s** (20 clicks/sec) to protect processing speed. |
| **Click Radius** (`ClickRadius`) | Linear | `0.10 - 0.15` | Keep max levels low (e.g. 5-10) to avoid sweep coverage consuming the entire screen. |
| **Planet Health / Shield** | Compound | `0.20 - 0.30` | High level runs have intense incoming threat damage, requiring compound scaling to keep up. |
| **Exact Quantities** (e.g. `SatelliteAmount`) | **Linear Only** | `1.0` | These values represent exact node counts. Capped at a maximum of 16 satellites. |
| **Satellite Multipliers** (`SatelliteSpeed` / `SatelliteDamage` / `SatelliteProjectileSpeed`) | Linear or Compound | `0.10 - 0.20` | Core satellite stats. Scale linearly or exponentially depending on late-game threat scaling. |
| **Satellite Unlock** (`SatelliteUnlock`) | **Linear Only** | `1.0` | Enables satellite spawning if level > 0. |

---

### 3. Sizing Rules for UI Layout
When designing new items in the upgrade/skill tree:
* **Backgrounds**: The upgrade button slot should have NO background panel showing in its idle/normal state (use `StyleBoxEmpty` on the slot container).
* **Icon Sizing**: The icon inside the slot must be **exactly 25% smaller** than the button size.
  * *Calculation*: `icon_rect.custom_minimum_size = custom_minimum_size * 0.75` (e.g., 60x60 pixels for an 80x80 button).
  * *Alignment*: Use `SIZE_SHRINK_CENTER` for both horizontal and vertical layout flags to keep it centered.
* **Rotation**: Spin animations on buy should apply only to the custom button background (`IconButton` rotates 405 degrees). The `IconRect` containing the `.png` visual must remain completely static.
