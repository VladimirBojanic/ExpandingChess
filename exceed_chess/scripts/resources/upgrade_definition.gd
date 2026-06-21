class_name UpgradeDefinition
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var sp_cost: int = 0
@export var phase_required: int = 0       # 0 = always, 50 = post-sinister-1, 100 = post-sinister-2
@export var eligible_piece_tags: Array[String] = []  # piece must have all these tags
@export var transforms_to: String = ""    # "" = no transform; "mage" = replace piece type
@export var added_movement: Array[MovementRule] = []
@export var added_abilities: Array[AbilityDefinition] = []
@export var removed_ability_ids: Array[String] = []
@export var added_tags: Array[String] = []
@export var removed_tags: Array[String] = []
