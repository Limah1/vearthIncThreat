extends Node3D
class_name GridBoard

@export var config: GridPrototypeConfig
@export var grid_color: Color = Color(0.18, 0.62, 0.82, 0.55)
@export var blocked_color: Color = Color(0.85, 0.22, 0.22, 0.22)

var occupied_cells: Dictionary = {}
var cells_by_occupant: Dictionary = {}
var highlight_cell: Vector2i = Vector2i(-1, -1)

var _highlight_meshes: Array[MeshInstance3D] = []
var _highlight_material: StandardMaterial3D = null
var _blocked_root: Node3D = null

func _ready() -> void:
	_build_grid_visual()
	_build_blocked_visuals()
	_build_highlight_visual()

func is_cell_inside(cell: Vector2i) -> bool:
	return is_instance_valid(config) and config.is_cell_inside(cell)

func is_cell_available(cell: Vector2i, ignored_occupant: Node = null) -> bool:
	if not is_cell_inside(cell) or config.is_cell_blocked(cell):
		return false
	var occupant: Node = occupied_cells.get(cell) as Node
	return not is_instance_valid(occupant) or occupant == ignored_occupant

func are_cells_available(cells: Array[Vector2i], ignored_occupant: Node = null) -> bool:
	if cells.is_empty():
		return false
	for cell in cells:
		if not is_cell_available(cell, ignored_occupant):
			return false
	return true

func occupy_cell(cell: Vector2i, occupant: Node) -> bool:
	var cells: Array[Vector2i] = [cell]
	return occupy_cells(cells, occupant)

func occupy_cells(cells: Array[Vector2i], occupant: Node) -> bool:
	if not is_instance_valid(occupant) or not are_cells_available(cells, occupant):
		return false
	release_occupant(occupant)
	var stored_cells: Array[Vector2i] = cells.duplicate()
	for cell in stored_cells:
		occupied_cells[cell] = occupant
	cells_by_occupant[occupant] = stored_cells
	return true

func release_occupant(occupant: Node) -> void:
	if not cells_by_occupant.has(occupant):
		return
	var cells: Array = cells_by_occupant[occupant]
	for cell_variant in cells:
		var cell: Vector2i = cell_variant
		if occupied_cells.get(cell) == occupant:
			occupied_cells.erase(cell)
	cells_by_occupant.erase(occupant)

func get_occupant_cell(occupant: Node) -> Vector2i:
	var cells: Array = cells_by_occupant.get(occupant, [])
	return cells[0] as Vector2i if not cells.is_empty() else Vector2i(-1, -1)

func get_occupant_cells(occupant: Node) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var stored_cells: Array = cells_by_occupant.get(occupant, [])
	for cell_variant in stored_cells:
		result.append(cell_variant as Vector2i)
	return result

func clear_occupancy() -> void:
	occupied_cells.clear()
	cells_by_occupant.clear()

func cell_to_world(cell: Vector2i) -> Vector3:
	if not is_instance_valid(config):
		return Vector3.ZERO
	var half_width: float = float(config.columns) * config.cell_size * 0.5
	var half_height: float = float(config.rows) * config.cell_size * 0.5
	return Vector3(
		config.world_origin.x - half_width + (float(cell.x) + 0.5) * config.cell_size,
		0.0,
		config.world_origin.y - half_height + (float(cell.y) + 0.5) * config.cell_size
	)

func world_to_cell(world_position: Vector3) -> Vector2i:
	if not is_instance_valid(config) or config.cell_size <= 0.0:
		return Vector2i(-1, -1)
	var half_width: float = float(config.columns) * config.cell_size * 0.5
	var half_height: float = float(config.rows) * config.cell_size * 0.5
	return Vector2i(
		floori((world_position.x - config.world_origin.x + half_width) / config.cell_size),
		floori((world_position.z - config.world_origin.y + half_height) / config.cell_size)
	)

func set_highlight(cell: Vector2i, valid: bool, selected: bool = false) -> void:
	var cells: Array[Vector2i] = [cell]
	set_highlight_cells(cells, valid, selected)

func set_highlight_cells(cells: Array[Vector2i], valid: bool, selected: bool = false) -> void:
	highlight_cell = cells[0] if not cells.is_empty() else Vector2i(-1, -1)
	if selected:
		_highlight_material.albedo_color = Color(1.0, 0.72, 0.18, 0.34)
	elif valid:
		_highlight_material.albedo_color = Color(0.2, 0.95, 0.48, 0.30)
	else:
		_highlight_material.albedo_color = Color(0.95, 0.18, 0.18, 0.34)
	_ensure_highlight_mesh_count(cells.size())
	for index in range(_highlight_meshes.size()):
		var highlight_mesh: MeshInstance3D = _highlight_meshes[index]
		var should_show: bool = index < cells.size() and is_cell_inside(cells[index])
		highlight_mesh.visible = should_show
		if should_show:
			highlight_mesh.global_position = cell_to_world(cells[index]) + Vector3(0.0, 0.35, 0.0)

func clear_highlight() -> void:
	highlight_cell = Vector2i(-1, -1)
	for highlight_mesh in _highlight_meshes:
		if is_instance_valid(highlight_mesh):
			highlight_mesh.visible = false

func _build_grid_visual() -> void:
	if not is_instance_valid(config):
		return
	var immediate_mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = grid_color
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)

	var half_width: float = float(config.columns) * config.cell_size * 0.5
	var half_height: float = float(config.rows) * config.cell_size * 0.5
	var minimum_x: float = config.world_origin.x - half_width
	var maximum_x: float = config.world_origin.x + half_width
	var minimum_z: float = config.world_origin.y - half_height
	var maximum_z: float = config.world_origin.y + half_height
	for column in range(config.columns + 1):
		var x: float = minimum_x + float(column) * config.cell_size
		immediate_mesh.surface_add_vertex(Vector3(x, 0.15, minimum_z))
		immediate_mesh.surface_add_vertex(Vector3(x, 0.15, maximum_z))
	for row in range(config.rows + 1):
		var z: float = minimum_z + float(row) * config.cell_size
		immediate_mesh.surface_add_vertex(Vector3(minimum_x, 0.15, z))
		immediate_mesh.surface_add_vertex(Vector3(maximum_x, 0.15, z))
	immediate_mesh.surface_end()

	var grid_mesh := MeshInstance3D.new()
	grid_mesh.name = "GridLines"
	grid_mesh.mesh = immediate_mesh
	grid_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(grid_mesh)

func _build_blocked_visuals() -> void:
	if not is_instance_valid(config):
		return
	_blocked_root = Node3D.new()
	_blocked_root.name = "BlockedCells"
	add_child(_blocked_root)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = blocked_color
	for blocked_cell in config.blocked_cells:
		if not config.is_cell_inside(blocked_cell):
			continue
		var plane_mesh := PlaneMesh.new()
		plane_mesh.size = Vector2(config.cell_size * 0.94, config.cell_size * 0.94)
		plane_mesh.material = material
		var cell_visual := MeshInstance3D.new()
		cell_visual.mesh = plane_mesh
		cell_visual.position = cell_to_world(blocked_cell) + Vector3(0.0, 0.1, 0.0)
		cell_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_blocked_root.add_child(cell_visual)

func _build_highlight_visual() -> void:
	if not is_instance_valid(config):
		return
	_highlight_material = StandardMaterial3D.new()
	_highlight_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_highlight_material.albedo_color = Color(0.2, 0.95, 0.48, 0.30)
	_ensure_highlight_mesh_count(2)
	clear_highlight()

func _ensure_highlight_mesh_count(required_count: int) -> void:
	if not is_instance_valid(config):
		return
	while _highlight_meshes.size() < required_count:
		var plane_mesh := PlaneMesh.new()
		plane_mesh.size = Vector2(config.cell_size * 0.92, config.cell_size * 0.92)
		plane_mesh.material = _highlight_material
		var highlight_mesh := MeshInstance3D.new()
		highlight_mesh.name = "CellHighlight%d" % _highlight_meshes.size()
		highlight_mesh.mesh = plane_mesh
		highlight_mesh.visible = false
		highlight_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(highlight_mesh)
		_highlight_meshes.append(highlight_mesh)
