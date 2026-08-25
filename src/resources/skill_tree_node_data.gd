@tool
class_name SkillTreeNodeData
extends Resource

enum RequirementMode {
	ANY,
	ALL,
}

@export var upgrade: UpgradeData
@export var grid_position: Vector2i = Vector2i.ZERO
@export var prerequisites: Array[UpgradeData] = []
@export var requirement_mode: RequirementMode = RequirementMode.ALL

func has_prerequisite(upgrade_data: UpgradeData) -> bool:
	return is_instance_valid(upgrade_data) and prerequisites.has(upgrade_data)

