# res://src/main/main.gd
extends Node3D

@onready var camera: Camera3D = $CameraController
@onready var world_2d: Node2D = $World2D
@onready var world_3d: Node3D = $World3D

# UI Nodes
@onready var hud: Control = $CanvasLayer/HUD
@onready var pause_overlay: Control = $CanvasLayer/PauseOverlay
@onready var skill_tree: Control = $CanvasLayer/SkillTree

var wave_active: bool = false

func _ready() -> void:
	# Trigger camera animation or start spawning directly
	var game_mgr = get_node("/root/GameManager")
	if game_mgr.b_can_animate_camera:
		game_mgr.trigger_camera_animation.emit()
		game_mgr.b_can_animate_camera = false
	else:
		var spawners = get_tree().get_nodes_in_group("spawner")
		for spawner in spawners:
			if spawner.has_method("start_spawning"):
				spawner.start_spawning()

func _process(_delta: float) -> void:
	var game_mgr = get_node("/root/GameManager")
	if game_mgr.current_state == game_mgr.GameState.PLAYING:
		var active_targets = GameManager._active_damageable.size()
		if not wave_active:
			if active_targets > 5:
				wave_active = true
		else:
			if active_targets <= 5:
				wave_active = false
				
				# Trigger spawners to start next wave immediately
				var spawners = get_tree().get_nodes_in_group("spawner")
				for spawner in spawners:
					if spawner.has_method("start_spawning"):
						spawner.start_spawning()
