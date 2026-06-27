class_name HumanController
extends PlayerController

# Set by Game scene after creating the controller
var renderer: BoardRenderer = null
var board: BoardManager = null
var move_validator: MoveValidator = null

var _selected_piece: PieceInstance = null
var _waiting: bool = false

func request_action(b: BoardManager) -> void:
	board = b
	_waiting = true
	_selected_piece = null
	renderer.clear_selection()

func handle_click(screen_pos: Vector2) -> void:
	if not _waiting:
		return
	var cell := renderer.cell_at_screen(screen_pos)
	if not board.is_valid_cell(cell):
		_deselect()
		return
	var piece := board.get_piece(cell)

	# --- Click on a legal move destination ---
	if _selected_piece:
		if cell in _get_current_legal_moves():
			_submit_move(_selected_piece, cell)
			return
		if cell in _get_current_legal_captures():
			_submit_move(_selected_piece, cell)
			return

	# --- Click on own piece: select it ---
	if piece and piece.owner_id == player_id:
		_select(piece)
		return

	_deselect()

func _select(piece: PieceInstance) -> void:
	_selected_piece = piece
	var moves := move_validator.get_legal_moves(piece, board)
	var captures := move_validator.get_legal_captures(piece, board)
	renderer.set_selection(piece.anchor_cell, moves, captures)

	# Highlight bridge-start tiles among legal moves in a distinct colour
	renderer.bridge_move_cells = []
	if piece.has_tag("bridge_builder"):
		for pos in moves:
			if board.is_bridge_start_tile(pos):
				renderer.bridge_move_cells.append(pos)
	renderer.queue_redraw()

func _deselect() -> void:
	_selected_piece = null
	renderer.clear_selection()

func _get_current_legal_moves() -> Array[Vector2i]:
	if not _selected_piece:
		return []
	return move_validator.get_legal_moves(_selected_piece, board)

func _get_current_legal_captures() -> Array[Vector2i]:
	if not _selected_piece:
		return []
	return move_validator.get_legal_captures(_selected_piece, board)

func _submit_move(piece: PieceInstance, dest: Vector2i) -> void:
	_waiting = false
	_selected_piece = null
	renderer.clear_selection()
	action_ready.emit({"type": "move", "piece": piece, "destination": dest})
