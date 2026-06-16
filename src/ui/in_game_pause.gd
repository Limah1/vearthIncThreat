# res://src/ui/in_game_pause.gd
extends Control
class_name InGamePause

@onready var pause_panel: VBoxContainer = $PanelContainer/MarginContainer/PausePanel
@onready var options_panel: VBoxContainer = $PanelContainer/MarginContainer/OptionsPanel

@onready var resume_button: Button = $PanelContainer/MarginContainer/PausePanel/ResumeButton
@onready var options_button: Button = $PanelContainer/MarginContainer/PausePanel/OptionsButton
@onready var quit_button: Button = $PanelContainer/MarginContainer/PausePanel/QuitButton

@onready var volume_slider: HSlider = $PanelContainer/MarginContainer/OptionsPanel/VolumeSlider
@onready var fullscreen_checkbox: CheckBox = $PanelContainer/MarginContainer/OptionsPanel/FullscreenCheckbox
@onready var back_button: Button = $PanelContainer/MarginContainer/OptionsPanel/BackButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	pause_panel.visible = true
	options_panel.visible = false
	
	# Connect buttons
	resume_button.pressed.connect(_resume_game)
	options_button.pressed.connect(_show_options)
	quit_button.pressed.connect(_quit_game)
	back_button.pressed.connect(_show_pause_menu)
	
	# Connect settings inputs
	volume_slider.value_changed.connect(_on_volume_changed)
	fullscreen_checkbox.toggled.connect(_on_fullscreen_toggled)
	
	# Initialize slider/checkbox states
	var master_bus_idx = AudioServer.get_bus_index("Master")
	if master_bus_idx != -1:
		var current_vol_db = AudioServer.get_bus_volume_db(master_bus_idx)
		volume_slider.value = db_to_linear(current_vol_db)
		
	var current_mode = DisplayServer.window_get_mode()
	fullscreen_checkbox.button_pressed = (current_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN or current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and not event.echo:
		if GameManager.current_state == GameManager.GameState.PLAYING:
			get_viewport().set_input_as_handled()
			if visible:
				_resume_game()
			else:
				_pause_game()

func _pause_game() -> void:
	visible = true
	_show_pause_menu()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _resume_game() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func _show_options() -> void:
	pause_panel.visible = false
	options_panel.visible = true

func _show_pause_menu() -> void:
	pause_panel.visible = true
	options_panel.visible = false

func _on_volume_changed(val: float) -> void:
	var master_bus_idx = AudioServer.get_bus_index("Master")
	if master_bus_idx != -1:
		if val <= 0.0001:
			AudioServer.set_bus_volume_db(master_bus_idx, -80.0)
		else:
			AudioServer.set_bus_volume_db(master_bus_idx, linear_to_db(val))

func _on_fullscreen_toggled(is_fullscreen: bool) -> void:
	if is_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _quit_game() -> void:
	GameManager.save_game()
	get_tree().quit()
