@tool
class_name EnemySpawnEntry
extends Resource

## Weighted reference to an enemy archetype in a level spawn roster.

@export var enemy: EnemyData
@export_range(0.0, 1000000.0, 0.1) var spawn_weight: float = 1.0


func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if not is_instance_valid(enemy):
		errors.append("enemy resource cannot be empty.")
	else:
		errors.append_array(enemy.get_validation_errors())
	if not is_finite(spawn_weight) or spawn_weight <= 0.0:
		errors.append("spawn_weight must be finite and greater than zero.")
	return errors


func is_valid_entry() -> bool:
	return get_validation_errors().is_empty()


static func validate_roster(entries: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	var first_index_by_enemy_id: Dictionary = {}

	for index in range(entries.size()):
		var resource = entries[index]
		if resource == null:
			errors.append("Enemy roster entry %d is empty." % index)
			continue
		if not resource is EnemySpawnEntry:
			errors.append("Enemy roster entry %d is not an EnemySpawnEntry resource." % index)
			continue

		var entry := resource as EnemySpawnEntry
		for validation_error in entry.get_validation_errors():
			errors.append("Enemy roster entry %d: %s" % [index, validation_error])

		if not is_instance_valid(entry.enemy):
			continue
		var id_text := String(entry.enemy.enemy_id).strip_edges()
		if id_text.is_empty():
			continue
		if first_index_by_enemy_id.has(id_text):
			errors.append(
				"Duplicate enemy_id '%s' at roster entries %d and %d." % [
					id_text,
					int(first_index_by_enemy_id[id_text]),
					index,
				]
			)
		else:
			first_index_by_enemy_id[id_text] = index

	return errors
