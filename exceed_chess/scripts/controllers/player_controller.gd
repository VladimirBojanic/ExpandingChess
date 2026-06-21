class_name PlayerController
extends RefCounted

signal action_ready(action: Dictionary)

var player_id: int = 0

# Subclasses override this. Called by TurnPipeline at the start of a player's turn.
func request_action(board: BoardManager) -> void:
	pass
