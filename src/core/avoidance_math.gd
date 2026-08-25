class_name AvoidanceMath
extends RefCounted

## Returns the normalized position of the closest point on the segment when
## the segment overlaps the circle. A negative result means no overlap.
static func segment_circle_hit_fraction(
	segment_start: Vector2,
	segment_end: Vector2,
	circle_center: Vector2,
	circle_radius: float
) -> float:
	var segment: Vector2 = segment_end - segment_start
	var segment_length_squared: float = segment.length_squared()
	if segment_length_squared <= 0.000001:
		return 0.0 if segment_start.distance_squared_to(circle_center) <= circle_radius * circle_radius else -1.0

	var closest_fraction: float = clampf(
		(circle_center - segment_start).dot(segment) / segment_length_squared,
		0.0,
		1.0
	)
	var closest_point: Vector2 = segment_start + segment * closest_fraction
	if closest_point.distance_squared_to(circle_center) > circle_radius * circle_radius:
		return -1.0
	return closest_fraction


## Chooses the side that moves away from an off-center obstacle. When the
## obstacle is exactly in front, the stable seed splits the swarm over both sides.
static func choose_side(
	position: Vector2,
	target: Vector2,
	obstacle_center: Vector2,
	stable_seed: int
) -> float:
	var target_direction: Vector2 = (target - position).normalized()
	var obstacle_direction: Vector2 = obstacle_center - position
	var cross_value: float = target_direction.cross(obstacle_direction)
	if absf(cross_value) > 0.001:
		return 1.0 if cross_value > 0.0 else -1.0
	return 1.0 if stable_seed % 2 == 0 else -1.0


## Produces a tangent direction around an inflated circular obstacle. The
## outward correction prevents a smoothly turning actor from cutting inside it.
static func circle_avoidance_direction(
	position: Vector2,
	target: Vector2,
	obstacle_center: Vector2,
	safe_radius: float,
	side: float
) -> Vector2:
	var target_direction: Vector2 = (target - position).normalized()
	if target_direction.is_zero_approx():
		return Vector2.ZERO

	var radial: Vector2 = position - obstacle_center
	var radial_distance: float = radial.length()
	if radial_distance <= 0.001:
		radial = -target_direction
		radial_distance = 1.0
	var radial_direction: Vector2 = radial / radial_distance
	var tangent_direction := Vector2(-radial_direction.y, radial_direction.x) * side

	var correction_band: float = maxf(18.0, safe_radius * 0.35)
	var outward_weight: float = clampf(
		(safe_radius + 18.0 - radial_distance) / correction_band,
		0.0,
		1.0
	) * 2.5
	var target_weight: float = clampf(
		(radial_distance - safe_radius) / maxf(safe_radius * 1.5, 0.001),
		0.0,
		0.35
	)

	return (
		tangent_direction
		+ radial_direction * outward_weight
		+ target_direction * target_weight
	).normalized()
