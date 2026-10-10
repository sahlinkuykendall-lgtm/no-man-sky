class_name GalaxyData
extends RefCounted
## The whole game world state: every star system, planet and ship, plus the current day.
## Everything the save system and (later) the multiplayer server need lives here.

const SAVE_VERSION := 1

var galaxy_seed: int = 0
var day: int = 1
var systems: Array[StarSystemData] = []
var ships: Array[ShipData] = []
var player_ship_id: int = -1
var next_ship_id: int = 0

var _ship_index: Dictionary = {} ## ship id -> ShipData, for fast lookup.


func add_ship(ship: ShipData) -> ShipData:
	if ship.id < 0:
		ship.id = next_ship_id
	next_ship_id = maxi(next_ship_id, ship.id + 1)
	ships.append(ship)
	_ship_index[ship.id] = ship
	return ship


func get_ship(ship_id: int) -> ShipData:
	return _ship_index.get(ship_id)


func get_system(system_id: int) -> StarSystemData:
	if system_id < 0 or system_id >= systems.size():
		return null
	return systems[system_id]


func player_ship() -> ShipData:
	return get_ship(player_ship_id)


## Ships currently flying inside a system (ships in hyperspace are not included).
func ships_in_system(system_id: int) -> Array[ShipData]:
	var result: Array[ShipData] = []
	for ship in ships:
		if ship.system_id == system_id and not ship.in_hyperspace:
			result.append(ship)
	return result


## Distance between two systems on the galaxy map, in parsecs.
func distance_between(system_a: int, system_b: int) -> float:
	return get_system(system_a).galaxy_pos.distance_to(get_system(system_b).galaxy_pos)


func home_system_of(race_id: String) -> StarSystemData:
	for system in systems:
		if system.is_home and system.race_id == race_id:
			return system
	return null


func to_dict() -> Dictionary:
	var system_dicts: Array = []
	for system in systems:
		system_dicts.append(system.to_dict())
	var ship_dicts: Array = []
	for ship in ships:
		ship_dicts.append(ship.to_dict())
	return {
		"save_version": SAVE_VERSION,
		"galaxy_seed": galaxy_seed,
		"day": day,
		"player_ship_id": player_ship_id,
		"next_ship_id": next_ship_id,
		"systems": system_dicts,
		"ships": ship_dicts,
	}


static func from_dict(d: Dictionary) -> GalaxyData:
	var g := GalaxyData.new()
	g.galaxy_seed = int(d.get("galaxy_seed", 0))
	g.day = int(d.get("day", 1))
	g.player_ship_id = int(d.get("player_ship_id", -1))
	for system_dict: Dictionary in d.get("systems", []):
		g.systems.append(StarSystemData.from_dict(system_dict))
	for ship_dict: Dictionary in d.get("ships", []):
		g.add_ship(ShipData.from_dict(ship_dict))
	g.next_ship_id = maxi(g.next_ship_id, int(d.get("next_ship_id", 0)))
	return g
