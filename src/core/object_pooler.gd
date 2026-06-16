# res://src/core/object_pooler.gd
extends Node
class_name ObjectPooler

# PackedScenes for 2D logic nodes (which internally load/reference their 3D visuals)
@export var garbage_scene: PackedScene
@export var asteroid_scene: PackedScene
@export var enemy_scene: PackedScene
@export var debris_scene: PackedScene
@export var enemy_projectile_scene: PackedScene
@export var satellite_projectile_scene: PackedScene

# Scene tree container nodes
var world_2d: Node2D
var world_3d: Node3D

# Pooled items: { "type_name": Array[Dictionary] }
# Items inside array: { "logic_2d": Entity2D, "visual_3d": Node3D }
var _pools: Dictionary = {
	"garbage": [],
	"asteroid": [],
	"enemy": [],
	"debris": [],
	"enemy_projectile": [],
	"satellite_projectile": []
}

func setup(p_world_2d: Node2D, p_world_3d: Node3D) -> void:
	world_2d = p_world_2d
	world_3d = p_world_3d
	get_node("/root/GameManager").object_pooler = self

# Retrieve an entity from the pool or instantiate if empty
func borrow_from_pool(type: String, position_2d: Vector2, velocity_2d: Vector2 = Vector2.ZERO) -> Node2D:
	if not _pools.has(type):
		push_error("Pool type not found: " + type)
		return null
		
	var pool_list = _pools[type]
	var entity_dict: Dictionary
	
	while not pool_list.is_empty():
		var candidate = pool_list.pop_back()
		if is_instance_valid(candidate.get("logic_2d")) and not candidate["logic_2d"].is_queued_for_deletion():
			if is_instance_valid(candidate.get("visual_3d")) and not candidate["visual_3d"].is_queued_for_deletion():
				entity_dict = candidate
				break
				
	if entity_dict.is_empty():
		entity_dict = _create_new_entity(type)
		
	var logic_2d: Node2D = entity_dict["logic_2d"]
	var visual_3d: Node3D = entity_dict["visual_3d"]
	
	# Add to scene tree
	world_2d.add_child(logic_2d)
	world_3d.add_child(visual_3d)
	
	# Link them dynamically
	logic_2d.visual_3d = visual_3d
	
	# Activate (initializes positions, velocities, HP, visuals, colliders)
	if logic_2d.has_method("on_pool_activate"):
		logic_2d.on_pool_activate(position_2d, velocity_2d)
		
	return logic_2d

# Return active entity back into the pool
func return_to_pool(type: String, logic_2d: Node2D) -> void:
	if not is_instance_valid(logic_2d) or logic_2d.is_queued_for_deletion():
		return
		
	if not _pools.has(type):
		push_error("Pool type not found: " + type)
		return
		
	var visual_3d = logic_2d.visual_3d
	if not is_instance_valid(visual_3d) or visual_3d.is_queued_for_deletion():
		return
	
	# Deactivate first
	if logic_2d.has_method("on_pool_deactivate"):
		logic_2d.on_pool_deactivate()
		
	# Remove from tree safely
	if logic_2d.get_parent():
		logic_2d.get_parent().remove_child(logic_2d)
	if visual_3d.get_parent():
		visual_3d.get_parent().remove_child(visual_3d)
		
	# Store back
	_pools[type].push_back({
		"logic_2d": logic_2d,
		"visual_3d": visual_3d
	})

# Scans all active children under world_2d and returns them to the pool
func return_all_active_to_pool() -> void:
	if not world_2d:
		return
	var active_nodes = world_2d.get_children()
	for child in active_nodes:
		if child.has_method("on_pool_deactivate") and child.get("active") == true:
			var p_type = child.get("pool_type")
			if p_type != "":
				return_to_pool(p_type, child)

func _create_new_entity(type: String) -> Dictionary:
	var scene_2d: PackedScene
	match type:
		"garbage": scene_2d = garbage_scene
		"asteroid": scene_2d = asteroid_scene
		"enemy": scene_2d = enemy_scene
		"debris": scene_2d = debris_scene
		"enemy_projectile": scene_2d = enemy_projectile_scene
		"satellite_projectile": scene_2d = satellite_projectile_scene
		_:
			push_error("Unknown type: " + type)
			return {}
			
	var logic_2d = scene_2d.instantiate() as Node2D
	
	# Instantiate corresponding 3D scene if defined in the 2D logic script
	var visual_3d: Node3D = null
	if "visual_3d_scene" in logic_2d and logic_2d.visual_3d_scene:
		visual_3d = logic_2d.visual_3d_scene.instantiate() as Node3D
	else:
		# Fallback: create a basic empty Node3D if no mesh is defined
		visual_3d = Node3D.new()
		
	return {
		"logic_2d": logic_2d,
		"visual_3d": visual_3d
	}

# Clear all entities in the pools to release memory
func clear_pools() -> void:
	for type in _pools:
		for item in _pools[type]:
			item["logic_2d"].queue_free()
			item["visual_3d"].queue_free()
		_pools[type].clear()
