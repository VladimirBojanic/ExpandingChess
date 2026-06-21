class_name MovementRule
extends Resource

enum MovementPattern {
	SLIDE,        # unlimited range in direction until blocked (rook, bishop, queen)
	STEP,         # fixed number of steps (king, pawn forward)
	JUMP,         # ignores pieces between origin and destination (knight)
	L_SHAPE,      # moves 1 orthogonally then 1 more in perpendicular — blocked (strider variant)
	BLOCK_SLIDE,  # entire multi-cell piece slides as a block (dragon, hydra)
	CONE,         # cone attack pattern (dragon breath)
}

@export var pattern: MovementPattern = MovementPattern.STEP
@export var directions: Array[Vector2i] = []  # valid movement directions
@export var max_range: int = 1                # 0 = unlimited
@export var capture_only: bool = false        # e.g. pawn diagonal attack
@export var move_only: bool = false           # e.g. pawn forward non-capture
@export var sweep_tags: Array[String] = []    # pieces with these tags deleted mid-path

# CONE pattern only
@export var cone_width_per_step: int = 1      # cells wider per row of distance
@export var cone_is_blocked: bool = true      # first piece in each column blocks further
