class_name FracturePattern
extends Resource

# Cells to remove from the board Dictionary when this fracture fires.
# Coordinates are relative to the original 8x8 board (0-indexed, (0,0) = top-left).
@export var cells_to_remove: Array[Vector2i] = []

# Where the Relic spawns after this fracture (board coordinates).
@export var relic_spawn_cell: Vector2i = Vector2i(4, 4)
