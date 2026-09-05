# res://src/entities/debris_master.gd
extends BaseMasterPool
class_name DebrisMaster

func _ready() -> void:
	add_to_group("debris_master")
	if GameManager.get_selected_level_config().use_mass_enemies:
		return
	super._ready()

## Borrow normal (debris disparado por burst no momento da morte)
func spawn_debris(spawn_pos_3d: Vector3, dir_3d: Vector3) -> Node3D:
	if is_instance_valid(GameManager.mass_combat):
		GameManager.mass_combat.fire_debris(spawn_pos_3d, dir_3d, 3.0 * UpgradeManager.get_multiplier("DebrisDamage"), int(UpgradeManager.get_total_bonus("DebrisPiercing")))
		return null
	var instance = borrow_instance()
	if instance:
		if instance.has_method("on_pool_activate"):
			instance.on_pool_activate(spawn_pos_3d, dir_3d)
	return instance
