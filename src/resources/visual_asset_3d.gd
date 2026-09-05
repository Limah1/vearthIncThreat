@tool
class_name VisualAsset3D
extends Resource

## Shared presentation contract. Gameplay dimensions and combat values stay in
## EnemyData/TurretConfig; this resource only describes how a 3D prefab appears.
@export var scene: PackedScene
@export var scale: Vector3 = Vector3.ONE
@export var rotation_degrees: Vector3 = Vector3.ZERO
@export var offset: Vector3 = Vector3.ZERO
@export var aim_pivot_path: NodePath
@export var muzzle_path: NodePath
@export var supports_instance_color: bool = true
@export var cast_shadow: bool = false


func get_local_transform() -> Transform3D:
	return Transform3D(Basis.from_euler(rotation_degrees * PI / 180.0).scaled(scale), offset)


func instantiate_visual() -> Node3D:
	if scene == null or not scene.can_instantiate():
		return null
	var instance := scene.instantiate()
	if not instance is Node3D:
		instance.free()
		return null
	var visual := instance as Node3D
	visual.transform = get_local_transform() * visual.transform
	_apply_shadow_setting(visual)
	return visual


func resolve_aim_pivot(root: Node3D) -> Node3D:
	if not is_instance_valid(root) or aim_pivot_path.is_empty():
		return null
	return root.get_node_or_null(aim_pivot_path) as Node3D


func resolve_muzzle(root: Node3D) -> Node3D:
	if not is_instance_valid(root) or muzzle_path.is_empty():
		return null
	return root.get_node_or_null(muzzle_path) as Node3D


func get_validation_errors(require_instancing: bool = false) -> PackedStringArray:
	var errors := PackedStringArray()
	if scene == null:
		errors.append("3D visual scene cannot be empty.")
		return errors
	if not scene.can_instantiate():
		errors.append("3D visual scene must be instantiable.")
		return errors
	if not scale.is_finite() or scale.x <= 0 or scale.y <= 0 or scale.z <= 0:
		errors.append("3D visual scale must be finite and positive on every axis.")
	if not rotation_degrees.is_finite() or not offset.is_finite():
		errors.append("3D visual rotation and offset must be finite.")
	var instance := scene.instantiate()
	if not instance is Node3D:
		errors.append("3D visual scene must have a Node3D root.")
		instance.free()
		return errors
	var root := instance as Node3D
	if require_instancing and _collect_meshes(root).is_empty():
		errors.append("Instanced enemy visual must contain at least one MeshInstance3D.")
	if not aim_pivot_path.is_empty() and root.get_node_or_null(aim_pivot_path) is not Node3D:
		errors.append("aim_pivot_path must resolve to a Node3D.")
	if not muzzle_path.is_empty() and root.get_node_or_null(muzzle_path) is not Node3D:
		errors.append("muzzle_path must resolve to a Node3D or Marker3D.")
	root.free()
	return errors


func _apply_shadow_setting(root: Node) -> void:
	var setting := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for mesh in _collect_meshes(root):
		(mesh as MeshInstance3D).cast_shadow = setting


static func _collect_meshes(root: Node) -> Array[Node]:
	var meshes: Array[Node] = []
	if root is MeshInstance3D:
		meshes.append(root)
	for child in root.get_children():
		meshes.append_array(_collect_meshes(child))
	return meshes
