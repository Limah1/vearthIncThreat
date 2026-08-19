@tool
class_name BarrierConfig
extends Resource

## Runtime data for one defensive barrier.
## Position uses gameplay X/Y coordinates; 3D visual maps Y to world Z.

@export var max_hp: float = 10.0
@export var size: Vector2 = Vector2(50.0, 80.0)
@export_range(0.0, 2000.0, 1.0) var distance_from_planet: float = 80.0
@export_enum("left", "right", "top", "bottom") var side: String = "left"
@export_range(1.0, 50.0, 0.5) var depth: float = 6.0

func get_planet_offset() -> Vector2:
	match side:
		"right":
			return Vector2(distance_from_planet, 0.0)
		"top":
			return Vector2(0.0, -distance_from_planet)
		"bottom":
			return Vector2(0.0, distance_from_planet)
	return Vector2(-distance_from_planet, 0.0)
