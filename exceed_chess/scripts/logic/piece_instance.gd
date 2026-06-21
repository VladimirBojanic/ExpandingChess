class_name PieceInstance
extends RefCounted

var definition: PieceDefinition
var owner_id: int = 0
var anchor_cell: Vector2i
var applied_upgrades: Array = []   # Array[UpgradeDefinition] — stores objects, not IDs
var lives_remaining: int = 1
var has_moved: bool = false
var status_effects: Array[Dictionary] = []

static func create(def: PieceDefinition, player: int, cell: Vector2i) -> PieceInstance:
	var inst := PieceInstance.new()
	inst.definition = def
	inst.owner_id = player
	inst.anchor_cell = cell
	inst.lives_remaining = def.lives
	return inst

func occupied_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for row in range(definition.size.y):
		for col in range(definition.size.x):
			cells.append(anchor_cell + Vector2i(col, row))
	return cells

func has_tag(tag: String) -> bool:
	if tag in definition.tags:
		return true
	for upgrade in applied_upgrades:
		if tag in upgrade.added_tags:
			return true
	return false

func has_upgrade(upgrade_id: String) -> bool:
	for upgrade in applied_upgrades:
		if upgrade.id == upgrade_id:
			return true
	return false

func get_all_movement_rules() -> Array[MovementRule]:
	var rules: Array[MovementRule] = []
	rules.assign(definition.movement_rules)
	for upgrade in applied_upgrades:
		rules.append_array(upgrade.added_movement)
	return rules

func get_all_abilities() -> Array[AbilityDefinition]:
	var abilities: Array[AbilityDefinition] = []
	abilities.assign(definition.abilities)
	var removed: Array[String] = []
	for upgrade in applied_upgrades:
		abilities.append_array(upgrade.added_abilities)
		removed.append_array(upgrade.removed_ability_ids)
	return abilities.filter(func(a): return a.id not in removed)

func get_status(effect_type: String) -> Dictionary:
	for effect in status_effects:
		if effect["type"] == effect_type:
			return effect
	return {}

func is_rooted() -> bool:
	return not get_status("root").is_empty()

func tick_status_effects() -> void:
	var remaining: Array[Dictionary] = []
	for effect in status_effects:
		effect["turns_left"] -= 1
		if effect["turns_left"] > 0:
			remaining.append(effect)
	status_effects = remaining
