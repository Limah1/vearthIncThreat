# res://src/entities/space_garbage_master.gd
extends BaseMasterPool
class_name SpaceGarbageMaster

signal wave_cleared

func _ready() -> void:
	add_to_group("garbage_master")
	super._ready()

func spawn_garbage(spawn_pos_2d: Vector2) -> Node3D:
	var instance = borrow_instance()
	if instance is SpaceGarbageInstance:
		var spawn_pos_3d = Vector3(spawn_pos_2d.x, 0.0, spawn_pos_2d.y)
		instance.on_pool_activate(spawn_pos_3d)
	elif instance:
		var spawn_pos_3d = Vector3(spawn_pos_2d.x, 0.0, spawn_pos_2d.y)
		if instance.has_method("on_pool_activate"):
			instance.on_pool_activate(spawn_pos_3d)
	return instance

func return_to_pool(instance: Node3D) -> void:
	super.return_to_pool(instance)

	if active_count == 0:
		wave_cleared.emit()
