extends Node

enum TurnPhase { NORMAL, BONUS_STOMP, BONUS_EXTRA_MOVE, UPGRADE_SELECT_PIECE }

var board: BoardManager = null
var validator: MoveValidator = null
var upgrade_registry = null  # UpgradeRegistry — untyped until Godot indexes the class
var ability_system = null    # AbilitySystem
var board_renderer: BoardRenderer = null
var controllers: Array = []

var current_player: int = 0
var turn_number: int = 1
var game_phase: int = 0   # 0 = pre-50, 50 = post-first-sinister, 100 = post-second
var sp: Array[int] = [0, 0]

var _ep_pawn: PieceInstance = null
var _ep_target: Vector2i = Vector2i(-1, -1)

var _phase: TurnPhase = TurnPhase.NORMAL
var _bonus_piece: PieceInstance = null
var _bonus_targets: Array[Vector2i] = []
var _pending_upgrade = null  # UpgradeDefinition

# Bridge tracking — list of active BridgeState objects being built
var _bridges_building: Array = []

# Camera panning (right-click drag)
var _panning: bool = false
var _pan_mouse_start: Vector2 = Vector2.ZERO
var _pan_renderer_start: Vector2 = Vector2.ZERO

# Sinister / Relic
var relic_points: Array[int] = [0, 0]
var _relic_cell: Vector2i = Vector2i(-1, -1)
var _relic_was_claimed: bool = false

# No cells are removed in the Sinister split.
# Instead the 8x8 board is logically divided into 4 quadrants + a new 3x3 center island.
# The quadrants are defined by column/row thresholds.
const SINISTER_ISLAND_ORIGIN: Vector2i = Vector2i(20, 3)  # far-right coords for new island
const RELIC_SPAWN_50: Vector2i = Vector2i(21, 4)           # center cell of new 3x3 island

# HUD nodes
var _turn_label: Label = null
var _sp_label: Label = null
var _upgrade_btn: Button = null
var _upgrade_panel: Panel = null
var _upgrade_vbox: VBoxContainer = null
var _relic_label: Label = null
var _sinister_label: Label = null
var _win_panel: Panel = null
var _win_label: Label = null

func _ready() -> void:
	_build_scene()

	board = BoardManager.new()
	board.setup_8x8()
	validator = MoveValidator.new()
	upgrade_registry = UpgradeRegistry.new()
	ability_system = AbilitySystem.new()
	board_renderer.initialize(board)

	for i in range(2):
		var ctrl := HumanController.new()
		ctrl.player_id = i
		ctrl.renderer = board_renderer
		ctrl.board = board
		ctrl.move_validator = validator
		ctrl.action_ready.connect(_on_action_ready)
		controllers.append(ctrl)

	_setup_starting_pieces()
	_start_turn()

func _build_scene() -> void:
	board_renderer = BoardRenderer.new()
	add_child(board_renderer)

	_turn_label = Label.new()
	_turn_label.position = Vector2(10, 10)
	_turn_label.size = Vector2(600, 30)
	add_child(_turn_label)

	_sp_label = Label.new()
	_sp_label.position = Vector2(10, 40)
	_sp_label.size = Vector2(400, 30)
	add_child(_sp_label)

	_relic_label = Label.new()
	_relic_label.position = Vector2(10, 68)
	_relic_label.size = Vector2(400, 24)
	_relic_label.text = "Relic Points: White 0  |  Black 0"
	_relic_label.hide()
	add_child(_relic_label)

	_sinister_label = Label.new()
	_sinister_label.set_anchors_preset(Control.PRESET_CENTER)
	_sinister_label.size = Vector2(700, 120)
	_sinister_label.position = Vector2(290, 300)
	_sinister_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sinister_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sinister_label.add_theme_font_size_override("font_size", 36)
	_sinister_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.1))
	_sinister_label.hide()
	add_child(_sinister_label)

	_upgrade_btn = Button.new()
	_upgrade_btn.text = "Buy Upgrades"
	_upgrade_btn.position = Vector2(10, 70)
	_upgrade_btn.size = Vector2(140, 32)
	_upgrade_btn.pressed.connect(_on_upgrade_btn_pressed)
	add_child(_upgrade_btn)

	_upgrade_panel = _build_upgrade_panel()
	_upgrade_panel.hide()
	add_child(_upgrade_panel)

	_win_panel = Panel.new()
	_win_panel.size = Vector2(320, 180)
	_win_panel.position = Vector2(480, 270)
	_win_panel.hide()
	add_child(_win_panel)

	_win_label = Label.new()
	_win_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_win_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_win_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_win_panel.add_child(_win_label)

	var restart_btn := Button.new()
	restart_btn.text = "Play Again"
	restart_btn.position = Vector2(80, 130)
	restart_btn.size = Vector2(160, 40)
	restart_btn.pressed.connect(func(): get_tree().reload_current_scene())
	_win_panel.add_child(restart_btn)

func _build_upgrade_panel() -> Panel:
	var panel := Panel.new()
	panel.position = Vector2(160, 10)
	panel.size = Vector2(500, 420)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.position = Vector2(460, 5)
	close_btn.size = Vector2(35, 30)
	close_btn.pressed.connect(func(): panel.hide())
	panel.add_child(close_btn)

	var title := Label.new()
	title.text = "Buy Upgrades  (free action — does not cost your move)"
	title.position = Vector2(10, 10)
	title.size = Vector2(445, 30)
	panel.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(5, 45)
	scroll.size = Vector2(490, 370)
	panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	_upgrade_vbox = vbox   # store reference directly

	return panel

func _refresh_upgrade_panel() -> void:
	if not _upgrade_vbox:
		return
	for child in _upgrade_vbox.get_children():
		child.queue_free()

	var current_sp: int = sp[current_player]

	# Show SP reminder when broke
	if current_sp == 0:
		var lbl := Label.new()
		lbl.text = "You have 0 SP.\nCapture enemy pieces to earn Soul Points,\nthen come back to buy upgrades."
		_upgrade_vbox.add_child(lbl)
		return

	var available: Array = upgrade_registry.available_for_player(board, current_player, current_sp, game_phase)

	if available.is_empty():
		var lbl := Label.new()
		lbl.text = "No upgrades available.\n(SP: %d — may need more captures, or all eligible\npieces already upgraded.)" % current_sp
		_upgrade_vbox.add_child(lbl)
		return

	for upgrade in available:
		var eligible: Array = upgrade_registry.eligible_pieces(board, current_player, upgrade)
		_add_upgrade_row(upgrade, eligible)

	# Spawn upgrades (Dragon, Hydra, etc.) — no target piece needed
	var spawns: Array = upgrade_registry.get_spawn_upgrades(current_sp, game_phase)
	for upgrade in spawns:
		_add_upgrade_row(upgrade, [])

func _add_upgrade_row(upgrade, eligible: Array) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "%s  [%d SP]  → %s" % [upgrade.display_name, upgrade.sp_cost, _upgrade_desc(upgrade)]
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var btn := Button.new()
	btn.text = "Buy"
	btn.size = Vector2(60, 28)
	var u = upgrade
	var pieces = eligible
	btn.pressed.connect(func(): _on_buy_upgrade(u, pieces))
	row.add_child(btn)
	_upgrade_vbox.add_child(row)

func _upgrade_desc(upgrade) -> String:
	if upgrade.transforms_to != "":
		return "Transform to " + upgrade.transforms_to.capitalize()
	if not upgrade.added_movement.is_empty():
		return "+ movement rule"
	if not upgrade.added_abilities.is_empty():
		var ab: AbilityDefinition = upgrade.added_abilities[0]
		return "+ " + ab.id
	return "upgrade"

func _on_upgrade_btn_pressed() -> void:
	if _phase != TurnPhase.NORMAL:
		return
	_refresh_upgrade_panel()
	_upgrade_panel.show()

func _on_buy_upgrade(upgrade, eligible: Array) -> void:
	if sp[current_player] < upgrade.sp_cost:
		return
	if eligible.is_empty() and upgrade.transforms_to != "":
		# Spawn action — no target piece
		_apply_spawn(upgrade)
		return
	if eligible.size() == 1:
		_apply_upgrade(upgrade, eligible[0])
	else:
		_upgrade_panel.hide()
		_pending_upgrade = upgrade
		_phase = TurnPhase.UPGRADE_SELECT_PIECE
		board_renderer.set_upgrade_targets(eligible.map(func(p): return p.anchor_cell))
		if _turn_label:
			_turn_label.text = "Click the piece to upgrade — or press Escape to cancel"

func _apply_spawn(upgrade) -> void:
	sp[current_player] -= upgrade.sp_cost
	var def := PieceRegistry.get_definition(upgrade.transforms_to)
	if not def or def.arrival_island_size == Vector2i.ZERO:
		return
	var island_sz := def.arrival_island_size
	# Place island to the right of the main board with a 1-cell gap (col 8).
	# Player 0 island anchors at bottom; Player 1 at top.
	var row_offset := 8 - island_sz.y if current_player == 0 else 0
	var island_origin := Vector2i(9, row_offset)
	var island_cells: Array[Vector2i] = []
	for r in range(island_sz.y):
		for c in range(island_sz.x):
			island_cells.append(island_origin + Vector2i(c, r))
	var island_id := board.add_island(island_cells)
	var new_piece := PieceInstance.create(def, current_player, island_origin)
	board.place_piece(new_piece)
	EventBus.super_unit_spawned.emit(new_piece, island_id)
	_upgrade_panel.hide()
	_update_hud()
	board_renderer.queue_redraw()

func _apply_upgrade(upgrade, piece: PieceInstance) -> void:
	sp[current_player] -= upgrade.sp_cost
	upgrade_registry.apply(upgrade, piece, board)
	EventBus.upgrade_applied.emit(piece, upgrade.id)
	_pending_upgrade = null
	_phase = TurnPhase.NORMAL
	board_renderer.clear_upgrade_targets()
	_upgrade_panel.hide()
	_update_hud()
	board_renderer.queue_redraw()

# ── Input ─────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	# ── Escape: cancel bonus/upgrade ──────────────────────────────────────────
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_bonus_or_upgrade()
		return

	# ── Right-click drag: pan the board ───────────────────────────────────────
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_panning = event.pressed
		if event.pressed:
			_pan_mouse_start = event.position
			_pan_renderer_start = board_renderer.position
		return
	if event is InputEventMouseMotion and _panning:
		board_renderer.position = _pan_renderer_start + (event.position - _pan_mouse_start)
		return

	# ── Left-click: game actions (convert to board_renderer local space) ───────
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	var local := board_renderer.to_local(event.position)
	match _phase:
		TurnPhase.BONUS_STOMP:
			_handle_bonus_click(local, true)
		TurnPhase.BONUS_EXTRA_MOVE:
			_handle_bonus_click(local, false)
		TurnPhase.UPGRADE_SELECT_PIECE:
			_handle_upgrade_piece_click(local)
		TurnPhase.NORMAL:
			if controllers.size() > current_player:
				controllers[current_player].handle_click(local)

func _cancel_bonus_or_upgrade() -> void:
	match _phase:
		TurnPhase.BONUS_STOMP, TurnPhase.BONUS_EXTRA_MOVE:
			board_renderer.clear_selection()
			_phase = TurnPhase.NORMAL
			_bonus_piece = null
			_bonus_targets = []
			_end_turn()
		TurnPhase.UPGRADE_SELECT_PIECE:
			board_renderer.clear_upgrade_targets()
			_pending_upgrade = null
			_phase = TurnPhase.NORMAL
			_update_hud()

func _handle_bonus_click(screen_pos: Vector2, is_stomp: bool) -> void:
	var cell := board_renderer.cell_at_screen(screen_pos)
	if cell not in _bonus_targets:
		# Clicking outside targets cancels the bonus and ends turn
		board_renderer.clear_selection()
		_phase = TurnPhase.NORMAL
		_end_turn()
		return
	var target_piece := board.get_piece(cell)
	if is_stomp and target_piece and target_piece.owner_id != current_player:
		var reward := GameConfig.sp_value(target_piece.definition.id)
		sp[current_player] += reward
		EventBus.sp_changed.emit(current_player, sp[current_player], reward)
		board.remove_piece(target_piece)
		EventBus.piece_captured.emit(target_piece, _bonus_piece)
	elif not is_stomp:
		board.move_piece(_bonus_piece, cell)
		EventBus.piece_moved.emit(_bonus_piece, _bonus_piece.anchor_cell, cell)
	board_renderer.clear_selection()
	_phase = TurnPhase.NORMAL
	_end_turn()

func _handle_upgrade_piece_click(screen_pos: Vector2) -> void:
	var cell := board_renderer.cell_at_screen(screen_pos)
	var piece := board.get_piece(cell)
	if piece == null or piece.owner_id != current_player or _pending_upgrade == null:
		return
	if not upgrade_registry._is_eligible(piece, _pending_upgrade):
		return
	_apply_upgrade(_pending_upgrade, piece)

# ── Turn flow ─────────────────────────────────────────────────────────────────

func _start_turn() -> void:
	validator.en_passant_target = _ep_target
	validator.en_passant_pawn = _ep_pawn
	_phase = TurnPhase.NORMAL
	EventBus.turn_started.emit(current_player, turn_number)
	_update_hud()
	if controllers.size() > current_player:
		controllers[current_player].request_action(board)

func _on_action_ready(action: Dictionary) -> void:
	match action["type"]:
		"move":
			_execute_move(action["piece"], action["destination"])

func _execute_move(piece: PieceInstance, dest: Vector2i) -> void:
	var from := piece.anchor_cell

	# ── Portal toggle: Mage "moves" to its own cell ────────────────────────────
	if piece.has_tag("mage") and dest == from:
		if board.is_in_portal_mode(piece):
			board.close_portal(piece)
		else:
			board.open_portal(piece)
		_update_hud()
		board_renderer.queue_redraw()
		_check_win_or_end_turn()
		return

	# ── Dragon/Hydra hit: attacker moves onto a super unit cell ───────────────
	var target_on_dest: PieceInstance = board.get_piece(dest)
	if target_on_dest and target_on_dest.owner_id != current_player and target_on_dest.has_tag("super_unit"):
		if piece.has_tag("pawn") and target_on_dest.definition.id in target_on_dest.definition.immunities:
			return  # Pawn immune block — shouldn't reach here due to MoveValidator, safety guard
		board.remove_piece(piece)          # attacker is destroyed
		target_on_dest.lives_remaining -= 1
		EventBus.piece_captured.emit(piece, target_on_dest)
		if target_on_dest.lives_remaining <= 0:
			board.remove_piece(target_on_dest)
			var reward := GameConfig.sp_value(target_on_dest.definition.id)
			sp[current_player] += reward
			EventBus.sp_changed.emit(current_player, sp[current_player], reward)
			EventBus.piece_captured.emit(target_on_dest, piece)
		_update_hud()
		board_renderer.queue_redraw()
		_check_win_or_end_turn()
		return

	var is_castling: bool = piece.has_tag("royalty") and abs(dest.x - from.x) == 2
	if is_castling:
		var dir: int = sign(dest.x - from.x)
		var rook_col := 7 if dir > 0 else 0
		var rook := board.get_piece(Vector2i(rook_col, from.y))
		if rook:
			board.move_piece(rook, Vector2i(from.x + dir, from.y))
			rook.has_moved = true

	var is_en_passant: bool = (piece.has_tag("pawn")
		and dest == _ep_target
		and board.get_piece(dest) == null
		and _ep_pawn != null)
	if is_en_passant:
		board.remove_piece(_ep_pawn)
		if _ep_pawn.has_tag("mage"):
			board.close_portal(_ep_pawn)
		var ep_reward := GameConfig.sp_value(_ep_pawn.definition.id)
		sp[current_player] += ep_reward
		EventBus.sp_changed.emit(current_player, sp[current_player], ep_reward)
		EventBus.piece_captured.emit(_ep_pawn, piece)

	var captured := board.move_piece(piece, dest)
	piece.has_moved = true

	for cap in captured:
		if cap.has_tag("mage"):
			board.close_portal(cap)
		var reward := GameConfig.sp_value(cap.definition.id)
		sp[current_player] += reward
		EventBus.sp_changed.emit(current_player, sp[current_player], reward)
		EventBus.piece_captured.emit(cap, piece)

	# ── Pawn sweep along BLOCK_SLIDE path (Dragon etc.) ───────────────────────
	if piece.definition.size.x > 1 or piece.definition.size.y > 1:
		var swept := _collect_swept_along_path(piece, from, dest)
		for sw in swept:
			board.remove_piece(sw)
			var sw_reward := GameConfig.sp_value(sw.definition.id)
			sp[current_player] += sw_reward
			EventBus.sp_changed.emit(current_player, sp[current_player], sw_reward)
			EventBus.piece_swept.emit(sw, piece)

	if piece.has_tag("pawn") and abs(dest.y - from.y) == 2:
		_ep_pawn = piece
		_ep_target = Vector2i(dest.x, (from.y + dest.y) / 2)
	else:
		_ep_pawn = null
		_ep_target = Vector2i(-1, -1)

	EventBus.piece_moved.emit(piece, from, dest)
	_try_start_bridge(piece)
	_tick_bridges()
	_tick_neutral_monsters()
	_check_pawn_promotion(piece)
	_update_hud()

	# Check for bonus abilities before handing off the turn
	var bonus: Dictionary = ability_system.check_post_move(piece, board)
	if not bonus.is_empty():
		_enter_bonus_phase(bonus)
		return

	_check_win_or_end_turn()

func _enter_bonus_phase(bonus: Dictionary) -> void:
	_bonus_piece = bonus["piece"]
	_bonus_targets = bonus["targets"]
	if bonus["type"] == "stomp":
		_phase = TurnPhase.BONUS_STOMP
		board_renderer.set_selection(_bonus_piece.anchor_cell, [], _bonus_targets)
		if _turn_label:
			_turn_label.text = "STOMP — click an adjacent enemy to capture it  (Escape to skip)"
	else:
		_phase = TurnPhase.BONUS_EXTRA_MOVE
		board_renderer.set_selection(_bonus_piece.anchor_cell, _bonus_targets, [])
		if _turn_label:
			_turn_label.text = "EXTRA STEP — click a cell to move  (Escape to skip)"

func _end_turn() -> void:
	_check_win_or_end_turn()

func _check_win_or_end_turn() -> void:
	var opponent := 1 - current_player
	var in_check := validator.is_in_check(opponent, board)
	var has_moves := validator.has_any_legal_action(opponent, board)

	if in_check:
		var king := _find_king(opponent)
		if king:
			EventBus.check_detected.emit(king)
		if not has_moves:
			EventBus.checkmate.emit(current_player)
			EventBus.game_ended.emit(current_player, "checkmate")
			_show_win("checkmate")
			return
	else:
		EventBus.check_resolved.emit()
		if not has_moves:
			_show_stalemate_notice(opponent)

	# Relic control scoring at the end of each player's turn
	_check_relic_control()

	current_player = opponent
	turn_number += 1

	if turn_number == 50 and game_phase < 50:
		_fire_sinister()
	elif turn_number == 100 and game_phase < 100:
		_fire_sinister_2()

	# Turn 200 score win
	if turn_number > 200:
		var winner := 0 if relic_points[0] >= relic_points[1] else 1
		EventBus.game_ended.emit(winner, "score")
		_show_win("score — Relic Points: W%d / B%d" % [relic_points[0], relic_points[1]])
		return

	_start_turn()

func _check_pawn_promotion(piece: PieceInstance) -> void:
	if not piece.has_tag("pawn"):
		return
	var back_rank := 0 if piece.owner_id == 0 else 7
	if piece.anchor_cell.y == back_rank:
		var queen_def := PieceRegistry.get_definition("queen")
		if queen_def:
			board.remove_piece(piece)
			var new_piece := PieceInstance.create(queen_def, piece.owner_id, piece.anchor_cell)
			board.place_piece(new_piece)
			EventBus.piece_promoted.emit(new_piece, "pawn", "queen")

func _find_king(player_id: int) -> PieceInstance:
	for p in board.get_pieces_for_player(player_id):
		if p.has_tag("royalty"):
			return p
	return null

func _update_hud() -> void:
	var name := "White" if current_player == 0 else "Black"
	if _turn_label and _phase == TurnPhase.NORMAL:
		_turn_label.text = "Turn %d — %s to move" % [turn_number, name]
	if _sp_label:
		_sp_label.text = "SP:  White %d  |  Black %d" % [sp[0], sp[1]]
	if _relic_label and _relic_cell != Vector2i(-1, -1):
		_relic_label.text = "Relic Points:  White %d  |  Black %d" % [relic_points[0], relic_points[1]]
	if _upgrade_btn:
		_upgrade_btn.disabled = (_phase != TurnPhase.NORMAL)

func _show_win(reason: String) -> void:
	var name := "White" if current_player == 0 else "Black"
	if _win_label:
		_win_label.text = "%s wins!\n(%s)" % [name, reason]
	if _win_panel:
		_win_panel.show()
	if _upgrade_btn:
		_upgrade_btn.disabled = true

func _show_stalemate_notice(player_id: int) -> void:
	var name := "White" if player_id == 0 else "Black"
	if _turn_label:
		_turn_label.text = "%s has no legal moves — forced pass" % name

# ── Sinister & Relic ──────────────────────────────────────────────────────────

func _fire_sinister() -> void:
	game_phase = 50
	EventBus.sinister_fired.emit(turn_number)
	_bridges_building.clear()

	# ── Step 1: Re-assign existing 8x8 cells into 4 quadrant islands ───────────
	# No cells are removed. The quadrants are defined by thresholds:
	#   top-left  : cols 0-3, rows 0-3
	#   top-right : cols 4-7, rows 0-3
	#   bottom-left  : cols 0-3, rows 4-7
	#   bottom-right : cols 4-7, rows 4-7
	board.islands.clear()
	board._next_island_id = 0
	var quad_ids: Array[int] = [
		board.new_island().id,  # 0 = top-left
		board.new_island().id,  # 1 = top-right
		board.new_island().id,  # 2 = bottom-left
		board.new_island().id,  # 3 = bottom-right
	]
	for pos in board.cells:
		var q: int
		if pos.x <= 3 and pos.y <= 3:
			q = 0
		elif pos.x >= 4 and pos.y <= 3:
			q = 1
		elif pos.x <= 3 and pos.y >= 4:
			q = 2
		else:
			q = 3
		board.cells[pos].island_id = quad_ids[q]
		board.get_island(quad_ids[q]).cells.append(pos)

	# ── Step 2: Spawn the 3x3 Sinister Island at separate coordinates ──────────
	var sin_cells: Array[Vector2i] = []
	for r in range(3):
		for c in range(3):
			sin_cells.append(SINISTER_ISLAND_ORIGIN + Vector2i(c, r))
	var sin_island_id := board.add_island(sin_cells)

	# Mark the Relic on the center cell of the Sinister Island
	if board.is_valid_cell(RELIC_SPAWN_50):
		board.cells[RELIC_SPAWN_50].type = BoardManager.CellType.RELIC
		_relic_cell = RELIC_SPAWN_50
		EventBus.relic_spawned.emit(RELIC_SPAWN_50)

	# ── Step 3: Apply visual drift so islands spread apart on screen ────────────
	_apply_sinister_drift(sin_island_id)

	EventBus.board_fractured.emit([])
	if _relic_label:
		_relic_label.show()

	_show_sinister_announcement("THE FIRST SINISTER\nThe board fractures!\nBridge to the center island to claim the Relic.")

func _apply_sinister_drift(sinister_island_id: int, drift_px: float = 300.0) -> void:

	# Centre of the main 8x8 grid in cell-coordinate space
	var center := Vector2(3.5, 3.5)

	# ── Pass 1: compute island drifts and apply them ───────────────────────────
	var offsets: Dictionary = {}
	for island_id in board.islands:
		if island_id == sinister_island_id:
			continue
		var island := board.get_island(island_id)
		if island.cells.is_empty():
			continue
		var ic := Vector2.ZERO
		for pos in island.cells:
			ic += Vector2(pos.x, pos.y)
		ic /= island.cells.size()
		offsets[island_id] = (ic - center).normalized() * drift_px

	board_renderer.set_island_offsets(offsets)   # board_origin is now recalculated

	# ── Pass 2: centre the sinister island on the visual board centre ───────────
	var board_origin := board_renderer.get_board_origin()
	var screen_center := board_origin + center * BoardRenderer.CELL_SIZE

	# Natural (un-offset) screen position of the sinister island's centre cell
	var sin_c := Vector2(SINISTER_ISLAND_ORIGIN.x + 1.0, SINISTER_ISLAND_ORIGIN.y + 1.0)
	var sin_natural_screen := board_origin + sin_c * BoardRenderer.CELL_SIZE

	offsets[sinister_island_id] = screen_center - sin_natural_screen

	board_renderer.set_island_offsets(offsets)   # final layout with sinister centred

func _show_sinister_announcement(text: String) -> void:
	if not _sinister_label:
		return
	_sinister_label.text = text
	_sinister_label.show()
	get_tree().create_timer(3.5).timeout.connect(func(): _sinister_label.hide())

func _check_relic_control() -> void:
	if _relic_cell == Vector2i(-1, -1):
		return
	var relic_island_id := board.get_island_id(_relic_cell)
	if relic_island_id < 0:
		return
	var counts := [0, 0]
	for piece in board.get_all_pieces():
		if piece.owner_id < 0 or piece.owner_id > 1:
			continue
		if board.get_island_id(piece.anchor_cell) == relic_island_id:
			counts[piece.owner_id] += 1
	for player in range(2):
		if counts[player] > 0 and counts[1 - player] == 0:
			relic_points[player] += GameConfig.relic_points()
			_relic_was_claimed = true
			EventBus.relic_claimed.emit(player, relic_points[player])
			EventBus.relic_points_changed.emit(player, relic_points[player])
			_update_hud()

# ── Second Sinister (Turn 100) ────────────────────────────────────────────────

func _fire_sinister_2() -> void:
	game_phase = 100
	EventBus.sinister_fired.emit(turn_number)
	_bridges_building.clear()

	# Relic timeout: nobody held the relic since Turn 50 → spawn a beast
	if not _relic_was_claimed and board.is_valid_cell(_relic_cell):
		_spawn_neutral_monster_at(_relic_cell)
	_relic_was_claimed = false

	# Collect sinister island cells before clearing
	var sin_cells: Array[Vector2i] = []
	for r in range(3):
		for c in range(3):
			var pos := SINISTER_ISLAND_ORIGIN + Vector2i(c, r)
			if board.is_valid_cell(pos):
				sin_cells.append(pos)

	# Rebuild island table from scratch
	board.islands.clear()
	board._next_island_id = 0

	# Restore sinister island (cells already exist in board.cells)
	var sin_island := board.new_island()
	for pos in sin_cells:
		board.cells[pos].island_id = sin_island.id
		sin_island.cells.append(pos)

	# Split each 4×4 quadrant into two 2×4 vertical strips → 8 sub-islands
	# col_group: 0=cols0-1, 1=cols2-3, 2=cols4-5, 3=cols6-7
	# row_group: 0=rows0-3, 1=rows4-7
	# key = row_group*4 + col_group (0-7)
	var sub_refs: Dictionary = {}
	for pos in board.cells:
		if not (pos.x >= 0 and pos.x <= 7 and pos.y >= 0 and pos.y <= 7):
			continue
		var col_group: int = pos.x / 2
		var row_group: int = 0 if pos.y < 4 else 1
		var key: int = row_group * 4 + col_group
		if not sub_refs.has(key):
			sub_refs[key] = board.new_island()
		var isl = sub_refs[key]
		board.cells[pos].island_id = isl.id
		isl.cells.append(pos)

	# Spawn fresh Relic on Sinister Island
	if board.is_valid_cell(RELIC_SPAWN_50):
		board.cells[RELIC_SPAWN_50].type = BoardManager.CellType.RELIC
		_relic_cell = RELIC_SPAWN_50
		EventBus.relic_spawned.emit(RELIC_SPAWN_50)

	_apply_sinister_drift(sin_island.id, 500.0)
	EventBus.board_fractured.emit([])
	board_renderer.queue_redraw()
	_show_sinister_announcement("THE SECOND SINISTER\nThe fractures deepen!\nThe board splinters further...")

# ── Neutral Monster ────────────────────────────────────────────────────────────

func _spawn_neutral_monster_at(relic_pos: Vector2i) -> void:
	var def := PieceRegistry.get_definition("neutral_monster")
	if not def:
		return
	var candidates: Array[Vector2i] = [relic_pos]
	var dirs: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	for dir in dirs:
		candidates.append(relic_pos + dir)
	for pos in candidates:
		if board.is_valid_cell(pos) and board.is_empty(pos):
			var monster := PieceInstance.create(def, -1, pos)
			board.place_piece(monster)
			EventBus.neutral_monster_spawned.emit(monster)
			return

func _tick_neutral_monsters() -> void:
	var dirs: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1),
								  Vector2i(1,1), Vector2i(-1,1), Vector2i(1,-1), Vector2i(-1,-1)]
	for piece in board.get_all_pieces():
		if piece.owner_id != -1:
			continue
		dirs.shuffle()
		for dir in dirs:
			var dest: Vector2i = piece.anchor_cell + dir
			if not board.is_valid_cell(dest):
				continue
			var target := board.get_piece(dest)
			if target and target.has_tag("royalty"):
				continue  # beasts don't capture kings
			var from := piece.anchor_cell
			var captured := board.move_piece(piece, dest)
			for cap in captured:
				EventBus.piece_captured.emit(cap, piece)
			EventBus.neutral_monster_moved.emit(piece, dest)
			break

# ── BLOCK_SLIDE sweep helper ───────────────────────────────────────────────────

func _collect_swept_along_path(piece: PieceInstance, from: Vector2i, to: Vector2i) -> Array:
	var result: Array = []
	var dir := Vector2i(sign(to.x - from.x), sign(to.y - from.y))
	var sweep_tags: Array[String] = []
	for rule in piece.get_all_movement_rules():
		sweep_tags.append_array(rule.sweep_tags)
	if sweep_tags.is_empty():
		return result
	# March from one step past `from` to the step before `to`
	var pos := from + dir
	while pos != to:
		for r in range(piece.definition.size.y):
			for c in range(piece.definition.size.x):
				var check_pos := pos + Vector2i(c, r)
				var occ: PieceInstance = board.get_piece(check_pos)
				if occ and occ != piece and occ not in result:
					for tag in sweep_tags:
						if occ.has_tag(tag):
							result.append(occ)
							break
		pos += dir
	return result

# ── Bridge logic ───────────────────────────────────────────────────────────────

func _try_start_bridge(piece: PieceInstance) -> void:
	if not piece.has_tag("bridge_builder"):
		return
	if not board.is_bridge_start_tile(piece.anchor_cell):
		return
	var from_island_id := board.get_island_id(piece.anchor_cell)
	var target := _find_bridge_target(piece.anchor_cell, from_island_id)
	if target.is_empty():
		return
	# Don't start a duplicate bridge in the same direction from the same island
	for b in _bridges_building:
		if b["from_island"] == from_island_id and b["dir"] == target["dir"]:
			return
	_bridges_building.append({
		"from_pos": piece.anchor_cell,
		"dir": target["dir"],
		"gap_cells": target["gap_cells"],
		"from_island": from_island_id,
		"to_island": target["to_island"],
		"turns_remaining": GameConfig.bridge_build_turns(),
	})

func _find_bridge_target(from_pos: Vector2i, from_island_id: int) -> Dictionary:
	var dirs: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	for dir in dirs:
		var gap: Array[Vector2i] = []
		var pos := from_pos + dir
		# Walk through void space
		while not board.is_valid_cell(pos):
			gap.append(pos)
			pos += dir
			if pos.x < -3 or pos.x > 30 or pos.y < -3 or pos.y > 30:
				break
		if board.is_valid_cell(pos):
			var target_island := board.get_island_id(pos)
			if target_island != from_island_id and target_island >= 0:
				return {"dir": dir, "gap_cells": gap, "to_island": target_island}
	return {}

func _tick_bridges() -> void:
	for b in _bridges_building.duplicate():
		b["turns_remaining"] -= 1
		if b["turns_remaining"] <= 0:
			_complete_bridge(b)
			_bridges_building.erase(b)

func _complete_bridge(b: Dictionary) -> void:
	var gap: Array = b["gap_cells"]
	if gap.is_empty():
		# Islands are already adjacent — just mark them connected
		var from_island := board.get_island(b["from_island"])
		var to_island := board.get_island(b["to_island"])
		if from_island and to_island:
			if b["to_island"] not in from_island.connected_to:
				from_island.connected_to.append(b["to_island"])
			if b["from_island"] not in to_island.connected_to:
				to_island.connected_to.append(b["from_island"])
		EventBus.bridge_completed.emit(-1, b["from_island"], b["to_island"])
		return
	# Add bridge cells to board
	for pos in gap:
		var cell := BoardManager.CellState.new()
		cell.island_id = b["from_island"]
		cell.type = BoardManager.CellType.BRIDGE
		board.cells[pos] = cell
	# Connect islands
	var from_island := board.get_island(b["from_island"])
	var to_island := board.get_island(b["to_island"])
	if from_island and to_island:
		if b["to_island"] not in from_island.connected_to:
			from_island.connected_to.append(b["to_island"])
		if b["from_island"] not in to_island.connected_to:
			to_island.connected_to.append(b["from_island"])
	EventBus.bridge_completed.emit(-1, b["from_island"], b["to_island"])
	board_renderer.queue_redraw()

func _setup_starting_pieces() -> void:
	_place_standard_side(0)
	_place_standard_side(1)

func _place_standard_side(player: int) -> void:
	var back_row := 7 if player == 0 else 0
	var pawn_row := 6 if player == 0 else 1
	var back_rank := ["rook", "knight", "bishop", "queen", "king", "bishop", "knight", "rook"]
	for col in range(8):
		var def := PieceRegistry.get_definition(back_rank[col])
		if def:
			board.place_piece(PieceInstance.create(def, player, Vector2i(col, back_row)))
	for col in range(8):
		var def := PieceRegistry.get_definition("pawn")
		if def:
			board.place_piece(PieceInstance.create(def, player, Vector2i(col, pawn_row)))
