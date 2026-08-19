# res://src/main/main.gd
extends Node3D

@onready var camera: Camera3D = $CameraController
@onready var world_2d: Node2D = $World2D
@onready var world_3d: Node3D = $World3D

# UI Nodes
@onready var hud: Control = $CanvasLayer/HUD
@onready var pause_overlay: Control = $CanvasLayer/PauseOverlay
@onready var skill_tree: Control = $CanvasLayer/SkillTree

func _ready() -> void:
	# Disable shadow casting on every current 3D geometry, including imported meshes.
	# Deferred call includes visuals created by PlayerPlanet and PlayerCursor in _ready().
	call_deferred("_disable_all_shadows")

	# The bootstrap scene loads the selected full level scene before this node
	# enters the tree. Configure its spawners before any wave starts.
	var game_mgr = get_node("/root/GameManager")
	var selected_level = game_mgr.get_selected_level_config()
	var spawners = get_tree().get_nodes_in_group("spawner")
	for spawner in spawners:
		if selected_level and spawner.has_method("set_level_config"):
			spawner.set_level_config(selected_level)

	if game_mgr.b_can_animate_camera:
		game_mgr.trigger_camera_animation.emit()
		game_mgr.b_can_animate_camera = false
	elif game_mgr.current_state == game_mgr.GameState.PLAYING:
		for spawner in spawners:
			if selected_level and spawner.has_method("start_level"):
				spawner.start_level(selected_level)
			elif spawner.has_method("start_spawning"):
				spawner.start_spawning()

func _disable_all_shadows() -> void:
	var scene_root: Node = self
	var tree: SceneTree = get_tree()
	if tree and tree.current_scene:
		scene_root = tree.current_scene
	_disable_shadows_recursive(scene_root)

func _disable_shadows_recursive(node: Node) -> void:
	if node is GeometryInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	for child in node.get_children():
		_disable_shadows_recursive(child)
