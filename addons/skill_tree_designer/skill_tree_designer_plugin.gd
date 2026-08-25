@tool
extends EditorPlugin

const DESIGNER_SCRIPT := preload("res://addons/skill_tree_designer/skill_tree_designer.gd")

var designer: Control

func _enter_tree() -> void:
	designer = DESIGNER_SCRIPT.new()
	designer.name = "SkillTreeDesigner"
	designer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	EditorInterface.get_editor_main_screen().add_child(designer)
	designer.hide()

func _exit_tree() -> void:
	if is_instance_valid(designer):
		designer.queue_free()
	designer = null

func _has_main_screen() -> bool:
	return true

func _make_visible(visible: bool) -> void:
	if is_instance_valid(designer):
		designer.visible = visible

func _get_plugin_name() -> String:
	return "Skill Tree"

func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("GraphEdit", "EditorIcons")
