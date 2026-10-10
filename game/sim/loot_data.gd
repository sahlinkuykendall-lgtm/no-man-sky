class_name LootData
extends RefCounted
## A cargo container floating in space: what's left of a destroyed ship or asteroid.
## Ships with a gripper pick it up when they come close. It drifts away after a while.

const LIFETIME_DAYS := 20

var id: int = 0
var position: Vector2 = Vector2.ZERO
var cargo: Dictionary = {} ## good id -> units.
var days_left: int = LIFETIME_DAYS


func is_empty() -> bool:
	return cargo.is_empty()


func total_units() -> int:
	var total := 0
	for good_id: String in cargo:
		total += int(cargo[good_id])
	return total


func to_dict() -> Dictionary:
	return {"id": id, "position": [position.x, position.y], "cargo": cargo.duplicate(), "days_left": days_left}


static func from_dict(d: Dictionary) -> LootData:
	var loot := LootData.new()
	loot.id = int(d.get("id", 0))
	var pos: Array = d.get("position", [0, 0])
	loot.position = Vector2(float(pos[0]), float(pos[1]))
	var contents: Dictionary = d.get("cargo", {})
	for good_id: String in contents:
		if int(contents[good_id]) > 0:
			loot.cargo[good_id] = int(contents[good_id])
	loot.days_left = int(d.get("days_left", LIFETIME_DAYS))
	return loot
