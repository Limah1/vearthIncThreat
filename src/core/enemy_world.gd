extends Node
class_name EnemyWorld

## CPU data foundation. No per-enemy Nodes, Resources, physics bodies or signals.
## Packed arrays are owned by this world; use handles at external boundaries.
signal events_flushed(spawned: int, recycled: int, rejected: int, active: int)

const INVALID_HANDLE: int = -1
const SLOT_MASK: int = 0xFFFFFFFF
const MAX_GENERATION: int = 0x7FFFFFFF
enum State { INACTIVE, MOVING, APPROACH_BARRIER, ATTACK_BARRIER, ROTATE_TO_PLANET, ATTACK_PLANET }

## Unique within this process, including across worlds and resets. Never wrap.
static var _next_generation: int = 1

@export_range(1, 100000, 1) var capacity: int = 10000

var positions := PackedVector3Array()
var velocities := PackedVector3Array()
var health := PackedFloat32Array()
var hit_times := PackedFloat32Array()
var states := PackedInt32Array()
var archetype_indices := PackedInt32Array()
var attack_timers := PackedFloat32Array()
var headings := PackedFloat32Array()
var target_handles := PackedInt64Array()

var _generations := PackedInt64Array()
var _active_slots := PackedInt32Array()
var _active_indices := PackedInt32Array()
var _free_slots := PackedInt32Array()
var _active_count: int = 0
var _free_count: int = 0
var _initialized: bool = false
var mutation_revision: int = 0
var use_legacy_rules: bool = false
var zone: int = 1
## Enabled only by the authoritative GPU consumer. Ordered allocation journal.
var record_gpu_changes: bool = false
var gpu_changes: Array = []
var _archetypes: Array[EnemyData] = []
var _archetype_by_resource: Dictionary = {}
var _archetype_by_id: Dictionary = {}
var _pending_spawned: int = 0
var _pending_recycled: int = 0
var _pending_rejected: int = 0


func _ready() -> void:
	initialize()


func initialize() -> bool:
	if _initialized:
		return true
	if capacity < 1 or capacity > 100000:
		return false
	positions.resize(capacity)
	velocities.resize(capacity)
	health.resize(capacity)
	hit_times.resize(capacity)
	states.resize(capacity)
	archetype_indices.resize(capacity)
	attack_timers.resize(capacity)
	headings.resize(capacity)
	target_handles.resize(capacity)
	_generations.resize(capacity)
	_active_slots.resize(capacity)
	_active_indices.resize(capacity)
	_free_slots.resize(capacity)
	archetype_indices.fill(-1)
	target_handles.fill(INVALID_HANDLE)
	_active_indices.fill(-1)
	for slot in range(capacity):
		_free_slots[slot] = capacity - slot - 1
	_free_count = capacity
	_initialized = true
	return true


## Validates the entire addition before committing. Snapshots keep runtime
## defaults independent of Inspector changes. Meshes/materials remain shared.
func register_catalog(catalog: Array[EnemyData]) -> PackedStringArray:
	var errors := EnemyData.validate_catalog(catalog)
	for enemy in catalog:
		if enemy == null:
			continue
		if _archetype_by_id.has(enemy.enemy_id) and not _archetype_by_resource.has(enemy):
			errors.append("enemy_id '%s' already belongs to another Resource." % enemy.enemy_id)
	if not errors.is_empty():
		return errors
	for enemy in catalog:
		if _archetype_by_resource.has(enemy):
			continue
		var index := _archetypes.size()
		var definition := enemy.duplicate() as EnemyData
		if use_legacy_rules:
			var zone_offset := maxi(0, zone - 1)
			if definition.behavior == EnemyData.BehaviorType.ASTEROID:
				definition.movement_speed *= 1.0 + zone_offset * 0.05
				definition.hit_slow_duration = 0.4
				definition.hit_speed_factor = 0.8
				definition.drops_debris = true
				definition.tumble_visual = not definition.face_planet
				definition.planet_contact_includes_radius = false
			else:
				definition.max_hp *= 1.0 + zone_offset * 0.12
				definition.credit_value *= 1.0 + zone_offset * 0.12
		_archetypes.append(definition)
		_archetype_by_resource[enemy] = index
		_archetype_by_id[enemy.enemy_id] = index
	return errors


## Hot path: archetypes must be registered once before spawning.
func request_spawn(enemy: EnemyData, world_position: Vector3) -> int:
	if not initialize() or not world_position.is_finite() or not _archetype_by_resource.has(enemy):
		_pending_rejected += 1
		return INVALID_HANDLE
	if _free_count == 0 or _next_generation > MAX_GENERATION:
		_pending_rejected += 1
		return INVALID_HANDLE
	var archetype: int = _archetype_by_resource[enemy]
	var definition := _archetypes[archetype]
	_free_count -= 1
	var slot := _free_slots[_free_count]
	_generations[slot] = _next_generation
	_next_generation += 1
	positions[slot] = world_position
	velocities[slot] = Vector3.ZERO
	health[slot] = float(randi_range(definition.spawn_hp_min, definition.spawn_hp_max)) if definition.spawn_hp_min > 0 else definition.max_hp
	hit_times[slot] = -100.0
	states[slot] = State.APPROACH_BARRIER if definition.behavior == EnemyData.BehaviorType.BARRIER_ATTACKER else State.MOVING
	archetype_indices[slot] = archetype
	attack_timers[slot] = 0.0
	headings[slot] = 0.0
	target_handles[slot] = INVALID_HANDLE
	_active_slots[_active_count] = slot
	_active_indices[slot] = _active_count
	_active_count += 1
	mutation_revision += 1
	_pending_spawned += 1
	if record_gpu_changes:
		gpu_changes.append([1, slot, _generations[slot], archetype, world_position, health[slot], states[slot], headings[slot]])
	return (_generations[slot] << 32) | slot


func is_handle_valid(handle: int) -> bool:
	if handle < 0 or not _initialized:
		return false
	var slot := handle & SLOT_MASK
	return slot < positions.size() and _active_indices[slot] >= 0 and _generations[slot] == (handle >> 32)


func recycle(handle: int) -> bool:
	if not is_handle_valid(handle):
		return false
	var slot := handle & SLOT_MASK
	if record_gpu_changes:
		gpu_changes.append([2, slot, _generations[slot]])
	var active_index := _active_indices[slot]
	_active_count -= 1
	var replacement := _active_slots[_active_count]
	_active_slots[active_index] = replacement
	_active_indices[replacement] = active_index
	_active_indices[slot] = -1
	states[slot] = State.INACTIVE
	archetype_indices[slot] = -1
	positions[slot] = Vector3.ZERO
	velocities[slot] = Vector3.ZERO
	health[slot] = 0.0
	attack_timers[slot] = 0.0
	headings[slot] = 0.0
	target_handles[slot] = INVALID_HANDLE
	_free_slots[_free_count] = slot
	_free_count += 1
	_pending_recycled += 1
	mutation_revision += 1
	return true


## Keeps allocation and archetype table for the next wave; invalidates all handles.
func reset_world() -> void:
	while _active_count > 0:
		recycle(get_active_handle(_active_count - 1))


func get_active_count() -> int:
	return _active_count


func get_available_capacity() -> int:
	return _free_count if _initialized else capacity


func get_archetype_count() -> int:
	return _archetypes.size()


func get_archetype(index: int) -> EnemyData:
	return _archetypes[index]


func get_active_slot(index: int) -> int:
	return _active_slots[index]


func get_active_handle(active_index: int) -> int:
	if active_index < 0 or active_index >= _active_count:
		return INVALID_HANDLE
	var slot := _active_slots[active_index]
	return (_generations[slot] << 32) | slot


## Debug/inspection only: allocates a snapshot, not intended for per-frame loops.
func get_enemy_snapshot(handle: int) -> Dictionary:
	if not is_handle_valid(handle):
		return {}
	var slot := handle & SLOT_MASK
	return {
		"position": positions[slot], "velocity": velocities[slot],
		"hp": health[slot], "state": states[slot],
		"archetype_id": _archetypes[archetype_indices[slot]].enemy_id,
		"attack_timer": attack_timers[slot], "target": target_handles[slot],
	}


func _process(_delta: float) -> void:
	flush_events()


## At most one aggregate notification per flush, regardless of enemy count.
func flush_events() -> void:
	if _pending_spawned == 0 and _pending_recycled == 0 and _pending_rejected == 0:
		return
	var spawned := _pending_spawned
	var recycled := _pending_recycled
	var rejected := _pending_rejected
	_pending_spawned = 0
	_pending_recycled = 0
	_pending_rejected = 0
	events_flushed.emit(spawned, recycled, rejected, _active_count)
