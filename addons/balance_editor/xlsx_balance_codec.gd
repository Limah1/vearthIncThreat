@tool
extends RefCounted

const XML_HEADER := "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"

func write_workbook(file_path: String, sheets: Dictionary) -> Error:
	var sheet_names: Array = sheets.keys()
	var packer := ZIPPacker.new()
	var open_error := packer.open(file_path)
	if open_error != OK:
		return open_error

	var files := {
		"[Content_Types].xml": _build_content_types(sheet_names.size()),
		"_rels/.rels": _build_root_relationships(),
		"docProps/app.xml": _build_app_properties(sheet_names),
		"docProps/core.xml": _build_core_properties(),
		"xl/workbook.xml": _build_workbook_xml(sheet_names, sheets),
		"xl/_rels/workbook.xml.rels": _build_workbook_relationships(sheet_names.size()),
		"xl/styles.xml": _build_styles_xml(),
	}
	for index in range(sheet_names.size()):
		var sheet_name: String = sheet_names[index]
		files["xl/worksheets/sheet%d.xml" % (index + 1)] = _build_worksheet_xml(sheets[sheet_name])

	for archive_path in files:
		var write_error := _write_zip_text(packer, archive_path, files[archive_path])
		if write_error != OK:
			packer.close()
			return write_error
	return packer.close()

func read_workbook(file_path: String) -> Dictionary:
	var reader := ZIPReader.new()
	var open_error := reader.open(file_path)
	if open_error != OK:
		return {"ok": false, "error": "Could not open XLSX archive (error %d)." % open_error}
	var file_lookup: Dictionary = {}
	for file_name in reader.get_files():
		file_lookup[file_name] = true
	if not file_lookup.has("xl/workbook.xml") or not file_lookup.has("xl/_rels/workbook.xml.rels"):
		reader.close()
		return {"ok": false, "error": "The file is not a supported XLSX workbook."}

	var shared_strings: Array[String] = []
	if file_lookup.has("xl/sharedStrings.xml"):
		shared_strings = _parse_shared_strings(reader.read_file("xl/sharedStrings.xml"))
	var relationships := _parse_relationships(reader.read_file("xl/_rels/workbook.xml.rels"))
	var workbook_sheets := _parse_workbook_sheets(reader.read_file("xl/workbook.xml"))
	var parsed_sheets: Dictionary = {}
	for sheet in workbook_sheets:
		var relationship_id: String = sheet.relationship_id
		if not relationships.has(relationship_id):
			reader.close()
			return {"ok": false, "error": "Worksheet relationship is missing for '%s'." % sheet.name}
		var worksheet_path := _normalize_worksheet_path(relationships[relationship_id])
		if not file_lookup.has(worksheet_path):
			reader.close()
			return {"ok": false, "error": "Worksheet data is missing for '%s'." % sheet.name}
		parsed_sheets[sheet.name] = _parse_worksheet(reader.read_file(worksheet_path), shared_strings)
	reader.close()
	return {"ok": true, "sheets": parsed_sheets}

func _write_zip_text(packer: ZIPPacker, archive_path: String, content: String) -> Error:
	var start_error := packer.start_file(archive_path)
	if start_error != OK:
		return start_error
	var write_error := packer.write_file(content.to_utf8_buffer())
	if write_error != OK:
		return write_error
	return packer.close_file()

func _build_content_types(sheet_count: int) -> String:
	var overrides := ""
	for index in range(sheet_count):
		overrides += "<Override PartName=\"/xl/worksheets/sheet%d.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>" % (index + 1)
	return XML_HEADER + (
		"<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
		+ "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
		+ "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
		+ "<Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>"
		+ "<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>"
		+ "<Override PartName=\"/docProps/core.xml\" ContentType=\"application/vnd.openxmlformats-package.core-properties+xml\"/>"
		+ "<Override PartName=\"/docProps/app.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.extended-properties+xml\"/>"
		+ overrides
		+ "</Types>"
	)

func _build_root_relationships() -> String:
	return XML_HEADER + (
		"<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
		+ "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/>"
		+ "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties\" Target=\"docProps/core.xml\"/>"
		+ "<Relationship Id=\"rId3\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties\" Target=\"docProps/app.xml\"/>"
		+ "</Relationships>"
	)

func _build_workbook_xml(sheet_names: Array, sheets: Dictionary) -> String:
	var sheet_xml := ""
	for index in range(sheet_names.size()):
		var sheet_name: String = sheet_names[index]
		var state_attribute := " state=\"hidden\"" if sheets[sheet_name].get("hidden", false) else ""
		sheet_xml += "<sheet name=\"%s\" sheetId=\"%d\" r:id=\"rId%d\"%s/>" % [
			sheet_name.xml_escape(), index + 1, index + 1, state_attribute
		]
	return XML_HEADER + (
		"<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">"
		+ "<bookViews><workbookView activeTab=\"0\"/></bookViews>"
		+ "<sheets>" + sheet_xml + "</sheets>"
		+ "<calcPr calcId=\"191029\" fullCalcOnLoad=\"1\"/>"
		+ "</workbook>"
	)

func _build_workbook_relationships(sheet_count: int) -> String:
	var relationship_xml := ""
	for index in range(sheet_count):
		relationship_xml += "<Relationship Id=\"rId%d\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet%d.xml\"/>" % [index + 1, index + 1]
	relationship_xml += "<Relationship Id=\"rId%d\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>" % (sheet_count + 1)
	return XML_HEADER + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" + relationship_xml + "</Relationships>"

func _build_styles_xml() -> String:
	return XML_HEADER + (
		"<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
		+ "<fonts count=\"3\">"
		+ "<font><sz val=\"10\"/><name val=\"Aptos\"/></font>"
		+ "<font><b/><color rgb=\"FFFFFFFF\"/><sz val=\"10\"/><name val=\"Aptos Display\"/></font>"
		+ "<font><color rgb=\"FF667085\"/><sz val=\"10\"/><name val=\"Aptos\"/></font>"
		+ "</fonts>"
		+ "<fills count=\"5\">"
		+ "<fill><patternFill patternType=\"none\"/></fill>"
		+ "<fill><patternFill patternType=\"gray125\"/></fill>"
		+ "<fill><patternFill patternType=\"solid\"><fgColor rgb=\"FF173B57\"/><bgColor indexed=\"64\"/></patternFill></fill>"
		+ "<fill><patternFill patternType=\"solid\"><fgColor rgb=\"FFFFF2CC\"/><bgColor indexed=\"64\"/></patternFill></fill>"
		+ "<fill><patternFill patternType=\"solid\"><fgColor rgb=\"FFF2F4F7\"/><bgColor indexed=\"64\"/></patternFill></fill>"
		+ "</fills>"
		+ "<borders count=\"2\">"
		+ "<border><left/><right/><top/><bottom/><diagonal/></border>"
		+ "<border><left/><right/><top/><bottom style=\"thin\"><color rgb=\"FFD0D5DD\"/></bottom><diagonal/></border>"
		+ "</borders>"
		+ "<cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs>"
		+ "<cellXfs count=\"5\">"
		+ "<xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/>"
		+ "<xf numFmtId=\"0\" fontId=\"1\" fillId=\"2\" borderId=\"1\" xfId=\"0\" applyFont=\"1\" applyFill=\"1\" applyBorder=\"1\" applyAlignment=\"1\"><alignment vertical=\"center\"/></xf>"
		+ "<xf numFmtId=\"0\" fontId=\"0\" fillId=\"3\" borderId=\"0\" xfId=\"0\" applyFill=\"1\" applyAlignment=\"1\"><alignment vertical=\"center\"/></xf>"
		+ "<xf numFmtId=\"0\" fontId=\"2\" fillId=\"4\" borderId=\"0\" xfId=\"0\" applyFont=\"1\" applyFill=\"1\"/>"
		+ "<xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyAlignment=\"1\"><alignment wrapText=\"1\" vertical=\"top\"/></xf>"
		+ "</cellXfs>"
		+ "<cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles>"
		+ "</styleSheet>"
	)

func _build_worksheet_xml(sheet_spec: Dictionary) -> String:
	var headers: Array = sheet_spec.get("headers", [])
	var rows: Array = sheet_spec.get("rows", [])
	var editable_columns: Array = sheet_spec.get("editable_columns", [])
	var hidden_columns: Array = sheet_spec.get("hidden_columns", [])
	var max_column := maxi(headers.size(), 1)
	var last_row := rows.size() + 1
	var last_cell := "%s%d" % [_column_name(max_column - 1), last_row]
	var columns_xml := "<cols>"
	for column_index in range(max_column):
		var width := _column_width(column_index, max_column)
		var hidden := " hidden=\"1\"" if hidden_columns.has(column_index) else ""
		columns_xml += "<col min=\"%d\" max=\"%d\" width=\"%s\" customWidth=\"1\"%s/>" % [column_index + 1, column_index + 1, _number_string(width), hidden]
	columns_xml += "</cols>"

	var data_xml := "<sheetData>"
	data_xml += "<row r=\"1\" ht=\"24\" customHeight=\"1\">"
	for column_index in range(headers.size()):
		data_xml += _build_cell(column_index, 1, headers[column_index], 1)
	data_xml += "</row>"
	for row_index in range(rows.size()):
		var spreadsheet_row := row_index + 2
		data_xml += "<row r=\"%d\">" % spreadsheet_row
		var row_values: Array = rows[row_index]
		for column_index in range(row_values.size()):
			var style_id := 0
			if editable_columns.has(column_index):
				style_id = 2
			elif hidden_columns.has(column_index):
				style_id = 3
			elif column_index == headers.size() - 1:
				style_id = 4
			data_xml += _build_cell(column_index, spreadsheet_row, row_values[column_index], style_id)
		data_xml += "</row>"
	data_xml += "</sheetData>"

	var auto_filter := "<autoFilter ref=\"A1:%s\"/>" % last_cell if headers.size() > 1 else ""
	return XML_HEADER + (
		"<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
		+ "<dimension ref=\"A1:%s\"/>" % last_cell
		+ "<sheetViews><sheetView workbookViewId=\"0\" showGridLines=\"0\"><pane ySplit=\"1\" topLeftCell=\"A2\" activePane=\"bottomLeft\" state=\"frozen\"/></sheetView></sheetViews>"
		+ "<sheetFormatPr defaultRowHeight=\"15\"/>"
		+ columns_xml + data_xml + auto_filter
		+ "</worksheet>"
	)

func _build_cell(column_index: int, row_index: int, value: Variant, style_id: int) -> String:
	var reference := "%s%d" % [_column_name(column_index), row_index]
	var style_attribute := " s=\"%d\"" % style_id if style_id > 0 else ""
	if value == null:
		return "<c r=\"%s\"%s/>" % [reference, style_attribute]
	if value is bool:
		return "<c r=\"%s\" t=\"b\"%s><v>%d</v></c>" % [reference, style_attribute, 1 if value else 0]
	if value is int or value is float:
		return "<c r=\"%s\"%s><v>%s</v></c>" % [reference, style_attribute, _number_string(float(value))]
	if value is Vector2:
		value = "%s, %s" % [_number_string(value.x), _number_string(value.y)]
	var escaped := String(value).xml_escape()
	return "<c r=\"%s\" t=\"inlineStr\"%s><is><t xml:space=\"preserve\">%s</t></is></c>" % [reference, style_attribute, escaped]

func _build_core_properties() -> String:
	var timestamp := Time.get_datetime_string_from_system(true) + "Z"
	return XML_HEADER + (
		"<cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:dcterms=\"http://purl.org/dc/terms/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\">"
		+ "<dc:creator>Vearth Balance Editor</dc:creator>"
		+ "<cp:lastModifiedBy>Vearth Balance Editor</cp:lastModifiedBy>"
		+ "<dcterms:created xsi:type=\"dcterms:W3CDTF\">%s</dcterms:created>" % timestamp
		+ "<dcterms:modified xsi:type=\"dcterms:W3CDTF\">%s</dcterms:modified>" % timestamp
		+ "</cp:coreProperties>"
	)

func _build_app_properties(sheet_names: Array) -> String:
	var titles := ""
	for sheet_name in sheet_names:
		titles += "<vt:lpstr>%s</vt:lpstr>" % String(sheet_name).xml_escape()
	return XML_HEADER + (
		"<Properties xmlns=\"http://schemas.openxmlformats.org/officeDocument/2006/extended-properties\" xmlns:vt=\"http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes\">"
		+ "<Application>Godot Vearth Balance Editor</Application>"
		+ "<HeadingPairs><vt:vector size=\"2\" baseType=\"variant\"><vt:variant><vt:lpstr>Worksheets</vt:lpstr></vt:variant><vt:variant><vt:i4>%d</vt:i4></vt:variant></vt:vector></HeadingPairs>" % sheet_names.size()
		+ "<TitlesOfParts><vt:vector size=\"%d\" baseType=\"lpstr\">%s</vt:vector></TitlesOfParts>" % [sheet_names.size(), titles]
		+ "</Properties>"
	)

func _parse_relationships(xml_bytes: PackedByteArray) -> Dictionary:
	var relationships: Dictionary = {}
	var parser := XMLParser.new()
	if parser.open_buffer(xml_bytes) != OK:
		return relationships
	while parser.read() == OK:
		if parser.get_node_type() != XMLParser.NODE_ELEMENT or _xml_local_name(parser.get_node_name()) != "relationship":
			continue
		var relationship_id := _xml_attribute(parser, "id")
		var target := _xml_attribute(parser, "target")
		if not relationship_id.is_empty() and not target.is_empty():
			relationships[relationship_id] = target
	return relationships

func _parse_workbook_sheets(xml_bytes: PackedByteArray) -> Array[Dictionary]:
	var sheets: Array[Dictionary] = []
	var parser := XMLParser.new()
	if parser.open_buffer(xml_bytes) != OK:
		return sheets
	while parser.read() == OK:
		if parser.get_node_type() != XMLParser.NODE_ELEMENT or _xml_local_name(parser.get_node_name()) != "sheet":
			continue
		var sheet_name := _xml_attribute(parser, "name")
		var relationship_id := _xml_attribute(parser, "id")
		if not sheet_name.is_empty() and not relationship_id.is_empty():
			sheets.append({
				"name": sheet_name,
				"relationship_id": relationship_id,
			})
	return sheets

func _parse_shared_strings(xml_bytes: PackedByteArray) -> Array[String]:
	var strings: Array[String] = []
	var parser := XMLParser.new()
	if parser.open_buffer(xml_bytes) != OK:
		return strings
	var inside_string_item := false
	var inside_text := false
	var current_text := ""
	while parser.read() == OK:
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				var element_name := _xml_local_name(parser.get_node_name())
				if element_name == "si":
					inside_string_item = true
					current_text = ""
				elif inside_string_item and element_name == "t":
					inside_text = true
			XMLParser.NODE_TEXT:
				if inside_string_item and inside_text:
					current_text += parser.get_node_data()
			XMLParser.NODE_ELEMENT_END:
				var element_name := _xml_local_name(parser.get_node_name())
				if element_name == "t":
					inside_text = false
				elif element_name == "si":
					strings.append(current_text)
					inside_string_item = false
	return strings

func _parse_worksheet(xml_bytes: PackedByteArray, shared_strings: Array[String]) -> Dictionary:
	var cells_by_row: Dictionary = {}
	var parser := XMLParser.new()
	if parser.open_buffer(xml_bytes) != OK:
		return {"headers": [], "rows": []}
	var current_reference := ""
	var current_type := ""
	var current_raw := ""
	var inside_value := false
	var inside_inline_text := false
	while parser.read() == OK:
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				var element_name := _xml_local_name(parser.get_node_name())
				if element_name == "c":
					current_reference = _xml_attribute(parser, "r")
					current_type = _xml_attribute(parser, "t", "n")
					current_raw = ""
				elif not current_reference.is_empty() and element_name == "v":
					inside_value = true
				elif not current_reference.is_empty() and element_name == "t":
					inside_inline_text = true
			XMLParser.NODE_TEXT:
				if inside_value or inside_inline_text:
					current_raw += parser.get_node_data()
			XMLParser.NODE_ELEMENT_END:
				var element_name := _xml_local_name(parser.get_node_name())
				if element_name == "v":
					inside_value = false
				elif element_name == "t":
					inside_inline_text = false
				elif element_name == "c" and not current_reference.is_empty():
					_store_parsed_cell(cells_by_row, current_reference, _decode_cell(current_type, current_raw, shared_strings))
					current_reference = ""
	return _rows_from_cells(cells_by_row)

func _xml_local_name(qualified_name: String) -> String:
	var separator_index := qualified_name.rfind(":")
	if separator_index >= 0:
		return qualified_name.substr(separator_index + 1).to_lower()
	return qualified_name.to_lower()

func _xml_attribute(parser: XMLParser, local_name: String, default_value: String = "") -> String:
	var wanted_name := local_name.to_lower()
	for index in range(parser.get_attribute_count()):
		if _xml_local_name(parser.get_attribute_name(index)) == wanted_name:
			return parser.get_attribute_value(index)
	return default_value

func _decode_cell(cell_type: String, raw_value: String, shared_strings: Array[String]) -> Dictionary:
	if raw_value.is_empty():
		return {"kind": "blank", "value": null}
	match cell_type:
		"s":
			var index := int(raw_value)
			if index >= 0 and index < shared_strings.size():
				return {"kind": "string", "value": shared_strings[index]}
			return {"kind": "string", "value": ""}
		"b":
			return {"kind": "bool", "value": raw_value == "1" or raw_value.to_lower() == "true"}
		"inlineStr", "str":
			return {"kind": "string", "value": raw_value}
		_:
			if raw_value.is_valid_float():
				return {"kind": "number", "value": float(raw_value)}
			return {"kind": "string", "value": raw_value}

func _store_parsed_cell(cells_by_row: Dictionary, reference: String, cell: Dictionary) -> void:
	var row_index := _row_number_from_reference(reference)
	var column_index := _column_index_from_reference(reference)
	if row_index <= 0 or column_index < 0:
		return
	if not cells_by_row.has(row_index):
		cells_by_row[row_index] = {}
	cells_by_row[row_index][column_index] = cell

func _rows_from_cells(cells_by_row: Dictionary) -> Dictionary:
	var header_cells: Dictionary = cells_by_row.get(1, {})
	var column_indices: Array = header_cells.keys()
	column_indices.sort()
	var headers: Array[String] = []
	for column_index in column_indices:
		headers.append(String(header_cells[column_index].value))
	var row_numbers: Array = cells_by_row.keys()
	row_numbers.sort()
	var rows: Array[Dictionary] = []
	for row_number in row_numbers:
		if row_number <= 1:
			continue
		var source_cells: Dictionary = cells_by_row[row_number]
		var row: Dictionary = {"row_number": row_number, "cells": {}}
		for header_index in range(headers.size()):
			var column_index: int = column_indices[header_index]
			row.cells[headers[header_index]] = source_cells.get(column_index, {"kind": "blank", "value": null})
		rows.append(row)
	return {"headers": headers, "rows": rows}

func _normalize_worksheet_path(target: String) -> String:
	var normalized := target.replace("\\", "/")
	if normalized.begins_with("/"):
		normalized = normalized.trim_prefix("/")
	if not normalized.begins_with("xl/"):
		normalized = "xl/" + normalized
	return normalized.simplify_path()

func _column_name(column_index: int) -> String:
	var result := ""
	var value := column_index + 1
	while value > 0:
		value -= 1
		result = String.chr(65 + value % 26) + result
		value = value / 26
	return result

func _column_index_from_reference(reference: String) -> int:
	var index := 0
	var found_letter := false
	for character in reference.to_upper():
		if character < "A" or character > "Z":
			break
		found_letter = true
		index = index * 26 + character.unicode_at(0) - 64
	return index - 1 if found_letter else -1

func _row_number_from_reference(reference: String) -> int:
	var digits := ""
	for character in reference:
		if character >= "0" and character <= "9":
			digits += character
	return int(digits) if not digits.is_empty() else -1

func _column_width(column_index: int, column_count: int) -> float:
	var widths := [34.0, 14.0, 28.0, 26.0, 16.0, 16.0, 12.0, 12.0, 12.0, 48.0, 24.0, 60.0]
	if column_count <= 2:
		return 24.0 if column_index == 0 else 72.0
	return widths[column_index] if column_index < widths.size() else 18.0

func _number_string(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return str(int(round(value)))
	return ("%.12f" % value).trim_suffix("0").trim_suffix(".")
