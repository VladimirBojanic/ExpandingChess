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

# HUD nodes
var _turn_label: Label = null
var _sp_label: Label = null
var _upgrade_btn: Button = null
var _upgrade_panel: Panel = null
var _upgrade_vbox: VBoxContainer = null   # stored directly — avoids brittle get_node() path
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

func _upgrade_desc(upgrade: UpgradeDefinition) -> String:
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

func _on_buy_upgrade(upgrade: UpgradeDefinition, eligible: Array[PieceInstance]) -> void:
	if sp[current_player] < upgrade.sp_cost:
		return
	if eligible.size() == 1:
		_apply_upgrade(upgrade, eligible[0])
	else:
		# Multiple eligible pieces — ask player to click one on the board
		_upgrade_panel.hide()
		_pending_upgrade = upgrade
		_phase = TurnPhase.UPGRADE_SELECT_PIECE
		board_renderer.set_upgrade_targets(eligible.map(func(p): return p.anchor_cell))
		if _turn_label:
			_turn_label.text = "Click the piece to upgrade — or press Escape to cancel"

func _apply_upgrade(upgrade: UpgradeDefinition, piece: PieceInstance) -> void:
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
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_bonus_or_upgrade()
		return

	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	match _phase:
		TurnPhase.BONUS_STOMP:
			_handle_bonus_click(event.position, true)
		TurnPhase.BONUS_EXTRA_MOVE:
			_handle_bonus_click(event.position, false)
		TurnPhase.UPGRADE_SELECT_PIECE:
			_handle_upgrade_piece_click(event.position)
		TurnPhase.NORMAL:
			if controllers.size() > current_player:
				controllers[current_player].handle_click(event.position)

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

	if piece.has_tag("pawn") and abs(dest.y - from.y) == 2:
		_ep_pawn = piece
		_ep_target = Vector2i(dest.x, (from.y + dest.y) / 2)
	else:
		_ep_pawn = null
		_ep_target = Vector2i(-1, -1)

	EventBus.piece_moved.emit(piece, from, dest)
	board.tick_bridges()
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

	current_player = opponent
	turn_number += 1
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
		_turn_label.text = "Turn %d — %s to move  |  Press Escape to skip bonus" % [turn_number, name]
	if _sp_label:
		_sp_label.text = "SP:  White %d  |  Black %d" % [sp[0], sp[1]]
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
