extends Node

## F6 entry point using the production level and normal preparation UI.
@export var level_config: LevelConfig = preload("res://src/prototypes/mass_enemies/MassEnemyPlayable5000Config.tres")


func _ready() -> void:
	GameManager.selected_level_config = level_config
	GameManager.selected_level_config_path = level_config.resource_path
	GameManager.current_zone = level_config.level_number
	GameManager.run_credits = 0
	GameManager.eliminated_threats = 0
	GameManager.current_level_completed = false
	GameManager.change_state(GameManager.GameState.PREPARATION, false)
	add_child(level_config.level_scene.instantiate())
