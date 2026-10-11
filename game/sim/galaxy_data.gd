class_name GalaxyData
extends RefCounted
## The whole game world state: every star system, planet and ship, plus the current day.
## Everything the save system and (later) the multiplayer server need lives here.

## Version 2 added markets, credits and cargo (Milestone 2).
## Version 3 added hulls and equipment (Milestone 3).
## Version 4 added weapons, pirates, asteroids and loot (Milestone 4).
## Version 5 added shields, radar, karma, police, rangers and news (Milestone 5).
const SAVE_VERSION := 5

var galaxy_seed: int = 0
var day: int = 1
var systems: Array[StarSystemData] = []
var ships: Array[ShipData] = []
var player_ship_id: int = -1
var next_ship_id: int = 0
var ranger_limit: int = 0 ## How many NPC rangers the galaxy normally has (see NpcSpawner).
var news: Array[Dictionary] = [] ## Headlines, newest first: {"day", "text"}. See News.

var _ship_index: Dictionary = {} ## ship id -> ShipData, for fast lookup.


func add_ship(ship: ShipData) -> ShipData:
	if ship.id < 0:
		ship.id = next_ship_id
	next_ship_id = maxi(next_ship_id, ship.id + 1)
	ships.append(ship)
	_ship_index[ship.id] = ship
	return ship


## Takes a ship out of the galaxy (it was destroyed or left for good).
func remove_ship(ship_id: int) -> void:
	var ship := get_ship(ship_id)
	if ship != null:
		ships.erase(ship)
		_ship_index.erase(ship_id)


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


## The player and the NPC rangers, best first (by ranking points, then pirates destroyed).
func ranger_ranking() -> Array[ShipData]:
	var rangers: Array[ShipData] = []
	for ship in ships:
		if ship.is_player or ship.role == ShipData.ROLE_RANGER:
			rangers.append(ship)
	rangers.sort_custom(func(a: ShipData, b: ShipData) -> bool:
		if a.points != b.points:
			return a.points > b.points
		if a.kills != b.kills:
			return a.kills > b.kills
		return a.id < b.id)
	return rangers


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
		"ranger_limit": ranger_limit,
		"news": news.duplicate(true),
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
	g.ranger_limit = int(d.get("ranger_limit", 0))
	for item: Dictionary in d.get("news", []):
		g.news.append({"day": int(item.get("day", 0)), "text": str(item.get("text", ""))})
	var version := int(d.get("save_version", 1))
	if version < 2:
		_upgrade_from_version_1(g)
	if version < 3:
		_upgrade_from_version_2(g)
	if version < 4:
		_upgrade_from_version_3(g)
	if version < 5:
		_upgrade_from_version_4(g)
	# Recompute stats from equipment, so balance changes in equipment.json reach old saves.
	for ship in g.ships:
		Equipment.apply_stats(ship)
	return g


## Saves from Milestone 1 had no markets or money.
static func _upgrade_from_version_1(g: GalaxyData) -> void:
	Economy.ensure_markets(g)
	var player := g.player_ship()
	if player != null:
		player.credits = GalaxyGenerator.PLAYER_START_CREDITS


## Saves from Milestones 1-2 had no hull or equipment: give the player the starting kit
## (keeping their fuel).
static func _upgrade_from_version_2(g: GalaxyData) -> void:
	var player := g.player_ship()
	if player != null and player.hull == null:
		var fuel := player.fuel
		Equipment.give_starting_kit(player, player.race_id)
		player.fuel = minf(fuel, player.fuel_max)


## Saves from Milestones 1-3 had no combat: the player gets a gripper and a laser,
## old NPC traders are replaced by armed-and-armored ones, and pirates and asteroid
## belts are added.
static func _upgrade_from_version_3(g: GalaxyData) -> void:
	var player := g.player_ship()
	if player != null and player.hull != null:
		if player.gripper == null:
			player.gripper = ItemData.make(Equipment.STARTING_GRIPPER, player.race_id)
		if player.weapons.is_empty():
			player.weapons.append(ItemData.make(Equipment.STARTING_WEAPON, player.race_id))
	_remove_npcs(g)
	for system in g.systems:
		GalaxyGenerator.make_asteroid_belt(g.galaxy_seed, system)
	NpcSpawner.populate(g)


## Saves from Milestones 1-4 had no radar, police or rangers: the player gets a radar (if
## there is room for it) and all NPCs are replaced by the new kinds.
static func _upgrade_from_version_4(g: GalaxyData) -> void:
	var player := g.player_ship()
	if player != null and player.hull != null and player.radar == null:
		var radar := ItemData.make(Equipment.STARTING_RADAR, player.race_id)
		Equipment.apply_stats(player)
		if player.cargo_free() >= Equipment.weight(radar):
			player.radar = radar
	if player != null:
		player.clear_target()
	_remove_npcs(g)
	NpcSpawner.populate(g)


static func _remove_npcs(g: GalaxyData) -> void:
	for ship in g.ships.duplicate():
		if not ship.is_player:
			g.remove_ship(ship.id)
