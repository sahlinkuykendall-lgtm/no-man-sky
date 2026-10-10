class_name NpcBrain
extends RefCounted
## Decides what NPC ships do each turn.
##   Traders fly between the planets of their system and rest in orbit for a few days.
##   When attacked they run for the nearest inhabited planet (see Combat).
##   Pirates roam the system and attack any non-pirate ship that comes within their
##   detection range, unless it is protected in orbit of an inhabited planet. They give up
##   when the prey gets away or reaches safety.
## Milestone 5 makes NPCs trade for real, travel between systems, and adds police.

const CHANCE_TO_LEAVE_ORBIT := 0.35 ## Per day, once the minimum rest is over.
const MIN_REST_DAYS := 2
const PIRATE_CHANCE_TO_MOVE := 0.5 ## Per day, for a pirate with nothing to do.


static func think(galaxy: GalaxyData, ship: ShipData, events: Array[Dictionary]) -> void:
	if ship.in_hyperspace:
		return
	Combat.forget_lost_target(galaxy, ship)
	# A random generator seeded from (galaxy, day, ship) keeps decisions deterministic,
	# so a saved game or a multiplayer client always gets the same result.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([galaxy.galaxy_seed, galaxy.day, ship.id])
	if ship.is_pirate():
		_think_pirate(galaxy, ship, rng, events)
	else:
		_think_trader(galaxy, ship, rng)


static func _think_trader(galaxy: GalaxyData, ship: ShipData, rng: RandomNumberGenerator) -> void:
	if Combat.is_protected(galaxy, ship):
		ship.clear_target() # Safe at a planet: the fight is over.
	if ship.has_destination:
		return
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


static func _think_pirate(galaxy: GalaxyData, ship: ShipData, rng: RandomNumberGenerator, events: Array[Dictionary]) -> void:
	var npc_settings := NpcSpawner.settings()
	# Keep chasing the current prey while it is attackable and not too far away.
	if ship.target_kind == Combat.TARGET_SHIP:
		var prey := galaxy.get_ship(ship.target_id)
		if Combat.can_attack_ship(galaxy, ship, prey) and \
				prey.position.distance_to(ship.position) <= float(npc_settings.get("give_up_range", 900.0)):
			ship.pursue = true
			return
		ship.clear_target()

	# Look for new prey: the closest non-pirate ship in detection range.
	var best: ShipData = null
	var best_distance := float(npc_settings.get("detection_range", 500.0))
	for other in galaxy.ships_in_system(ship.system_id):
		if other.is_pirate() or not Combat.can_attack_ship(galaxy, ship, other):
			continue
		var distance := other.position.distance_to(ship.position)
		if distance <= best_distance:
			best = other
			best_distance = distance
	if best != null:
		ship.clear_course()
		ship.target_kind = Combat.TARGET_SHIP
		ship.target_id = best.id
		ship.pursue = true
		events.append({"type": Combat.EVENT_UNDER_ATTACK, "ship_id": best.id, "attacker_id": ship.id})
		return

	# Nothing to hunt: drift around the system, now and then.
	if ship.has_destination or rng.randf() > PIRATE_CHANCE_TO_MOVE:
		return
	var system := galaxy.get_system(ship.system_id)
	var point := Vector2.from_angle(rng.randf() * TAU) * system.jump_radius * rng.randf_range(0.3, 0.85)
	TurnResolver.apply_order(galaxy, ship, {"type": "move_to_point", "point": point})
