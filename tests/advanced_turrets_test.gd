extends Node

const LASER_SCENE := preload("res://src/entities/laser_turret.tscn")
const MINER_SCENE := preload("res://src/entities/turret_miner.tscn")
const BARRIER_SCENE := preload("res://src/entities/barrier.tscn")
const DamageSystemScript = preload("res://src/core/damage_system.gd")

class DummyHostile extends Node3D:
	var active: bool = true
	var radius: float = 1.0
	var damage_received: float = 0.0

	func _ready() -> void:
		add_to_group("asteroid")

	func receive_damage(amount: float, source_team: int) -> bool:
		if source_team != DamageSystemScript.Team.ALLY:
			return false
		damage_received += amount
		return true

var failures: int = 0

func _ready() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	UpgradeManager.purchased_levels.clear()
	UpgradeManager.load_all_upgrades()
	GameManager.current_state = GameManager.GameState.PLAYING
	await _test_piercing_laser()
	await _test_laser_upgrades()
	await _test_mine_fuse_and_area_damage()
	await _test_miner_upgrades()
	await _test_unlocked_preparation_inventory()
	if failures == 0:
		print("Advanced turret tests passed.")
	else:
		push_error("Advanced turret tests failed: %d" % failures)
	get_tree().quit(failures)

func _test_piercing_laser() -> void:
	var barrier := BARRIER_SCENE.instantiate() as Barrier
	add_child(barrier)
	var laser := LASER_SCENE.instantiate() as LaserTurret
	add_child(laser)
	laser.barrier_ref = barrier
	laser.active = false
	laser.set_aim_configuration(0.0, 90.0)
	var first := await _create_hostile(Vector3(0.0, 0.0, 100.0))
	var second := await _create_hostile(Vector3(0.0, 0.0, 200.0))
	var outside := await _create_hostile(Vector3(100.0, 0.0, 100.0))
	laser._begin_beam(first)
	_expect(is_equal_approx(laser.beam_remaining, 3.0), "Laser beam must last 3 seconds.")
	_expect(is_equal_approx(first.damage_received, 1.0), "A 5 DPS laser must deal 1 damage per 0.2-second tick.")
	_expect(is_equal_approx(second.damage_received, 1.0), "Laser must pierce and damage a second target on the beam.")
	_expect(is_zero_approx(outside.damage_received), "Laser must not damage a target outside its beam width.")
	laser._stop_beam(true)
	_expect(is_equal_approx(laser.cooldown, 10.0), "Laser cooldown must begin at 10 seconds after the beam ends.")
	_cleanup_hostile(first)
	_cleanup_hostile(second)
	_cleanup_hostile(outside)
	laser.queue_free()
	barrier.queue_free()
	await get_tree().process_frame

func _test_laser_upgrades() -> void:
	UpgradeManager.purchased_levels["DA_LaserCooldownReduction"] = 3
	UpgradeManager.purchased_levels["DA_LaserDamage"] = 1
	var laser := LASER_SCENE.instantiate() as LaserTurret
	add_child(laser)
	await get_tree().process_frame
	_expect(is_equal_approx(laser.effective_damage, 10.0), "Laser damage upgrade must raise DPS from 5 to 10.")
	_expect(is_equal_approx(laser.effective_beam_cooldown, 7.0), "Three cooldown ranks must reduce cooldown from 10 to 7 seconds.")
	laser.queue_free()
	UpgradeManager.purchased_levels["DA_LaserCooldownReduction"] = 0
	UpgradeManager.purchased_levels["DA_LaserDamage"] = 0

func _test_mine_fuse_and_area_damage() -> void:
	var miner := MINER_SCENE.instantiate() as TurretMiner
	add_child(miner)
	await get_tree().process_frame
	miner.set_aim_configuration(0.0, 90.0)
	miner._launch_mine_at_random_cone_position()
	var launch_offset := Vector2(
		miner.mine_end_positions[0].x - miner.global_position.x,
		miner.mine_end_positions[0].z - miner.global_position.z
	)
	_expect(
		miner.turret_config.contains_offset_in_action_cone(launch_offset, miner.get_aim_forward_2d(), miner.get_cone_angle()),
		"A mine destination must be randomly selected inside the configured action cone."
	)
	var hostile := await _create_hostile(Vector3(0.0, 0.0, 0.0))
	miner.mine_states[0] = TurretMiner.MineState.ARMED
	miner.mine_timers[0] = 1.5
	miner.mine_end_positions[0] = hostile.global_position
	miner.mine_visuals[0].visible = true
	miner._update_mines(1.49)
	_expect(is_zero_approx(hostile.damage_received), "A stopped mine must not explode before its 1.5-second fuse expires.")
	miner._update_mines(0.02)
	_expect(is_equal_approx(hostile.damage_received, 5.0), "An unupgraded mine must deal 5 area damage once.")
	_expect(miner.mine_states[0] == TurretMiner.MineState.AVAILABLE, "Mine must recycle immediately after its one explosion.")
	_cleanup_hostile(hostile)
	miner.queue_free()
	await get_tree().process_frame

func _test_miner_upgrades() -> void:
	UpgradeManager.purchased_levels["DA_MinerDamage"] = 1
	UpgradeManager.purchased_levels["DA_MinerRadius"] = 1
	var miner := MINER_SCENE.instantiate() as TurretMiner
	add_child(miner)
	await get_tree().process_frame
	_expect(is_equal_approx(miner.effective_damage, 10.0), "Mine damage upgrade must raise damage from 5 to 10.")
	_expect(is_equal_approx(miner.effective_explosion_radius, 20.0), "Mine radius upgrade must raise radius from 10 to 20.")
	miner.queue_free()
	UpgradeManager.purchased_levels["DA_MinerDamage"] = 0
	UpgradeManager.purchased_levels["DA_MinerRadius"] = 0

func _test_unlocked_preparation_inventory() -> void:
	UpgradeManager.purchased_levels["DA_UnlockTurret"] = 1
	UpgradeManager.purchased_levels["DA_UnlockLaserTurret"] = 1
	UpgradeManager.purchased_levels["DA_UnlockTurretMiner"] = 1
	var controller := PreparationController.new()
	add_child(controller)
	await get_tree().process_frame
	controller._reset_inventory()
	_expect(controller.get_available_turrets() == 4, "Defense Blaster unlock must provide four units.")
	_expect(controller.get_available_laser_turrets() == 1, "Laser Turret unlock must provide exactly one unit.")
	_expect(controller.get_available_turret_miners() == 2, "Turret Miner unlock must provide exactly two units.")
	controller.queue_free()
	UpgradeManager.purchased_levels["DA_UnlockTurret"] = 0
	UpgradeManager.purchased_levels["DA_UnlockLaserTurret"] = 0
	UpgradeManager.purchased_levels["DA_UnlockTurretMiner"] = 0

func _create_hostile(world_position: Vector3) -> DummyHostile:
	var hostile := DummyHostile.new()
	add_child(hostile)
	hostile.global_position = world_position
	GameManager.register_active_damageable(hostile)
	await get_tree().process_frame
	return hostile

func _cleanup_hostile(hostile: DummyHostile) -> void:
	GameManager.unregister_active_damageable(hostile)
	hostile.queue_free()

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
