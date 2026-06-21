class_name PieceDefinition
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var sp_value: int = 1                        # SP earned when this piece is captured
@export var size: Vector2i = Vector2i(1, 1)          # cells occupied (1,1 standard; 3,3 dragon; 4,4 hydra)
@export var arrival_island_size: Vector2i = Vector2i(0, 0)  # (0,0) = no island needed
@export var lives: int = 1                           # 1 standard; 3 dragon; 7 hydra
@export var movement_rules: Array[MovementRule] = []
@export var abilities: Array[AbilityDefinition] = []
@export var available_upgrades: Array[UpgradeDefinition] = []
@export var immunities: Array[String] = []           # piece ids that CANNOT capture this piece
@export var tags: Array[String] = []
# common tags: "royalty", "bridge_builder", "mage", "super_unit", "pawn", "neutral"
