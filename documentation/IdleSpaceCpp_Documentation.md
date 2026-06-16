# IdleSpaceCpp - Core Architecture & Documentation

This document outlines the core classes, subsystems, and key gameplay mechanics within the **IdleSpaceCpp** project.

---

## 1. Core Systems & Subsystems (Managers)

### `UUpgradeManagerSubsystem`
* **Functionality**: The brain behind progression. It reads upgrade configuration from Data Assets (`UDAUpgrades`), manages unlocked/purchased nodes in a skill tree, and calculates final multipliers dynamically.
* **Key Mechanisms**:
  - **Tree Unlocks**: Automatically unlocks child upgrades in the skill tree (adding them to `UnlockedCategories`) when their prerequisites are purchased.
  - **Level Registration**: Default-unlocked nodes register at **Level 1** (so base stats apply immediately), while locked nodes start at **Level 0** (contributing nothing until unlocked).
  - **Multiplier Accumulation**: Calculates final multipliers using a category-based sum of relative bonuses:
    $$\text{FinalMultiplier} = 1.0f + \sum (\text{UpgradeValue} - 1.0f)$$
    This ensures multiple upgrades in the same category stack additively rather than compounding each other directly.
  - **Special Behaviors**: Specifically tracks `DebrisChance` level 1 unlock to guarantee the next debris spawn (`bNextDebrisSpawnGuaranteed`).

### `UGameManagerSubsystem`
* **Functionality**: Controls the global match states (`Playing`, `Paused`, `UpgradeScreen`, `SessionEnd`, `Defeat`, `Victory`) and tracks the currency earned specifically in the current run (Session Currency).
* **Zone & Camera Transition System**:
  - Subscribes to upgrade purchases. When upgrades under `CameraAnimTriggerCategories` (`GarbageAmount`, `ThreatAmount`) are bought, it sets `bCanAnimateCamera = true`.
  - When returning from the shop/menus to the `Playing` state, if `bCanAnimateCamera` is active, it runs `PlayCameraFlyToNewZone()`.
  - This launches a smooth `FTSTicker` that interpolates the camera height upwards by `CameraAnimHeightStep` (`800.f` units) over `CameraAnimDuration` (`3.0s`).
  - Spawners are paused during this transition and only activate (`StartSpawning()` and `SpawnSpaceGarbage()`) once the fly-to-zone animation finishes.

### `UObjectPoolSubsystem`
* **Functionality**: Memory optimization. Instead of constantly using `SpawnActor` and `Destroy`, it pre-spawns entities (garbage, enemies, debris, projectiles) and recycles them using borrowing/returning logic.
* **Key Functions**:
  - `BorrowFromPool(TSubclassOf<AActor> ActorClass, FTransform SpawnTransform)`: Retrieves an available actor from the inactive pool, moves it to the target location, and activates it.
  - `ReturnToPool(AActor* Actor)`: Resets the actor's state and hides it for future reuse.

### `USpatialGridSubsystem`
* **Functionality**: Performance-oriented spatial grid that registers moving actors into discrete buckets, allowing extremely fast proximity queries (e.g. debris searching for nearby enemies) without calling expensive physics traces.

### `UDSDGameInstance`
* **Functionality**: Global persistent state throughout the entire game session, persisting across level transitions. It maintains the player's lifetime currency bank.

---

## 2. Player & Input Architecture

### `ADSDPlayerController`
* **Functionality**: The bridge between the player and the gameplay field. It handles HUD display, mouse cursor positioning, auto-clicking timers, and physical clicks.
* **Key Mechanisms**:
  - **3D Sweep Cylinder Clicks (`HandleClickMath`)**:
    Instead of simple raycasting, it converts screen clicks to a world position and direction, then sweeps a perfect 3D cylinder along the perspective ray via `UKismetSystemLibrary::SphereTraceMultiForObjects` (calibrated using `ScreenToWorldScale`).
    It collects all overlapping clickable actors (Garbage, Enemies) and processes their clicks without duplicate hits using a `TSet<AActor*>`.
  - **Auto-Clicker**:
    Runs an automated clicking loop controlled by a timer. The click frequency is dynamically scaled:
    $$\text{FinalAutoClickInterval} = \frac{\text{BaseAutoClickRate}}{\text{AutoClickRateMultiplier}}$$
    It is safely capped at a minimum interval of **0.05s** (20 clicks per second) to prevent game crashes.
  - **Cursor UI Syncing**:
    Constantly updates the custom screenspace mouse cursor widget and translates the physical `ClickRadius` into visual pixel bounds.

---

## 3. Gameplay Actors & Entities

### `ASpawner`
* **Functionality**: Drives the game loop and difficulty waves. It orchestrates enemy waves and asteroid/garbage resource drops.
* **Enemy Wave Spawning**:
  - Generates waves of ships from 8 directional bounds using `SpawnFromSide()`.
  - The wave frequency scales dynamically: $\text{SideSwitchInterval} = \frac{\text{BaseSideSwitchInterval}}{\text{SpawnRateMultiplier}}$, capped at a minimum of **0.2s**.
  - Uses weighted selection tables (`EnemySpawnTable`) where enemies can have specific C++ unlock categories (requires level > 0 to spawn) and chance categories (increases weight per upgrade level).
* **Space Garbage Orbit Spawning**:
  - Dictates orbital resource waves. The total count scales via `BaseGarbageAmount + (GarbageAmountMultiplier - 1.0f)`.
  - Spawns in **two stages**:
    1. *Wave 1 (Immediate)*: Spawns exactly one piece of garbage per orbital spawn point immediately (up to the required wave count).
    2. *Wave 2 (Delayed)*: If the total amount exceeds spawn point count, it spawns the remaining pieces after a `2.0s` delay.
  - Features premium garbage spawning: every spawn rolls against `CurrentPremiumChance` (from the `GarbageQuality` upgrade) to substitute normal garbage with premium garbage.
  - Listens to `OnGarbageDestroyed` delegates. When the active count hits 0, it automatically triggers a new wave.

### `ASpaceGarbage` (Inherits from `AResources`)
* **Functionality**: The central resource node of the game. It spawns in orbit and travels in a direct linear trajectory towards the planet.
* **Key Behaviors**:
  - **Massify Integration**: If the `Massify` upgrade category level is $>0$, the garbage's health, monetary value, and planet collision damage are instantly doubled.
  - **Damage Slowdown**: When hit, its speed is halved (`MoveSpeed * 0.5f`) for `0.8s` to give the player more time to destroy it.
  - **Collisions & Overlaps**:
    - *Flocking/Soft Separation*: Nudges itself away from neighboring garbage nodes on overlap to prevent ugly stacking.
    - *Asteroid/Enemy Projectiles*: If struck by hostile projectiles or an asteroid, it is destroyed **without granting any currency** to the player.
    - *Planet/Shield Overlap*: If it reaches the planet or its shield, it inflicts damage equal to its base data asset value (scaled by Massify if active) and recycles itself.
    - *Player Clicks/Projectiles*: Grants currency and triggers debris burst upon player-inflicted death.

### `ADebrisProjectile`
* **Functionality**: Formed from destroyed space garbage. Sweeps linearly through space, scanning `USpatialGridSubsystem` to damage any enemies or resources in its path. Scales its bounces, damage, and lifetime directly from debris upgrades.

### `AAPlayerPlanet`
* **Functionality**: Positioned at the center of the world. Manages global player health and shields, applying upgrade modifiers dynamically and syncing HP bars to prevent visual HUD errors.

---

## 4. Configuration & Math Definition

### `UDAUpgrades` (Data Asset)
* **Structure**: A blueprint-configurable asset containing metadata (Name, Description, Icon), prerequisite unlocks, base cost, max purchases, internal step level (`InternalLevel`), and increment values (`ValueIncrement`).
* **Cost Logic**: Costs are currently evaluated as fixed flat amounts (`BaseCost`).
* **Multiplier formulas**:
  Given level $L$, increment rate $r$, and internal step size $I$, the effective level is $N = L \times I$:
  - **Linear Progression (`bIsPercentage = false`)**:
    $$\text{Multiplier} = 1.0f + (r \times N)$$
  - **Exponential/Percentage Compound Progression (`bIsPercentage = true`)**:
    $$\text{Multiplier} = (1.0f + r)^{N}$$
