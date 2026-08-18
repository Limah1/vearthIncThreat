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
	# Disable shadow casting on every current 3D geometry, including imported meshes.
	# Deferred call includes visuals created by PlayerPlanet and PlayerCursor in _ready().
	call_deferred("_disable_all_shadows")

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

func _disable_all_shadows() -> void:
	_disable_shadows_recursive(self)

func _disable_shadows_recursive(node: Node) -> void:
	if node is GeometryInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	for child in node.get_children():
		_disable_shadows_recursive(child)

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
