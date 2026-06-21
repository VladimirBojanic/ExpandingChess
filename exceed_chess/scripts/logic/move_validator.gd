class_name MoveValidator
extends RefCounted

# Set by GameManager at the start of each turn.
# en_passant_target: the empty square a pawn can capture into.
# en_passant_pawn:   the pawn that double-stepped and can be taken.
var en_passant_target: Vector2i = Vector2i(-1, -1)
var en_passant_pawn: PieceInstance = null

# Returns cells a piece can MOVE to (non-capture destinations).
func get_legal_moves(piece: PieceInstance, board: BoardManager) -> Array[Vector2i]:
	if piece.is_rooted():
		return []

	# Mage frozen in portal mode: only action is toggling the portal off (own cell).
	if piece.has_tag("mage") and board.is_in_portal_mode(piece):
		return [piece.anchor_cell]

	var raw := _raw_destinations(piece, board, false)
	if piece.has_tag("royalty"):
		raw.append_array(_castling_destinations(piece, board))
	# Mage on eligible tile can open a portal (own cell as toggle destination).
	if piece.has_tag("mage") and _can_open_portal(piece, board):
		raw.append(piece.anchor_cell)
	# Any piece adjacent to an open friendly portal can transit to the exit portal.
	raw.append_array(_portal_transit_moves(piece, board))
	return _filter_for_check(piece, board, raw)

# Returns cells a piece can CAPTURE on (enemy-occupied).
func get_legal_captures(piece: PieceInstance, board: BoardManager) -> Array[Vector2i]:
	if piece.is_rooted():
		return []
	var raw := _raw_captures(piece, board)
	var filtered := _filter_for_check(piece, board, raw)
	filtered.append_array(_en_passant_captures_filtered(piece, board))
	return filtered

# All destinations (moves + captures combined) used internally and for attack coverage.
func all_reachable(piece: PieceInstance, board: BoardManager) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.append_array(_raw_destinations(piece, board, false))
	result.append_array(_raw_captures(piece, board))
	return result

# Attack coverage map: all cells any enemy piece can reach (for check detection).
# Does NOT filter for the enemy's own king safety — avoids recursion.
func get_attack_coverage(player_id: int, board: BoardManager) -> Array[Vector2i]:
	var enemy_id := 1 - player_id
	var coverage: Array[Vector2i] = []
	for piece in board.get_pieces_for_player(enemy_id):
		coverage.append_array(_raw_captures(piece, board))
		coverage.append_array(_raw_destinations(piece, board, true))
	return coverage

func is_in_check(player_id: int, board: BoardManager) -> bool:
	var king := _find_king(player_id, board)
	if not king:
		return false
	var coverage := get_attack_coverage(player_id, board)
	for cell in king.occupied_cells():
		if cell in coverage:
			return true
	return false

func has_any_legal_action(player_id: int, board: BoardManager) -> bool:
	for piece in board.get_pieces_for_player(player_id):
		if not get_legal_moves(piece, board).is_empty():
			return true
		if not get_legal_captures(piece, board).is_empty():
			return true
	return false

# ── Raw destination generation (no check filtering) ───────────────────────────

func _raw_destinations(piece: PieceInstance, board: BoardManager, for_coverage: bool) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for rule in piece.get_all_movement_rules():
		if rule.capture_only:
			continue
		result.append_array(_apply_rule(piece, board, rule, false, for_coverage))
	return _unique(result)

func _raw_captures(piece: PieceInstance, board: BoardManager) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for rule in piece.get_all_movement_rules():
		if rule.move_only:
			continue
		result.append_array(_apply_rule(piece, board, rule, true, false))
	return _unique(result)

func _apply_rule(piece: PieceInstance, board: BoardManager, rule: MovementRule, capture_pass: bool, for_coverage: bool) -> Array[Vector2i]:
	match rule.pattern:
		MovementRule.MovementPattern.SLIDE:
			return _slide(piece, board, rule, capture_pass)
		MovementRule.MovementPattern.STEP:
			return _step(piece, board, rule, capture_pass, for_coverage)
		MovementRule.MovementPattern.JUMP:
			return _jump(piece, board, rule, capture_pass)
		MovementRule.MovementPattern.L_SHAPE:
			return _l_shape(piece, board, rule, capture_pass)
		MovementRule.MovementPattern.BLOCK_SLIDE:
			return _block_slide(piece, board, rule, capture_pass)
		_:
			return []

func _slide(piece: PieceInstance, board: BoardManager, rule: MovementRule, capture_pass: bool) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dir in rule.directions:
		var pos := piece.anchor_cell + dir
		var steps := 0
		var max_s := rule.max_range if rule.max_range > 0 else 9999
		while board.is_valid_cell(pos) and steps < max_s:
			var occupant := board.get_piece(pos)
			if occupant:
				if occupant.owner_id != piece.owner_id and capture_pass:
					if not _is_immune(occupant, piece):
						result.append(pos)
				break
			elif not capture_pass:
				result.append(pos)
			pos += dir
			steps += 1
	return result

func _step(piece: PieceInstance, board: BoardManager, rule: MovementRule, capture_pass: bool, for_coverage: bool) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var effective_range := rule.max_range if rule.max_range > 0 else 1
	# For pawns: range can be 2 on first move; directions are owner-relative
	if piece.has_tag("pawn") and not piece.has_moved and not capture_pass:
		effective_range = 2
	for base_dir in rule.directions:
		# Flip vertical direction for Player 1 (moves downward on the board)
		var dir := base_dir
		if piece.has_tag("pawn") and piece.owner_id == 1:
			dir = Vector2i(base_dir.x, -base_dir.y)
		for step in range(1, effective_range + 1):
			var pos := piece.anchor_cell + dir * step
			if not board.is_valid_cell(pos):
				break
			var occupant := board.get_piece(pos)
			if occupant:
				if occupant.owner_id != piece.owner_id and capture_pass and not _is_immune(occupant, piece):
					result.append(pos)
				break
			elif not capture_pass or for_coverage:
				result.append(pos)
	return result

func _jump(piece: PieceInstance, board: BoardManager, rule: MovementRule, capture_pass: bool) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dir in rule.directions:
		var pos := piece.anchor_cell + dir
		if not board.is_valid_cell(pos):
			continue
		var occupant := board.get_piece(pos)
		if occupant:
			if occupant.owner_id != piece.owner_id and capture_pass and not _is_immune(occupant, piece):
				result.append(pos)
		elif not capture_pass:
			result.append(pos)
	return result

func _l_shape(piece: PieceInstance, board: BoardManager, rule: MovementRule, capture_pass: bool) -> Array[Vector2i]:
	# L-shape: 1 step orthogonally + 1 step perpendicular — BLOCKED (not a jump)
	var result: Array[Vector2i] = []
	var ortho: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	for first: Vector2i in ortho:
		var mid: Vector2i = piece.anchor_cell + first
		if not board.is_valid_cell(mid) or board.get_piece(mid):
			continue
		var perp: Array[Vector2i] = []
		if first.x == 0:
			perp = [Vector2i(1, 0), Vector2i(-1, 0)]
		else:
			perp = [Vector2i(0, 1), Vector2i(0, -1)]
		for second: Vector2i in perp:
			var dest: Vector2i = mid + second
			if not board.is_valid_cell(dest):
				continue
			var occupant := board.get_piece(dest)
			if occupant:
				if occupant.owner_id != piece.owner_id and capture_pass and not _is_immune(occupant, piece):
					result.append(dest)
			elif not capture_pass:
				result.append(dest)
	return result

func _block_slide(piece: PieceInstance, board: BoardManager, rule: MovementRule, capture_pass: bool) -> Array[Vector2i]:
	# Entire multi-cell piece slides as a block. Only orthogonal in MVP.
	var result: Array[Vector2i] = []
	for dir in rule.directions:
		var new_anchor := piece.anchor_cell + dir
		var steps := 0
		var max_s := rule.max_range if rule.max_range > 0 else 9999
		while steps < max_s:
			if not _block_can_fit(piece, board, new_anchor):
				break
			var occupants := _block_occupants(piece, board, new_anchor)
			var enemy_occupants := occupants.filter(func(o): return o.owner_id != piece.owner_id)
			var swept := _apply_sweep(piece, board, new_anchor, dir, rule)
			if enemy_occupants.is_empty():
				if not capture_pass:
					result.append(new_anchor)
				new_anchor += dir
				steps += 1
			else:
				# Block stops here; can hit (if capture pass)
				if capture_pass:
					for occ in enemy_occupants:
						if not _is_immune(occ, piece):
							result.append(new_anchor)
				break
	return result

func _block_can_fit(piece: PieceInstance, board: BoardManager, anchor: Vector2i) -> bool:
	for row in range(piece.definition.size.y):
		for col in range(piece.definition.size.x):
			var pos := anchor + Vector2i(col, row)
			if not board.is_valid_cell(pos):
				return false
	return true

func _block_occupants(piece: PieceInstance, board: BoardManager, anchor: Vector2i) -> Array[PieceInstance]:
	var result: Array[PieceInstance] = []
	for row in range(piece.definition.size.y):
		for col in range(piece.definition.size.x):
			var pos := anchor + Vector2i(col, row)
			var occ := board.get_piece(pos)
			if occ and occ != piece and occ not in result:
				result.append(occ)
	return result

func _apply_sweep(piece: PieceInstance, board: BoardManager, anchor: Vector2i, dir: Vector2i, rule: MovementRule) -> Array[PieceInstance]:
	if rule.sweep_tags.is_empty():
		return []
	var swept: Array[PieceInstance] = []
	var check_anchor := piece.anchor_cell + dir
	while check_anchor != anchor:
		var occs := _block_occupants(piece, board, check_anchor)
		for occ in occs:
			for tag in rule.sweep_tags:
				if occ.has_tag(tag) and occ not in swept:
					swept.append(occ)
					break
		check_anchor += dir
	return swept

# ── Portal ────────────────────────────────────────────────────────────────────

func _can_open_portal(piece: PieceInstance, board: BoardManager) -> bool:
	if board.is_in_portal_mode(piece):
		return false
	# Void Mage can open from anywhere; base Mage needs an edge tile.
	return piece.has_tag("void_mage") or board.is_bridge_start_tile(piece.anchor_cell)

func _portal_transit_moves(piece: PieceInstance, board: BoardManager) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var player_portals := board.get_portals_for_player(piece.owner_id)
	if player_portals.size() < 2:
		return result
	var ortho: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	for i in range(player_portals.size()):
		var entry_cell := player_portals[i].mage.anchor_cell
		if not _is_ortho_adjacent(piece.anchor_cell, entry_cell):
			continue
		# Piece is adjacent to portal i — can exit adjacent to any other portal.
		for j in range(player_portals.size()):
			if i == j:
				continue
			var exit_cell := player_portals[j].mage.anchor_cell
			for dir in ortho:
				var pos := exit_cell + dir
				if board.is_valid_cell(pos) and board.is_empty(pos):
					result.append(pos)
	return _unique(result)

func _is_ortho_adjacent(a: Vector2i, b: Vector2i) -> bool:
	var d := (a - b).abs()
	return (d.x == 1 and d.y == 0) or (d.x == 0 and d.y == 1)

# ── Castling ──────────────────────────────────────────────────────────────────

func _castling_destinations(king: PieceInstance, board: BoardManager) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if king.has_moved or is_in_check(king.owner_id, board):
		return result
	var back_row := king.anchor_cell.y
	for rook in board.get_pieces_for_player(king.owner_id):
		if rook.definition.id != "rook" or rook.has_moved:
			continue
		if rook.anchor_cell.y != back_row:
			continue
		var dir := 1 if rook.anchor_cell.x > king.anchor_cell.x else -1
		var king_dest := king.anchor_cell + Vector2i(dir * 2, 0)
		# All squares between king and rook must be empty
		var col := king.anchor_cell.x + dir
		var path_clear := true
		while col != rook.anchor_cell.x:
			if board.get_piece(Vector2i(col, back_row)) != null:
				path_clear = false
				break
			col += dir
		if not path_clear:
			continue
		# King must not pass through check on the intermediate square
		var pass_through := king.anchor_cell + Vector2i(dir, 0)
		if _leaves_king_in_check(king, board, pass_through, []):
			continue
		result.append(king_dest)
	return result

# ── En passant ─────────────────────────────────────────────────────────────────

func _en_passant_captures_filtered(piece: PieceInstance, board: BoardManager) -> Array[Vector2i]:
	if not piece.has_tag("pawn"):
		return []
	if en_passant_target == Vector2i(-1, -1) or en_passant_pawn == null:
		return []
	if en_passant_pawn.owner_id == piece.owner_id:
		return []
	# Capturing pawn must be on the same row as the double-stepped pawn, adjacent file
	if piece.anchor_cell.y != en_passant_pawn.anchor_cell.y:
		return []
	if abs(piece.anchor_cell.x - en_passant_pawn.anchor_cell.x) != 1:
		return []
	# Check that this capture doesn't expose own king (simulate removing the ep pawn too)
	if _leaves_king_in_check(piece, board, en_passant_target, [en_passant_pawn]):
		return []
	return [en_passant_target]

# ── Check filtering ────────────────────────────────────────────────────────────
# Every move is simulated on the board to verify it doesn't leave the king exposed.
# This handles pinned pieces, forced block-of-check, and king walk-into-check.

func _filter_for_check(piece: PieceInstance, board: BoardManager, destinations: Array[Vector2i]) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dest in destinations:
		if not _leaves_king_in_check(piece, board, dest, []):
			result.append(dest)
	return result

func _leaves_king_in_check(piece: PieceInstance, board: BoardManager, dest: Vector2i, extra_remove: Array) -> bool:
	# Collect pieces that occupy the destination cells (will be displaced by the move).
	var displaced: Array[PieceInstance] = []
	for row in range(piece.definition.size.y):
		for col in range(piece.definition.size.x):
			var target_pos := dest + Vector2i(col, row)
			var occ: PieceInstance = board.get_piece(target_pos)
			if occ != null and occ != piece and occ not in displaced:
				displaced.append(occ)
	# Extra pieces to remove from the board during simulation (e.g. en passant target pawn).
	for extra in extra_remove:
		if extra not in displaced:
			displaced.append(extra)

	# Apply simulated move.
	var saved_anchor := piece.anchor_cell
	board.remove_piece(piece)
	for cap in displaced:
		board.remove_piece(cap)
	piece.anchor_cell = dest
	board.place_piece(piece)

	var in_check := is_in_check(piece.owner_id, board)

	# Restore board to original state.
	board.remove_piece(piece)
	piece.anchor_cell = saved_anchor
	board.place_piece(piece)
	for cap in displaced:
		board.place_piece(cap)

	return in_check

# ── Helpers ───────────────────────────────────────────────────────────────────

func _is_immune(target: PieceInstance, attacker: PieceInstance) -> bool:
	return attacker.definition.id in target.definition.immunities

func _find_king(player_id: int, board: BoardManager) -> PieceInstance:
	for piece in board.get_pieces_for_player(player_id):
		if piece.has_tag("royalty"):
			return piece
	return null

func _unique(arr: Array[Vector2i]) -> Array[Vector2i]:
	var seen: Array[Vector2i] = []
	for v in arr:
		if v not in seen:
			seen.append(v)
	return seen
