class_name ShipData
extends RefCounted
## One ship (the player's or an NPC's). Positions are system units inside its current system.

const ROLE_PLAYER := "player"
const ROLE_TRADER := "trader"
const ROLE_PIRATE := "pirate"
const ROLE_POLICE := "police"
const ROLE_RANGER := "ranger" ## NPC rangers (the player is a ranger too, with ROLE_PLAYER).

var id: int = -1
var name: String = ""
var role: String = ROLE_TRADER
var race_id: String = ""
var is_player: bool = false

var system_id: int = 0
var position: Vector2 = Vector2.ZERO
var heading: float = 0.0 ## Radians, direction the ship faces.

# Hull and equipment. Equipment.apply_stats() works the ship's stats out from them.
# (A ship without a hull just keeps the stats below; only very old saves have those.)
var hull: ItemData = null
var engine: ItemData = null
var fuel_tank: ItemData = null
var gripper: ItemData = null
var radar: ItemData = null
var shield: ItemData = null
var weapons: Array[ItemData] = [] ## Up to the hull's number of weapon slots.
var hull_hp: float = 0.0 ## The ship is destroyed when this reaches 0.

# Ship stats.
var speed: float = 150.0 ## System units per day.
var fuel: float = 30.0
var fuel_max: float = 30.0
var jump_range: float = 20.0 ## Parsecs.
var jump_speed: float = 8.0 ## Parsecs per day in hyperspace.
var hull_hp_max: float = 0.0
var cargo_capacity: int = 0 ## Units (tons) of goods the hold can carry.

# Money and cargo. For now the pilot's money lives on their ship.
var credits: int = 0
var cargo: Dictionary = {} ## good id -> units carried. Goods with 0 units are removed.

# Current course. Only one of these targets is used at a time.
var has_destination: bool = false
var destination: Vector2 = Vector2.ZERO ## A point in space.
var target_planet_id: int = -1 ## Fly to (and follow) this planet.
var jump_target_system_id: int = -1 ## Fly to the system edge, then jump here.

# Parked in orbit of a planet (moves with it).
var orbiting_planet_id: int = -1
var orbit_offset: Vector2 = Vector2.ZERO

# Hyperspace travel.
var in_hyperspace: bool = false
var jump_origin_system_id: int = -1
var jump_days_left: int = 0

# Combat. The target is what the weapons shoot at: "ship" or "asteroid" (or "" for none).
var target_kind: String = ""
var target_id: int = -1
var pursue: bool = false ## Fly after the target to keep it in weapon range.
var bounty: int = 0 ## Pirates: what the Ranger Corps pays for destroying this ship.

# Law and reputation (see Law).
var karma: int = 0 ## Goes down for crimes, up for destroying pirates.
var wanted: Dictionary = {} ## race id -> unpaid fine. Wanted by that race's police.

# Ranger ranking (the player and NPC rangers).
var kills: int = 0 ## Pirates destroyed.
var points: int = 0 ## Ranking points.

# Simple NPC memory.
var idle_days: int = 0
var truce: Dictionary = {} ## ship id -> days left. Won't attack that ship (bribed, scared off...).
var plan_system_id: int = -1 ## Traders and rangers: where they are heading next.
var plan_planet_id: int = -1


## The item in a single slot: "hull", "engine", "fuel_tank", "gripper", "radar" or "shield"
## (null if empty).
## Weapons have several slots: see `weapons`.
func slot(kind: String) -> ItemData:
	match kind:
		"hull":
			return hull
		"engine":
			return engine
		"fuel_tank":
			return fuel_tank
		"gripper":
			return gripper
		"radar":
			return radar
		"shield":
			return shield
	return null


func set_slot(kind: String, item: ItemData) -> void:
	match kind:
		"hull":
			hull = item
		"engine":
			engine = item
		"fuel_tank":
			fuel_tank = item
		"gripper":
			gripper = item
		"radar":
			radar = item
		"shield":
			shield = item


## Everything installed in the hull (engine, fuel tank, gripper, radar, shield and weapons).
func equipment() -> Array[ItemData]:
	var items: Array[ItemData] = []
	for item in [engine, fuel_tank, gripper, radar, shield]:
		if item != null:
			items.append(item)
	items.append_array(weapons)
	return items


func has_target() -> bool:
	return target_kind != ""


## Stops shooting (and chasing).
func clear_target() -> void:
	target_kind = ""
	target_id = -1
	pursue = false


func is_pirate() -> bool:
	return role == ROLE_PIRATE


## Rangers and the police hunt pirates.
func is_lawful_fighter() -> bool:
	return role == ROLE_POLICE or role == ROLE_RANGER


## True while this ship has agreed not to attack the ship `other_id`.
func has_truce_with(other_id: int) -> bool:
	return int(truce.get(other_id, 0)) > 0


## Unpaid fines with every race, added up.
func total_fines() -> int:
	var total := 0
	for fined_race: String in wanted:
		total += int(wanted[fined_race])
	return total


## Total units of cargo on board.
func cargo_used() -> int:
	var total := 0
	for good_id: String in cargo:
		total += int(cargo[good_id])
	return total


func cargo_free() -> int:
	return cargo_capacity - cargo_used()


func cargo_amount(good_id: String) -> int:
	return int(cargo.get(good_id, 0))


## Adds (or with a negative amount, removes) cargo.
func add_cargo(good_id: String, amount: int) -> void:
	var new_amount := cargo_amount(good_id) + amount
	if new_amount > 0:
		cargo[good_id] = new_amount
	else:
		cargo.erase(good_id)


## Forgets the current course (does not leave orbit).
func clear_course() -> void:
	has_destination = false
	target_planet_id = -1
	jump_target_system_id = -1


func to_dict() -> Dictionary:
	var weapon_dicts: Array = []
	for weapon in weapons:
		weapon_dicts.append(weapon.to_dict())
	return {
		"id": id,
		"name": name,
		"role": role,
		"race_id": race_id,
		"is_player": is_player,
		"system_id": system_id,
		"position": [position.x, position.y],
		"heading": heading,
		"speed": speed,
		"fuel": fuel,
		"fuel_max": fuel_max,
		"jump_range": jump_range,
		"jump_speed": jump_speed,
		"hull_hp": hull_hp,
		"hull_hp_max": hull_hp_max,
		"hull": _item_to_dict(hull),
		"engine": _item_to_dict(engine),
		"fuel_tank": _item_to_dict(fuel_tank),
		"gripper": _item_to_dict(gripper),
		"radar": _item_to_dict(radar),
		"shield": _item_to_dict(shield),
		"weapons": weapon_dicts,
		"target_kind": target_kind,
		"target_id": target_id,
		"pursue": pursue,
		"bounty": bounty,
		"cargo_capacity": cargo_capacity,
		"credits": credits,
		"cargo": cargo.duplicate(),
		"has_destination": has_destination,
		"destination": [destination.x, destination.y],
		"target_planet_id": target_planet_id,
		"jump_target_system_id": jump_target_system_id,
		"orbiting_planet_id": orbiting_planet_id,
		"orbit_offset": [orbit_offset.x, orbit_offset.y],
		"in_hyperspace": in_hyperspace,
		"jump_origin_system_id": jump_origin_system_id,
		"jump_days_left": jump_days_left,
		"idle_days": idle_days,
		"karma": karma,
		"wanted": wanted.duplicate(),
		"kills": kills,
		"points": points,
		"truce": _int_keys_to_strings(truce),
		"plan_system_id": plan_system_id,
		"plan_planet_id": plan_planet_id,
	}


static func from_dict(d: Dictionary) -> ShipData:
	var s := ShipData.new()
	s.id = int(d.get("id", -1))
	s.name = str(d.get("name", ""))
	s.role = str(d.get("role", ROLE_TRADER))
	s.race_id = str(d.get("race_id", ""))
	s.is_player = bool(d.get("is_player", false))
	s.system_id = int(d.get("system_id", 0))
	s.position = _vec(d.get("position", [0, 0]))
	s.heading = float(d.get("heading", 0.0))
	s.speed = float(d.get("speed", 150.0))
	s.fuel = float(d.get("fuel", 30.0))
	s.fuel_max = float(d.get("fuel_max", 30.0))
	s.jump_range = float(d.get("jump_range", 20.0))
	s.jump_speed = float(d.get("jump_speed", 8.0))
	s.hull_hp = float(d.get("hull_hp", 0.0))
	s.hull_hp_max = float(d.get("hull_hp_max", 0.0))
	for kind: String in Equipment.SINGLE_SLOT_KINDS:
		var item_dict: Variant = d.get(kind)
		if item_dict is Dictionary:
			s.set_slot(kind, ItemData.from_dict(item_dict))
	for weapon_dict: Dictionary in d.get("weapons", []):
		s.weapons.append(ItemData.from_dict(weapon_dict))
	s.target_kind = str(d.get("target_kind", ""))
	s.target_id = int(d.get("target_id", -1))
	s.pursue = bool(d.get("pursue", false))
	s.bounty = int(d.get("bounty", 0))
	s.cargo_capacity = int(d.get("cargo_capacity", 0))
	s.credits = int(d.get("credits", 0))
	var hold: Dictionary = d.get("cargo", {})
	for good_id: String in hold:
		s.add_cargo(good_id, int(hold[good_id]))
	s.has_destination = bool(d.get("has_destination", false))
	s.destination = _vec(d.get("destination", [0, 0]))
	s.target_planet_id = int(d.get("target_planet_id", -1))
	s.jump_target_system_id = int(d.get("jump_target_system_id", -1))
	s.orbiting_planet_id = int(d.get("orbiting_planet_id", -1))
	s.orbit_offset = _vec(d.get("orbit_offset", [0, 0]))
	s.in_hyperspace = bool(d.get("in_hyperspace", false))
	s.jump_origin_system_id = int(d.get("jump_origin_system_id", -1))
	s.jump_days_left = int(d.get("jump_days_left", 0))
	s.idle_days = int(d.get("idle_days", 0))
	s.karma = int(d.get("karma", 0))
	var fines: Dictionary = d.get("wanted", {})
	for fined_race: String in fines:
		s.wanted[fined_race] = int(fines[fined_race])
	s.kills = int(d.get("kills", 0))
	s.points = int(d.get("points", 0))
	var truces: Dictionary = d.get("truce", {})
	for other_id: String in truces:
		s.truce[int(other_id)] = int(truces[other_id])
	s.plan_system_id = int(d.get("plan_system_id", -1))
	s.plan_planet_id = int(d.get("plan_planet_id", -1))
	return s


## An item as a dictionary, or null for an empty slot.
static func _item_to_dict(item: ItemData) -> Variant:
	if item == null:
		return null
	return item.to_dict()


## JSON only allows text keys, so number keys are saved as text.
static func _int_keys_to_strings(dict: Dictionary) -> Dictionary:
	var result := {}
	for key: int in dict:
		result[str(key)] = dict[key]
	return result


static func _vec(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))
