class_name ShipData
extends RefCounted
## One ship (the player's or an NPC's). Positions are system units inside its current system.

const ROLE_PLAYER := "player"
const ROLE_TRADER := "trader"

var id: int = -1
var name: String = ""
var role: String = ROLE_TRADER
var race_id: String = ""
var is_player: bool = false

var system_id: int = 0
var position: Vector2 = Vector2.ZERO
var heading: float = 0.0 ## Radians, direction the ship faces.

# Ship stats (equipment comes in Milestone 3; these are the placeholders).
var speed: float = 150.0 ## System units per day.
var fuel: float = 30.0
var fuel_max: float = 30.0
var jump_range: float = 20.0 ## Parsecs.
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

# Simple NPC memory.
var idle_days: int = 0


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
	return s


static func _vec(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))
