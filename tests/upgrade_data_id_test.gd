extends Node

var _failures: int = 0

func _ready() -> void:
	var first_id := UpgradeData.generate_unique_id("LaserDamage")
	_expect(
		first_id.begins_with("UPG_LASERDAMAGE_"),
		"Generated IDs must include the normalized upgrade category."
	)
	var next_id := UpgradeData.generate_unique_id("LaserDamage", first_id)
	_expect(next_id != first_id, "The generator must skip an ignored ID.")
	_expect(
		next_id.begins_with("UPG_LASERDAMAGE_"),
		"Sequential IDs must preserve the category prefix."
	)
	_expect(
		UpgradeData.generate_unique_id("  Turret Damage ").begins_with("UPG_TURRET_DAMAGE_"),
		"Generated IDs must normalize spaces and punctuation."
	)

	if _failures == 0:
		print("Upgrade data ID tests passed.")
	else:
		push_error("Upgrade data ID tests failed: %d" % _failures)
	get_tree().quit(_failures)

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
