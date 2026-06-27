class_name BoardManager
extends RefCounted

enum CellType { NORMAL, BRIDGE, RELIC, PORTAL_NODE }

class CellState:
	var piece: PieceInstance = null
	var island_id: int = 0
	var type: CellType = CellType.NORMAL

class IslandState:
	var id: int = 0
	var cells: Array[Vector2i] = []
	var connected_to: Array[int] = []  # island ids reachable via bridge or portal

class BridgeState:
	var id: int = 0
	var from_island: int = 0
	var to_island: int = 0
	var tiles: Array[Vector2i] = []
	var turns_remaining: int = 2

class PortalState:
	var mage: PieceInstance = null
	var island_id: int = 0

var cells: Dictionary = {}      # Vector2i → CellState
var islands: Dictionary = {}    # int → IslandState
var bridges: Array[BridgeState] = []
var portals: Array[PortalState] = []

var _next_island_id: int = 0
var _next_bridge_id: int = 0

# ── Setup ─────────────────────────────────────────────────────────────────────

func setup_8x8() -> void:
	cells.clear()
	islands.clear()
	bridges.clear()
	portals.clear()
	_next_island_id = 0

	var island := _new_island()
	for row in range(8):
		for col in range(8):
			var pos := Vector2i(col, row)
			var cell := CellState.new()
			cell.island_id = island.id
			cells[pos] = cell
			island.cells.append(pos)

# ── Cell queries ──────────────────────────────────────────────────────────────

func is_valid_cell(pos: Vector2i) -> bool:
	return cells.has(pos)

func is_empty(pos: Vector2i) -> bool:
	return is_valid_cell(pos) and cells[pos].piece == null

func get_piece(pos: Vector2i) -> PieceInstance:
	if not is_valid_cell(pos):
		return null
	return cells[pos].piece

func get_cell(pos: Vector2i) -> CellState:
	return cells.get(pos, null)

func get_island_id(pos: Vector2i) -> int:
	var cell := get_cell(pos)
	return cell.island_id if cell else -1

func get_island(id: int) -> IslandState:
	return islands.get(id, null)

func same_island(pos_a: Vector2i, pos_b: Vector2i) -> bool:
	return get_island_id(pos_a) == get_island_id(pos_b)

func is_bridge_start_tile(pos: Vector2i) -> bool:
	var cell := get_cell(pos)
	if not cell:
		return false
	var my_island := cell.island_id
	var bst_dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for dir: Vector2i in bst_dirs:
		var neighbor: Vector2i = pos + dir
		if not is_valid_cell(neighbor):
			return true  # adjacent to void
		var nc := get_cell(neighbor)
		if nc and nc.island_id != my_island:
			return true  # adjacent to a different island
	return false

# ── Piece placement (atomic) ──────────────────────────────────────────────────

func place_piece(piece: PieceInstance) -> bool:
	var target_cells := piece.occupied_cells()
	for pos in target_cells:
		if not is_valid_cell(pos) or cells[pos].piece != null:
			return false
	for pos in target_cells:
		cells[pos].piece = piece
	return true

func remove_piece(piece: PieceInstance) -> void:
	for pos in piece.occupied_cells():
		if is_valid_cell(pos) and cells[pos].piece == piece:
			cells[pos].piece = null

func move_piece(piece: PieceInstance, new_anchor: Vector2i) -> Array[PieceInstance]:
	var captured: Array[PieceInstance] = []
	# Collect enemies that will be displaced
	var new_cells: Array[Vector2i] = []
	for row in range(piece.definition.size.y):
		for col in range(piece.definition.size.x):
			new_cells.append(new_anchor + Vector2i(col, row))
	for pos in new_cells:
		if is_valid_cell(pos):
			var existing: PieceInstance = cells[pos].piece
			if existing and existing != piece:
				captured.append(existing)
	# Remove each captured piece
	for cap in captured:
		remove_piece(cap)
	# Remove piece from old cells
	remove_piece(piece)
	# Place at new location
	piece.anchor_cell = new_anchor
	place_piece(piece)
	return captured

# ── Island management ─────────────────────────────────────────────────────────

func add_island(island_cells: Array[Vector2i]) -> int:
	var island := _new_island()
	for pos in island_cells:
		if not cells.has(pos):
			var cell := CellState.new()
			cell.island_id = island.id
			cells[pos] = cell
			island.cells.append(pos)
	EventBus.island_added.emit(island.id, island.cells.duplicate())
	return island.id

func remove_cells(positions: Array[Vector2i]) -> Array[PieceInstance]:
	var destroyed: Array[PieceInstance] = []
	for pos in positions:
		if cells.has(pos):
			var existing: PieceInstance = cells[pos].piece
			if existing:
				if existing not in destroyed:
					destroyed.append(existing)
			cells.erase(pos)
	# Clean up pieces whose anchor is gone
	var truly_destroyed: Array[PieceInstance] = []
	for piece in destroyed:
		# Remove any remaining cell references
		for pos in piece.occupied_cells():
			if cells.has(pos) and cells[pos].piece == piece:
				cells[pos].piece = null
		truly_destroyed.append(piece)
	return truly_destroyed

# ── Bridge management ─────────────────────────────────────────────────────────

func start_bridge(from_island: int, to_island: int) -> BridgeState:
	var bridge := BridgeState.new()
	bridge.id = _next_bridge_id
	_next_bridge_id += 1
	bridge.from_island = from_island
	bridge.to_island = to_island
	bridge.turns_remaining = GameConfig.bridge_build_turns()
	bridges.append(bridge)
	EventBus.bridge_started.emit(bridge.id)
	return bridge

func tick_bridges() -> void:
	for bridge in bridges.duplicate():
		if bridge.turns_remaining > 0:
			bridge.turns_remaining -= 1
			if bridge.turns_remaining == 0:
				_complete_bridge(bridge)

func _complete_bridge(bridge: BridgeState) -> void:
	var from := get_island(bridge.from_island)
	var to := get_island(bridge.to_island)
	if from and to:
		if bridge.to_island not in from.connected_to:
			from.connected_to.append(bridge.to_island)
		if bridge.from_island not in to.connected_to:
			to.connected_to.append(bridge.from_island)
	EventBus.bridge_completed.emit(bridge.id, bridge.from_island, bridge.to_island)

# ── Portal management ─────────────────────────────────────────────────────────

func open_portal(mage: PieceInstance) -> bool:
	if not is_bridge_start_tile(mage.anchor_cell) and not mage.has_tag("void_mage"):
		return false
	# Close existing portal from same mage if any
	close_portal(mage)
	var portal := PortalState.new()
	portal.mage = mage
	portal.island_id = get_island_id(mage.anchor_cell)
	portals.append(portal)
	EventBus.portal_opened.emit(mage)
	return true

func close_portal(mage: PieceInstance) -> void:
	for i in range(portals.size() - 1, -1, -1):
		if portals[i].mage == mage:
			portals.remove_at(i)
			EventBus.portal_closed.emit(mage)
			break

func is_in_portal_mode(mage: PieceInstance) -> bool:
	for portal in portals:
		if portal.mage == mage:
			return true
	return false

func get_portals_for_player(player_id: int) -> Array[PortalState]:
	var result: Array[PortalState] = []
	for portal in portals:
		if portal.mage and portal.mage.owner_id == player_id:
			result.append(portal)
	return result

func recompute_islands() -> void:
	for pos in cells:
		cells[pos].island_id = -1
	islands.clear()
	_next_island_id = 0
	var dirs: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	for start_pos in cells:
		if cells[start_pos].island_id != -1:
			continue
		var island := _new_island()
		var frontier: Array[Vector2i] = [start_pos]
		while not frontier.is_empty():
			var pos: Vector2i = frontier.pop_back()
			if not cells.has(pos) or cells[pos].island_id != -1:
				continue
			cells[pos].island_id = island.id
			island.cells.append(pos)
			for dir in dirs:
				var nb := pos + dir
				if cells.has(nb) and cells[nb].island_id == -1:
					frontier.append(nb)

func get_all_pieces() -> Array[PieceInstance]:
	var seen: Array[PieceInstance] = []
	for cell in cells.values():
		if cell.piece and cell.piece not in seen:
			seen.append(cell.piece)
	return seen

func get_pieces_for_player(player_id: int) -> Array[PieceInstance]:
	return get_all_pieces().filter(func(p): return p.owner_id == player_id)

# ── Helpers ───────────────────────────────────────────────────────────────────

func new_island() -> IslandState:
	return _new_island()

func _new_island() -> IslandState:
	var island := IslandState.new()
	island.id = _next_island_id
	_next_island_id += 1
	islands[island.id] = island
	return island
