# res://src/ui/hud.gd
extends Control
class_name HUD

@onready var credits_label: Label = $MarginContainer/VBoxContainer/BottomRow/BarsContainer/CreditsLabel
@onready var fps_label: Label = $FPSLabel
@onready var spawn_label: Label = $SpawnLabel

@onready var hp_bar: ProgressBar = $MarginContainer/VBoxContainer/BottomRow/BarsContainer/HPBar
@onready var shield_bar: ProgressBar = $MarginContainer/VBoxContainer/BottomRow/BarsContainer/ShieldBar

var planet: PlayerPlanet
var spawner: Spawner

func _ready() -> void:
	# Connect GameManager signals
	var game_mgr = get_node("/root/GameManager")
	game_mgr.credits_changed.connect(_on_credits_changed)
	
	# Initial UI state
	_on_credits_changed(game_mgr.run_credits, game_mgr.lifetime_credits)
	
	# Find player planet
	planet = get_tree().current_scene.find_child("PlayerPlanet", true, false) as PlayerPlanet
	spawner = get_tree().get_first_node_in_group("spawner") as Spawner

func _process(_delta: float) -> void:
	# Update FPS
	if is_instance_valid(fps_label):
		fps_label.text = "FPS: " + str(Engine.get_frames_per_second())
	if is_instance_valid(spawn_label):
		if not is_instance_valid(spawner):
			spawner = get_tree().get_first_node_in_group("spawner") as Spawner
		if is_instance_valid(spawner):
			var game_mgr = get_node("/root/GameManager")
			var total: int = spawner.get_spawn_total()
			if game_mgr.is_current_level_complete():
				spawn_label.text = "LEVEL COMPLETE — ELIMINATED: %d/%d" % [
					game_mgr.eliminated_threats,
					total
				]
			else:
				spawn_label.text = "SPAWNED: %d/%d | ELIMINATED: %d/%d" % [
					spawner.get_spawned_actor_count(),
					total,
					game_mgr.eliminated_threats,
					total
				]

	# Periodically update planet health and shield bars
	if planet and is_instance_valid(planet):
		hp_bar.max_value = planet.max_hp
		hp_bar.value = planet.hp
		hp_bar.get_node("Label").text = "HP: %d/%d" % [int(planet.hp), int(planet.max_hp)]

		shield_bar.max_value = planet.max_shield
		shield_bar.value = planet.shield
		shield_bar.get_node("Label").text = "SHIELD: %d/%d" % [int(planet.shield), int(planet.max_shield)]
		shield_bar.visible = planet.max_shield > 0.0
	else:
		# Search again if it was added late
		planet = get_tree().current_scene.find_child("PlayerPlanet", true, false) as PlayerPlanet

func _on_credits_changed(run_credits: float, _lifetime_credits: float) -> void:
	credits_label.text = "CREDITS: $" + str(int(run_credits))
