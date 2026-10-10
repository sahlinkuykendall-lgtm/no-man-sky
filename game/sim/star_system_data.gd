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


func star_radius() -> float:
	return float(GameData.star_type(star_type_id).get("radius", 60))


func to_dict() -> Dictionary:
	var planet_dicts: Array = []
	for planet in planets:
		planet_dicts.append(planet.to_dict())
	return {
		"id": id,
		"name": name,
		"galaxy_pos": [galaxy_pos.x, galaxy_pos.y],
		"star_type_id": star_type_id,
		"race_id": race_id,
		"is_home": is_home,
		"jump_radius": jump_radius,
		"planets": planet_dicts,
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
	return s
