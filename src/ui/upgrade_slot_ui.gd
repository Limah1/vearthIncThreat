@tool
extends PanelContainer
class_name UpgradeSlotUI

@export var upgrade_data: UpgradeData:
	set(value):
		upgrade_data = value
		if Engine.is_editor_hint():
			_update_editor_icon()

@onready var icon_button: Button = $IconButton
@onready var placeholder_rect: ColorRect = $IconButton/PlaceholderRect
@onready var icon_rect: TextureRect = $IconButton/IconRect
@onready var lvl_indicator: Label = $IconButton/LvlIndicator

var is_newly_unlocked: bool = false
var glow_rotation: float = 0.0

func _ready() -> void:
	if Engine.is_editor_hint():
		_update_editor_icon()
		return
		
	# Connect local button signals
	if not icon_button.pressed.is_connected(_on_buy_pressed):
		icon_button.pressed.connect(_on_buy_pressed)
		
	# Connect mouse entered/exited for floating tooltip
	if not icon_button.mouse_entered.is_connected(_on_mouse_entered):
		icon_button.mouse_entered.connect(_on_mouse_entered)
	if not icon_button.mouse_exited.is_connected(_on_mouse_exited):
		icon_button.mouse_exited.connect(_on_mouse_exited)
		
	if upgrade_data:
		setup(upgrade_data)

func _update_icon_node(rect: TextureRect, placeholder: ColorRect) -> void:
	if upgrade_data:
		if upgrade_data.icon:
			rect.texture = upgrade_data.icon
			rect.visible = true
			placeholder.visible = false
		else:
			var hash_val = upgrade_data.upgrade_id.hash()
			var r = (hash_val & 0xFF0000) >> 16
			var g = (hash_val & 0x00FF00) >> 8
			var b = (hash_val & 0x0000FF)
			placeholder.color = Color(r / 255.0, g / 255.0, b / 255.0)
			placeholder.visible = true
			rect.visible = false
	else:
		rect.texture = null
		rect.visible = false
		placeholder.color = Color(0.15, 0.15, 0.18, 1.0)
		placeholder.visible = true

func _update_editor_icon() -> void:
	# Safely access nodes in the editor before _ready is called
	var rect = get_node_or_null("IconButton/IconRect") as TextureRect
	var placeholder = get_node_or_null("IconButton/PlaceholderRect") as ColorRect
	if rect and placeholder:
		_update_icon_node(rect, placeholder)

func setup(data: UpgradeData) -> void:
	upgrade_data = data
	_refresh_ui()

func _refresh_ui() -> void:
	if not upgrade_data:
		return
		
	_update_icon_node(icon_rect, placeholder_rect)
		
	var current_lvl = get_node("/root/UpgradeManager").get_upgrade_level(upgrade_data.upgrade_id)
	
	# Level indicator (checkmark for purchased/MAXed)
	if current_lvl >= upgrade_data.max_level:
		lvl_indicator.visible = true
		rotation_degrees = 45.0
	else:
		lvl_indicator.visible = false
		rotation_degrees = 0.0
		
	# Visual modulation based on lock state and affordability
	var upgrade_mgr = get_node("/root/UpgradeManager")
	var prerequisites_met = upgrade_mgr.can_unlock_upgrade(upgrade_data) or current_lvl > 0
	
	if not prerequisites_met:
		modulate = Color(0.3, 0.3, 0.3, 1.0) # Locked
	else:
		var cost = upgrade_data.get_cost(current_lvl)
		var can_afford = get_node("/root/GameManager").lifetime_credits >= cost or current_lvl >= upgrade_data.max_level
		if not can_afford:
			modulate = Color(0.6, 0.6, 0.6, 1.0) # Cannot afford
		else:
			modulate = Color(1.0, 1.0, 1.0, 1.0) # Unlocked and affordable

func _on_buy_pressed() -> void:
	var upgrade_mgr = get_node("/root/UpgradeManager")
	var current_lvl = upgrade_mgr.get_upgrade_level(upgrade_data.upgrade_id)
	if current_lvl >= upgrade_data.max_level:
		return # Already purchased
		
	if upgrade_mgr.purchase_upgrade(upgrade_data):
		_refresh_ui()
		# Reset rotation to 0 before animating to a full spin + 45 degrees (405 degrees total)
		rotation_degrees = 0.0
		pivot_offset = size / 2.0
		var rotate_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		rotate_tween.tween_property(self, "rotation_degrees", 405.0, 0.5)
		
		# Update tooltip if we are still hovering it
		_on_mouse_entered()

func _on_mouse_entered() -> void:
	if Engine.is_editor_hint():
		return
		
	# Disable new glow indicator
	is_newly_unlocked = false
	queue_redraw()
		
	# Scale up to 1.5x on hover
	pivot_offset = size / 2.0
	var scale_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	scale_tween.tween_property(self, "scale", Vector2(1.5, 1.5), 0.2)
	
	var skill_tree = get_tree().current_scene.find_child("SkillTree", true, false)
	if skill_tree and skill_tree.has_method("show_tooltip") and upgrade_data:
		skill_tree.show_tooltip(upgrade_data, global_position)

func _on_mouse_exited() -> void:
	if Engine.is_editor_hint():
		return
		
	# Scale back down to 1.0x on hover leave
	pivot_offset = size / 2.0
	var scale_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	scale_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.2)
	
	var skill_tree = get_tree().current_scene.find_child("SkillTree", true, false)
	if skill_tree and skill_tree.has_method("hide_tooltip"):
		skill_tree.hide_tooltip()

func play_bounce_animation() -> void:
	if Engine.is_editor_hint():
		return
	is_newly_unlocked = true
	pivot_offset = size / 2.0
	var scale_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	scale_tween.tween_property(self, "scale", Vector2(1.5, 1.5), 0.2)
	scale_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.2)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if is_newly_unlocked:
		glow_rotation += delta * 2.5
		queue_redraw()

func _draw() -> void:
	if Engine.is_editor_hint() or not is_newly_unlocked:
		return
		
	var center = size / 2.0
	var pulse = 1.0 + 0.05 * sin(Time.get_ticks_msec() * 0.006)
	var radius = 54.0 * pulse
	var color = Color(0.0, 0.8, 1.0, 0.9) # Cyan glow
	var width = 2.5
	var point_count = 32
	
	# Draw 3 arcs forming a dashed circle
	for i in range(3):
		var start_angle = glow_rotation + i * (2.0 * PI / 3.0)
		var end_angle = start_angle + (PI / 3.0) # 60 degree arcs
		
		# Draw dark outline/shadow first
		draw_arc(center, radius, start_angle, end_angle, point_count, Color(0.0, 0.0, 0.0, 0.8), width + 2.0, true)
		# Draw bright front arc
		draw_arc(center, radius, start_angle, end_angle, point_count, color, width, true)
