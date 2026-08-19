extends Node
class_name GameBootstrap

## Loads the full level scene selected by the level data asset.
## The level scene contains the planet, spawners, pools, camera, UI, and AllyShips.
func _ready() -> void:
	var game_manager: Node = get_node_or_null("/root/GameManager")
	var config: LevelConfig = null
	if game_manager:
		config = game_manager.get_selected_level_config() as LevelConfig
	if not is_instance_valid(config) or not config.level_scene:
		push_error("Selected level has no level_scene assigned.")
		return

	var level_instance: Node = config.level_scene.instantiate()
	if not level_instance:
		push_error("Could not instantiate selected level scene.")
		return
	add_child(level_instance)
