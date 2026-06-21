class_name BeastTable
extends Resource

@export var entries: Array[BeastTableEntry] = []

func roll() -> BeastTableEntry:
	var total_weight: int = 0
	for entry in entries:
		total_weight += entry.weight
	var roll_value := randi() % total_weight
	var cumulative := 0
	for entry in entries:
		cumulative += entry.weight
		if roll_value < cumulative:
			return entry
	return entries[-1]
