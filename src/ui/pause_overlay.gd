# res://src/ui/pause_overlay.gd
extends Control
class_name PauseOverlay

@onready var title_label: Label = $PanelContainer/MarginContainer/VBoxContainer/TitleLabel
@onready var stats_label: Label = $PanelContainer/MarginContainer/VBoxContainer/StatsLabel
@onready var button_container: HBoxContainer = $PanelContainer/MarginContainer/VBoxContainer/ButtonContainer

@onready var skill_tree_button: Button = $PanelContainer/MarginContainer/VBoxContainer/ButtonContainer/SkillTreeButton
@onready var continue_button: Button = $PanelContainer/MarginContainer/VBoxContainer/ButtonContainer/ContinueButton

func _ready() -> void:
	# Hide by default
	visible = false
	
	# Connect to GameManager state changes
	var game_mgr = get_node("/root/GameManager")
	game_mgr.state_changed.connect(_on_state_changed)
	
	# Button signals
	skill_tree_button.pressed.connect(_on_skill_tree_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	
	_on_state_changed(game_mgr.current_state)

func _on_state_changed(state: int) -> void:
	var game_mgr = get_node("/root/GameManager")
	if state == game_mgr.GameState.PAUSED or state == game_mgr.GameState.DEFEAT:
		visible = true
		title_label.text = "Session Finished"
		stats_label.text = "Credits on this session: $%d\nEliminated Threats: %d" % [int(game_mgr.run_credits), game_mgr.eliminated_threats]
		skill_tree_button.visible = true
		continue_button.visible = true
	else:
		visible = false

func _on_skill_tree_pressed() -> void:
	var game_mgr = get_node("/root/GameManager")
	game_mgr.change_state(game_mgr.GameState.UPGRADE_SCREEN)

func _on_continue_pressed() -> void:
	var game_mgr = get_node("/root/GameManager")
	if game_mgr.current_state == game_mgr.GameState.DEFEAT:
		game_mgr.reset_game()
		get_tree().reload_current_scene()
	else:
		game_mgr.start_next_round()
