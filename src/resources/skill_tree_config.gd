@tool
class_name SkillTreeConfig
extends Resource

@export_range(1, 64, 1) var columns: int = 12
@export_range(1, 64, 1) var rows: int = 8
@export_range(40.0, 300.0, 1.0) var horizontal_spacing: float = 120.0
@export_range(40.0, 300.0, 1.0) var vertical_spacing: float = 120.0
@export_range(0.0, 200.0, 1.0) var canvas_padding: float = 80.0
@export var nodes: Array[SkillTreeNodeData] = []

func find_node_by_upgrade(upgrade: UpgradeData) -> SkillTreeNodeData:
	if not is_instance_valid(upgrade):
		return null
	for node_data in nodes:
		if is_instance_valid(node_data) and node_data.upgrade == upgrade:
			return node_data
	return null

func find_node_by_id(upgrade_id: String) -> SkillTreeNodeData:
	for node_data in nodes:
		if (
			is_instance_valid(node_data)
			and is_instance_valid(node_data.upgrade)
			and node_data.upgrade.upgrade_id == upgrade_id
		):
			return node_data
	return null

func find_node_at(grid_position: Vector2i) -> SkillTreeNodeData:
	for node_data in nodes:
		if is_instance_valid(node_data) and node_data.grid_position == grid_position:
			return node_data
	return null

func get_children_of(parent_upgrade: UpgradeData) -> Array[SkillTreeNodeData]:
	var children: Array[SkillTreeNodeData] = []
	if not is_instance_valid(parent_upgrade):
		return children
	for node_data in nodes:
		if is_instance_valid(node_data) and node_data.prerequisites.has(parent_upgrade):
			children.append(node_data)
	return children

func grid_to_canvas(grid_position: Vector2i) -> Vector2:
	return Vector2(
		canvas_padding + float(grid_position.x) * horizontal_spacing,
		canvas_padding + float(grid_position.y) * vertical_spacing
	)

func get_canvas_size(slot_size: Vector2 = Vector2(80.0, 80.0)) -> Vector2:
	return Vector2(
		canvas_padding * 2.0 + float(maxi(columns - 1, 0)) * horizontal_spacing + slot_size.x,
		canvas_padding * 2.0 + float(maxi(rows - 1, 0)) * vertical_spacing + slot_size.y
	)

func validate_tree() -> PackedStringArray:
	var errors := PackedStringArray()
	var positions: Dictionary = {}
	var upgrades: Dictionary = {}
	for node_index in range(nodes.size()):
		var node_data: SkillTreeNodeData = nodes[node_index]
		if not is_instance_valid(node_data):
			errors.append("Node %d is empty." % node_index)
			continue
		if not is_instance_valid(node_data.upgrade):
			errors.append("Node %d has no upgrade assigned." % node_index)
			continue
		var upgrade_id: String = node_data.upgrade.upgrade_id
		if upgrade_id.is_empty():
			errors.append("The node at %s has an empty upgrade ID." % node_data.grid_position)
		if upgrades.has(node_data.upgrade):
			errors.append("Upgrade '%s' is placed more than once." % upgrade_id)
		else:
			upgrades[node_data.upgrade] = node_data
		if positions.has(node_data.grid_position):
			errors.append("Grid position %s is occupied more than once." % node_data.grid_position)
		else:
			positions[node_data.grid_position] = node_data
		if (
			node_data.grid_position.x < 0
			or node_data.grid_position.y < 0
			or node_data.grid_position.x >= columns
			or node_data.grid_position.y >= rows
		):
			errors.append("Upgrade '%s' is outside the configured grid." % upgrade_id)
		for prerequisite in node_data.prerequisites:
			if not is_instance_valid(prerequisite):
				errors.append("Upgrade '%s' has an empty prerequisite." % upgrade_id)
			elif prerequisite == node_data.upgrade:
				errors.append("Upgrade '%s' requires itself." % upgrade_id)

	for node_data in nodes:
		if not is_instance_valid(node_data) or not is_instance_valid(node_data.upgrade):
			continue
		for prerequisite in node_data.prerequisites:
			if is_instance_valid(prerequisite) and not upgrades.has(prerequisite):
				errors.append("Upgrade '%s' requires an upgrade that is not placed: '%s'." % [
				node_data.upgrade.upgrade_id,
				prerequisite.upgrade_id
			])

	var visiting: Dictionary = {}
	var visited: Dictionary = {}
	for node_data in nodes:
		if _has_cycle(node_data, visiting, visited):
			errors.append("The skill tree contains a prerequisite cycle.")
			break
	return errors

func _has_cycle(
	node_data: SkillTreeNodeData,
	visiting: Dictionary,
	visited: Dictionary
) -> bool:
	if not is_instance_valid(node_data) or not is_instance_valid(node_data.upgrade):
		return false
	if visited.has(node_data.upgrade):
		return false
	if visiting.has(node_data.upgrade):
		return true
	visiting[node_data.upgrade] = true
	for prerequisite in node_data.prerequisites:
		var prerequisite_node := find_node_by_upgrade(prerequisite)
		if is_instance_valid(prerequisite_node) and _has_cycle(prerequisite_node, visiting, visited):
			return true
	visiting.erase(node_data.upgrade)
	visited[node_data.upgrade] = true
	return false
