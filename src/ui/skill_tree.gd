# res://src/ui/skill_tree.gd
extends Control
class_name SkillTree

@onready var balance_label: Label = $MarginContainer/VBoxContainer/Header/BalanceLabel
@onready var close_button: Button = $MarginContainer/VBoxContainer/CloseButton
@onready var grid_container: Control = $MarginContainer/VBoxContainer/ScrollContainer/GridContainer
@onready var scroll_container: ScrollContainer = $MarginContainer/VBoxContainer/ScrollContainer

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
		
		for child_id in slot.upgrade_data.unlocks:
			if slot_map.has(child_id):
				var key = parent_id + "->" + child_id
				if not connection_progress.has(key):
					continue
					
				var progress = connection_progress[key]
				if progress <= 0.0:
					continue
					
				var child_slot = slot_map[child_id]
				var child_center = child_slot.position + child_slot.size / 2.0
				
				# Interpolate line endpoint for filling effect
				var line_end = parent_center.lerp(child_center, progress)
				
				# White line connecting the upgrade to the upgrades it unlocks
				var line_color = Color(1.0, 1.0, 1.0, 0.9)
				var line_width = 3.5
				
				# Draw black outline/shadow first for high contrast contrast
				grid_container.draw_line(parent_center, line_end, Color(0.0, 0.0, 0.0, 0.8), line_width + 2.0, true)
				# Draw foreground colored line
				grid_container.draw_line(parent_center, line_end, line_color, line_width, true)

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
			for child_id in slot.upgrade_data.unlocks:
				if slot_map.has(child_id):
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
	for child_id in parent_slot.upgrade_data.unlocks:
		if slot_map.has(child_id):
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
			# Avoid duplicating animations for the same key
			var exists = false
			for a in active_line_animations:
				if a.key == key:
					exists = true
					break
			if not exists:
				active_line_animations.append(anim)

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
	# Find child slot and trigger bounce animation
	var slots = _find_slots_recursive(self)
	var child_slot: UpgradeSlotUI = null
	for slot in slots:
		if slot.upgrade_data and slot.upgrade_data.upgrade_id == anim.child_id:
			child_slot = slot
			break
			
	if child_slot:
		child_slot.play_bounce_animation()
		
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
	var max_x = 1920.0 # default min fallback
	var max_y = 1080.0
	
	for slot in slots:
		var slot_end_x = slot.position.x + slot.size.x
		var slot_end_y = slot.position.y + slot.size.y
		if slot_end_x > max_x:
			max_x = slot_end_x
		if slot_end_y > max_y:
			max_y = slot_end_y
			
	# Add padding margin so items don't sit right at the edge
	var padding = 200.0
	grid_container.custom_minimum_size = Vector2(max_x + padding, max_y + padding)
