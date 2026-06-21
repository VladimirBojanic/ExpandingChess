extends Node

# ── Movement ──────────────────────────────────────────────────────────────────
signal piece_moved(piece: Object, from: Vector2i, to: Vector2i)
signal piece_captured(piece: Object, by_piece: Object)
signal piece_swept(piece: Object, by_super_unit: Object)   # Dragon/Hydra path sweep

# ── Economy ───────────────────────────────────────────────────────────────────
signal sp_changed(player_id: int, new_total: int, delta: int)
signal upgrade_applied(piece: Object, upgrade_id: String)
signal super_unit_spawned(piece: Object, island_id: int)
signal piece_promoted(piece: Object, from_type: String, to_type: String)

# ── Board structure ───────────────────────────────────────────────────────────
signal board_fractured(removed_cells: Array)      # Array[Vector2i]
signal island_added(island_id: int, cells: Array) # Array[Vector2i]
signal bridge_started(bridge_id: int)
signal bridge_completed(bridge_id: int, from_island: int, to_island: int)
signal bridge_destroyed(bridge_id: int, tiles: Array) # Array[Vector2i]
signal portal_opened(mage: Object)
signal portal_closed(mage: Object)

# ── Sinister events ───────────────────────────────────────────────────────────
signal sinister_fired(turn_number: int)
signal relic_spawned(cell: Vector2i)
signal relic_claimed(player_id: int, points: int)
signal relic_timed_out(cell: Vector2i)
signal neutral_monster_spawned(monster: Object)
signal neutral_monster_moved(monster: Object, to: Vector2i)

# ── Game state ────────────────────────────────────────────────────────────────
signal check_detected(king: Object)
signal check_resolved()
signal checkmate(winner_id: int)
signal game_ended(winner_id: int, reason: String)
signal turn_started(player_id: int, turn_number: int)
signal relic_points_changed(player_id: int, new_total: int)
