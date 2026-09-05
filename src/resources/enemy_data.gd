@tool
class_name EnemyData
extends Resource

## Shared authoring data for one enemy archetype.
## Runtime enemies reference this resource; they do not duplicate it per entity.

enum BehaviorType {
	ASTEROID,
	BARRIER_ATTACKER,
	PLANET_ATTACKER,
}

@export_group("Identity")
## Stable identifier used by saves, level configuration, and GPU archetype tables.
@export var enemy_id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var behavior: BehaviorType = BehaviorType.ASTEROID
## Optional runtime profile. Zero HP bounds keep max_hp fixed.
@export var spawn_hp_min: int = 0
@export var spawn_hp_max: int = 0
@export var hit_slow_duration: float = 0.0
@export var hit_speed_factor: float = 1.0
@export var drops_debris: bool = false
@export var tumble_visual: bool = false
## Keeps the visual forward axis aimed at the planet instead of tumbling.
@export var face_planet: bool = false
@export var planet_contact_includes_radius: bool = true

@export_group("Visual")
## Preferred shared visual contract. Enemy visuals are extracted into MultiMeshes.
@export var visual_asset: VisualAsset3D
## Compatibility for definitions not migrated to VisualAsset3D yet.
@export var visual_scene: PackedScene
@export_range(0.001, 1000.0, 0.001) var visual_scale: float = 1.0

@export_group("Combat")
@export_range(0.001, 1000000.0, 0.1) var max_hp: float = 1.0
@export_range(0.0, 1000000.0, 0.1) var damage: float = 1.0
@export_range(0.0, 3600.0, 0.01) var attack_interval: float = 0.0
## Distance from the target surface at which an attacking ship stops moving.
@export_range(1.0, 1000.0, 1.0) var attack_range: float = 100.0
@export_range(1.0, 10000.0, 1.0) var projectile_speed: float = 140.0
@export_range(0.001, 10000.0, 0.1) var radius: float = 20.0

@export_group("Movement")
@export_range(0.0, 10000.0, 0.1) var movement_speed: float = 100.0
@export_range(0.0, 1000.0, 0.01) var rotation_speed: float = 1.0

@export_group("Rewards")
@export_range(0.0, 1000000000.0, 0.1) var credit_value: float = 1.0


func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var id_text := String(enemy_id).strip_edges()
	if id_text.is_empty():
		errors.append("enemy_id cannot be empty.")
	if display_name.strip_edges().is_empty():
		errors.append("display_name cannot be empty for enemy '%s'." % id_text)
	if visual_asset != null:
		for error in visual_asset.get_validation_errors(true):
			errors.append("Enemy '%s': %s" % [id_text, error])
	elif not is_instance_valid(visual_scene):
		errors.append("visual_asset or legacy visual_scene cannot be empty for enemy '%s'." % id_text)
	elif not visual_scene.can_instantiate():
		errors.append("visual_scene must contain a packed scene for enemy '%s'." % id_text)
	if behavior not in BehaviorType.values():
		errors.append("Unknown behavior for enemy '%s'." % id_text)
	for field in ["max_hp", "radius", "visual_scale", "damage", "attack_interval", "attack_range", "projectile_speed", "movement_speed", "rotation_speed", "credit_value", "hit_slow_duration", "hit_speed_factor"]:
		if not is_finite(float(get(field))):
			errors.append("%s must be finite for enemy '%s'." % [field, id_text])
	if max_hp <= 0.0:
		errors.append("max_hp must be greater than zero for enemy '%s'." % id_text)
	if spawn_hp_min < 0 or spawn_hp_max < spawn_hp_min or (spawn_hp_min == 0 and spawn_hp_max != 0):
		errors.append("Spawn HP bounds must both be zero or a positive ordered range.")
	if hit_slow_duration < 0 or hit_speed_factor < 0 or hit_speed_factor > 1:
		errors.append("Hit slowdown duration/factor are invalid.")
	if radius <= 0.0:
		errors.append("radius must be greater than zero for enemy '%s'." % id_text)
	if visual_scale <= 0.0:
		errors.append("visual_scale must be greater than zero for enemy '%s'." % id_text)
	if damage < 0.0:
		errors.append("damage cannot be negative for enemy '%s'." % id_text)
	if attack_interval < 0.0:
		errors.append("attack_interval cannot be negative for enemy '%s'." % id_text)
	if behavior != BehaviorType.ASTEROID and attack_interval <= 0.0:
		errors.append("Attacking ships need a positive attack_interval.")
	if attack_range <= 0.0 or projectile_speed <= 0.0:
		errors.append("attack_range and projectile_speed must be positive.")
	if movement_speed < 0.0:
		errors.append("movement_speed cannot be negative for enemy '%s'." % id_text)
	if rotation_speed < 0.0:
		errors.append("rotation_speed cannot be negative for enemy '%s'." % id_text)
	if credit_value < 0.0:
		errors.append("credit_value cannot be negative for enemy '%s'." % id_text)
	return errors


func is_valid_definition() -> bool:
	return get_validation_errors().is_empty()


func instantiate_visual() -> Node3D:
	if visual_asset != null:
		return visual_asset.instantiate_visual()
	if visual_scene == null or not visual_scene.can_instantiate():
		return null
	var instance := visual_scene.instantiate()
	if not instance is Node3D:
		instance.free()
		return null
	var visual := instance as Node3D
	visual.scale *= visual_scale
	return visual


static func validate_catalog(enemy_resources: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	var first_index_by_id: Dictionary = {}

	for index in range(enemy_resources.size()):
		var resource = enemy_resources[index]
		if resource == null:
			errors.append("Enemy catalog entry %d is empty." % index)
			continue
		if not resource is EnemyData:
			errors.append("Enemy catalog entry %d is not an EnemyData resource." % index)
			continue

		var enemy := resource as EnemyData
		for validation_error in enemy.get_validation_errors():
			errors.append("Enemy catalog entry %d: %s" % [index, validation_error])

		var id_text := String(enemy.enemy_id).strip_edges()
		if id_text.is_empty():
			continue
		if first_index_by_id.has(id_text):
			errors.append(
				"Duplicate enemy_id '%s' at catalog entries %d and %d." % [
					id_text,
					int(first_index_by_id[id_text]),
					index,
				]
			)
		else:
			first_index_by_id[id_text] = index

	return errors
