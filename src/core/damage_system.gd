class_name DamageSystem
extends RefCounted

## Identifies who owns damage. Targets decide which teams are allowed to hurt them.
enum Team {
	NEUTRAL,
	ALLY,
	ENEMY,
}

static func apply(target: Node, amount: float, source_team: int) -> bool:
	if not is_instance_valid(target) or amount <= 0.0:
		return false

	if target.has_method("receive_damage"):
		return bool(target.call("receive_damage", amount, source_team))

	# Compatibility for actors that have not migrated to receive_damage yet.
	if source_team == Team.ALLY and target.has_method("take_player_damage"):
		target.call("take_player_damage", amount)
		return true
	if target.has_method("take_damage"):
		target.call("take_damage", amount)
		return true
	return false
