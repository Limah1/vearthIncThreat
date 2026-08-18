# res://src/core/base_master_pool.gd
extends Node3D
class_name BaseMasterPool

@export var scene_to_pool: PackedScene
@export var pool_size: int = 100

var _pool: Array[Node3D] = []
var _active_instances: Array[Node3D] = []
var _active_indices: Dictionary = {}
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
			_disable_shadows_recursive(instance)
			
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
			_disable_shadows_recursive(instance)
			if instance.has_method("on_pool_deactivate"):
				instance.on_pool_deactivate()
				
	if instance:
		_active_instances.append(instance)
		_active_indices[instance] = _active_instances.size() - 1
		instance.process_mode = Node.PROCESS_MODE_INHERIT
		active_count += 1
		
	return instance

func return_to_pool(instance: Node3D) -> void:
	if not is_instance_valid(instance) or instance.is_queued_for_deletion():
		return
		
	if not _active_indices.has(instance):
		return

	_remove_active_at(int(_active_indices[instance]))
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

func _remove_active_at(index: int) -> void:
	if index < 0 or index >= _active_instances.size():
		return

	var last_index = _active_instances.size() - 1
	var removed = _active_instances[index]
	if index != last_index:
		var replacement = _active_instances[last_index]
		_active_instances[index] = replacement
		_active_indices[replacement] = index
	_active_instances.pop_back()
	_active_indices.erase(removed)

func _disable_shadows_recursive(node: Node) -> void:
	if node is GeometryInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	for child in node.get_children():
		_disable_shadows_recursive(child)
