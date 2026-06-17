# res://src/ui/debug_menu.gd
extends Control

@onready var upgrades_list: VBoxContainer = %UpgradesList
@onready var credits_label: Label = %CreditsLabel
@onready var zone_label: Label = %ZoneLabel

@onready var add_1k_button: Button = %Add1kButton
@onready var add_10k_button: Button = %Add10kButton
@onready var add_100k_button: Button = %Add100kButton
@onready var reset_credits_button: Button = %ResetCreditsButton

@onready var add_zone_button: Button = %AddZoneButton
@onready var sub_zone_button: Button = %SubZoneButton
@onready var reload_zone_button: Button = %ReloadZoneButton

@onready var max_all_button: Button = %MaxAllButton
@onready var reset_all_button: Button = %ResetAllButton
@onready var close_button: Button = %CloseButton

var previous_pause_state: bool = false
var upgrade_ui_elements: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	
	# Connect status controls
	add_1k_button.pressed.connect(func(): _add_credits(1000.0))
	add_10k_button.pressed.connect(func(): _add_credits(10000.0))
	add_100k_button.pressed.connect(func(): _add_credits(100000.0))
	reset_credits_button.pressed.connect(_reset_credits)
	
	add_zone_button.pressed.connect(func(): _change_zone(1))
	sub_zone_button.pressed.connect(func(): _change_zone(-1))
	reload_zone_button.pressed.connect(_reload_zone)
	add_zone_button.get_parent().visible = false
	
	max_all_button.pressed.connect(_max_all)
	reset_all_button.pressed.connect(_reset_all)
	close_button.pressed.connect(toggle_menu)
	
	# Populate dynamically
	_populate_upgrades()
	_update_status()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F12 and not event.echo:
		get_viewport().set_input_as_handled()
		toggle_menu()

func toggle_menu() -> void:
	visible = !visible
	if visible:
		previous_pause_state = get_tree().paused
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_update_status()
		_refresh_upgrade_list()
	else:
		get_tree().paused = previous_pause_state
		if GameManager.current_state == GameManager.GameState.PLAYING and not get_tree().paused:
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func _update_status() -> void:
	credits_label.text = "Credits: $%d" % int(GameManager.lifetime_credits)
	var sat_count = get_tree().get_nodes_in_group("satellites").size()
	zone_label.text = "Satellites: %d" % sat_count

func _populate_upgrades() -> void:
	for child in upgrades_list.get_children():
		child.queue_free()
		
	upgrade_ui_elements.clear()
	
	for upgrade in UpgradeManager.upgrades_list:
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 10)
		
		var label = Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		upgrade_ui_elements[upgrade.upgrade_id] = label
		
		var btn_sub = Button.new()
		btn_sub.text = "-"
		btn_sub.custom_minimum_size = Vector2(40, 30)
		btn_sub.pressed.connect(func(): _change_level(upgrade, -1))
		row.add_child(btn_sub)
		
		var btn_add = Button.new()
		btn_add.text = "+"
		btn_add.custom_minimum_size = Vector2(40, 30)
		btn_add.pressed.connect(func(): _change_level(upgrade, 1))
		row.add_child(btn_add)
		
		upgrades_list.add_child(row)

func _refresh_upgrade_list() -> void:
	for upgrade in UpgradeManager.upgrades_list:
		var label = upgrade_ui_elements.get(upgrade.upgrade_id)
		if label:
			var current_lvl = UpgradeManager.get_upgrade_level(upgrade.upgrade_id)
			label.text = "%s: %d/%d" % [upgrade.upgrade_name, current_lvl, upgrade.max_level]

func _change_level(upgrade: UpgradeData, diff: int) -> void:
	var current_lvl = UpgradeManager.get_upgrade_level(upgrade.upgrade_id)
	var new_lvl = clamp(current_lvl + diff, 0, upgrade.max_level)
	if new_lvl != current_lvl:
		UpgradeManager.purchased_levels[upgrade.upgrade_id] = new_lvl
		UpgradeManager.upgrade_purchased.emit(upgrade.upgrade_id, new_lvl)
		GameManager.save_game()
		_update_status()
		_refresh_upgrade_list()

func _max_all() -> void:
	for upgrade in UpgradeManager.upgrades_list:
		UpgradeManager.purchased_levels[upgrade.upgrade_id] = upgrade.max_level
		UpgradeManager.upgrade_purchased.emit(upgrade.upgrade_id, upgrade.max_level)
	GameManager.save_game()
	_update_status()
	_refresh_upgrade_list()

func _reset_all() -> void:
	for upgrade in UpgradeManager.upgrades_list:
		UpgradeManager.purchased_levels[upgrade.upgrade_id] = 0
		UpgradeManager.upgrade_purchased.emit(upgrade.upgrade_id, 0)
	GameManager.save_game()
	_update_status()
	_refresh_upgrade_list()

func _add_credits(amount: float) -> void:
	GameManager.lifetime_credits += amount
	GameManager.credits_changed.emit(GameManager.run_credits, GameManager.lifetime_credits)
	GameManager.save_game()
	_update_status()

func _reset_credits() -> void:
	GameManager.lifetime_credits = 0.0
	GameManager.credits_changed.emit(GameManager.run_credits, GameManager.lifetime_credits)
	GameManager.save_game()
	_update_status()

func _change_zone(diff: int) -> void:
	GameManager.current_zone = max(1, GameManager.current_zone + diff)
	GameManager.save_game()
	_update_status()

func _reload_zone() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
	visible = false
