class_name GameConfigResource
extends Resource

@export var sp_values: Dictionary = {
	"pawn": 1,
	"knight": 3,
	"bishop": 3,
	"rook": 5,
	"queen": 9,
	"king": 0,      # cannot be captured; win condition
	"mage": 3,
	"dragon": 20,
	"hydra": 40,
}

@export var sinister_turns: Array[int] = [50, 100, 150, 200]

@export var relic_points: int = 50

@export var island_sizes: Dictionary = {
	"dragon": Vector2i(5, 5),
	"hydra": Vector2i(7, 7),
}

@export var bridge_build_turns: int = 2
