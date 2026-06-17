# res://src/entities/asteroid_master.gd
extends BaseMasterPool
class_name AsteroidMaster

func _ready() -> void:
	add_to_group("asteroid_master")
	super._ready()

func spawn_asteroid(spawn_pos_3d: Vector3, dir_3d: Vector3, type: String = "small") -> Node3D:
	var instance = borrow_instance()
	if instance:
		if instance.has_method("set_asteroid_type"):
			instance.set_asteroid_type(type)
		if instance.has_method("on_pool_activate"):
			instance.on_pool_activate(spawn_pos_3d, dir_3d)
	return instance
