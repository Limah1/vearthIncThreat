extends Control
class_name PreparationFooter

@onready var status_label: Label = $Panel/Margin/VBox/StatusLabel
@onready var turret_button: Button = $Panel/Margin/VBox/Controls/TurretButton
@onready var reset_button: Button = $Panel/Margin/VBox/Controls/ResetButton
@onready var start_button: Button = $Panel/Margin/VBox/Controls/StartButton

var controller: PreparationController = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	turret_button.pressed.connect(_on_turret_pressed)
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
	if not is_instance_valid(controller):
		_find_controller()
	_refresh_controls()

func _refresh_controls() -> void:
	if not turret_button or not start_button:
		return
	if not is_instance_valid(controller):
		turret_button.text = "TURRET  4"
		turret_button.disabled = true
		start_button.disabled = true
		return
	turret_button.text = "TURRET  %d" % controller.get_available_turrets()
	turret_button.disabled = controller.get_available_turrets() <= 0 or controller.get_barrier_count() <= 0
	start_button.disabled = not controller.can_start_wave()

func _on_turret_pressed() -> void:
	if is_instance_valid(controller):
		controller.begin_turret_placement()

func _on_reset_pressed() -> void:
	if is_instance_valid(controller):
		controller.reset_layout()

func _on_start_pressed() -> void:
	if is_instance_valid(controller):
		controller.start_wave()
