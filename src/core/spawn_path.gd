# res://src/core/spawn_path.gd
@tool
extends Path2D
class_name SpawnPath

const GENERIC_SPAWNER_GROUP: String = "spawn_point"

@export var circle_radius: float = 650.0:
	set(value):
		circle_radius = value
		if Engine.is_editor_hint():
			_generate_circle()
			_rebuild_spawners()

@export var spawner_count: int = 40:
	set(value):
		spawner_count = value
		if Engine.is_editor_hint():
			_rebuild_spawners()

## Legacy editor category. Every point is also registered in the generic pool.
@export_enum("asteroid_spawner", "enemy_spawner") var spawner_group: String = "asteroid_spawner":
	set(value):
		spawner_group = value
		if Engine.is_editor_hint():
			_rebuild_spawners()

func _ready() -> void:
	if not curve or curve.get_point_count() == 0:
		_generate_circle()
	if get_child_count() == 0 or Engine.is_editor_hint():
		_rebuild_spawners()
	else:
		_register_existing_spawners()

func _register_existing_spawners() -> void:
	for child in get_children():
		if child is PathFollow2D:
			for sub_child in child.get_children():
				if sub_child is Node2D and sub_child.name.begins_with("SpawnerPoint_"):
					sub_child.add_to_group(GENERIC_SPAWNER_GROUP)
					if not spawner_group.is_empty():
						sub_child.add_to_group(spawner_group)

func _generate_circle() -> void:
	var new_curve = Curve2D.new()
	var points = 16
	var handle_length = circle_radius * (4.0 / 3.0) * tan(PI / (2.0 * points))
	for i in range(points):
		var angle = (i * TAU) / points
		var pos = Vector2.RIGHT.rotated(angle) * circle_radius
		var tangent = Vector2.UP.rotated(angle)
		new_curve.add_point(pos, -tangent * handle_length, tangent * handle_length)
	new_curve.add_point(new_curve.get_point_position(0), new_curve.get_point_in(0), new_curve.get_point_out(0))
	curve = new_curve

func _rebuild_spawners() -> void:
	if not is_inside_tree():
		return
		
	# Clean up old child PathFollow2D nodes safely
	for child in get_children():
		if child is PathFollow2D:
			remove_child(child)
			child.queue_free()
			
	if not curve or spawner_count <= 0:
		return
		
	var root = get_tree().edited_scene_root if is_inside_tree() else null
	
	for i in range(spawner_count):
		var ratio = float(i) / float(spawner_count)
		
		# Create PathFollower to handle spacing
		var pf = PathFollow2D.new()
		pf.rotates = false
		add_child(pf)
		pf.progress_ratio = ratio
		if root and root.is_inside_tree():
			pf.owner = root
			
		# Create a plain marker Node2D
		var spawner = Node2D.new()
		spawner.name = "SpawnerPoint_" + str(i)
		spawner.add_to_group(GENERIC_SPAWNER_GROUP)
		if not spawner_group.is_empty():
			spawner.add_to_group(spawner_group) # Register in the group so spawner.gd finds it
		pf.add_child(spawner)
		if root and root.is_inside_tree():
			spawner.owner = root
			
	if Engine.is_editor_hint():
		queue_redraw()

func _draw() -> void:
	if Engine.is_editor_hint():
		var center = -global_position
		# Draw planet core (radius 40.0) in semi-transparent blue
		draw_circle(center, 40.0, Color(0.1, 0.4, 0.8, 0.2))
		draw_arc(center, 40.0, 0.0, TAU, 64, Color(0.1, 0.4, 0.8, 0.6), 2.0)
		
		# Draw atmosphere/shield boundary (radius 50.0)
		draw_arc(center, 50.0, 0.0, TAU, 64, Color(0.0, 0.8, 1.0, 0.3), 1.5)
