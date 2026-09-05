# res://src/core/spawner_point.gd
extends Node2D
class_name SpawnerPoint

const GROUP_NAME: StringName = &"spawn_point"

## Marker node in the scene. SpawnPath also supports legacy plain Node2D points
## by registering them in the same group.

func _enter_tree() -> void:
	add_to_group(GROUP_NAME)
