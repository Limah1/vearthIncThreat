# res://src/entities/enemy_master.gd
extends BaseMasterPool
class_name EnemyMaster

func _ready() -> void:
	add_to_group("enemy_master")
	super._ready()

func spawn_enemy(spawn_pos_3d: Vector3) -> Node3D:
	var instance = borrow_instance()
	if instance:
		if instance.has_method("on_pool_activate"):
			instance.on_pool_activate(spawn_pos_3d)
	return instance
