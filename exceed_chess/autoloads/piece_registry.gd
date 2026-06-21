extends Node

const PIECES_DIR := "res://resources/pieces/"

var _registry: Dictionary = {}  # String id → PieceDefinition

func _ready() -> void:
	_load_all()

func _load_all() -> void:
	var dir := DirAccess.open(PIECES_DIR)
	if not dir:
		push_error("PieceRegistry: cannot open directory " + PIECES_DIR)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var path := PIECES_DIR + file_name
			var definition := load(path) as PieceDefinition
			if definition and definition.id != "":
				_registry[definition.id] = definition
			else:
				push_warning("PieceRegistry: skipped invalid resource at " + path)
		file_name = dir.get_next()
	dir.list_dir_end()

func get_definition(id: String) -> PieceDefinition:
	if not _registry.has(id):
		push_error("PieceRegistry: no piece with id '%s'" % id)
		return null
	return _registry[id]

func all_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in _registry:
		ids.append(key)
	return ids
