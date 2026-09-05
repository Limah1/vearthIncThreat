extends Node3D
class_name EnemyMultiMeshRenderer

## World positions + headings -> batches. Prototypes never enter the SceneTree.
@export var enemy_world: EnemyWorld
@export var use_gpu_transforms: bool = true
@export var gpu_combat: EnemyGPUCombat
@export var render_bounds := AABB(Vector3(-4096, -512, -4096), Vector3(8192, 1024, 8192))

class VisualBatch:
	var mesh_instance: MultiMeshInstance3D
	var local_transform := Transform3D.IDENTITY
	var archetype: int
	var count: int = 0
	var buffer := PackedFloat32Array()

var batches: Array[VisualBatch] = []
var _by_archetype: Array = []
var _known_archetypes: int = 0
var _slot_groups: Array[PackedInt32Array] = []
var _group_revision: int = -1
var _gpu: EnemyGPUTransforms
var last_update_ms: float = 0.0
var rendered_enemies: int = 0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	process_priority = 100
	if gpu_combat == null and use_gpu_transforms and RenderingServer.get_rendering_device() != null:
		_gpu = EnemyGPUTransforms.new()
		_gpu.failed.connect(_on_gpu_failed, CONNECT_DEFERRED)


func _exit_tree() -> void:
	if _gpu != null:
		RenderingServer.call_on_render_thread(_gpu.release)


func _process(_delta: float) -> void:
	update_visuals()


func _on_gpu_failed() -> void:
	if _gpu != null:
		RenderingServer.call_on_render_thread(_gpu.release)
		_gpu = null
	use_gpu_transforms = false


func update_visuals() -> void:
	if not is_instance_valid(enemy_world):
		return
	var start := Time.get_ticks_usec()
	_sync_prototypes()
	if _gpu != null or gpu_combat != null:
		_update_gpu_visuals()
		rendered_enemies = enemy_world.get_active_count()
		last_update_ms = (Time.get_ticks_usec() - start) / 1000.0
		return
	for batch in batches:
		batch.count = 0
	for index in range(enemy_world.get_active_count()):
		var slot := enemy_world.get_active_slot(index)
		var archetype := enemy_world.archetype_indices[slot]
		var position_3d := enemy_world.positions[slot]
		var angle := enemy_world.headings[slot]
		for batch: VisualBatch in _by_archetype[archetype]:
			_ensure_capacity(batch, batch.count + 1)
			var transform := Transform3D(enemy_basis(angle, enemy_world.get_archetype(archetype).tumble_visual), position_3d) * batch.local_transform
			write_transform(batch.buffer, batch.count * 12, transform)
			batch.count += 1
	for batch in batches:
		var mm := batch.mesh_instance.multimesh
		mm.visible_instance_count = batch.count
		if batch.count == 0:
			continue
		mm.buffer = batch.buffer
	rendered_enemies = enemy_world.get_active_count()
	last_update_ms = (Time.get_ticks_usec() - start) / 1000.0


func _update_gpu_visuals() -> void:
	# Membership changes only on spawn/recycle. Movement never rebuilds these lists.
	if _group_revision != enemy_world.mutation_revision:
		_slot_groups.resize(_known_archetypes)
		for i in range(_slot_groups.size()):
			_slot_groups[i] = PackedInt32Array()
		for i in range(enemy_world.get_active_count()):
			var slot := enemy_world.get_active_slot(i)
			_slot_groups[enemy_world.archetype_indices[slot]].append(slot)
		_group_revision = enemy_world.mutation_revision
	var dispatches: Array = []
	for batch in batches:
		var slots := _slot_groups[batch.archetype]
		batch.count = slots.size()
		_ensure_capacity(batch, batch.count)
		batch.mesh_instance.multimesh.visible_instance_count = batch.count
		if batch.count > 0:
			dispatches.append({"multimesh": batch.mesh_instance.multimesh, "slots": slots.to_byte_array(),
				"count": batch.count, "local": batch.local_transform, "tumble": enemy_world.get_archetype(batch.archetype).tumble_visual})
	if not dispatches.is_empty():
		if gpu_combat != null:
			RenderingServer.call_on_render_thread(gpu_combat.backend.render.bind(dispatches, gpu_combat.epoch))
			return
		# Packed world arrays go directly to SSBOs; no GDScript loop packing transforms/poses.
		RenderingServer.call_on_render_thread(_gpu.dispatch.bind(dispatches,
			enemy_world.positions.to_byte_array(), enemy_world.headings.to_byte_array()))


func _sync_prototypes() -> void:
	while _known_archetypes < enemy_world.get_archetype_count():
		var definition := enemy_world.get_archetype(_known_archetypes)
		if gpu_combat != null and definition.visual_asset != null and not definition.visual_asset.supports_instance_color:
			push_warning("Enemy visual '%s' does not declare instance-color support; HP/flash may be invisible." % definition.enemy_id)
		var prototype := definition.instantiate_visual()
		var group: Array[VisualBatch] = []
		if prototype is Node3D:
			_collect(prototype, Transform3D.IDENTITY, group)
		else:
			push_warning("Enemy visual prototype must have a Node3D root: %s" % definition.enemy_id)
		if prototype != null:
			prototype.free()
		_by_archetype.append(group)
		_known_archetypes += 1


func _collect(node: Node, parent_transform: Transform3D, group: Array[VisualBatch]) -> void:
	if node is Node3D and not node.visible:
		return
	var local := parent_transform
	if node is Node3D:
		local *= node.transform
	if node is MeshInstance3D and node.mesh != null:
		var batch := VisualBatch.new()
		batch.archetype = _known_archetypes
		batch.local_transform = local
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = gpu_combat != null
		mm.mesh = node.mesh.duplicate() as Mesh
		for surface in range(mm.mesh.get_surface_count()):
			var override_material: Material = node.get_surface_override_material(surface)
			if override_material != null:
				mm.mesh.surface_set_material(surface, override_material)
			if mm.use_colors:
				mm.mesh.surface_set_material(surface, _colored_material(mm.mesh.surface_get_material(surface)))
		mm.custom_aabb = render_bounds
		batch.mesh_instance = MultiMeshInstance3D.new()
		batch.mesh_instance.multimesh = mm
		batch.mesh_instance.material_override = _colored_material(node.material_override) if mm.use_colors else node.material_override
		batch.mesh_instance.cast_shadow = node.cast_shadow
		add_child(batch.mesh_instance)
		batches.append(batch)
		group.append(batch)
	for child in node.get_children():
		_collect(child, local, group)


static func _colored_material(material: Material) -> Material:
	if material is BaseMaterial3D:
		var copy := material.duplicate() as BaseMaterial3D
		copy.vertex_color_use_as_albedo = true
		return copy
	return material


func _ensure_capacity(batch: VisualBatch, required: int) -> void:
	var mm := batch.mesh_instance.multimesh
	if mm.instance_count >= required:
		return
	var allocation := maxi(required, maxi(64, mm.instance_count * 2))
	mm.instance_count = allocation
	batch.buffer.resize(allocation * 12)


static func write_transform(buffer: PackedFloat32Array, offset: int, transform: Transform3D) -> void:
	buffer[offset] = transform.basis.x.x
	buffer[offset + 1] = transform.basis.y.x
	buffer[offset + 2] = transform.basis.z.x
	buffer[offset + 3] = transform.origin.x
	buffer[offset + 4] = transform.basis.x.y
	buffer[offset + 5] = transform.basis.y.y
	buffer[offset + 6] = transform.basis.z.y
	buffer[offset + 7] = transform.origin.y
	buffer[offset + 8] = transform.basis.x.z
	buffer[offset + 9] = transform.basis.y.z
	buffer[offset + 10] = transform.basis.z.z
	buffer[offset + 11] = transform.origin.z


static func enemy_basis(angle: float, tumble: bool) -> Basis:
	return Basis(Vector3.RIGHT, angle) * Basis(Vector3.BACK, angle * 0.5) if tumble else Basis(Vector3.UP, angle)
