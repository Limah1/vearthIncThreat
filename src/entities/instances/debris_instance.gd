# res://src/entities/debris_instance.gd
extends Node3D
class_name DebrisInstance

@export var base_speed: float = 240.0 # --- VELOCIDADE DO DEBRIS (MAIS ALTO = MAIS RAPIDO)
@export var base_damage: float = 3.0 # --- DANO DO DEBRIS AOS INIMIGOS/LIXOS
@export var hit_radius: float = 20.0 # --- RAIO DE COLISÃO DO DEBRIS

var damage: float = 3.0
var max_pierce: int = 0
var current_pierce: int = 0

var hit_targets: Dictionary = {}
var active: bool = false
var pool_type: String = "debris"
var master_node: Node = null
var movement_direction: Vector3 = Vector3.ZERO


var lifetime_timer: float = 0.0

func _ready() -> void:
	add_to_group("debris")
	# NÃO adicionar "damageable" aqui — grupo é gerenciado dinamicamente em activate/deactivate
	# para evitar que 500 instâncias inativas sejam varridas pelo spatial grid todo frame

func on_pool_activate(spawn_pos_3d: Vector3, dir_3d: Vector3) -> void:
	activate_at(spawn_pos_3d, dir_3d)

func on_pool_deactivate() -> void:
	active = false
	visible = false

## Ativação de debris pre-slotted — chamado diretamente pelo SpaceGarbageInstance na morte
func activate_at(pos: Vector3, dir: Vector3) -> void:
	global_position = pos
	movement_direction = dir.normalized()
	current_pierce = 0
	lifetime_timer = 0.0
	hit_targets.clear()
	active = true
	visible = true

	# Upgrades de dano e pierce — responsabilidade do DebrisInstance
	var damage_mult = UpgradeManager.get_multiplier("DebrisDamage")
	damage = base_damage * damage_mult
	max_pierce = int(UpgradeManager.get_total_bonus("DebrisPiercing"))

	# Rotacionar para a direção de movimento
	if movement_direction.length_squared() > 0.01:
		global_rotation.y = - Vector2(movement_direction.x, movement_direction.z).angle()
	
	process_mode = Node.PROCESS_MODE_INHERIT

func take_damage(_amount: float) -> void:
	# Debris não recebe dano
	pass

func _physics_process(delta: float) -> void:
	if not is_inside_tree() or not active:
		return

	# Mover
	global_position += movement_direction * base_speed * delta

	# Checar tempo de vida (3 segundos)
	lifetime_timer += delta
	if lifetime_timer >= 3.0:
		_recycle()
		return

	# Sweep de dano: throttle a cada 2 physics frames (debris é rápido mas hit_radius grande)
	if Engine.get_physics_frames() % 2 == 0:
		_sweep_damage()

func _sweep_damage() -> void:
	var my_pos_2d = Vector2(global_position.x, global_position.z)
	var targets = GameManager.get_nearby_entities(global_position)

	for target in targets:
		if not is_instance_valid(target) or not target.active:
			continue
		if hit_targets.has(target):
			continue

		var target_pos_2d = target.global_position
		if target is Node3D:
			target_pos_2d = Vector2(target.global_position.x, target.global_position.z)

		var target_dist_sq = my_pos_2d.distance_squared_to(target_pos_2d)
		if target_dist_sq <= (hit_radius * hit_radius):
			if target.has_method("take_player_damage"):
				target.take_player_damage(damage)
			else:
				target.take_damage(damage)

			hit_targets[target] = true

			if current_pierce < max_pierce:
				current_pierce += 1
			else:
				_recycle()
				return

func _recycle() -> void:
	active = false
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	position = Vector3(99999.0, 0.0, 99999.0)
	hit_targets.clear()

	if master_node and master_node.has_method("return_to_pool"):
		master_node.return_to_pool(self)
