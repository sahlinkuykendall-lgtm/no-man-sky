class_name GalaxyGenerator
extends RefCounted
## Builds a brand-new galaxy from a seed. The same seed always gives the same galaxy.

const DEFAULT_SYSTEM_COUNT := 60
const GALAXY_SIZE := Vector2(140.0, 90.0) ## Parsecs.
const MIN_SYSTEM_DISTANCE := 6.5 ## Systems are never closer than this.
## Every new system is placed within this distance of an existing one, so every
## system can be reached with the starting jump range.
const MAX_NEIGHBOR_DISTANCE := 13.0

const FIRST_ORBIT := Vector2(170.0, 230.0) ## Min/max radius of the innermost orbit.
const ORBIT_GAP := Vector2(110.0, 170.0) ## Min/max distance between orbits.
const JUMP_MARGIN := 160.0 ## How far past the last orbit the hyperspace boundary is.
const BASE_ORBIT_SPEED := 0.22 ## Radians/day for a planet at REFERENCE_ORBIT.
const REFERENCE_ORBIT := 200.0

const PLAYER_SHIP_NAME := "Ranger"
const PLAYER_START_CREDITS := 2500


static func generate(galaxy_seed: int, system_count: int = DEFAULT_SYSTEM_COUNT, player_race_id: String = "human") -> GalaxyData:
	var rng := RandomNumberGenerator.new()
	rng.seed = galaxy_seed
	var namer := NameGenerator.new(rng)
	var galaxy := GalaxyData.new()
	galaxy.galaxy_seed = galaxy_seed

	var races := GameData.races()
	var positions := _place_systems(rng, system_count)
	var homes := _pick_spread_out(rng, positions, races.size())

	for i in positions.size():
		var system := StarSystemData.new()
		system.id = i
		system.name = namer.unique_name()
		system.galaxy_pos = positions[i]
		system.star_type_id = GameData.pick_weighted(rng, GameData.star_types()).get("id", "yellow")
		system.race_id = races[_nearest(positions[i], homes, positions)].get("id", "")
		system.is_home = homes.has(i)
		_make_planets(rng, namer, system)
		galaxy.systems.append(system)

	_spawn_npc_traders(rng, galaxy)
	_spawn_player(galaxy, player_race_id)
	return galaxy


## Places systems by "growing" outward from the center, so they are always connected.
static func _place_systems(rng: RandomNumberGenerator, count: int) -> Array[Vector2]:
	var points: Array[Vector2] = [GALAXY_SIZE * 0.5]
	var attempts := 0
	while points.size() < count and attempts < count * 1000:
		attempts += 1
		var base := points[rng.randi_range(0, points.size() - 1)]
		var candidate := base + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(MIN_SYSTEM_DISTANCE, MAX_NEIGHBOR_DISTANCE)
		if candidate.x < 0.0 or candidate.y < 0.0 or candidate.x > GALAXY_SIZE.x or candidate.y > GALAXY_SIZE.y:
			continue
		var too_close := false
		for point in points:
			if point.distance_to(candidate) < MIN_SYSTEM_DISTANCE:
				too_close = true
				break
		if not too_close:
			points.append(candidate)
	return points


## Picks `count` indices that are as far apart from each other as possible (race home systems).
static func _pick_spread_out(rng: RandomNumberGenerator, points: Array[Vector2], count: int) -> Array[int]:
	var chosen: Array[int] = [rng.randi_range(0, points.size() - 1)]
	while chosen.size() < mini(count, points.size()):
		var best_index := -1
		var best_distance := -1.0
		for i in points.size():
			if chosen.has(i):
				continue
			var nearest := INF
			for c in chosen:
				nearest = minf(nearest, points[i].distance_to(points[c]))
			if nearest > best_distance:
				best_distance = nearest
				best_index = i
		chosen.append(best_index)
	return chosen


## Returns which entry of `homes` (by list position) is closest to `point`.
static func _nearest(point: Vector2, homes: Array[int], positions: Array[Vector2]) -> int:
	var best := 0
	for k in homes.size():
		if point.distance_to(positions[homes[k]]) < point.distance_to(positions[homes[best]]):
			best = k
	return best


static func _make_planets(rng: RandomNumberGenerator, namer: NameGenerator, system: StarSystemData) -> void:
	# Average of two dice gives mostly 2-5 planets, sometimes 1 or 6.
	var count := int(round((rng.randi_range(1, 6) + rng.randi_range(1, 6)) / 2.0))
	var orbit := rng.randf_range(FIRST_ORBIT.x, FIRST_ORBIT.y)
	var direction := 1.0 if rng.randf() < 0.5 else -1.0
	for i in count:
		var planet := PlanetData.new()
		planet.id = i
		planet.name = namer.unique_name()
		var planet_type := GameData.pick_weighted(rng, GameData.planet_types())
		planet.type_id = planet_type.get("id", "barren")
		planet.orbit_radius = orbit
		planet.orbit_angle = rng.randf() * TAU
		planet.orbit_speed = direction * BASE_ORBIT_SPEED * pow(REFERENCE_ORBIT / orbit, 1.5)
		planet.radius = rng.randf_range(16.0, 30.0)
		planet.planet_seed = rng.randi()
		if planet_type.get("habitable", false) and rng.randf() < 0.7:
			_populate(rng, planet, system.race_id)
		system.planets.append(planet)
		orbit += rng.randf_range(ORBIT_GAP.x, ORBIT_GAP.y)
	system.jump_radius = system.planets.back().orbit_radius + JUMP_MARGIN

	# A race's home system always has at least one inhabited world.
	if system.is_home and system.inhabited_planets().is_empty():
		var capital := system.planets[mini(1, system.planets.size() - 1)]
		capital.type_id = "temperate"
		_populate(rng, capital, system.race_id)


static func _populate(rng: RandomNumberGenerator, planet: PlanetData, race_id: String) -> void:
	planet.inhabited = true
	planet.race_id = race_id
	planet.economy_id = GameData.pick_weighted(rng, GameData.economies()).get("id", "mixed")
	planet.government_id = GameData.pick_weighted(rng, GameData.governments()).get("id", "republic")
	planet.tech_level = rng.randi_range(2, 8)
	planet.population = rng.randi_range(50, 9000)
	Economy.init_market(planet)


static func _spawn_npc_traders(rng: RandomNumberGenerator, galaxy: GalaxyData) -> void:
	for system in galaxy.systems:
		var inhabited := system.inhabited_planets()
		if inhabited.is_empty():
			continue
		for i in rng.randi_range(2, 4):
			var ship := ShipData.new()
			ship.role = ShipData.ROLE_TRADER
			ship.race_id = system.race_id
			ship.name = "%s trader" % GameData.race(system.race_id).get("adjective", "Free")
			ship.system_id = system.id
			ship.speed = rng.randf_range(90.0, 140.0)
			ship.cargo_capacity = 80
			var home := inhabited[rng.randi_range(0, inhabited.size() - 1)]
			ship.orbiting_planet_id = home.id
			ship.orbit_offset = Vector2.from_angle(rng.randf() * TAU) * (home.radius + 18.0)
			ship.position = home.position() + ship.orbit_offset
			ship.idle_days = rng.randi_range(0, 3)
			galaxy.add_ship(ship)


static func _spawn_player(galaxy: GalaxyData, player_race_id: String) -> void:
	var home := galaxy.home_system_of(player_race_id)
	if home == null:
		home = galaxy.systems[0]
	var ship := ShipData.new()
	ship.name = PLAYER_SHIP_NAME
	ship.role = ShipData.ROLE_PLAYER
	ship.is_player = true
	ship.race_id = player_race_id
	ship.system_id = home.id
	# A Courier with a Spark Drive and a Standard Tank, built by the player's own race.
	Equipment.give_starting_kit(ship, player_race_id)
	ship.credits = PLAYER_START_CREDITS
	var inhabited := home.inhabited_planets()
	var start_planet := inhabited[0] if not inhabited.is_empty() else home.planets[0]
	ship.orbiting_planet_id = start_planet.id
	ship.orbit_offset = Vector2.from_angle(start_planet.orbit_angle) * (start_planet.radius + 18.0)
	ship.position = start_planet.position() + ship.orbit_offset
	galaxy.player_ship_id = galaxy.add_ship(ship).id
