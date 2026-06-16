# res://src/entities/entity_2d.gd
class_name Entity2D
extends CharacterBody2D

# 3D Visual template and instance reference
@export var visual_3d_scene: PackedScene
var visual_3d: Node3D

@export var max_hp: float = 10.0
var hp: float = 10.0

var active: bool = false
var pool_type: String = "" # Set in child classes to identify pool type (e.g. "garbage", "asteroid")

# Called by ObjectPooler when borrowed
func on_pool_activate(spawn_pos_2d: Vector2, initial_velocity: Vector2) -> void:
	global_position = spawn_pos_2d
	velocity = initial_velocity
	hp = max_hp
	active = true
	visible = true
	add_to_group("damageable")
	
	if visual_3d:
		visual_3d.visible = true
		visual_3d.global_position = Vector3(spawn_pos_2d.x, 0.0, spawn_pos_2d.y)
		visual_3d.global_rotation = Vector3.ZERO
		if visual_3d.has_method("on_pool_activate"):
			visual_3d.on_pool_activate()

# Called by ObjectPooler when returned
func on_pool_deactivate() -> void:
	active = false
	visible = false
	velocity = Vector2.ZERO
	if is_in_group("damageable"):
		remove_from_group("damageable")
	
	if visual_3d:
		visual_3d.visible = false
		if visual_3d.has_method("on_pool_deactivate"):
			visual_3d.on_pool_deactivate()

func take_damage(amount: float) -> void:
	if not active:
		return
	
	hp -= amount
	
	if pool_type in ["garbage", "asteroid", "enemy"]:
		var damage_text = str(int(round(amount)))
		spawn_popup(damage_text, Color(1.0, 1.0, 1.0))
		
	if hp <= 0.0:
		die()

func spawn_popup(text: String, color: Color) -> void:
	if not visual_3d or not visual_3d.is_inside_tree():
		return
		
	var label = Label3D.new()
	label.text = text
	label.modulate = color
	label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	label.no_depth_test = true
	label.font_size = 48
	label.pixel_size = 1.0
	
	var world_3d = visual_3d.get_parent()
	if world_3d:
		world_3d.add_child(label)
		
		# Offset slightly on Y to float above gameplay plane, and randomize horizontal spread
		var offset = Vector3(randf_range(-15.0, 15.0), 3.0, randf_range(-15.0, 15.0))
		label.global_position = visual_3d.global_position + offset
		
		var tween = label.create_tween()
		tween.set_parallel(true)
		# Rise up along the screen-up axis (-Z in 3D)
		tween.tween_property(label, "global_position:z", label.global_position.z - 35.0, 0.7)
		# Fade out modulate.a
		tween.tween_property(label, "modulate:a", 0.0, 0.7)
		
		tween.set_parallel(false)
		tween.tween_callback(label.queue_free)

func die() -> void:
	if not active:
		return
	# Child classes override to give currency, spawn debris/bursts
	_on_death()
	# Return to pool
	if GameManager.object_pooler:
		GameManager.object_pooler.return_to_pool(pool_type, self)
	else:
		# Fallback if pooler not initialized or direct deletion
		queue_free()

func _on_death() -> void:
	pass

func _physics_process(_delta: float) -> void:
	if active and visual_3d:
		# Sync position to 3D X-Z plane
		visual_3d.global_position = Vector3(global_position.x, 0.0, global_position.y)
		# Sync rotation (2D rotation around Z maps to 3D rotation around Y)
		visual_3d.global_rotation.y = -global_rotation
