# res://src/core/base_master_pool.gd
extends Node3D
class_name BaseMasterPool

@export var scene_to_pool: PackedScene
@export var pool_size: int = 100

var _pool: Array[Node3D] = []
var _active_instances: Array[Node3D] = []
var active_count: int = 0

func _ready() -> void:
	_initialize_pool()

func _initialize_pool() -> void:
	if not scene_to_pool:
		push_error("[BaseMasterPool] scene_to_pool is not assigned on " + name)
		return
		
	for i in range(pool_size):
		var instance = scene_to_pool.instantiate() as Node3D
		if instance:
			# Check if property exists before setting to avoid warnings
			if "master_node" in instance:
				instance.set("master_node", self)
				
			instance.process_mode = Node.PROCESS_MODE_DISABLED
			instance.visible = false
			instance.position = Vector3(99999.0, 0.0, 99999.0)
			add_child(instance)
			
			if instance.has_method("on_pool_deactivate"):
				instance.on_pool_deactivate()
				
			_pool.append(instance)

func borrow_instance() -> Node3D:
	var instance: Node3D = null
	while not _pool.is_empty():
		var candidate = _pool.pop_back()
		if is_instance_valid(candidate) and not candidate.is_queued_for_deletion():
			instance = candidate
			break
			
	if not instance:
		# Steal/recycle the oldest active instance!
		if not _active_instances.is_empty():
			var oldest = _active_instances[0]
			return_to_pool(oldest)
			if not _pool.is_empty():
				instance = _pool.pop_back()
				
	if not instance:
		# Dynamic fallback (only if pool size was 0 or setup failed)
		instance = scene_to_pool.instantiate() as Node3D
		if instance:
			if "master_node" in instance:
				instance.set("master_node", self)
			add_child(instance)
			if instance.has_method("on_pool_deactivate"):
				instance.on_pool_deactivate()
				
	if instance:
		_active_instances.append(instance)
		instance.process_mode = Node.PROCESS_MODE_INHERIT
		active_count += 1
		
	return instance

func return_to_pool(instance: Node3D) -> void:
	if not is_instance_valid(instance) or instance.is_queued_for_deletion():
		return
		
	if _active_instances.has(instance):
		_active_instances.erase(instance)
		active_count = max(0, active_count - 1)
		
	if instance.has_method("on_pool_deactivate"):
		instance.on_pool_deactivate()
		
	instance.process_mode = Node.PROCESS_MODE_DISABLED
	instance.visible = false
	instance.position = Vector3(99999.0, 0.0, 99999.0)
	
	_pool.append(instance)

func return_all_active_to_pool() -> void:
	var active_copy = _active_instances.duplicate()
	for instance in active_copy:
		return_to_pool(instance)
