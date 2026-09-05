extends MultiMeshInstance3D
class_name EnemyProjectileRenderer

@export var combat: EnemyCombat
var _buffer := PackedFloat32Array()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	var mesh := SphereMesh.new()
	mesh.radius = 2.5
	mesh.height = 5.0
	mesh.radial_segments = 6
	mesh.rings = 2
	var material := ShaderMaterial.new()
	var projectile_shader := Shader.new()
	projectile_shader.code = """
shader_type spatial;
render_mode unshaded;

void fragment() {
	ALBEDO = COLOR.rgb;
	float ally = step(0.9, COLOR.g) * (1.0 - step(0.9, COLOR.r));
	EMISSION = COLOR.rgb * ally * 3.0;
}
"""
	material.shader = projectile_shader
	var outline := StandardMaterial3D.new()
	outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline.albedo_color = Color.BLACK
	outline.cull_mode = BaseMaterial3D.CULL_FRONT
	outline.grow = true
	outline.grow_amount = 0.8
	material.next_pass = outline
	mesh.material = material
	multimesh.mesh = mesh
	multimesh.custom_aabb = AABB(Vector3(-4096, -512, -4096), Vector3(8192, 1024, 8192))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(_delta: float) -> void:
	if not is_instance_valid(combat):
		return
	if multimesh.instance_count < combat.shot_positions.size():
		multimesh.instance_count = combat.shot_positions.size()
		_buffer.resize(multimesh.instance_count * 16)
	if combat is EnemyGPUCombat:
		multimesh.visible_instance_count = multimesh.instance_count
		var batch := {"multimesh": multimesh, "slots": PackedByteArray(), "count": multimesh.instance_count,
			"local": Transform3D.IDENTITY, "projectile": true}
		RenderingServer.call_on_render_thread(combat.backend.render.bind([batch], combat.epoch))
		return
	multimesh.visible_instance_count = combat.shot_count
	if combat.shot_count == 0:
		return
	for i in range(combat.shot_count):
		var debris := combat.shot_kinds[i] == 1
		var ally := combat.shot_teams[i] == DamageSystem.Team.ALLY
		var visual_scale := 3.2 if debris else (3.0 if ally else 1.0)
		EnemyMultiMeshRenderer.write_transform(_buffer, i * 16, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * visual_scale), combat.shot_positions[i] + Vector3(0, 8, 0)))
		_buffer[i * 16 + 12] = 1.0 if debris else (0.2 if ally else 1.0)
		_buffer[i * 16 + 13] = 0.6 if debris else (1.0 if ally else 0.2)
		_buffer[i * 16 + 14] = 0.1 if debris else (0.8 if ally else 0.1)
		_buffer[i * 16 + 15] = 1.0
	multimesh.buffer = _buffer
