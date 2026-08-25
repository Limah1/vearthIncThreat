@tool
class_name TurretConfig
extends Resource

## Combat values shared by every turret instance of this type.
@export_range(0.0, 10000.0, 0.1) var damage: float = 1.0
## Shots per second. Runtime cooldown is derived from this value.
@export_range(0.05, 100.0, 0.05) var fire_rate: float = 2.85
@export_range(10.0, 5000.0, 1.0) var attack_range: float = 700.0

## Player-configurable action cone.
@export_range(1.0, 179.0, 1.0) var default_cone_angle: float = 90.0
@export_range(1.0, 179.0, 1.0) var minimum_cone_angle: float = 20.0
@export_range(1.0, 179.0, 1.0) var maximum_cone_angle: float = 160.0

## Idle scan movement, measured in complete bell sweeps per second.
@export_range(0.0, 10.0, 0.05) var sweep_speed: float = 0.45
@export_range(0.02, 1.0, 0.01) var target_refresh_interval: float = 0.1

## Placement handle distances. Near = wide cone; far = narrow cone.
@export_range(5.0, 500.0, 1.0) var minimum_handle_distance: float = 24.0
@export_range(5.0, 1000.0, 1.0) var maximum_handle_distance: float = 130.0

func get_clamped_cone_angle(angle_degrees: float) -> float:
	var minimum_angle: float = minf(minimum_cone_angle, maximum_cone_angle)
	var maximum_angle: float = maxf(minimum_cone_angle, maximum_cone_angle)
	return clampf(angle_degrees, minimum_angle, maximum_angle)

func get_cone_angle_for_handle_distance(distance: float) -> float:
	var minimum_distance: float = minf(minimum_handle_distance, maximum_handle_distance)
	var maximum_distance: float = maxf(minimum_handle_distance, maximum_handle_distance)
	var ratio: float = inverse_lerp(minimum_distance, maximum_distance, clampf(
		distance,
		minimum_distance,
		maximum_distance
	))
	return lerpf(maximum_cone_angle, minimum_cone_angle, ratio)

func get_handle_distance_for_cone_angle(angle_degrees: float) -> float:
	var clamped_angle: float = get_clamped_cone_angle(angle_degrees)
	var angle_span: float = maximum_cone_angle - minimum_cone_angle
	if is_zero_approx(angle_span):
		return minimum_handle_distance
	var ratio: float = clampf(
		(maximum_cone_angle - clamped_angle) / angle_span,
		0.0,
		1.0
	)
	return lerpf(minimum_handle_distance, maximum_handle_distance, ratio)

func contains_offset_in_action_cone(
	world_offset: Vector2,
	forward: Vector2,
	angle_degrees: float
) -> bool:
	var distance_squared: float = world_offset.length_squared()
	if distance_squared <= 0.0001:
		return true
	if distance_squared > attack_range * attack_range:
		return false
	var normalized_forward: Vector2 = forward.normalized()
	if normalized_forward.is_zero_approx():
		return false
	var target_direction: Vector2 = world_offset / sqrt(distance_squared)
	var minimum_dot: float = cos(deg_to_rad(get_clamped_cone_angle(angle_degrees) * 0.5))
	return normalized_forward.dot(target_direction) >= minimum_dot
