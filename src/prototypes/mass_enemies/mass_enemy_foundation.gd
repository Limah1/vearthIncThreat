extends Node

## Run this scene with F6 to inspect the step-4 data foundation independently.
@export_range(1, 1000, 1) var spawn_point_count: int = 40

@onready var world: EnemyWorld = $EnemyWorld
@onready var spawner: MassEnemySpawner = $MassEnemySpawner
@onready var status: Label = $CanvasLayer/Status


func _ready() -> void:
	for index in range(spawn_point_count):
		var point := SpawnerPoint.new()
		point.name = "Point%04d" % index
		point.position = Vector2.from_angle(index * TAU / float(spawn_point_count)) * 650.0
		$SpawnPoints.add_child(point)
	world.events_flushed.connect(_on_events)
	spawner.spawning_completed.connect(_on_completed)
	_update_status()
	# Spawner auto_start is deferred, so all markers exist before discovery.


func _on_events(_spawned: int, _recycled: int, _rejected: int, _active: int) -> void:
	_update_status()


func _on_completed(total: int) -> void:
	_update_status()
	print("MassEnemyFoundation complete: %d spawned, %d active, %d archetypes." % [
		total, world.get_active_count(), world.get_archetype_count(),
	])


func _update_status() -> void:
	status.text = "EnemyWorld — teste da fundação\n\nAtivos: %d / %d\nSpawns confirmados: %d / %d\nArquétipos: %d\n\n%d pontos × %d inimigos a cada %.2f s\n\nEste teste mostra contadores.\nA renderização dos inimigos será o passo 5." % [
		world.get_active_count(), world.capacity,
		spawner.spawned_enemy_count, spawner.level_config.total_enemies,
		world.get_archetype_count(), spawn_point_count,
		spawner.level_config.enemies_per_spawn_point,
		spawner.level_config.spawn_interval_seconds,
	]
