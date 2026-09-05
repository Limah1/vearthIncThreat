class_name GridLayoutStore
extends RefCounted

## Small, versioned save dedicated to player-authored Grid Combat layouts.
## Runtime state such as HP, enemies and wave progress intentionally stays out.
const SAVE_VERSION: int = 1
const DEFAULT_STORAGE_PATH: String = "user://grid_combat_layouts.json"

## Tests may redirect storage without changing the production path.
static var storage_path: String = DEFAULT_STORAGE_PATH
static var allow_headless: bool = false


static func is_available() -> bool:
	return allow_headless or DisplayServer.get_name() != "headless"


static func has_layout(layout_key: String) -> bool:
	if layout_key.is_empty():
		return false
	var root := _read_root()
	var layouts: Variant = root.get("layouts", {})
	return layouts is Dictionary and (layouts as Dictionary).has(layout_key)


static func load_layout(layout_key: String) -> Dictionary:
	if layout_key.is_empty():
		return {}
	var root := _read_root()
	var layouts: Variant = root.get("layouts", {})
	if not layouts is Dictionary:
		return {}
	var layout: Variant = (layouts as Dictionary).get(layout_key, {})
	return (layout as Dictionary).duplicate(true) if layout is Dictionary else {}


static func save_layout(layout_key: String, layout: Dictionary) -> Error:
	if layout_key.is_empty():
		return ERR_INVALID_PARAMETER
	var root := _read_root()
	root["version"] = SAVE_VERSION
	var layouts: Dictionary = root.get("layouts", {}) as Dictionary
	layouts[layout_key] = layout.duplicate(true)
	root["layouts"] = layouts

	var file := FileAccess.open(storage_path, FileAccess.WRITE)
	if file == null:
		var open_error := FileAccess.get_open_error()
		push_warning("Could not save Grid Combat layout to %s (error %d)." % [storage_path, open_error])
		return open_error
	file.store_string(JSON.stringify(root, "\t"))
	return OK


static func clear_layout(layout_key: String) -> Error:
	var root := _read_root()
	var layouts: Variant = root.get("layouts", {})
	if not layouts is Dictionary or not (layouts as Dictionary).has(layout_key):
		return OK
	(layouts as Dictionary).erase(layout_key)
	root["layouts"] = layouts
	var file := FileAccess.open(storage_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(root, "\t"))
	return OK


static func _read_root() -> Dictionary:
	if not FileAccess.file_exists(storage_path):
		return {"version": SAVE_VERSION, "layouts": {}}
	var file := FileAccess.open(storage_path, FileAccess.READ)
	if file == null:
		return {"version": SAVE_VERSION, "layouts": {}}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_warning("Ignoring invalid Grid Combat layout save at %s." % storage_path)
		return {"version": SAVE_VERSION, "layouts": {}}
	var root := parsed as Dictionary
	if int(root.get("version", 0)) != SAVE_VERSION:
		return {"version": SAVE_VERSION, "layouts": {}}
	if not root.get("layouts", {}) is Dictionary:
		root["layouts"] = {}
	return root
