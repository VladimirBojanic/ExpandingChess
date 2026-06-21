class_name AbilityDefinition
extends Resource

enum AbilityTrigger {
	ON_CAPTURE,     # fires after this piece captures another
	AFTER_MOVE,     # fires after this piece completes a move
	PASSIVE,        # always active, no trigger needed
	ACTIVE,         # player must manually activate (costs a turn or uses_per_turn)
	ON_TURN_START,  # fires at the start of owner's turn
	ON_HIT,         # fires when this piece takes damage (super units)
}

enum EffectType {
	EXTRA_MOVE,      # piece may move or attack again
	PUSH,            # move another unit in a direction
	ROOT,            # target cannot move for N turns
	SLOW_AURA,       # halve movement range of enemies on same island
	TELEPORT,        # move this piece to any valid cell
	PORTAL,          # open a portal endpoint at current position
	CONE_ATTACK,     # fire a cone-shaped attack
	STOMP,           # capture 1 adjacent piece after landing
	SWEEP,           # delete pieces with matching tags mid-movement path
	PROTECTION_AURA, # friendly pieces in range cannot be captured by standard moves
	PULL_AURA,       # pull enemy pieces 1 step toward this piece each turn
	SWAP,            # swap positions of two pieces
	REMOTE_CAPTURE,  # capture without entering destination cell
}

@export var id: String = ""
@export var trigger: AbilityTrigger = AbilityTrigger.PASSIVE
@export var effect_type: EffectType = EffectType.EXTRA_MOVE
@export var effect_params: Dictionary = {}
@export var sp_cost: int = 0       # 0 if passive or auto-triggered
@export var uses_per_turn: int = 1 # -1 = unlimited
@export var phase_required: int = 0  # 0 = always, 50 = post-sinister-1, 100 = post-sinister-2
