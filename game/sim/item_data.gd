class_name ItemData
extends RefCounted
## One physical hull or piece of equipment: which model it is (an id from equipment.json),
## which race built it, and how worn it is. Its stats come from Equipment.

var type_id: String = ""
var race_id: String = "" ## Manufacturer. Changes price, weight, wear and armor.
var condition: float = 100.0 ## 100 = new, 0 = broken. Not used for hulls (they use hull_hp).
var ammo: int = 0 ## Missiles left (only for missile launchers).


static func make(item_type_id: String, maker_race_id: String) -> ItemData:
	var item := ItemData.new()
	item.type_id = item_type_id
	item.race_id = maker_race_id
	item.ammo = item.max_ammo()
	return item


## How many missiles a full launcher holds (0 for everything else).
func max_ammo() -> int:
	return int(stats().get("ammo", 0))


## "hull", "engine", "fuel_tank", "gripper", "radar", "shield" or "weapon".
func kind() -> String:
	return GameData.item_kind(type_id)


## The model's entry in equipment.json.
func stats() -> Dictionary:
	return GameData.item_type(type_id)


## For example "Gorruk Spark Drive".
func display_name() -> String:
	return "%s %s" % [GameData.race(race_id).get("adjective", ""), stats().get("name", type_id)]


func to_dict() -> Dictionary:
	return {"type_id": type_id, "race_id": race_id, "condition": condition, "ammo": ammo}


static func from_dict(d: Dictionary) -> ItemData:
	var item := ItemData.new()
	item.type_id = str(d.get("type_id", ""))
	item.race_id = str(d.get("race_id", ""))
	item.condition = float(d.get("condition", 100.0))
	item.ammo = int(d.get("ammo", item.max_ammo()))
	return item
