# res://src/entities/space_garbage_instance.gd
extends Node3D
class_name SpaceGarbageInstance

@export var base_speed: float = 30.0 # --- VELOCIDADE DE MOVIMENTO
@export var base_value: float = 1.0 # --- CRÉDITOS NA DESTRUIÇÃO PELO JOGADOR
@export var base_planet_damage: float = 1.0 # --- DANO AO COLIDIR NO PLANETA
@export var base_hp: float = 3.0 # --- VIDA INICIAL

var current_move_speed: float = 30.0
var current_value: float = 10.0
var planet_damage: float = 10.0

var slowdown_timer: float = 0.0
var killed_by_player: bool = false
var is_quality: bool = false

@export_group("Physics & Visual Behavior")
@export var rotation_speed: float = -1.6
@export var radius: float = 18.0

var max_hp: float = 3.0
var hp: float = 3.0
var active: bool = false
var pool_type: String = "garbage"
var master_node: Node = null
var movement_direction: Vector3 = Vector3.ZERO

# --- Cache de PlayerPlanet: evita find_child() todo frame
var _planet_ref: Node = null

# --- Scale animation via lerp (sem Tween allocation)
var _scale_timer: float = 0.0
const _SCALE_DURATION: float = 1.0
var _target_scale: float = 1.0



# --- Directions estáticas: sem alloc nem shuffle no Vector3 array ---------
static var _DIRECTIONS: Array[Vector3] = [
	Vector3(0, 0, -1),
	Vector3(0, 0, 1),
	Vector3(1, 0, 0),
	Vector3(-1, 0, 0),
	Vector3(1, 0, -1).normalized(),
	Vector3(-1, 0, 1).normalized(),
	Vector3(-1, 0, -1).normalized(),
	Vector3(1, 0, 1).normalized(),
	Vector3(0.5, 0, -1).normalized(),
	Vector3(1, 0, -0.5).normalized(),
	Vector3(1, 0, 0.5).normalized(),
	Vector3(0.5, 0, 1).normalized(),
	Vector3(-0.5, 0, 1).normalized(),
	Vector3(-1, 0, 0.5).normalized(),
	Vector3(-1, 0, -0.5).normalized(),
	Vector3(-0.5, 0, -1).normalized()
]
# Índices shuffleados in-place para selecionar direções aleatórias por morte
static var _dir_indices: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
# -------------------------------------------------------------------------

func _ready() -> void:
	add_to_group("garbage")
	# NÃO adicionar "damageable" aqui — grupo dinâmico p/ não poluir o spatial grid

func on_pool_activate(spawn_pos_3d: Vector3) -> void:
	global_position = spawn_pos_3d
	killed_by_player = false
	slowdown_timer = 0.0
	current_move_speed = base_speed
	active = true
	visible = true
	GameManager.register_active_damageable(self)

	# Calcular direção linear ao centro
	var dir = (Vector3.ZERO - spawn_pos_3d)
	dir.y = 0.0
	movement_direction = dir.normalized()

	# Orientar ao centro
	global_rotation.y = - Vector2(movement_direction.x, movement_direction.z).angle()

	# Resetar rotação do mesh filho
	if get_child_count() > 0:
		get_child(0).rotation = Vector3.ZERO

	# Determinar qualidade
	is_quality = false
	var quality_lvl = UpgradeManager.get_upgrade_level("GarbageQuality")
	if quality_lvl > 0:
		is_quality = randf() < 0.20

	# Calcular multiplicadores
	var hp_mult = 1.0
	var value_mult = 1.0
	var scale_mult = 1.0

	var massify_lvl = UpgradeManager.get_upgrade_level("massify")
	if massify_lvl > 0:
		hp_mult *= 2.0
		value_mult *= 2.0
		planet_damage = base_planet_damage * 2.0
		scale_mult *= 1.6
	else:
		planet_damage = base_planet_damage

	if is_quality:
		hp_mult *= 2.0
		value_mult *= 2.0
		scale_mult *= 1.5

	max_hp = base_hp * hp_mult
	hp = max_hp
	current_value = base_value * value_mult

	# Iniciar animação de scale via lerp (sem Tween)
	_target_scale = scale_mult
	_scale_timer = 0.0
	scale = Vector3.ONE * 0.2

	# Cache do planeta (só busca se inválida)
	if not is_instance_valid(_planet_ref):
		_planet_ref = get_tree().current_scene.find_child("PlayerPlanet", true, false)

func on_pool_deactivate() -> void:
	active = false
	visible = false
	GameManager.unregister_active_damageable(self)

func take_damage(amount: float) -> void:
	if not active:
		return
	slowdown_timer = 0.4
	hp -= amount

	var damage_text = str(int(round(amount)))
	if is_quality:
		damage_text += " HQ"
	var popup_color = Color(1.0, 0.85, 0.0) if is_quality else Color(1.0, 1.0, 1.0)
	GameManager.spawn_popup_3d(damage_text, popup_color, global_position)

	if hp <= 0.0:
		die()

func take_player_damage(amount: float) -> void:
	killed_by_player = true
	take_damage(amount)

func _physics_process(delta: float) -> void:
	if not is_inside_tree() or not active:
		return

	# --- Animação de scale via lerp (sem Tween) ---
	if _scale_timer < _SCALE_DURATION:
		_scale_timer += delta
		var t = _scale_timer / _SCALE_DURATION
		# Simular EASE_OUT_QUAD: t = 1 - (1-t)^2
		t = 1.0 - (1.0 - t) * (1.0 - t)
		scale = Vector3.ONE * lerp(0.2, _target_scale, t)

	# --- Slowdown decay ---
	var speed = base_speed
	if slowdown_timer > 0.0:
		slowdown_timer -= delta
		speed = base_speed * 0.8
	current_move_speed = speed

	# --- Movimento linear ---
	global_position += movement_direction * current_move_speed * delta

	# --- Tumble do mesh filho ---
	if get_child_count() > 0:
		get_child(0).rotate_object_local(Vector3.RIGHT, rotation_speed * delta)

	# --- Colisão com planeta (cacheado) ---
	if global_position.length() < 45.0:
		if is_instance_valid(_planet_ref):
			_planet_ref.take_damage(planet_damage)
		killed_by_player = false
		die()

func stop_movement() -> void:
	current_move_speed = 0.0
	base_speed = 0.0

func die() -> void:
	active = false
	_on_death()
	if master_node and master_node.has_method("return_to_pool"):
		master_node.return_to_pool(self)
	else:
		queue_free()

func _on_death() -> void:
	if killed_by_player:
		GameManager.add_credits_delayed(current_value, global_position)
		GameManager.register_eliminated_threat()

		# Roll de chance de debris
		var roll_chance = GameManager.debris_chance
		var roll_success = randf() < roll_chance

		if "b_next_debris_guaranteed" in UpgradeManager and UpgradeManager.get("b_next_debris_guaranteed") == true:
			roll_success = true
			UpgradeManager.set("b_next_debris_guaranteed", false)

		if roll_success:
			_spawn_debris_burst()
			GameManager.debris_chance = 1.0

## Ativa debris em burst — borrow direto do DebrisMaster
func _spawn_debris_burst() -> void:
	var debris_master = get_tree().get_first_node_in_group("debris_master")
	if not debris_master:
		return

	# Quantidade de debris: responsabilidade do garbage (DebrisAmount upgrade)
	var extra_debris = int(UpgradeManager.get_total_bonus("DebrisAmount"))
	var count = clamp(2 + extra_debris, 1, 16)

	# Shufflear índices de direção (Fisher-Yates parcial — sem alocar novo array)
	for i in range(count):
		var j = randi_range(i, _DIRECTIONS.size() - 1)
		var tmp = _dir_indices[i]
		_dir_indices[i] = _dir_indices[j]
		_dir_indices[j] = tmp

	for i in range(count):
		var dir = _DIRECTIONS[_dir_indices[i]]
		var random_variation = Vector3(randf_range(-0.15, 0.15), 0.0, randf_range(-0.15, 0.15))
		debris_master.spawn_debris(global_position, (dir + random_variation).normalized())
