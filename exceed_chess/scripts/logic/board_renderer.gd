class_name BoardRenderer
extends Node2D

const CELL_SIZE := 72.0
const COLORS := {
	"light_cell":      Color(0.94, 0.85, 0.71),
	"dark_cell":       Color(0.56, 0.35, 0.18),
	"selected":        Color(0.27, 0.72, 0.27, 0.7),
	"legal_move":      Color(0.27, 0.72, 0.27, 0.4),
	"legal_capture":   Color(0.87, 0.27, 0.27, 0.5),
	"portal_toggle":   Color(0.55, 0.10, 0.90, 0.7),
	"portal_transit":  Color(0.10, 0.75, 0.90, 0.45),
	"portal_open":     Color(0.65, 0.20, 1.00, 0.85),
	"bridge_tile":     Color(0.70, 0.60, 0.40),
	"relic_tile":      Color(0.95, 0.85, 0.10, 0.6),
	"check_highlight": Color(0.95, 0.20, 0.20, 0.5),
	"void_cell":       Color(0.05, 0.05, 0.10),
}

var board: BoardManager = null
var _board_origin: Vector2 = Vector2.ZERO

# Display state (set by HumanController)
var selected_cell: Vector2i = Vector2i(-1, -1)
var legal_moves: Array[Vector2i] = []
var legal_captures: Array[Vector2i] = []
var check_cell: Vector2i = Vector2i(-1, -1)
var upgrade_targets: Array[Vector2i] = []
var _open_portal_cells: Array[Vector2i] = []
var bridge_move_cells: Array[Vector2i] = []  # edge cells that would start a bridge if moved to

# Per-island visual offsets — applied after Sinister splits drift islands apart.
# Dictionary: island_id (int) → Vector2 (pixel offset)
var _island_offsets: Dictionary = {}

func _ready() -> void:
	EventBus.island_added.connect(_on_board_changed)
	EventBus.board_fractured.connect(_on_board_changed)
	EventBus.bridge_completed.connect(_on_bridge_complete)
	EventBus.piece_moved.connect(_on_piece_moved)
	EventBus.piece_captured.connect(_on_board_changed)
	EventBus.relic_spawned.connect(_on_board_changed)
	EventBus.check_detected.connect(_on_check)
	EventBus.check_resolved.connect(_on_check_resolved)
	EventBus.portal_opened.connect(_on_portal_opened)
	EventBus.portal_closed.connect(_on_portal_closed)

func get_board_origin() -> Vector2:
	return _board_origin

func initialize(board_manager: BoardManager) -> void:
	board = board_manager
	_recalculate_origin()
	queue_redraw()

func set_selection(cell: Vector2i, moves: Array[Vector2i], captures: Array[Vector2i]) -> void:
	selected_cell = cell
	legal_moves = moves
	legal_captures = captures
	queue_redraw()

func clear_selection() -> void:
	selected_cell = Vector2i(-1, -1)
	legal_moves = []
	legal_captures = []
	bridge_move_cells = []
	queue_redraw()

func set_upgrade_targets(cells: Array) -> void:
	upgrade_targets = []
	for c in cells:
		upgrade_targets.append(c)
	queue_redraw()

func clear_upgrade_targets() -> void:
	upgrade_targets = []
	queue_redraw()

func cell_at_screen(screen_pos: Vector2) -> Vector2i:
	if not _island_offsets.is_empty() and board:
		# After a sinister split, tiles are no longer on a uniform grid — check each one
		for pos in board.cells:
			if _cell_rect(pos).has_point(screen_pos):
				return pos
		return Vector2i(-1, -1)
	# Fast path before any split: simple grid math
	var local_pos := screen_pos - _board_origin
	var col := int(local_pos.x / CELL_SIZE)
	var row := int(local_pos.y / CELL_SIZE)
	return Vector2i(col, row)

func cell_center(cell: Vector2i) -> Vector2:
	return _board_origin + Vector2(cell.x * CELL_SIZE + CELL_SIZE * 0.5,
								   cell.y * CELL_SIZE + CELL_SIZE * 0.5)

func _draw() -> void:
	if not board:
		return
	_draw_cells()
	_draw_highlights()
	_draw_pieces()
	if _island_offsets.is_empty():
		_draw_coordinates()

func _draw_cells() -> void:
	for pos in board.cells:
		var cell := board.get_cell(pos) as BoardManager.CellState
		var rect := _cell_rect(pos)
		var color: Color
		match cell.type:
			BoardManager.CellType.BRIDGE:
				color = COLORS["bridge_tile"]
			BoardManager.CellType.RELIC:
				color = COLORS["relic_tile"]
			_:
				if _island_offsets.is_empty():
					# Pre-sinister: classic chess checkerboard
					color = COLORS["light_cell"] if (pos.x + pos.y) % 2 == 0 else COLORS["dark_cell"]
				else:
					# Post-sinister: uniform island shading, no chess pattern
					color = Color(0.45, 0.60, 0.45) if (pos.x + pos.y) % 2 == 0 else Color(0.30, 0.45, 0.30)
		draw_rect(rect, color)
		draw_rect(rect, Color.BLACK, false, 1.0)

func _draw_highlights() -> void:
	# Open portal glow — drawn before selection so selection can overlay
	for pos in _open_portal_cells:
		if board.is_valid_cell(pos):
			draw_rect(_cell_rect(pos), COLORS["portal_open"])

	if selected_cell != Vector2i(-1, -1) and board.is_valid_cell(selected_cell):
		draw_rect(_cell_rect(selected_cell), COLORS["selected"])

	for pos in bridge_move_cells:
		if pos not in legal_moves:
			continue
		draw_rect(_cell_rect(pos), COLORS["bridge_tile"])
		_draw_dot(pos, Color(0.9, 0.75, 0.3))

	for pos in legal_moves:
		if pos in bridge_move_cells:
			continue  # already drawn above
		if pos == selected_cell:
			# Mage's own cell = portal toggle action
			draw_rect(_cell_rect(pos), COLORS["portal_toggle"])
			_draw_dot(pos, Color(0.9, 0.5, 1.0))
		else:
			draw_rect(_cell_rect(pos), COLORS["legal_move"])
			_draw_dot(pos, COLORS["selected"])

	for pos in legal_captures:
		draw_rect(_cell_rect(pos), COLORS["legal_capture"])

	if check_cell != Vector2i(-1, -1):
		draw_rect(_cell_rect(check_cell), COLORS["check_highlight"])

	for pos in upgrade_targets:
		draw_rect(_cell_rect(pos), Color(0.4, 0.2, 0.8, 0.6))
		_draw_dot(pos, Color(0.6, 0.3, 1.0))

func _draw_pieces() -> void:
	for pos in board.cells:
		var piece := board.get_piece(pos) as PieceInstance
		if piece == null or piece.anchor_cell != pos:
			continue
		var anchor_rect := _cell_rect(pos)
		var w := anchor_rect.size.x * piece.definition.size.x
		var h := anchor_rect.size.y * piece.definition.size.y
		var full_rect := Rect2(anchor_rect.position, Vector2(w, h))
		var piece_color: Color
		var border_color: Color
		if piece.owner_id == -1:
			piece_color = Color(0.55, 0.10, 0.10)
			border_color = Color(1.0, 0.4, 0.4)
		elif piece.owner_id == 0:
			piece_color = Color(0.85, 0.85, 0.95)
			border_color = Color(0.3, 0.3, 0.4)
		else:
			piece_color = Color(0.15, 0.12, 0.18)
			border_color = Color(0.7, 0.7, 0.8)
		var inset := full_rect.grow(-6.0)
		draw_rect(inset, piece_color)
		draw_rect(inset, border_color, false, 2.0)
		var label := _piece_label(piece)
		var font := ThemeDB.fallback_font
		var font_size := 14 if piece.definition.size == Vector2i(1, 1) else 18
		var text_pos := inset.get_center() - Vector2(font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * 0.5, -font_size * 0.35)
		draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, border_color)

func _draw_coordinates() -> void:
	var font := ThemeDB.fallback_font
	var font_size := 11
	var col_labels := "ABCDEFGH"
	# Find the bounding box of valid cells to know where to draw labels
	var min_col := 9999
	var max_col := -9999
	var min_row := 9999
	var max_row := -9999
	for pos in board.cells:
		if pos.x < min_col: min_col = pos.x
		if pos.x > max_col: max_col = pos.x
		if pos.y < min_row: min_row = pos.y
		if pos.y > max_row: max_row = pos.y
	for col in range(min_col, max_col + 1):
		if col - min_col < col_labels.length():
			var label := col_labels[col - min_col]
			var x := _board_origin.x + col * CELL_SIZE + CELL_SIZE * 0.5 - 4
			draw_string(font, Vector2(x, _board_origin.y - 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.LIGHT_GRAY)
	for row in range(min_row, max_row + 1):
		var label := str(8 - row)
		var y := _board_origin.y + row * CELL_SIZE + CELL_SIZE * 0.5 + 4
		draw_string(font, Vector2(_board_origin.x - 16, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.LIGHT_GRAY)

func set_island_offsets(offsets: Dictionary) -> void:
	_island_offsets = offsets
	_recalculate_origin()
	queue_redraw()

func _raw_cell_offset(pos: Vector2i) -> Vector2:
	# Position WITHOUT board_origin — used internally for bounds calculation
	var island_id := board.get_island_id(pos) if board else -1
	var island_shift: Vector2 = _island_offsets.get(island_id, Vector2.ZERO)
	return Vector2(pos.x, pos.y) * CELL_SIZE + island_shift

func _cell_rect(pos: Vector2i) -> Rect2:
	return Rect2(_board_origin + _raw_cell_offset(pos), Vector2(CELL_SIZE, CELL_SIZE))

func _draw_dot(pos: Vector2i, color: Color) -> void:
	draw_circle(_cell_rect(pos).get_center(), 10.0, color)

func _piece_label(piece: PieceInstance) -> String:
	var labels := {
		"pawn": "P", "knight": "N", "bishop": "B", "rook": "R",
		"queen": "Q", "king": "K", "mage": "M",
			"dragon": "DRG", "hydra": "HYD", "neutral_monster": "BST",
	}
	return labels.get(piece.definition.id, piece.definition.id.substr(0, 3).to_upper())

func _recalculate_origin() -> void:
	if not board or board.cells.is_empty():
		return
	var min_x := 99999.0
	var min_y := 99999.0
	for pos in board.cells:
		var raw := _raw_cell_offset(pos)
		if raw.x < min_x: min_x = raw.x
		if raw.y < min_y: min_y = raw.y
	_board_origin = Vector2(-min_x, -min_y) + Vector2(40, 40)

func _on_board_changed(_a = null, _b = null) -> void:
	_recalculate_origin()
	queue_redraw()

func _on_bridge_complete(_id, _from, _to) -> void:
	queue_redraw()

func _on_piece_moved(_piece, _from, _to) -> void:
	queue_redraw()

func _on_check(king: Object) -> void:
	check_cell = (king as PieceInstance).anchor_cell
	queue_redraw()

func _on_check_resolved() -> void:
	check_cell = Vector2i(-1, -1)
	queue_redraw()

func _on_portal_opened(mage: Object) -> void:
	var cell := (mage as PieceInstance).anchor_cell
	if cell not in _open_portal_cells:
		_open_portal_cells.append(cell)
	queue_redraw()

func _on_portal_closed(mage: Object) -> void:
	var cell := (mage as PieceInstance).anchor_cell
	_open_portal_cells.erase(cell)
	queue_redraw()
