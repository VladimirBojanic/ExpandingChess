class_name BeastTableEntry
extends Resource

@export var id: String = ""
@export var weight: int = 1                    # relative roll probability
@export var piece_definition_id: String = ""   # which PieceDefinition to spawn
@export var sp_reward: int = 15                # SP earned by player who kills it
