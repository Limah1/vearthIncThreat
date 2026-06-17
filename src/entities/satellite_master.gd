# res://src/entities/satellite_master.gd
extends BaseMasterPool
class_name SatelliteMaster

func _ready() -> void:
	add_to_group("satellite_master")
	super._ready()

func spawn_satellite(angle: float) -> Node3D:
	var instance = borrow_instance()
	if instance:
		if instance.has_method("set_orbit_angle"):
			instance.set_orbit_angle(angle)
		if instance.has_method("on_pool_activate"):
			instance.on_pool_activate()
	return instance
