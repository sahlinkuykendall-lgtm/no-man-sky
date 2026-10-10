class_name NpcBrain
extends RefCounted
## Decides what NPC ships do each turn. For now NPC traders just fly between the planets of
## their system and rest in orbit for a few days. Milestone 5 makes them trade, flee, fight
## and travel between systems.

const CHANCE_TO_LEAVE_ORBIT := 0.35 ## Per day, once the minimum rest is over.
const MIN_REST_DAYS := 2


static func think(galaxy: GalaxyData, ship: ShipData) -> void:
	if ship.in_hyperspace or ship.has_destination:
		return
	# A random generator seeded from (galaxy, day, ship) keeps decisions deterministic,
	# so a saved game or a multiplayer client always gets the same result.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([galaxy.galaxy_seed, galaxy.day, ship.id])

	if ship.orbiting_planet_id >= 0:
		ship.idle_days += 1
		if ship.idle_days < MIN_REST_DAYS or rng.randf() > CHANCE_TO_LEAVE_ORBIT:
			return

	var system := galaxy.get_system(ship.system_id)
	var choices: Array[PlanetData] = []
	for planet in system.planets:
		if planet.id != ship.orbiting_planet_id:
			choices.append(planet)
	if choices.is_empty():
		return
	# Traders prefer inhabited planets (that is where business is).
	var inhabited := choices.filter(func(p: PlanetData) -> bool: return p.inhabited)
	if not inhabited.is_empty() and rng.randf() < 0.8:
		choices.assign(inhabited)
	var target := choices[rng.randi_range(0, choices.size() - 1)]
	ship.idle_days = 0
	TurnResolver.apply_order(galaxy, ship, {"type": "move_to_planet", "planet_id": target.id})
