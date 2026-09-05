@tool
class_name LevelConfig
extends Resource

## Data used to describe one playable level.
## The mass-enemy path selects archetypes from enemy_roster and schedules one
## batch per spawn_interval_seconds. Legacy actor_type remains temporarily for
## the existing Node-based Spawner.

@export var level_number: int = 1
@export var level_name: String = "Level 1"
@export_multiline var description: String = ""
@export var icon: Texture2D
## Full playable level scene. It is a copy/instance of the first-level world
## and contains the planet, spawners, pools, camera, UI, and AllyShips.
@export var level_scene: PackedScene

@export_group("Level Selection")
## Debug/test maps can remain loadable without appearing in the player-facing selector.
@export var show_in_level_select: bool = true

@export_group("Mass Enemy Spawning")
## Enables the complete data-runtime bridge for this level; legacy remains a fallback.
@export var use_mass_enemies: bool = false
## Authoritative compute simulation when a RenderingDevice is available.
@export var use_gpu_enemy_simulation: bool = true
## Reproduces asteroid HP rolls, zone scaling, hit slowdown and offensive debris.
@export var use_mass_legacy_rules: bool = false
## Bounded hit/credit popups and death effects; does not change gameplay damage.
@export var use_mass_enemy_feedback: bool = false
## Test-only option: enemies still impact/despawn, but their aggregated damage is not applied to the planet.
@export var mass_planet_invulnerable: bool = false
## Radius of the spawn disk. Zero preserves exact SpawnPoint positions.
@export_range(0.0, 2000.0, 1.0) var mass_spawn_spread_radius: float = 0.0
## Bounded soft separation in the authoritative GPU simulation.
@export var mass_gpu_separation: bool = false
@export_range(0.0, 500.0, 1.0) var mass_separation_speed: float = 120.0
@export_range(0.0, 50.0, 0.5) var mass_separation_padding: float = 2.0
## Total spawn commands emitted during the level, not the simultaneous alive cap.
@export_range(0, 100000, 1) var total_enemies: int = 10
## Number emitted by every SpawnPoint during one spawn cycle.
@export_range(1, 10000, 1) var enemies_per_spawn_point: int = 1
## Seconds between spawn cycles.
@export_range(0.01, 3600.0, 0.01) var spawn_interval_seconds: float = 1.0
## Weighted enemy archetypes available to the mass spawner.
@export var enemy_roster: Array[EnemySpawnEntry] = []

@export_group("Legacy Spawner")
## Compatibility only. MassEnemySpawner never reads this property.
@export_enum(
	"small_asteroid",
	"medium_asteroid",
	"large_asteroid",
	"enemy",
	"garbage"
) var actor_type: String = "small_asteroid"

@export_group("Grid Combat")
## When enabled, this level always starts in grid preparation before the wave.
@export var grid_combat_enabled: bool = false
@export var grid_board_config: GridPrototypeConfig
## Optional per-level override for the Defense Blaster unlock. Global upgrade state remains the default.
@export var defense_blasters_unlocked: bool = false
## Number of Defense Blasters available during this level's preparation phase.
@export_range(0, 64, 1) var starting_defense_blasters: int = 4
@export_range(0, 64, 1) var starting_ally_ships: int = 4
@export_range(0, 64, 1) var starting_defense_blocks: int = 3
@export_range(0, 64, 1) var minimum_ally_ships_to_start: int = 1

func get_total_configured_enemies() -> int:
	return maxi(total_enemies, 0)

func get_spawn_commands_per_cycle(spawn_point_count: int) -> int:
	return maxi(spawn_point_count, 0) * maxi(enemies_per_spawn_point, 0)

func get_spawn_commands_per_second(spawn_point_count: int) -> float:
	if not is_finite(spawn_interval_seconds) or spawn_interval_seconds <= 0.0:
		return 0.0
	return float(get_spawn_commands_per_cycle(spawn_point_count)) / spawn_interval_seconds

func get_mass_spawn_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	for field in ["mass_spawn_spread_radius", "mass_separation_speed", "mass_separation_padding"]:
		if not is_finite(float(get(field))) or float(get(field)) < 0:
			errors.append("%s must be finite and nonnegative." % field)
	if total_enemies < 0:
		errors.append("total_enemies cannot be negative.")
	if enemies_per_spawn_point <= 0:
		errors.append("enemies_per_spawn_point must be greater than zero.")
	if not is_finite(spawn_interval_seconds) or spawn_interval_seconds <= 0.0:
		errors.append("spawn_interval_seconds must be finite and greater than zero.")
	if enemy_roster.is_empty():
		errors.append("enemy_roster cannot be empty.")
	else:
		for roster_error in EnemySpawnEntry.validate_roster(enemy_roster):
			errors.append(roster_error)
		var weight_sum: float = 0.0
		for entry in enemy_roster:
			if entry != null:
				weight_sum += entry.spawn_weight
		if not is_finite(weight_sum):
			errors.append("Sum of spawn weights must be finite.")
	return errors

func is_mass_spawn_config_valid() -> bool:
	return get_mass_spawn_validation_errors().is_empty()

func requires_preparation() -> bool:
	return grid_combat_enabled

func get_actor_display_name() -> String:
	match actor_type:
		"small_asteroid":
			return "Small Asteroids"
		"medium_asteroid":
			return "Medium Asteroids"
		"large_asteroid":
			return "Large Asteroids"
		"enemy":
			return "Enemy Ships"
		"garbage":
			return "Space Garbage"
	return actor_type.replace("_", " ").capitalize()
