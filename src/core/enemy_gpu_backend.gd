extends RefCounted
class_name EnemyGPUBackend

## Main RenderingDevice owner. Call methods through call_on_render_thread only.
signal report_ready(bytes: PackedByteArray, epoch: int)
signal diagnostic_ready(bytes: PackedByteArray, epoch: int)
signal failed(message: String)
const MAX_COMMANDS := 4096
const MAX_ARCHETYPES := 64
const MAX_OBSTACLES := 128
const MAX_QUERIES := 256
const MAX_EVENTS := 2048
const MAX_FEEDBACK := 128
const MAX_PROJECTILE_HITS := 16
const GRID_SIDE := 128
const QUERY_OFFSET := (4 + MAX_OBSTACLES) * 4
const EVENT_OFFSET := QUERY_OFFSET + MAX_QUERIES * 32
const FEEDBACK_OFFSET := EVENT_OFFSET + MAX_EVENTS * 32
const REPORT_BYTES := FEEDBACK_OFFSET + 16 + MAX_FEEDBACK * 32
var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _uniforms: RID
var _render_shader: RID
var _render_pipeline: RID
var _buffers: Array[RID] = []
var _render_inputs: Dictionary = {}
var _capacity: int = 0
var _shot_capacity: int = 0
var _epoch: int = -1
var _tick: int = 0
var _simulation_time: float = 0.0
var _readback_inflight: bool = false
var _released: bool = false
var _failed: bool = false


func _initialize(capacity: int, shot_capacity: int) -> bool:
	if _rd != null:
		return not _failed
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		_fail("Authoritative enemy simulation requires a RenderingDevice.")
		return false
	_capacity = capacity
	_shot_capacity = shot_capacity
	var source := load("res://src/assets/shaders/enemy_sim.glsl") as RDShaderFile
	var render_source := load("res://src/assets/shaders/enemy_sim_render.glsl") as RDShaderFile
	if source == null or render_source == null:
		_fail("GPU enemy shader resource is missing.")
		return false
	_shader = _rd.shader_create_from_spirv(source.get_spirv())
	_render_shader = _rd.shader_create_from_spirv(render_source.get_spirv())
	if not _shader.is_valid() or not _render_shader.is_valid():
		_fail("GPU enemy shader compilation failed.")
		return false
	_pipeline = _rd.compute_pipeline_create(_shader)
	_render_pipeline = _rd.compute_pipeline_create(_render_shader)
	if not _pipeline.is_valid() or not _render_pipeline.is_valid():
		_fail("GPU enemy pipeline creation failed.")
		return false
	var sizes := [_capacity * 64, MAX_ARCHETYPES * 48, MAX_OBSTACLES * 48, MAX_OBSTACLES * 8,
		_shot_capacity * 48, (GRID_SIDE * GRID_SIDE + _capacity) * 4, MAX_COMMANDS * 64,
		MAX_QUERIES * 48, MAX_QUERIES * 32, (16 + _shot_capacity) * 4, REPORT_BYTES,
		_capacity * 8, _shot_capacity * MAX_PROJECTILE_HITS * 8, _capacity * 8]
	var bindings: Array[RDUniform] = []
	for i in range(sizes.size()):
		var buffer := _rd.storage_buffer_create(sizes[i])
		_buffers.append(buffer)
		bindings.append(_binding(i, buffer))
	_uniforms = _rd.uniform_set_create(bindings, _shader, 0)
	if not _uniforms.is_valid():
		_fail("GPU enemy uniform set creation failed.")
		return false
	reset(_epoch)
	return true


static func _binding(index: int, rid: RID) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = index
	uniform.add_id(rid)
	return uniform


func reset(epoch: int) -> void:
	_epoch = epoch
	_tick = 0
	_simulation_time = 0
	_readback_inflight = false
	if _buffers.is_empty():
		return
	for index in [0, 3, 4, 8, 9, 10, 11, 12]:
		var size: int = [_capacity * 64, 0, 0, MAX_OBSTACLES * 8, _shot_capacity * 48, 0, 0, 0,
			MAX_QUERIES * 32, (16 + _shot_capacity) * 4, REPORT_BYTES, _capacity * 8, _shot_capacity * MAX_PROJECTILE_HITS * 8][index]
		_rd.buffer_clear(_buffers[index], 0, size)
	var control := PackedInt32Array()
	control.resize(16 + _shot_capacity)
	control[2] = _shot_capacity
	for i in range(_shot_capacity):
		control[16 + i] = i
	_rd.buffer_update(_buffers[9], 0, control.size() * 4, control.to_byte_array())


func advance(packet: Dictionary) -> void:
	if _released or _failed or not _initialize(packet.capacity, packet.shot_capacity):
		return
	if packet.epoch != _epoch:
		reset(packet.epoch)
	for pair in [[1, "archetypes"], [2, "obstacles"], [6, "commands"], [7, "queries"]]:
		var bytes: PackedByteArray = packet[pair[1]]
		if not bytes.is_empty():
			_rd.buffer_update(_buffers[pair[0]], 0, bytes.size(), bytes)
	var push := PackedByteArray()
	push.resize(80)
	push.encode_u32(4, _capacity)
	push.encode_u32(8, _shot_capacity)
	push.encode_u32(12, packet.command_count)
	push.encode_u32(16, packet.obstacle_count)
	push.encode_u32(20, packet.query_count)
	push.encode_u32(24, GRID_SIDE)
	push.encode_float(28, packet.cell_size)
	push.encode_float(32, packet.planet.x)
	push.encode_float(36, packet.planet.y)
	push.encode_float(40, packet.planet.z)
	push.encode_float(44, packet.planet_radius)
	push.encode_float(48, packet.delta)
	push.encode_float(52, packet.max_radius)
	push.encode_u32(56, packet.epoch)
	_simulation_time += float(packet.delta)
	push.encode_float(60, _simulation_time)
	push.encode_float(64, float(packet.get("separation_speed", 120.0)))
	push.encode_float(68, float(packet.get("separation_padding", 2.0)))
	var counts := [1, GRID_SIDE * GRID_SIDE, _capacity, _capacity, packet.command_count, _shot_capacity,
		_capacity, packet.query_count, 0, _capacity, _capacity, GRID_SIDE * GRID_SIDE]
	var passes := [0, 1, 2, 3, 4, 5, 6, 7]
	if bool(packet.get("separation", false)) and float(packet.delta) > 0:
		passes = [0, 1, 2, 3, 9, 10, 11, 3, 4, 5, 6, 7]
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _pipeline)
	_rd.compute_list_bind_uniform_set(list, _uniforms, 0)
	for pass_id in passes:
		if int(counts[pass_id]) == 0:
			continue
		push.encode_u32(0, pass_id)
		_rd.compute_list_set_push_constant(list, push, push.size())
		_rd.compute_list_dispatch(list, (int(counts[pass_id]) + 255) / 256, 1, 1)
		_rd.compute_list_add_barrier(list)
	_rd.compute_list_end()
	_tick += 1
	if not _readback_inflight and (_tick % int(packet.report_interval) == 0 or bool(packet.force_report)):
		_rd.buffer_clear(_buffers[10], 0, REPORT_BYTES)
		push.encode_u32(0, 8)
		_dispatch(_pipeline, _uniforms, push, maxi(_capacity, MAX_QUERIES))
		_readback_inflight = true
		var error := _rd.buffer_get_data_async(_buffers[10], _receive_report.bind(_epoch), 0, REPORT_BYTES)
		if error != OK:
			_readback_inflight = false
			_fail("GPU enemy async report failed: %s" % error)


func _receive_report(bytes: PackedByteArray, epoch: int) -> void:
	if _released or epoch != _epoch:
		return
	_readback_inflight = false
	report_ready.emit(bytes, epoch)


## Explicit diagnostic only. Never requested by the production tick.
func read_diagnostic() -> void:
	if not _released and not _buffers.is_empty():
		_rd.buffer_get_data_async(_buffers[0], _receive_diagnostic.bind(_epoch))


func _receive_diagnostic(bytes: PackedByteArray, epoch: int) -> void:
	if not _released and epoch == _epoch:
		diagnostic_ready.emit(bytes, epoch)


func render(batches: Array, epoch: int) -> void:
	if _released or _failed or _buffers.is_empty() or epoch != _epoch:
		return
	for batch: Dictionary in batches:
		var mm: MultiMesh = batch.multimesh
		var target := RenderingServer.multimesh_get_buffer_rd_rid(mm.get_rid())
		if not target.is_valid():
			continue
		var key := mm.get_rid()
		var allocation := maxi(4, mm.instance_count * 4)
		if _render_inputs.has(key):
			var old: Dictionary = _render_inputs[key]
			if old.target != target or old.size != allocation:
				_free_render_input(old)
				_render_inputs.erase(key)
		if not _render_inputs.has(key):
			var input := _rd.storage_buffer_create(allocation)
			var uniforms := _rd.uniform_set_create([_binding(0, _buffers[0]), _binding(1, input),
				_binding(2, target), _binding(3, _buffers[4]), _binding(4, _buffers[11]), _binding(5, _buffers[1])], _render_shader, 0)
			_render_inputs[key] = {"input": input, "uniforms": uniforms, "target": target, "size": allocation}
		var buffers: Dictionary = _render_inputs[key]
		var slots: PackedByteArray = batch.slots
		if not slots.is_empty():
			_rd.buffer_update(buffers.input, 0, slots.size(), slots)
		var floats := PackedFloat32Array()
		floats.resize(16)
		EnemyMultiMeshRenderer.write_transform(floats, 0, batch.local)
		var push := floats.to_byte_array()
		push.encode_u32(48, batch.count)
		push.encode_u32(52, int(batch.get("projectile", false)))
		push.encode_float(56, _simulation_time)
		push.encode_u32(60, int(mm.use_colors))
		_dispatch(_render_pipeline, buffers.uniforms, push, batch.count)


func _dispatch(pipeline: RID, uniforms: RID, push: PackedByteArray, count: int) -> void:
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, pipeline)
	_rd.compute_list_bind_uniform_set(list, uniforms, 0)
	_rd.compute_list_set_push_constant(list, push, push.size())
	_rd.compute_list_dispatch(list, (count + 255) / 256, 1, 1)
	_rd.compute_list_end()


func _free_render_input(buffers: Dictionary) -> void:
	if _rd.uniform_set_is_valid(buffers.uniforms):
		_rd.free_rid(buffers.uniforms)
	_rd.free_rid(buffers.input)


func release() -> void:
	_released = true
	if _rd == null:
		return
	for input: Dictionary in _render_inputs.values():
		_free_render_input(input)
	_render_inputs.clear()
	if _uniforms.is_valid() and _rd.uniform_set_is_valid(_uniforms):
		_rd.free_rid(_uniforms)
	for buffer in _buffers:
		_rd.free_rid(buffer)
	_buffers.clear()
	for rid in [_pipeline, _render_pipeline, _shader, _render_shader]:
		if rid.is_valid():
			_rd.free_rid(rid)


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	failed.emit(message)
