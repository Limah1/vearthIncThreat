# res://src/entities/enemy_proj_master.gd
extends BaseMasterPool
class_name EnemyProjMaster

func _ready() -> void:
	add_to_group("enemy_proj_master")
	super._ready()

func spawn_enemy_projectile(spawn_pos_3d: Vector3, dir_3d: Vector3) -> Node3D:
	var instance = borrow_instance()
	if instance:
		if instance.has_method("on_pool_activate"):
			instance.on_pool_activate(spawn_pos_3d, dir_3d)
	return instance
