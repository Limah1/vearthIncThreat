# res://src/core/performance_logger.gd
extends Node

@export var log_interval: float = 2.0
var log_timer: float = 0.0
var log_file: FileAccess

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Open log file inside application storage path (user://)
	log_file = FileAccess.open("user://performance_log.csv", FileAccess.WRITE)
	if log_file:
		log_file.store_line("timestamp,fps,process_ms,physics_ms,memory_static_mb,vram_mb,nodes,objects,draw_calls")
		print("[PerformanceLogger] Logging initialized at: ", OS.get_user_data_dir() + "/performance_log.csv")

func _process(delta: float) -> void:
	log_timer += delta
	if log_timer >= log_interval:
		log_timer = 0.0
		_log_metrics()

func _log_metrics() -> void:
	if not log_file:
		return
		
	var fps = Performance.get_monitor(Performance.TIME_FPS)
	var process_ms = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var memory_mb = Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0)
	var vram_mb = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / (1024.0 * 1024.0)
	var nodes = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var objects = Performance.get_monitor(Performance.OBJECT_COUNT)
	var draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	
	var timestamp = Time.get_time_string_from_system()
	
	# CSV line formatting
	var line = "%s,%.1f,%.2f,%.2f,%.2f,%.2f,%d,%d,%d" % [
		timestamp, fps, process_ms, physics_ms, memory_mb, vram_mb, nodes, objects, draw_calls
	]
	
	log_file.store_line(line)
	log_file.flush() # Force write immediately to disk

func _exit_tree() -> void:
	if log_file:
		log_file.close()
