@tool
class_name LevelConfig
extends Resource

## Data used to describe one playable level.
## One level spawns one actor type in one-second rounds at shared spawn points.

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

## Actor type routed to its pooled master by Spawner.
@export_enum(
	"small_asteroid",
	"medium_asteroid",
	"large_asteroid",
	"enemy",
	"garbage"
) var actor_type: String = "small_asteroid"

## Total actor instances spawned by this level.
@export_range(0, 100000, 1) var total_enemies: int = 10

@export_group("Grid Combat")
## When enabled, this level always starts in grid preparation before the wave.
@export var grid_combat_enabled: bool = false
@export var grid_board_config: GridPrototypeConfig
@export_range(0, 64, 1) var starting_ally_ships: int = 4
@export_range(0, 64, 1) var starting_defense_blocks: int = 3
@export_range(0, 64, 1) var minimum_ally_ships_to_start: int = 1

func get_total_configured_enemies() -> int:
	return maxi(total_enemies, 0)

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
