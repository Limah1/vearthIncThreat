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

func get_total_configured_enemies() -> int:
	return maxi(total_enemies, 0)

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
