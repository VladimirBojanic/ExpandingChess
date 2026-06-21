class_name UpgradeRegistry
extends RefCounted

const UPGRADES_DIR := "res://resources/upgrades/"

var _all: Array[UpgradeDefinition] = []

func _init() -> void:
	_load_all()

func _load_all() -> void:
	var dir := DirAccess.open(UPGRADES_DIR)
	if not dir:
		push_error("UpgradeRegistry: cannot open " + UPGRADES_DIR)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var upgrade := load(UPGRADES_DIR + file_name) as UpgradeDefinition
			if upgrade and upgrade.id != "":
				_all.append(upgrade)
		file_name = dir.get_next()
	dir.list_dir_end()

# Returns upgrades the given piece can receive (affordable, eligible, not already applied).
func available_for_piece(piece: PieceInstance, sp: int, game_phase: int) -> Array[UpgradeDefinition]:
	var result: Array[UpgradeDefinition] = []
	for upgrade in _all:
		if upgrade.sp_cost > sp:
			continue
		if upgrade.phase_required > game_phase:
			continue
		if piece.has_upgrade(upgrade.id):
			continue
		if _is_eligible(piece, upgrade):
			result.append(upgrade)
	return result

# Returns all upgrades available to any piece owned by player_id.
func available_for_player(board: BoardManager, player_id: int, sp: int, game_phase: int) -> Array[UpgradeDefinition]:
	var result: Array[UpgradeDefinition] = []
	for piece in board.get_pieces_for_player(player_id):
		for upgrade in available_for_piece(piece, sp, game_phase):
			if upgrade not in result:
				result.append(upgrade)
	return result

# Returns all pieces owned by player_id that are eligible for the given upgrade.
func eligible_pieces(board: BoardManager, player_id: int, upgrade: UpgradeDefinition) -> Array[PieceInstance]:
	var result: Array[PieceInstance] = []
	for piece in board.get_pieces_for_player(player_id):
		if _is_eligible(piece, upgrade):
			result.append(piece)
	return result

# Apply an upgrade to a piece. Returns the resulting PieceInstance (may be a new object on transform).
func apply(upgrade: UpgradeDefinition, piece: PieceInstance, board: BoardManager) -> PieceInstance:
	if upgrade.transforms_to != "":
		return _transform(piece, upgrade.transforms_to, board)
	piece.applied_upgrades.append(upgrade)   # store the object so get_all_movement_rules() can read it directly
	return piece

func _transform(piece: PieceInstance, target_id: String, board: BoardManager) -> PieceInstance:
	var new_def := PieceRegistry.get_definition(target_id)
	if not new_def:
		push_error("UpgradeRegistry: transform target '%s' not found" % target_id)
		return piece
	var new_piece := PieceInstance.create(new_def, piece.owner_id, piece.anchor_cell)
	board.remove_piece(piece)
	board.place_piece(new_piece)
	EventBus.piece_promoted.emit(new_piece, piece.definition.id, target_id)
	return new_piece

func _is_eligible(piece: PieceInstance, upgrade: UpgradeDefinition) -> bool:
	if upgrade.eligible_piece_tags.is_empty():
		return false
	for tag in upgrade.eligible_piece_tags:
		if not piece.has_tag(tag):
			return false
	return true
