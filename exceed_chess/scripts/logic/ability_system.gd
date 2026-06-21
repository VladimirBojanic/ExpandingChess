class_name AbilitySystem
extends RefCounted

# Checks if the piece that just moved has any AFTER_MOVE abilities to trigger.
# Returns a Dictionary describing the bonus action, or {} if none.
#
# Returned dict shape:
#   { "type": "stomp",      "piece": PieceInstance, "targets": Array[Vector2i] }
#   { "type": "extra_move", "piece": PieceInstance, "targets": Array[Vector2i] }
func check_post_move(piece: PieceInstance, board: BoardManager) -> Dictionary:
	for ability in piece.get_all_abilities():
		if ability.trigger != AbilityDefinition.AbilityTrigger.AFTER_MOVE:
			continue
		match ability.effect_type:
			AbilityDefinition.EffectType.STOMP:
				var targets := _stomp_targets(piece, board)
				if not targets.is_empty():
					return {"type": "stomp", "piece": piece, "targets": targets}
			AbilityDefinition.EffectType.EXTRA_MOVE:
				var targets := _extra_move_targets(piece, board)
				if not targets.is_empty():
					return {"type": "extra_move", "piece": piece, "targets": targets}
	return {}

func _stomp_targets(piece: PieceInstance, board: BoardManager) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var dirs: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1),
	                              Vector2i(1,1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(-1,-1)]
	for dir in dirs:
		var pos := piece.anchor_cell + dir
		var occ := board.get_piece(pos)
		if occ and occ.owner_id != piece.owner_id:
			result.append(pos)
	return result

func _extra_move_targets(piece: PieceInstance, board: BoardManager) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var dirs: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	for dir in dirs:
		var pos := piece.anchor_cell + dir
		if not board.is_valid_cell(pos):
			continue
		var occ := board.get_piece(pos)
		if occ == null or occ.owner_id != piece.owner_id:
			result.append(pos)
	return result
