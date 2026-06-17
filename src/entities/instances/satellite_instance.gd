# res://src/entities/satellite_instance.gd
extends Node3D
class_name SatelliteInstance

@export var orbit_radius: float = 110.0 # --- DISTANCIA DA ORBITA EM RELAÇÃO AO CENTRO DO PLANETA
@export var fire_interval: float = 2.0 # --- INTERVALO DE TIRO DO SATELLITE (SEGUNDOS)
@export var base_orbit_speed: float = 0.5 # --- VELOCIDADE ROTACIONAL DA ORBITA
var orbit_speed: float = 0.5

var angle: float = 0.0
var fire_timer: float = 0.0
var active: bool = false
var pool_type: String = "satellite"
var master_node: Node = null

func _ready() -> void:
	add_to_group("satellites")
	
	# Set default subnode scale
	var body = find_child("Body", true, false)
	if body:
		body.scale = Vector3(25.0, 25.0, 25.0)
	var dish = find_child("Dish", true, false)
	if dish:
		dish.scale = Vector3(5.0, 5.0, 5.0)

func on_pool_activate() -> void:
	active = true
	visible = true
	_update_position()
	
	# Startup scale animation
	scale = Vector3(0.2, 0.2, 0.2)
	var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector3.ONE, 1.0)
	
	fire_timer = randf() * fire_interval

func on_pool_deactivate() -> void:
	active = false
	visible = false

func take_damage(_amount: float) -> void:
	# Satellites do not take damage
	pass

func set_orbit_angle(new_angle: float) -> void:
	angle = new_angle

func _physics_process(delta: float) -> void:
	if not is_inside_tree() or not active:
		return
		
	var game_mgr = get_node_or_null("/root/GameManager")
	if game_mgr and game_mgr.current_state == game_mgr.GameState.PLAYING:
		var upgrade_mgr = get_node_or_null("/root/UpgradeManager")
		if upgrade_mgr:
			var speed_mult = upgrade_mgr.get_multiplier("SatelliteSpeed")
			orbit_speed = base_orbit_speed * speed_mult
		else:
			orbit_speed = base_orbit_speed
			
		angle += orbit_speed * delta
		
		# Shoot loop
		fire_timer += delta
		if fire_timer >= fire_interval:
			fire_timer = 0.0
			_shoot()
			
	_update_position()

func _update_position() -> void:
	global_position = Vector3(cos(angle) * orbit_radius, 0.0, sin(angle) * orbit_radius)
	global_rotation.y = -angle + PI / 2.0

func _shoot() -> void:
	var master_nodes = get_tree().get_nodes_in_group("sat_proj_master")
	if master_nodes.is_empty():
		return
	var master_node_proj = master_nodes[0]
	
	var shoot_dir = Vector3(cos(angle), 0.0, sin(angle)).normalized()
	master_node_proj.spawn_satellite_projectile(global_position, shoot_dir)

func animate_scale_down(duration: float) -> void:
	var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector3.ZERO, duration)
