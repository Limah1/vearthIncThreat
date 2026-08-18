extends Node3D
class_name MultiMeshRenderer

## Renders repeated pooled visuals in a small number of draw calls.
## Simulation still lives on the pooled entity nodes; this node owns only the
## visible transforms for debris, projectiles, and garbage.

class VisualGroup:
	var multimesh_instance: MultiMeshInstance3D
	var multimesh: MultiMesh
	var prototype_transform: Transform3D = Transform3D.IDENTITY
	var entities: Array[Node3D] = []
	var indices: Dictionary = {}

const GROUP_DEFINITIONS: Dictionary = {
	"garbage": {
		"scene": "res://src/entities/visuals/space_garbage_3d.tscn",
		"capacity": 550
	},
	"debris": {
		"scene": "res://src/entities/visuals/debris_3d.tscn",
		"capacity": 500
	},
	"enemy_projectile": {
		"scene": "res://src/entities/visuals/enemy_projectile_3d.tscn",
		"capacity": 50
	},
	"satellite_projectile": {
		"scene": "res://src/entities/visuals/satellite_projectile_3d.tscn",
		"capacity": 250
	}
}

var _groups_by_type: Dictionary = {}

func _ready() -> void:
	GameManager.set_multimesh_renderer(self)
	for visual_type in GROUP_DEFINITIONS.keys():
		_create_groups_for_type(str(visual_type), GROUP_DEFINITIONS[visual_type])

func _create_groups_for_type(visual_type: String, definition: Dictionary) -> void:
	var packed_scene = load(definition["scene"]) as PackedScene
	if not packed_scene:
		push_warning("[MultiMeshRenderer] Missing visual scene for " + visual_type)
		return

	var prototype = packed_scene.instantiate()
	var mesh_nodes: Array[MeshInstance3D] = []
	_collect_mesh_nodes(prototype, mesh_nodes)
	var groups: Array = []
	var capacity = int(definition["capacity"])

	for mesh_node in mesh_nodes:
		if not mesh_node.mesh:
			continue

		var group = VisualGroup.new()
		group.prototype_transform = mesh_node.global_transform
		group.multimesh = MultiMesh.new()
		group.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		group.multimesh.instance_count = max(1, capacity)
		group.multimesh.custom_aabb = AABB(Vector3(-1000.0, -1000.0, -1000.0), Vector3(2000.0, 2000.0, 2000.0))

		group.multimesh_instance = MultiMeshInstance3D.new()
		group.multimesh_instance.multimesh = group.multimesh
		group.multimesh_instance.visible_instance_count = 0
		group.multimesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mesh_node.material_override:
			group.multimesh_instance.material_override = mesh_node.material_override
		add_child(group.multimesh_instance)
		groups.append(group)

	_groups_by_type[visual_type] = groups
	prototype.free()

func _collect_mesh_nodes(node: Node, output: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		output.append(node)
	for child in node.get_children():
		_collect_mesh_nodes(child, output)

func register_entity(entity: Node3D, visual_type: String) -> void:
	if not is_instance_valid(entity):
		return
	var groups: Array = _groups_by_type.get(visual_type, [])
	if groups.is_empty():
		return

	for group in groups:
		_register_in_group(group, entity)
	_set_entity_mesh_visible(entity, false)

func unregister_entity(entity: Node3D, visual_type: String) -> void:
	if not is_instance_valid(entity):
		return
	var groups: Array = _groups_by_type.get(visual_type, [])
	for group in groups:
		if group.indices.has(entity):
			_remove_from_group(group, int(group.indices[entity]))

func _register_in_group(group: VisualGroup, entity: Node3D) -> void:
	if group.indices.has(entity):
		return
	var index = group.entities.size()
	group.indices[entity] = index
	group.entities.append(entity)
	_ensure_capacity(group, index + 1)
	group.multimesh.set_instance_transform_3d(index, entity.global_transform * group.prototype_transform)
	group.multimesh_instance.visible_instance_count = group.entities.size()

func _remove_from_group(group: VisualGroup, index: int) -> void:
	if index < 0 or index >= group.entities.size():
		return

	var last_index = group.entities.size() - 1
	var removed = group.entities[index]
	if index != last_index:
		var replacement = group.entities[last_index]
		group.entities[index] = replacement
		group.indices[replacement] = index
	group.entities.pop_back()
	group.indices.erase(removed)
	group.multimesh_instance.visible_instance_count = group.entities.size()

func _ensure_capacity(group: VisualGroup, required: int) -> void:
	if required <= group.multimesh.instance_count:
		return
	group.multimesh.instance_count = max(required, group.multimesh.instance_count * 2)

func _set_entity_mesh_visible(node: Node, is_visible: bool) -> void:
	if node is MeshInstance3D:
		node.visible = is_visible
	for child in node.get_children():
		_set_entity_mesh_visible(child, is_visible)

func _process(_delta: float) -> void:
	for groups in _groups_by_type.values():
		for group in groups:
			for i in range(group.entities.size() - 1, -1, -1):
				var entity = group.entities[i]
				if not is_instance_valid(entity):
					_remove_from_group(group, i)
					continue
				if not bool(entity.get("active")):
					_remove_from_group(group, i)
					continue
				group.multimesh.set_instance_transform_3d(i, entity.global_transform * group.prototype_transform)
