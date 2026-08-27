@tool
extends EditorPlugin

const BalanceSchemaScript := preload("res://addons/balance_editor/balance_schema.gd")
const XlsxCodecScript := preload("res://addons/balance_editor/xlsx_balance_codec.gd")
const BalanceImportValidatorScript := preload("res://addons/balance_editor/balance_import_validator.gd")
const PROJECT_ID := "vearth-incremental-threat"
const SCHEMA_VERSION := 2
const DATA_SHEETS: Array[String] = ["Upgrades", "Turrets", "Barriers", "Levels"]

var dock: VBoxContainer
var status_label: Label
var export_dialog: FileDialog
var import_dialog: FileDialog
var import_confirmation: ConfirmationDialog
var result_dialog: AcceptDialog
var pending_changes: Array[Dictionary] = []
var pending_import_path := ""

func _enter_tree() -> void:
	_build_dock()
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, dock)

func _exit_tree() -> void:
	if is_instance_valid(dock):
		remove_control_from_docks(dock)
		dock.queue_free()
	dock = null

func _build_dock() -> void:
	dock = VBoxContainer.new()
	dock.name = "BalanceEditor"
	dock.custom_minimum_size = Vector2(320.0, 0.0)
	dock.add_theme_constant_override("separation", 10)

	var title := Label.new()
	title.text = "BALANCE EDITOR"
	title.add_theme_font_size_override("font_size", 20)
	dock.add_child(title)

	var description := Label.new()
	description.text = "Export typed game balance to Excel, edit only New Value, then validate and inject it back into Godot."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dock.add_child(description)

	var export_button := Button.new()
	export_button.text = "EXTRACT DATA (.XLSX)"
	export_button.tooltip_text = "Create a fresh workbook from the current Godot resources."
	export_button.pressed.connect(_open_export_dialog)
	dock.add_child(export_button)

	var import_button := Button.new()
	import_button.text = "INJECT VALUES (.XLSX)"
	import_button.tooltip_text = "Validate a workbook, create a backup, and update the registered resources."
	import_button.pressed.connect(_open_import_dialog)
	dock.add_child(import_button)

	var rules := Label.new()
	rules.text = "Workbook tabs: Upgrades, Turrets, Barriers, Levels.\nOnly the yellow New Value column is editable.\nIDs, tree layout, prerequisites, and save-game progress are never imported."
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.modulate = Color(0.72, 0.78, 0.86)
	dock.add_child(rules)

	status_label = Label.new()
	status_label.text = "Ready. Extract a fresh workbook before balancing."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dock.add_child(status_label)

	export_dialog = FileDialog.new()
	export_dialog.title = "Export Vearth Balance Workbook"
	export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_dialog.filters = PackedStringArray(["*.xlsx ; Excel Workbook"])
	export_dialog.current_file = "VearthBalance.xlsx"
	export_dialog.use_native_dialog = true
	export_dialog.file_selected.connect(_export_workbook)
	dock.add_child(export_dialog)

	import_dialog = FileDialog.new()
	import_dialog.title = "Import Vearth Balance Workbook"
	import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	import_dialog.filters = PackedStringArray(["*.xlsx ; Excel Workbook"])
	import_dialog.use_native_dialog = true
	import_dialog.file_selected.connect(_prepare_import)
	dock.add_child(import_dialog)

	import_confirmation = ConfirmationDialog.new()
	import_confirmation.title = "Inject Balance Values"
	import_confirmation.confirmed.connect(_apply_pending_import)
	dock.add_child(import_confirmation)

	result_dialog = AcceptDialog.new()
	result_dialog.title = "Balance Editor"
	dock.add_child(result_dialog)

func _open_export_dialog() -> void:
	export_dialog.popup_centered_ratio(0.7)

func _open_import_dialog() -> void:
	import_dialog.popup_centered_ratio(0.7)

func _export_workbook(file_path: String) -> void:
	var normalized_path := file_path
	if not normalized_path.to_lower().ends_with(".xlsx"):
		normalized_path += ".xlsx"
	_set_status("Building workbook...", false)
	var schema := BalanceSchemaScript.new()
	var codec := XlsxCodecScript.new()
	var sheets := schema.build_workbook_sheets()
	var row_count := 0
	for sheet_name in DATA_SHEETS:
		row_count += sheets[sheet_name].rows.size()
	var error := codec.write_workbook(normalized_path, sheets)
	if error != OK:
		_show_result("Export failed with error code %d." % error, true)
		return
	_show_result("Exported %d editable balance fields to:\n%s" % [row_count, normalized_path], false)

func _prepare_import(file_path: String) -> void:
	_set_status("Reading and validating workbook...", false)
	var codec := XlsxCodecScript.new()
	var read_result: Dictionary = codec.read_workbook(file_path)
	if not read_result.get("ok", false):
		_show_result(read_result.get("error", "Could not read workbook."), true)
		return
	var validation := _validate_workbook(read_result.sheets)
	if not validation.ok:
		_show_result("Import rejected:\n\n" + "\n".join(validation.errors), true)
		return
	pending_changes = validation.changes
	pending_import_path = file_path
	if pending_changes.is_empty():
		_show_result("The workbook is valid, but no values changed.", false)
		return
	import_confirmation.dialog_text = (
		"Validation passed.\n\n%d value(s) will be changed.\nA JSON backup will be created before saving.\n\nContinue?"
		% pending_changes.size()
	)
	import_confirmation.popup_centered(Vector2i(520, 260))

func _validate_workbook(parsed_sheets: Dictionary) -> Dictionary:
	return BalanceImportValidatorScript.new().validate_workbook(parsed_sheets)

func _apply_pending_import() -> void:
	if pending_changes.is_empty():
		return
	var backup_result := _write_backup(pending_changes, pending_import_path)
	if not backup_result.ok:
		_show_result(backup_result.error, true)
		return
	var resources: Dictionary = {}
	var applied_changes: Array[Dictionary] = []
	for change in pending_changes:
		var resource_path: String = change.resource_path
		if not resources.has(resource_path):
			var resource := ResourceLoader.load(resource_path, "", ResourceLoader.CACHE_MODE_REPLACE)
			if not is_instance_valid(resource):
				_rollback(applied_changes, resources)
				_show_result("Could not load resource during injection: %s" % resource_path, true)
				return
			resources[resource_path] = resource
		resources[resource_path].set(change.property_key, change.new_value)
		applied_changes.append(change)

	for resource_path in resources:
		var save_error := ResourceSaver.save(resources[resource_path], resource_path)
		if save_error != OK:
			_rollback(applied_changes, resources)
			_show_result("Saving failed for %s (error %d). Every changed value was rolled back." % [resource_path, save_error], true)
			return
	get_editor_interface().get_resource_filesystem().scan()
	_show_result("Injected %d value(s).\nBackup: %s\nRestart the running game scene to refresh pooled instances." % [pending_changes.size(), backup_result.path], false)
	pending_changes.clear()
	pending_import_path = ""

func _rollback(applied_changes: Array[Dictionary], resources: Dictionary) -> void:
	for change in applied_changes:
		if resources.has(change.resource_path):
			resources[change.resource_path].set(change.property_key, change.old_value)
	for resource_path in resources:
		ResourceSaver.save(resources[resource_path], resource_path)

func _write_backup(changes: Array[Dictionary], source_path: String) -> Dictionary:
	var backup_directory := ProjectSettings.globalize_path("user://balance_backups")
	var directory_error := DirAccess.make_dir_recursive_absolute(backup_directory)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return {"ok": false, "error": "Could not create backup directory (error %d)." % directory_error}
	var timestamp := Time.get_datetime_string_from_system(true).replace(":", "-")
	var backup_path := backup_directory.path_join("balance_%s.json" % timestamp)
	var serialized_changes: Array[Dictionary] = []
	for change in changes:
		serialized_changes.append({
			"field_id": change.field_id,
			"resource_path": change.resource_path,
			"property_key": change.property_key,
			"type": change.type,
			"old_value": _serialize_value(change.old_value),
			"new_value": _serialize_value(change.new_value),
		})
	var payload := {
		"project_id": PROJECT_ID,
		"schema_version": SCHEMA_VERSION,
		"created_at_utc": Time.get_datetime_string_from_system(true),
		"source_workbook": source_path,
		"changes": serialized_changes,
	}
	var file := FileAccess.open(backup_path, FileAccess.WRITE)
	if not file:
		return {"ok": false, "error": "Could not create backup file."}
	file.store_string(JSON.stringify(payload, "  "))
	file.close()
	return {"ok": true, "path": backup_path}

func _serialize_value(value: Variant) -> Variant:
	if value is Vector2:
		return {"x": value.x, "y": value.y}
	return value

func _show_result(message: String, is_error: bool) -> void:
	_set_status(message, is_error)
	result_dialog.dialog_text = message
	result_dialog.popup_centered(Vector2i(680, 360))

func _set_status(message: String, is_error: bool) -> void:
	status_label.text = message
	status_label.add_theme_color_override("font_color", Color(1.0, 0.42, 0.42) if is_error else Color(0.56, 0.86, 0.68))
