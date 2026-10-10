class_name StarSystemData
extends RefCounted
## A star system: one star, its planets, and its place on the galaxy map.

var id: int = 0
var name: String = ""
var galaxy_pos: Vector2 = Vector2.ZERO ## Position on the galaxy map, in parsecs.
var star_type_id: String = ""
var race_id: String = "" ## Which race controls this system.
var is_home: bool = false ## True for a race's capital system.
var jump_radius: float = 1000.0 ## Ships must fly this far from the star to enter hyperspace.
var planets: Array[PlanetData] = []
var asteroids: Array[AsteroidData] = [] ## Empty if the system has no asteroid belt.
var loot: Array[LootData] = [] ## Cargo containers floating in space.
var next_loot_id: int = 0
## How many pirates and traders the system normally has. Destroyed ships are replaced
## over time until these numbers are reached again (see NpcSpawner).
var pirate_limit: int = 0
var trader_limit: int = 0


func get_planet(planet_id: int) -> PlanetData:
	for planet in planets:
		if planet.id == planet_id:
			return planet
	return null


func inhabited_planets() -> Array[PlanetData]:
	var result: Array[PlanetData] = []
	for planet in planets:
		if planet.inhabited:
			result.append(planet)
	return result


func get_asteroid(asteroid_id: int) -> AsteroidData:
	for asteroid in asteroids:
		if asteroid.id == asteroid_id:
			return asteroid
	return null


func get_loot(loot_id: int) -> LootData:
	for container in loot:
		if container.id == loot_id:
			return container
	return null


## Puts a new cargo container into space. Returns it (or null if `cargo` is empty).
func add_loot(at: Vector2, cargo: Dictionary) -> LootData:
	if cargo.is_empty():
		return null
	var container := LootData.new()
	container.id = next_loot_id
	next_loot_id += 1
	container.position = at
	container.cargo = cargo.duplicate()
	loot.append(container)
	return container


func star_radius() -> float:
	return float(GameData.star_type(star_type_id).get("radius", 60))


func to_dict() -> Dictionary:
	var planet_dicts: Array = []
	for planet in planets:
		planet_dicts.append(planet.to_dict())
	var asteroid_dicts: Array = []
	for asteroid in asteroids:
		asteroid_dicts.append(asteroid.to_dict())
	var loot_dicts: Array = []
	for container in loot:
		loot_dicts.append(container.to_dict())
	return {
		"id": id,
		"name": name,
		"galaxy_pos": [galaxy_pos.x, galaxy_pos.y],
		"star_type_id": star_type_id,
		"race_id": race_id,
		"is_home": is_home,
		"jump_radius": jump_radius,
		"planets": planet_dicts,
		"asteroids": asteroid_dicts,
		"loot": loot_dicts,
		"next_loot_id": next_loot_id,
		"pirate_limit": pirate_limit,
		"trader_limit": trader_limit,
	}


static func from_dict(d: Dictionary) -> StarSystemData:
	var s := StarSystemData.new()
	s.id = int(d.get("id", 0))
	s.name = str(d.get("name", ""))
	var pos: Array = d.get("galaxy_pos", [0, 0])
	s.galaxy_pos = Vector2(float(pos[0]), float(pos[1]))
	s.star_type_id = str(d.get("star_type_id", ""))
	s.race_id = str(d.get("race_id", ""))
	s.is_home = bool(d.get("is_home", false))
	s.jump_radius = float(d.get("jump_radius", 1000.0))
	for planet_dict: Dictionary in d.get("planets", []):
		s.planets.append(PlanetData.from_dict(planet_dict))
	for asteroid_dict: Dictionary in d.get("asteroids", []):
		s.asteroids.append(AsteroidData.from_dict(asteroid_dict))
	for loot_dict: Dictionary in d.get("loot", []):
		s.loot.append(LootData.from_dict(loot_dict))
	s.next_loot_id = int(d.get("next_loot_id", 0))
	s.pirate_limit = int(d.get("pirate_limit", 0))
	s.trader_limit = int(d.get("trader_limit", 0))
	return s
