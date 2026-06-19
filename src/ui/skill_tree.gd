# res://src/ui/skill_tree.gd
extends Control
class_name SkillTree

@onready var balance_label: Label = $MarginContainer/VBoxContainer/Header/RightContainer/BalanceLabel
@onready var close_button: Button = $MarginContainer/VBoxContainer/Header/RightContainer/CloseButton
@onready var grid_container: Control = $MarginContainer/VBoxContainer/ScrollContainer/GridContainer
@onready var scroll_container: ScrollContainer = $MarginContainer/VBoxContainer/ScrollContainer
@onready var options_button: Button = $MarginContainer/VBoxContainer/Header/RightContainer/OptionsButton
@onready var options_panel: VBoxContainer = $MarginContainer/VBoxContainer/OptionsPanel
@onready var volume_slider: HSlider = $MarginContainer/VBoxContainer/OptionsPanel/VolumeSlider
@onready var fullscreen_checkbox: CheckBox = $MarginContainer/VBoxContainer/OptionsPanel/FullscreenCheckbox
@onready var back_button: Button = $MarginContainer/VBoxContainer/OptionsPanel/BackButton

@onready var tooltip_popup: Control = $TooltipPopup
@onready var tooltip_title: Label = $TooltipPopup/Margin/VBox/TooltipTitle
@onready var tooltip_details: Label = $TooltipPopup/Margin/VBox/TooltipDetails
@onready var tooltip_desc: Label = $TooltipPopup/Margin/VBox/TooltipDesc

var active_line_animations: Array = []
var connection_progress: Dictionary = {}

var is_dragging: bool = false
var drag_start_mouse_pos: Vector2 = Vector2.ZERO
var drag_start_scroll_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	visible = false
	if tooltip_popup:
		tooltip_popup.visible = false
	
	# Connect to GameManager state
	var game_mgr = get_node("/root/GameManager")
	game_mgr.state_changed.connect(_on_state_changed)
	
	# Redraw when upgrades are purchased (to update affordability of others)
	get_node("/root/UpgradeManager").upgrade_purchased.connect(_on_upgrade_purchased)
	
	# Close button
	close_button.pressed.connect(_on_close_pressed)
	
	# Connect options actions
	options_button.pressed.connect(_on_options_pressed)
	back_button.pressed.connect(_on_options_back_pressed)
	volume_slider.value_changed.connect(_on_volume_changed)
	fullscreen_checkbox.toggled.connect(_on_fullscreen_toggled)
	_update_options_ui_states()
	
	# Connect to grid container draw for rendering connection lines
	grid_container.draw.connect(_on_grid_container_draw)
	
	# Set scrollable canvas size based on slot positions dynamically
	_update_canvas_size()
	
	# Connect drag panning inputs
	grid_container.gui_input.connect(_on_grid_container_gui_input)
	
	_on_state_changed(game_mgr.current_state)

func _on_state_changed(state: int) -> void:
	var game_mgr = get_node("/root/GameManager")
	if state == game_mgr.GameState.UPGRADE_SCREEN:
		visible = true
		if options_panel:
			options_panel.visible = false
		if scroll_container:
			scroll_container.visible = true
		if options_button:
			options_button.disabled = false
		if close_button:
			close_button.disabled = false
		_update_options_ui_states()
		_initialize_connection_progress()
		_update_balance()
		_populate_slots()
	else:
		visible = false
		hide_tooltip()
		active_line_animations.clear()
		is_dragging = false
		if scroll_container:
			scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
			scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

func _update_balance() -> void:
	balance_label.text = "BANK CREDITS: $" + str(int(get_node("/root/GameManager").lifetime_credits))

func _populate_slots() -> void:
	var upgrade_mgr = get_node("/root/UpgradeManager")
	var slots = _find_slots_recursive(self)
	for slot in slots:
		if slot.upgrade_data:
			# Show only if unlocked/visible
			if upgrade_mgr.is_upgrade_visible(slot.upgrade_data):
				slot.visible = true
				slot._refresh_ui()
			else:
				slot.visible = false
		else:
			# Hide if no upgrade resource is assigned in the inspector
			slot.visible = false
			
	grid_container.queue_redraw()

func _find_slots_recursive(node: Node) -> Array[UpgradeSlotUI]:
	var result: Array[UpgradeSlotUI] = []
	if node is UpgradeSlotUI:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_slots_recursive(child))
	return result

func _on_upgrade_purchased(id: String, _lvl: int) -> void:
	# Refresh balance text immediately
	_update_balance()
	
	# Delay populating slots and starting line animations until the 0.5s slot purchase animation finishes
	var timer = get_tree().create_timer(0.5)
	timer.timeout.connect(func():
		_populate_slots()
		_start_line_animation_from(id)
	)

func _on_close_pressed() -> void:
	# Resumes and moves to the next zone/wave
	get_node("/root/GameManager").start_next_round()

# Called by child slots when mouse enters
func show_tooltip(upgrade: UpgradeData, slot_global_pos: Vector2) -> void:
	if not tooltip_popup:
		return
		
	tooltip_title.text = upgrade.upgrade_name
	tooltip_desc.text = upgrade.description
	
	var current_lvl = get_node("/root/UpgradeManager").get_upgrade_level(upgrade.upgrade_id)
	
	# Cost string
	var cost_text = ""
	if current_lvl >= upgrade.max_level:
		cost_text = "MAXED"
	else:
		cost_text = "$%d" % int(upgrade.get_cost(current_lvl))
		
	# Bonus string
	var val = upgrade.value_increment
	var bonus_text = ""
	if upgrade.is_percentage:
		bonus_text = "+%d%%" % int(val * 100.0)
	else:
		bonus_text = "+%d" % int(val)
		
	tooltip_details.text = "COST: %s | BONUS: %s" % [cost_text, bonus_text]
	
	# Centered positioning above the slot with edge-of-screen boundary clamps
	var screen_size = get_viewport_rect().size
	var target_pos = Vector2(
		slot_global_pos.x + 40 - 125,
		slot_global_pos.y - 120
	)
	target_pos.x = clamp(target_pos.x, 10.0, screen_size.x - 260.0)
	target_pos.y = max(target_pos.y, 10.0)
	
	tooltip_popup.global_position = target_pos
	tooltip_popup.visible = true

# Called by child slots when mouse exits
func hide_tooltip() -> void:
	if tooltip_popup:
		tooltip_popup.visible = false

# Draw connections between prerequisite upgrades and their unlocks
func _get_furthest_children_by_direction(parent_slot: UpgradeSlotUI, slot_map: Dictionary) -> Dictionary:
	var result = {} # cluster_index (String) -> child_id (String)
	var parent_center = parent_slot.position + parent_slot.size / 2.0
	var clusters: Array = [] # Array of Dictionary: { "angle": float, "child_ids": Array }
	
	for child_id in parent_slot.upgrade_data.unlocks:
		if slot_map.has(child_id):
			var child_slot = slot_map[child_id]
			var child_center = child_slot.position + child_slot.size / 2.0
			var diff = child_center - parent_center
			var angle = diff.angle()
			
			# Find if there is an existing cluster within 20 degrees
			var found_cluster = false
			for cluster in clusters:
				var diff_angle = abs(angle_difference(cluster.angle, angle))
				if diff_angle <= deg_to_rad(20.0):
					cluster.child_ids.append(child_id)
					found_cluster = true
					break
			
			if not found_cluster:
				clusters.append({
					"angle": angle,
					"child_ids": [child_id]
				})
				
	# Find furthest child in each cluster
	var cluster_idx = 0
	for cluster in clusters:
		var furthest_child_id = ""
		var max_dist = -1.0
		for child_id in cluster.child_ids:
			var child_slot = slot_map[child_id]
			var child_center = child_slot.position + child_slot.size / 2.0
			var dist = parent_center.distance_to(child_center)
			if dist > max_dist:
				max_dist = dist
				furthest_child_id = child_id
		if not furthest_child_id.is_empty():
			result[str(cluster_idx)] = furthest_child_id
			cluster_idx += 1
				
	return result


func _on_grid_container_draw() -> void:
	var upgrade_mgr = get_node("/root/UpgradeManager")
	var game_mgr = get_node("/root/GameManager")
	
	var slots = _find_slots_recursive(grid_container)
	var slot_map = {}
	for slot in slots:
		if slot.visible and slot.upgrade_data:
			slot_map[slot.upgrade_data.upgrade_id] = slot
			
	for slot in slots:
		if not slot.visible or not slot.upgrade_data:
			continue
			
		var parent_id = slot.upgrade_data.upgrade_id
		var parent_center = slot.position + slot.size / 2.0
		
		# Draw line to the furthest child in each direction
		var furthest_children = _get_furthest_children_by_direction(slot, slot_map)
		for dir in furthest_children:
			var child_id = furthest_children[dir]
			var key = parent_id + "->" + child_id
			if not connection_progress.has(key):
				continue
				
			var progress = connection_progress[key]
			if progress <= 0.0:
				continue
				
			var child_slot = slot_map[child_id]
			var child_center = child_slot.position + child_slot.size / 2.0
			
			var line_start = parent_center
			var line_end = line_start.lerp(child_center, progress)
			
			var line_color = Color(1.0, 1.0, 1.0, 0.9)
			var line_width = 3.5
			
			# Draw black outline/shadow first for high contrast contrast
			grid_container.draw_line(line_start, line_end, Color(0.0, 0.0, 0.0, 0.8), line_width + 2.0, true)
			# Draw foreground colored line
			grid_container.draw_line(line_start, line_end, line_color, line_width, true)

func _add_active_animation(anim: Dictionary) -> void:
	var exists = false
	for a in active_line_animations:
		if a.key == anim.key:
			exists = true
			break
	if not exists:
		active_line_animations.append(anim)

func _initialize_connection_progress() -> void:
	connection_progress.clear()
	var upgrade_mgr = get_node("/root/UpgradeManager")
	var slots = _find_slots_recursive(self)
	var slot_map = {}
	for slot in slots:
		if slot.upgrade_data:
			slot_map[slot.upgrade_data.upgrade_id] = slot
			
	for slot in slots:
		if not slot.upgrade_data:
			continue
		var parent_id = slot.upgrade_data.upgrade_id
		var parent_lvl = upgrade_mgr.get_upgrade_level(parent_id)
		
		# If parent is already purchased on entry, its outgoing lines are fully drawn
		if parent_lvl > 0:
			var furthest_children = _get_furthest_children_by_direction(slot, slot_map)
			for dir in furthest_children:
				var child_id = furthest_children[dir]
				var key = parent_id + "->" + child_id
				connection_progress[key] = 1.0

func _start_line_animation_from(parent_id: String) -> void:
	var upgrade_mgr = get_node("/root/UpgradeManager")
	var slots = _find_slots_recursive(self)
	var slot_map = {}
	for slot in slots:
		if slot.upgrade_data:
			slot_map[slot.upgrade_data.upgrade_id] = slot
			
	if not slot_map.has(parent_id):
		return
		
	var parent_slot = slot_map[parent_id]
	var furthest_children = _get_furthest_children_by_direction(parent_slot, slot_map)
	for dir in furthest_children:
		var child_id = furthest_children[dir]
		var key = parent_id + "->" + child_id
		connection_progress[key] = 0.0
		
		var child_lvl = upgrade_mgr.get_upgrade_level(child_id)
		var trigger_next = child_lvl > 0
		
		var anim = {
			"parent_id": parent_id,
			"child_id": child_id,
			"key": key,
			"progress": 0.0,
			"duration": 0.4,
			"trigger_next_on_finish": trigger_next
		}
		_add_active_animation(anim)

func _process(delta: float) -> void:
	if not visible:
		return
		
	var needs_redraw = false
	var finished_anims = []
	
	for anim in active_line_animations:
		anim.progress = min(anim.progress + delta / anim.duration, 1.0)
		connection_progress[anim.key] = anim.progress
		needs_redraw = true
		if anim.progress >= 1.0:
			finished_anims.append(anim)
			
	for anim in finished_anims:
		active_line_animations.erase(anim)
		_on_line_animation_finished(anim)
		
	if needs_redraw:
		grid_container.queue_redraw()

func _on_line_animation_finished(anim: Dictionary) -> void:
	var slots = _find_slots_recursive(self)
	var slot_map = {}
	for slot in slots:
		if slot.upgrade_data:
			slot_map[slot.upgrade_data.upgrade_id] = slot
			
	var parent_id = anim.parent_id
	if slot_map.has(parent_id):
		var parent_slot = slot_map[parent_id]
		var parent_center = parent_slot.position + parent_slot.size / 2.0
		
		# Find the direction of the animation's target child
		var child_id = anim.child_id
		if slot_map.has(child_id):
			var child_slot = slot_map[child_id]
			var child_center = child_slot.position + child_slot.size / 2.0
			var diff = child_center - parent_center
			var target_angle = diff.angle()
				
			# Bounce all children that are in the same direction (within 20 degrees)!
			for other_id in parent_slot.upgrade_data.unlocks:
				if slot_map.has(other_id):
					var other_slot = slot_map[other_id]
					var other_center = other_slot.position + other_slot.size / 2.0
					var other_diff = other_center - parent_center
					var other_angle = other_diff.angle()
					
					if abs(angle_difference(target_angle, other_angle)) <= deg_to_rad(20.0):
						other_slot.play_bounce_animation()
					
	# If trigger_next is true, start next connection in chain
	if anim.trigger_next_on_finish:
		_start_line_animation_from(anim.child_id)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if is_dragging:
				is_dragging = false
				scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
				scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

func _on_grid_container_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				is_dragging = true
				scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
				scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
				drag_start_mouse_pos = event.global_position
				drag_start_scroll_pos = Vector2(scroll_container.scroll_horizontal, scroll_container.scroll_vertical)
			else:
				if is_dragging:
					is_dragging = false
					scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
					scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
				
	elif event is InputEventMouseMotion:
		if is_dragging:
			var diff = event.global_position - drag_start_mouse_pos
			scroll_container.scroll_horizontal = int(drag_start_scroll_pos.x - diff.x)
			scroll_container.scroll_vertical = int(drag_start_scroll_pos.y - diff.y)

func _update_canvas_size() -> void:
	var slots = _find_slots_recursive(grid_container)
	if slots.is_empty():
		grid_container.custom_minimum_size = Vector2(1920.0, 1080.0)
		return
		
	var min_x = INF
	var min_y = INF
	var max_x = -INF
	var max_y = -INF
	
	for slot in slots:
		if slot.position.x < min_x:
			min_x = slot.position.x
		if slot.position.y < min_y:
			min_y = slot.position.y
		var slot_end_x = slot.position.x + slot.size.x
		var slot_end_y = slot.position.y + slot.size.y
		if slot_end_x > max_x:
			max_x = slot_end_x
		if slot_end_y > max_y:
			max_y = slot_end_y
			
	# Shift slots so the leftmost and topmost slots sit exactly at the padding margin (200px)
	var target_min_x = 200.0
	var target_min_y = 200.0
	var shift_x = target_min_x - min_x
	var shift_y = target_min_y - min_y
	
	for slot in slots:
		slot.position.x += shift_x
		slot.position.y += shift_y
		
	# Recalculate max coordinates after shift
	var new_max_x = max_x + shift_x
	var new_max_y = max_y + shift_y
	
	# Add padding margin so items don't sit right at the right/bottom edge
	var padding = 200.0
	grid_container.custom_minimum_size = Vector2(new_max_x + padding, new_max_y + padding)

func _on_options_pressed() -> void:
	scroll_container.visible = false
	options_panel.visible = true
	options_button.disabled = true
	close_button.disabled = true
	_update_options_ui_states()

func _on_options_back_pressed() -> void:
	scroll_container.visible = true
	options_panel.visible = false
	options_button.disabled = false
	close_button.disabled = false

func _on_volume_changed(val: float) -> void:
	var master_bus_idx = AudioServer.get_bus_index("Master")
	if master_bus_idx != -1:
		if val <= 0.0001:
			AudioServer.set_bus_volume_db(master_bus_idx, -80.0)
		else:
			AudioServer.set_bus_volume_db(master_bus_idx, linear_to_db(val))
	get_node("/root/GameManager").save_game()

func _on_fullscreen_toggled(is_fullscreen: bool) -> void:
	if is_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	get_node("/root/GameManager").save_game()

func _update_options_ui_states() -> void:
	var master_bus_idx = AudioServer.get_bus_index("Master")
	if master_bus_idx != -1:
		var current_vol_db = AudioServer.get_bus_volume_db(master_bus_idx)
		volume_slider.value = db_to_linear(current_vol_db)
		
	var current_mode = DisplayServer.window_get_mode()
	fullscreen_checkbox.button_pressed = (current_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN or current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN)
