extends RefCounted
class_name EnemyGPUTransforms

## All methods below execute on the main rendering device's render thread.
signal failed
var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _inputs: Dictionary = {}
var _released: bool = false
var _failed: bool = false
var _positions: RID
var _headings: RID
var _position_bytes: int = 0


func dispatch(batches: Array, positions: PackedByteArray, headings: PackedByteArray) -> void:
	if _released or _failed:
		return
	if _rd == null:
		_rd = RenderingServer.get_rendering_device()
		if _rd == null:
			return
		var source := load("res://src/assets/shaders/enemy_transforms.glsl") as RDShaderFile
		if source == null:
			_fail("Enemy transform shader is unavailable; switching to CPU rendering.")
			return
		_shader = _rd.shader_create_from_spirv(source.get_spirv())
		if not _shader.is_valid():
			_fail("Enemy transform shader creation failed; switching to CPU rendering.")
			return
		_pipeline = _rd.compute_pipeline_create(_shader)
		if not _pipeline.is_valid():
			_fail("Enemy compute pipeline creation failed; switching to CPU rendering.")
			return
	if positions.size() != _position_bytes:
		for buffers: Dictionary in _inputs.values():
			_free_input(buffers)
		_inputs.clear()
		if _positions.is_valid():
			_rd.free_rid(_positions)
			_rd.free_rid(_headings)
		_positions = _rd.storage_buffer_create(positions.size())
		_headings = _rd.storage_buffer_create(headings.size())
		_position_bytes = positions.size()
	_rd.buffer_update(_positions, 0, positions.size(), positions)
	_rd.buffer_update(_headings, 0, headings.size(), headings)
	for batch: Dictionary in batches:
		var mm: MultiMesh = batch.multimesh
		var target := RenderingServer.multimesh_get_buffer_rd_rid(mm.get_rid())
		if not target.is_valid():
			continue
		var key := mm.get_rid()
		var bytes: PackedByteArray = batch.slots
		var allocation := mm.instance_count * 4
		if _inputs.has(key):
			var previous: Dictionary = _inputs[key]
			if previous.size != allocation or previous.target != target:
				_free_input(previous)
				_inputs.erase(key)
		if not _inputs.has(key):
			var input := _rd.storage_buffer_create(allocation)
			var input_uniform := RDUniform.new()
			input_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			input_uniform.binding = 0
			input_uniform.add_id(input)
			var output_uniform := RDUniform.new()
			output_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			output_uniform.binding = 1
			output_uniform.add_id(target)
			var position_uniform := RDUniform.new()
			position_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			position_uniform.binding = 2
			position_uniform.add_id(_positions)
			var heading_uniform := RDUniform.new()
			heading_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			heading_uniform.binding = 3
			heading_uniform.add_id(_headings)
			var uniforms := _rd.uniform_set_create([input_uniform, output_uniform, position_uniform, heading_uniform], _shader, 0)
			_inputs[key] = {"input": input, "uniforms": uniforms, "size": allocation, "target": target}
		var buffers: Dictionary = _inputs[key]
		_rd.buffer_update(buffers.input, 0, bytes.size(), bytes)
		var parameters := PackedFloat32Array()
		parameters.resize(16)
		EnemyMultiMeshRenderer.write_transform(parameters, 0, batch.local)
		var push := parameters.to_byte_array()
		push.encode_u32(48, batch.count)
		push.encode_u32(52, int(batch.get("tumble", false)))
		var list := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(list, _pipeline)
		_rd.compute_list_bind_uniform_set(list, buffers.uniforms, 0)
		_rd.compute_list_set_push_constant(list, push, push.size())
		_rd.compute_list_dispatch(list, (int(batch.count) + 255) / 256, 1, 1)
		_rd.compute_list_end()


func _fail(message: String) -> void:
	_failed = true
	push_warning(message)
	failed.emit()


func _free_input(buffers: Dictionary) -> void:
	if _rd.uniform_set_is_valid(buffers.uniforms):
		_rd.free_rid(buffers.uniforms)
	_rd.free_rid(buffers.input)


func release() -> void:
	_released = true
	if _rd == null:
		return
	for buffers: Dictionary in _inputs.values():
		_free_input(buffers)
	_inputs.clear()
	if _positions.is_valid():
		_rd.free_rid(_positions)
		_rd.free_rid(_headings)
	if _pipeline.is_valid():
		_rd.free_rid(_pipeline)
	if _shader.is_valid():
		_rd.free_rid(_shader)
