extends MultiMeshInstance3D
class_name MassEnemyFeedback

## Cosmetic-only bounded pool. Saturation never discards damage or rewards.
const CAPACITY := 128
const DURATION := 0.35
const POPUPS_PER_FRAME := 8
var dropped_effects: int = 0
var _positions := PackedVector3Array()
var _ages := PackedFloat32Array()
var _colors := PackedColorArray()
var _buffer := PackedFloat32Array()
var _count: int = 0
var _popup_budget: int = POPUPS_PER_FRAME


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	var ring := TorusMesh.new()
	ring.inner_radius = 0.8
	ring.outer_radius = 1.0
	ring.rings = 12
	ring.ring_segments = 4
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	ring.material = material
	multimesh.mesh = ring
	multimesh.instance_count = CAPACITY
	multimesh.visible_instance_count = 0
	multimesh.custom_aabb = AABB(Vector3(-4096, -512, -4096), Vector3(8192, 1024, 8192))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_positions.resize(CAPACITY)
	_ages.resize(CAPACITY)
	_colors.resize(CAPACITY)
	_buffer.resize(CAPACITY * 16)
	GameManager.state_changed.connect(_on_state_changed)


func show_events(events: Array, world: EnemyWorld) -> void:
	for event: Dictionary in events:
		if event.kind == "hit":
			_popup("%d" % roundi(event.damage), Color.WHITE, event.position)
		elif event.kind == "death":
			var data := world.get_archetype(event.archetype)
			_popup("+$%d" % roundi(data.credit_value), Color.GREEN, event.position)
			_explosion(event.position, Color(1, 0.6, 0.1))
		elif event.kind == "impact":
			_explosion(event.position, Color(1, 0.15, 0.05))


func _popup(text: String, color: Color, at: Vector3) -> void:
	if _popup_budget <= 0:
		return
	_popup_budget -= 1
	GameManager.spawn_popup_3d(text, color, at)


func _explosion(at: Vector3, color: Color) -> void:
	if _count >= CAPACITY:
		dropped_effects += 1
		return
	_positions[_count] = at + Vector3(0, 12, 0)
	_colors[_count] = color
	_ages[_count] = 0
	_count += 1


func _process(delta: float) -> void:
	_popup_budget = POPUPS_PER_FRAME
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return
	for i in range(_count - 1, -1, -1):
		_ages[i] += delta
		if _ages[i] >= DURATION:
			_count -= 1
			_positions[i] = _positions[_count]
			_colors[i] = _colors[_count]
			_ages[i] = _ages[_count]
	for i in range(_count):
		var progress := _ages[i] / DURATION
		EnemyMultiMeshRenderer.write_transform(_buffer, i * 16, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * lerpf(3, 40, progress)), _positions[i]))
		var color := _colors[i]
		_buffer[i * 16 + 12] = color.r
		_buffer[i * 16 + 13] = color.g
		_buffer[i * 16 + 14] = color.b
		_buffer[i * 16 + 15] = 1.0 - progress
	multimesh.visible_instance_count = _count
	if _count > 0:
		multimesh.buffer = _buffer


func _on_state_changed(state: GameManager.GameState) -> void:
	if state in [GameManager.GameState.PREPARATION, GameManager.GameState.END_SESSION]:
		_count = 0
		multimesh.visible_instance_count = 0
