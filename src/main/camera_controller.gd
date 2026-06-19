# res://src/main/camera_controller.gd
extends Camera3D
class_name CameraController

@export var height_step: float = 15.0
@export var transition_duration: float = 2.5
@export var base_height: float = 25.0

var target_height: float = 25.0

func _ready() -> void:
	# Set initial camera position looking down at center (0, 0, 0)
	projection = Camera3D.PROJECTION_ORTHOGONAL
	size = 1080.0
	far = 1000.0 # Prevent clipping planet/garbage at Y=100
	position = Vector3(0.0, 100.0, 0.0) # Elevated to avoid clipping to 100m distance
	rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	target_height = base_height
	current = true
	
	# Connect to camera fly-to-zone animation event
	get_node("/root/GameManager").trigger_camera_animation.connect(_on_trigger_camera_animation)

func _on_trigger_camera_animation() -> void:
	# Keep game paused during transition using TRANSITION state
	get_node("/root/GameManager").change_state(get_node("/root/GameManager").GameState.TRANSITION)
	
	# In orthogonal mode, zoom out by increasing camera view size
	var target_size = size + height_step * 10.0
	
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)
	# Interpolate size instead of position.y
	tween.tween_property(self, "size", target_size, transition_duration)
	tween.finished.connect(_on_transition_finished)

func _on_transition_finished() -> void:
	# Transition complete, start playing the new wave!
	get_node("/root/GameManager").change_state(get_node("/root/GameManager").GameState.PLAYING)
