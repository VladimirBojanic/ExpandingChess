extends Node

const CONFIG_PATH := "res://resources/game_config.tres"

var _config: GameConfigResource

func _ready() -> void:
	_config = load(CONFIG_PATH) as GameConfigResource
	if not _config:
		push_error("GameConfig: failed to load " + CONFIG_PATH)
		_config = GameConfigResource.new()

func sp_value(piece_id: String) -> int:
	return _config.sp_values.get(piece_id, 0)

func sinister_turns() -> Array[int]:
	return _config.sinister_turns

func is_sinister_turn(turn: int) -> bool:
	return turn in _config.sinister_turns

func relic_points() -> int:
	return _config.relic_points

func island_size_for(piece_id: String) -> Vector2i:
	return _config.island_sizes.get(piece_id, Vector2i.ZERO)

func bridge_build_turns() -> int:
	return _config.bridge_build_turns

func reload() -> void:
	ResourceLoader.load(CONFIG_PATH, "", ResourceLoader.CACHE_MODE_REPLACE)
	_config = load(CONFIG_PATH) as GameConfigResource
