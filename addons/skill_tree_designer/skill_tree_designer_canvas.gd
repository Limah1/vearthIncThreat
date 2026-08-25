@tool
class_name SkillTreeDesignerCanvas
extends Control

signal empty_cell_pressed(grid_position: Vector2i)
signal node_pressed(node_data: SkillTreeNodeData)

const SLOT_SIZE := Vector2(92.0, 92.0)

var tree_config: SkillTreeConfig
var selected_node: SkillTreeNodeData

func set_tree_config(new_config: SkillTreeConfig) -> void:
	tree_config = new_config
	selected_node = null
	refresh()

func set_selected_node(node_data: SkillTreeNodeData) -> void:
	selected_node = node_data
	refresh()

func refresh() -> void:
	for child in get_children():
		child.queue_free()
	if not is_instance_valid(tree_config):
		custom_minimum_size = Vector2(800.0, 600.0)
		queue_redraw()
		return

	custom_minimum_size = tree_config.get_canvas_size(SLOT_SIZE)
	for y in range(tree_config.rows):
		for x in range(tree_config.columns):
			var grid_position := Vector2i(x, y)
			var node_data := tree_config.find_node_at(grid_position)
			var slot_button := Button.new()
			slot_button.position = tree_config.grid_to_canvas(grid_position)
			slot_button.size = SLOT_SIZE
			slot_button.clip_text = true
			slot_button.add_theme_font_size_override("font_size", 12)
			if is_instance_valid(node_data) and is_instance_valid(node_data.upgrade):
				slot_button.text = node_data.upgrade.upgrade_name
				slot_button.icon = node_data.upgrade.icon
				slot_button.expand_icon = true
				slot_button.tooltip_text = "%s\n%s\nCell: %s" % [
					node_data.upgrade.upgrade_name,
					node_data.upgrade.upgrade_id,
					grid_position
				]
				if node_data == selected_node:
					slot_button.modulate = Color(0.45, 0.9, 1.0)
				slot_button.pressed.connect(_on_node_button_pressed.bind(node_data))
			else:
				slot_button.text = "+\n%d, %d" % [x, y]
				slot_button.modulate = Color(0.55, 0.55, 0.6, 0.75)
				slot_button.tooltip_text = "Place an upgrade at cell (%d, %d)" % [x, y]
				slot_button.pressed.connect(_on_empty_button_pressed.bind(grid_position))
			add_child(slot_button)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.055, 0.065, 0.09), true)
	if not is_instance_valid(tree_config):
		return

	for child_node in tree_config.nodes:
		if not is_instance_valid(child_node) or not is_instance_valid(child_node.upgrade):
			continue
		var child_center: Vector2 = tree_config.grid_to_canvas(child_node.grid_position) + SLOT_SIZE * 0.5
		for prerequisite in child_node.prerequisites:
			var parent_node := tree_config.find_node_by_upgrade(prerequisite)
			if not is_instance_valid(parent_node):
				continue
			var parent_center: Vector2 = tree_config.grid_to_canvas(parent_node.grid_position) + SLOT_SIZE * 0.5
			var line_color := Color(0.3, 0.85, 1.0, 0.9)
			if child_node.requirement_mode == SkillTreeNodeData.RequirementMode.ALL:
				line_color = Color(0.95, 0.95, 1.0, 0.9)
			draw_line(parent_center, child_center, Color(0.0, 0.0, 0.0, 0.8), 7.0, true)
			draw_line(parent_center, child_center, line_color, 3.0, true)

func _on_empty_button_pressed(grid_position: Vector2i) -> void:
	empty_cell_pressed.emit(grid_position)

func _on_node_button_pressed(node_data: SkillTreeNodeData) -> void:
	node_pressed.emit(node_data)
