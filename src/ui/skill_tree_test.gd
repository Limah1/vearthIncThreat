extends Control

func _ready() -> void:
	# Add some fake starting credits so you can test buying upgrades
	GameManager.lifetime_credits = 2500.0
	
	# Wait one frame to ensure SkillTree has connected to GameManager signals
	await get_tree().process_frame
	
	# Force the GameManager into the UPGRADE_SCREEN state to make the SkillTree visible
	GameManager.change_state(GameManager.GameState.UPGRADE_SCREEN)
