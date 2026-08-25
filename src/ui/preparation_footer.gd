extends Control
class_name PreparationFooter

@onready var status_label: Label = $Panel/Margin/VBox/StatusLabel
@onready var turret_button: Button = $Panel/Margin/VBox/Controls/TurretButton
@onready var laser_button: Button = $Panel/Margin/VBox/Controls/LaserButton
@onready var miner_button: Button = $Panel/Margin/VBox/Controls/MinerButton
@onready var reset_button: Button = $Panel/Margin/VBox/Controls/ResetButton
@onready var start_button: Button = $Panel/Margin/VBox/Controls/StartButton

var controller: PreparationController = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	turret_button.pressed.connect(_on_turret_pressed)
	laser_button.pressed.connect(_on_laser_pressed)
	miner_button.pressed.connect(_on_miner_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	start_button.pressed.connect(_on_start_pressed)
	call_deferred("_find_controller")

func _find_controller() -> void:
	controller = get_tree().get_first_node_in_group("preparation_controller") as PreparationController
	_refresh_controls()

func set_controller(new_controller: Node) -> void:
	controller = new_controller as PreparationController
	_refresh_controls()

func set_status(message: String) -> void:
	if status_label:
		status_label.text = message
	_refresh_controls()

func _process(_delta: float) -> void:
	if not visible:
		return
	if not is_instance_valid(controller):
		_find_controller()
	_refresh_controls()

func _refresh_controls() -> void:
	if not turret_button or not start_button:
		return
	if not is_instance_valid(controller):
		turret_button.text = "DEFENSE BLASTER  4"
		laser_button.text = "LASER TURRET  LOCKED"
		miner_button.text = "TURRET MINER  LOCKED"
		turret_button.disabled = true
		laser_button.disabled = true
		miner_button.disabled = true
		start_button.disabled = true
		return
	var has_barrier: bool = controller.get_barrier_count() > 0
	var defense_unlocked: bool = controller.is_defense_blaster_unlocked()
	var laser_unlocked: bool = controller.is_laser_turret_unlocked()
	var miner_unlocked: bool = controller.is_turret_miner_unlocked()
	turret_button.text = "DEFENSE BLASTER  %s" % str(controller.get_available_turrets()) if defense_unlocked else "DEFENSE BLASTER  LOCKED"
	laser_button.text = "LASER TURRET  %s" % str(controller.get_available_laser_turrets()) if laser_unlocked else "LASER TURRET  LOCKED"
	miner_button.text = "TURRET MINER  %s" % str(controller.get_available_turret_miners()) if miner_unlocked else "TURRET MINER  LOCKED"
	turret_button.disabled = not defense_unlocked or controller.get_available_turrets() <= 0 or not has_barrier
	laser_button.disabled = not laser_unlocked or controller.get_available_laser_turrets() <= 0 or not has_barrier
	miner_button.disabled = not miner_unlocked or controller.get_available_turret_miners() <= 0 or not has_barrier
	start_button.disabled = not controller.can_start_wave()

func _on_turret_pressed() -> void:
	if is_instance_valid(controller):
		controller.begin_turret_placement()

func _on_laser_pressed() -> void:
	if is_instance_valid(controller):
		controller.begin_laser_turret_placement()

func _on_miner_pressed() -> void:
	if is_instance_valid(controller):
		controller.begin_turret_miner_placement()

func _on_reset_pressed() -> void:
	if is_instance_valid(controller):
		controller.reset_layout()

func _on_start_pressed() -> void:
	if is_instance_valid(controller):
		controller.start_wave()
