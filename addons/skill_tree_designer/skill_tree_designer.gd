@tool
extends VBoxContainer

const CONFIG_PATH := "res://src/resources/skill_trees/MainSkillTreeConfig.tres"
const UPGRADE_DIRECTORY := "res://src/resources/upgrades"
const CANVAS_SCRIPT := preload("res://addons/skill_tree_designer/skill_tree_designer_canvas.gd")

enum InteractionMode {
	NORMAL,
	CONNECT,
	MOVE,
}

var tree_config: SkillTreeConfig
var selected_node: SkillTreeNodeData
var pending_grid_position: Vector2i
var interaction_mode: InteractionMode = InteractionMode.NORMAL
var is_dirty: bool = false

var canvas: SkillTreeDesignerCanvas
var status_label: Label
var selected_label: Label
var prerequisites_label: RichTextLabel
var columns_spin: SpinBox
var rows_spin: SpinBox
var requirement_option: OptionButton
var connect_button: Button
var move_button: Button
var remove_button: Button

var picker_popup: PopupPanel
var picker_search: LineEdit
var picker_category: OptionButton
var picker_only_unplaced: CheckBox
var picker_list: ItemList
var picker_place_button: Button
var picker_selected_upgrade: UpgradeData
var available_upgrades: Array[UpgradeData] = []
var validation_dialog: AcceptDialog

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_interface()
	call_deferred("_load_config")

func _build_interface() -> void:
	var title := Label.new()
	title.text = "SKILL TREE DESIGNER — MANUAL GRID"
	title.add_theme_font_size_override("font_size", 22)
	add_child(title)

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	add_child(toolbar)

	var config_label := Label.new()
	config_label.text = CONFIG_PATH
	config_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(config_label)

	toolbar.add_child(_make_label("Columns"))
	columns_spin = SpinBox.new()
	columns_spin.min_value = 1
	columns_spin.max_value = 64
	columns_spin.custom_minimum_size.x = 72.0
	toolbar.add_child(columns_spin)

	toolbar.add_child(_make_label("Rows"))
	rows_spin = SpinBox.new()
	rows_spin.min_value = 1
	rows_spin.max_value = 64
	rows_spin.custom_minimum_size.x = 72.0
	toolbar.add_child(rows_spin)

	var resize_button := _make_button("Apply Grid", _apply_grid_size)
	toolbar.add_child(resize_button)
	toolbar.add_child(_make_button("Reload", _load_config))
	toolbar.add_child(_make_button("Validate", _validate_config))
	toolbar.add_child(_make_button("Save", _save_config))

	status_label = Label.new()
	status_label.text = "Loading skill tree config..."
	status_label.add_theme_color_override("font_color", Color(0.65, 0.8, 1.0))
	add_child(status_label)

	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = -310
	add_child(split)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	split.add_child(scroll)

	canvas = CANVAS_SCRIPT.new() as SkillTreeDesignerCanvas
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.empty_cell_pressed.connect(_on_empty_cell_pressed)
	canvas.node_pressed.connect(_on_node_pressed)
	scroll.add_child(canvas)

	var side_panel := VBoxContainer.new()
	side_panel.custom_minimum_size.x = 300.0
	side_panel.add_theme_constant_override("separation", 10)
	split.add_child(side_panel)

	var instructions := Label.new()
	instructions.text = "Click an empty slot to search and place an upgrade.\nSelect a node to connect, move, or remove it."
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side_panel.add_child(instructions)

	selected_label = Label.new()
	selected_label.text = "No upgrade selected"
	selected_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	selected_label.add_theme_font_size_override("font_size", 18)
	side_panel.add_child(selected_label)

	prerequisites_label = RichTextLabel.new()
	prerequisites_label.bbcode_enabled = true
	prerequisites_label.fit_content = true
	prerequisites_label.custom_minimum_size.y = 110.0
	side_panel.add_child(prerequisites_label)

	var requirement_row := HBoxContainer.new()
	requirement_row.add_child(_make_label("Multiple parents"))
	requirement_option = OptionButton.new()
	requirement_option.add_item("ANY purchased", SkillTreeNodeData.RequirementMode.ANY)
	requirement_option.add_item("ALL purchased", SkillTreeNodeData.RequirementMode.ALL)
	requirement_option.item_selected.connect(_on_requirement_mode_selected)
	requirement_row.add_child(requirement_option)
	side_panel.add_child(requirement_row)

	connect_button = _make_button("Connect Parent → Child", _begin_connect_mode)
	move_button = _make_button("Move to Empty Slot", _begin_move_mode)
	remove_button = _make_button("Remove From Tree", _remove_selected_node)
	side_panel.add_child(connect_button)
	side_panel.add_child(move_button)
	side_panel.add_child(remove_button)
	side_panel.add_child(_make_button("Cancel Current Action", _cancel_interaction))

	var legend := Label.new()
	legend.text = "White connection: ALL prerequisites\nBlue connection: ANY prerequisite\nNo automatic positioning is performed."
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend.modulate = Color(0.75, 0.8, 0.9)
	side_panel.add_child(legend)

	_build_picker_popup()
	validation_dialog = AcceptDialog.new()
	validation_dialog.title = "Skill Tree Validation"
	add_child(validation_dialog)
	_refresh_selected_panel()

func _build_picker_popup() -> void:
	picker_popup = PopupPanel.new()
	picker_popup.size = Vector2i(620, 560)
	add_child(picker_popup)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	picker_popup.add_child(margin)

	var picker_vbox := VBoxContainer.new()
	picker_vbox.add_theme_constant_override("separation", 8)
	margin.add_child(picker_vbox)

	var picker_title := Label.new()
	picker_title.text = "PLACE UPGRADE"
	picker_title.add_theme_font_size_override("font_size", 20)
	picker_vbox.add_child(picker_title)

	picker_search = LineEdit.new()
	picker_search.placeholder_text = "Search by name, ID, or category..."
	picker_search.text_changed.connect(_on_picker_filter_changed)
	picker_vbox.add_child(picker_search)

	var filter_row := HBoxContainer.new()
	picker_category = OptionButton.new()
	picker_category.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker_category.item_selected.connect(_on_picker_category_changed)
	filter_row.add_child(picker_category)
	picker_only_unplaced = CheckBox.new()
	picker_only_unplaced.text = "Only unplaced"
	picker_only_unplaced.button_pressed = true
	picker_only_unplaced.toggled.connect(_on_picker_only_unplaced_toggled)
	filter_row.add_child(picker_only_unplaced)
	picker_vbox.add_child(filter_row)

	picker_list = ItemList.new()
	picker_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	picker_list.select_mode = ItemList.SELECT_SINGLE
	picker_list.item_selected.connect(_on_picker_item_selected)
	picker_list.item_activated.connect(_on_picker_item_activated)
	picker_vbox.add_child(picker_list)

	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_END
	button_row.add_child(_make_button("Cancel", _close_picker))
	picker_place_button = _make_button("Place", _place_selected_upgrade)
	picker_place_button.disabled = true
	button_row.add_child(picker_place_button)
	picker_vbox.add_child(button_row)

func _load_config() -> void:
	var loaded_resource := ResourceLoader.load(
		CONFIG_PATH,
		"",
		ResourceLoader.CACHE_MODE_REPLACE
	)
	if not loaded_resource is SkillTreeConfig:
		_set_status("Could not load SkillTreeConfig at " + CONFIG_PATH, true)
		return
	tree_config = loaded_resource as SkillTreeConfig
	selected_node = null
	interaction_mode = InteractionMode.NORMAL
	is_dirty = false
	columns_spin.value = tree_config.columns
	rows_spin.value = tree_config.rows
	canvas.set_tree_config(tree_config)
	_refresh_selected_panel()
	_set_status("Loaded %d placed upgrades. Click an empty slot to add another." % tree_config.nodes.size())

func _save_config() -> void:
	if not is_instance_valid(tree_config):
		return
	var validation_errors := tree_config.validate_tree()
	if not validation_errors.is_empty():
		_show_validation_result(validation_errors)
		_set_status("Fix validation errors before saving.", true)
		return
	tree_config.emit_changed()
	var save_error := ResourceSaver.save(tree_config, CONFIG_PATH)
	if save_error != OK:
		_set_status("Could not save config. Error code: %d" % save_error, true)
		return
	is_dirty = false
	EditorInterface.get_resource_filesystem().scan()
	_set_status("Saved SkillTreeConfig.tres successfully.")

func _validate_config() -> void:
	if not is_instance_valid(tree_config):
		return
	var validation_errors := tree_config.validate_tree()
	var ids: Dictionary = {}
	for upgrade in _scan_all_upgrades():
		if ids.has(upgrade.upgrade_id):
			validation_errors.append("Duplicate upgrade ID found on disk: '%s'." % upgrade.upgrade_id)
		else:
			ids[upgrade.upgrade_id] = upgrade.resource_path
	_show_validation_result(validation_errors)
	if validation_errors.is_empty():
		_set_status("Validation passed: %d placed upgrades." % tree_config.nodes.size())
	else:
		_set_status("Validation found %d problem(s)." % validation_errors.size(), true)

func _show_validation_result(errors: PackedStringArray) -> void:
	validation_dialog.dialog_text = (
		"Skill tree is valid."
		if errors.is_empty()
		else "Problems found:\n\n• " + "\n• ".join(errors)
	)
	validation_dialog.popup_centered(Vector2i(700, 480))

func _apply_grid_size() -> void:
	if not is_instance_valid(tree_config):
		return
	var requested_columns := int(columns_spin.value)
	var requested_rows := int(rows_spin.value)
	for node_data in tree_config.nodes:
		if (
			is_instance_valid(node_data)
			and (
				node_data.grid_position.x >= requested_columns
				or node_data.grid_position.y >= requested_rows
			)
		):
			columns_spin.value = tree_config.columns
			rows_spin.value = tree_config.rows
			_set_status("Grid cannot shrink past placed upgrade '%s'." % node_data.upgrade.upgrade_name, true)
			return
	tree_config.columns = requested_columns
	tree_config.rows = requested_rows
	_mark_dirty("Grid resized to %d × %d." % [requested_columns, requested_rows])
	canvas.refresh()

func _on_empty_cell_pressed(grid_position: Vector2i) -> void:
	if not is_instance_valid(tree_config):
		return
	if interaction_mode == InteractionMode.MOVE:
		if not is_instance_valid(selected_node):
			_cancel_interaction()
			return
		selected_node.grid_position = grid_position
		interaction_mode = InteractionMode.NORMAL
		_mark_dirty("Moved '%s' to cell %s." % [selected_node.upgrade.upgrade_name, grid_position])
		canvas.refresh()
		_refresh_selected_panel()
		return
	if interaction_mode == InteractionMode.CONNECT:
		_set_status("Connections require an occupied child slot. Click an upgrade node.", true)
		return
	pending_grid_position = grid_position
	_open_picker()

func _on_node_pressed(node_data: SkillTreeNodeData) -> void:
	if interaction_mode == InteractionMode.CONNECT:
		_toggle_connection(selected_node, node_data)
		return
	if interaction_mode == InteractionMode.MOVE:
		_set_status("That slot is occupied. Choose an empty slot or cancel.", true)
		return
	_select_node(node_data)

func _select_node(node_data: SkillTreeNodeData) -> void:
	selected_node = node_data
	interaction_mode = InteractionMode.NORMAL
	canvas.set_selected_node(node_data)
	_refresh_selected_panel()
	if is_instance_valid(node_data) and is_instance_valid(node_data.upgrade):
		_set_status("Selected '%s'." % node_data.upgrade.upgrade_name)

func _begin_connect_mode() -> void:
	if not is_instance_valid(selected_node):
		return
	interaction_mode = InteractionMode.CONNECT
	_set_status("Connection mode: click a child node. Existing connections are removed when clicked again.")
	_refresh_selected_panel()

func _toggle_connection(parent_node: SkillTreeNodeData, child_node: SkillTreeNodeData) -> void:
	if not is_instance_valid(parent_node) or not is_instance_valid(child_node):
		_cancel_interaction()
		return
	if parent_node == child_node:
		_set_status("An upgrade cannot require itself.", true)
		return
	var was_connected := child_node.prerequisites.has(parent_node.upgrade)
	if was_connected:
		child_node.prerequisites.erase(parent_node.upgrade)
	else:
		child_node.prerequisites.append(parent_node.upgrade)
		var errors := tree_config.validate_tree()
		if errors.has("The skill tree contains a prerequisite cycle."):
			child_node.prerequisites.erase(parent_node.upgrade)
			_set_status("Connection rejected because it creates a cycle.", true)
			interaction_mode = InteractionMode.NORMAL
			canvas.refresh()
			return
	interaction_mode = InteractionMode.NORMAL
	var action := "Removed" if was_connected else "Connected"
	_mark_dirty("%s %s → %s." % [action, parent_node.upgrade.upgrade_name, child_node.upgrade.upgrade_name])
	_select_node(child_node)

func _begin_move_mode() -> void:
	if not is_instance_valid(selected_node):
		return
	interaction_mode = InteractionMode.MOVE
	_set_status("Move mode: click an empty grid slot.")
	_refresh_selected_panel()

func _remove_selected_node() -> void:
	if not is_instance_valid(tree_config) or not is_instance_valid(selected_node):
		return
	var removed_upgrade := selected_node.upgrade
	tree_config.nodes.erase(selected_node)
	for node_data in tree_config.nodes:
		if is_instance_valid(node_data):
			node_data.prerequisites.erase(removed_upgrade)
	selected_node = null
	interaction_mode = InteractionMode.NORMAL
	_mark_dirty("Removed '%s' from the tree. The upgrade asset was not deleted." % removed_upgrade.upgrade_name)
	canvas.refresh()
	_refresh_selected_panel()

func _cancel_interaction() -> void:
	interaction_mode = InteractionMode.NORMAL
	_set_status("Current action cancelled.")
	_refresh_selected_panel()

func _on_requirement_mode_selected(index: int) -> void:
	if not is_instance_valid(selected_node):
		return
	selected_node.requirement_mode = requirement_option.get_item_id(index) as SkillTreeNodeData.RequirementMode
	_mark_dirty("Updated prerequisite mode for '%s'." % selected_node.upgrade.upgrade_name)
	canvas.refresh()
	_refresh_selected_panel()

func _refresh_selected_panel() -> void:
	var has_selection := is_instance_valid(selected_node) and is_instance_valid(selected_node.upgrade)
	connect_button.disabled = not has_selection
	move_button.disabled = not has_selection
	remove_button.disabled = not has_selection
	requirement_option.disabled = not has_selection
	if not has_selection:
		selected_label.text = "No upgrade selected"
		prerequisites_label.text = "[color=gray]Click an occupied slot to select it.[/color]"
		return

	selected_label.text = "%s\n%s\nCell: %s" % [
		selected_node.upgrade.upgrade_name,
		selected_node.upgrade.upgrade_id,
		selected_node.grid_position
	]
	var prerequisite_names := PackedStringArray()
	for prerequisite in selected_node.prerequisites:
		if is_instance_valid(prerequisite):
			prerequisite_names.append(prerequisite.upgrade_name)
	prerequisites_label.text = (
		"[b]Prerequisites[/b]\n[color=gray]None — root node[/color]"
		if prerequisite_names.is_empty()
		else "[b]Prerequisites[/b]\n• " + "\n• ".join(prerequisite_names)
	)
	requirement_option.select(int(selected_node.requirement_mode))
	connect_button.text = (
		"Click Child to Connect"
		if interaction_mode == InteractionMode.CONNECT
		else "Connect Parent → Child"
	)
	move_button.text = (
		"Click Empty Slot"
		if interaction_mode == InteractionMode.MOVE
		else "Move to Empty Slot"
	)

func _open_picker() -> void:
	available_upgrades = _scan_all_upgrades()
	_rebuild_picker_categories()
	picker_search.clear()
	picker_selected_upgrade = null
	picker_place_button.disabled = true
	_refresh_picker_results()
	picker_popup.popup_centered(Vector2i(620, 560))
	picker_search.grab_focus.call_deferred()

func _close_picker() -> void:
	picker_popup.hide()

func _rebuild_picker_categories() -> void:
	var previous_category := picker_category.get_item_text(picker_category.selected) if picker_category.item_count > 0 else "All categories"
	var categories := PackedStringArray()
	for upgrade in available_upgrades:
		if not upgrade.category.is_empty() and not categories.has(upgrade.category):
			categories.append(upgrade.category)
	categories.sort()
	picker_category.clear()
	picker_category.add_item("All categories")
	for category in categories:
		picker_category.add_item(category)
	for index in range(picker_category.item_count):
		if picker_category.get_item_text(index) == previous_category:
			picker_category.select(index)
			break

func _refresh_picker_results() -> void:
	picker_list.clear()
	picker_selected_upgrade = null
	picker_place_button.disabled = true
	var query := picker_search.text.strip_edges().to_lower()
	var category := picker_category.get_item_text(picker_category.selected) if picker_category.item_count > 0 else "All categories"
	for upgrade in available_upgrades:
		var is_placed := is_instance_valid(tree_config.find_node_by_upgrade(upgrade))
		if picker_only_unplaced.button_pressed and is_placed:
			continue
		if category != "All categories" and upgrade.category != category:
			continue
		var searchable := "%s %s %s" % [upgrade.upgrade_name, upgrade.upgrade_id, upgrade.category]
		if not query.is_empty() and not searchable.to_lower().contains(query):
			continue
		var label := "[%s] %s  —  %s" % [upgrade.category, upgrade.upgrade_name, upgrade.upgrade_id]
		if is_placed:
			label += "  (already placed)"
		var item_index := picker_list.add_item(label, upgrade.icon)
		picker_list.set_item_metadata(item_index, upgrade.resource_path)

func _on_picker_item_selected(index: int) -> void:
	var resource_path: String = picker_list.get_item_metadata(index)
	picker_selected_upgrade = load(resource_path) as UpgradeData
	picker_place_button.disabled = (
		not is_instance_valid(picker_selected_upgrade)
		or is_instance_valid(tree_config.find_node_by_upgrade(picker_selected_upgrade))
	)

func _on_picker_item_activated(index: int) -> void:
	_on_picker_item_selected(index)
	if not picker_place_button.disabled:
		_place_selected_upgrade()

func _place_selected_upgrade() -> void:
	if not is_instance_valid(tree_config) or not is_instance_valid(picker_selected_upgrade):
		return
	if is_instance_valid(tree_config.find_node_by_upgrade(picker_selected_upgrade)):
		_set_status("That upgrade is already placed.", true)
		return
	var node_data := SkillTreeNodeData.new()
	node_data.upgrade = picker_selected_upgrade
	node_data.grid_position = pending_grid_position
	tree_config.nodes.append(node_data)
	picker_popup.hide()
	_mark_dirty("Placed '%s' at cell %s." % [picker_selected_upgrade.upgrade_name, pending_grid_position])
	canvas.refresh()
	_select_node(node_data)

func _on_picker_filter_changed(_new_text: String) -> void:
	_refresh_picker_results()

func _on_picker_category_changed(_index: int) -> void:
	_refresh_picker_results()

func _on_picker_only_unplaced_toggled(_enabled: bool) -> void:
	_refresh_picker_results()

func _scan_all_upgrades() -> Array[UpgradeData]:
	var results: Array[UpgradeData] = []
	_scan_upgrade_directory(UPGRADE_DIRECTORY, results)
	results.sort_custom(func(first: UpgradeData, second: UpgradeData) -> bool:
		return first.upgrade_name.naturalnocasecmp_to(second.upgrade_name) < 0
	)
	return results

func _scan_upgrade_directory(directory_path: String, output: Array[UpgradeData]) -> void:
	var directory := DirAccess.open(directory_path)
	if not directory:
		return
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		var resource_path := directory_path.path_join(file_name)
		if directory.current_is_dir():
			_scan_upgrade_directory(resource_path, output)
		elif file_name.ends_with(".tres") or file_name.ends_with(".res"):
			var upgrade := load(resource_path) as UpgradeData
			if is_instance_valid(upgrade):
				output.append(upgrade)
		file_name = directory.get_next()
	directory.list_dir_end()

func _mark_dirty(message: String) -> void:
	is_dirty = true
	if is_instance_valid(tree_config):
		tree_config.emit_changed()
	_set_status(message + " Unsaved changes.")

func _set_status(message: String, is_error: bool = false) -> void:
	status_label.text = message
	status_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.45, 0.45) if is_error else Color(0.65, 0.85, 1.0)
	)

func _make_label(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	return label

func _make_button(text_value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.pressed.connect(callback)
	return button
