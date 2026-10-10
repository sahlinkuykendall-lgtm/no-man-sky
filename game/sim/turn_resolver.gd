class_name TurnResolver
extends RefCounted
## The rules of the game's turns. One turn = one galactic day.
##
## apply_order() changes what a ship *intends* to do (it is how players and AI give orders).
## resolve_turn() then advances the whole galaxy by one day and returns a list of events
## (dictionaries) describing what happened, which the views use for messages and animation.
##
## Pure logic with no scene/node code, so the same rules run in solo, on a host, or on a
## dedicated server.

const JUMP_SPEED := 8.0 ## Parsecs travelled per day in hyperspace.
const FUEL_PER_PARSEC := 1.0
const PLANET_ARRIVAL_MARGIN := 18.0 ## Ships park this far from a planet's surface.

# Event types returned by resolve_turn().
const EVENT_ARRIVED_PLANET := "arrived_planet"
const EVENT_ARRIVED_POINT := "arrived_point"
const EVENT_ENTERED_HYPERSPACE := "entered_hyperspace"
const EVENT_ARRIVED_SYSTEM := "arrived_system"
const EVENT_JUMP_FAILED := "jump_failed"
const EVENT_REFUELED := "refueled"


## Gives a ship a new order. Returns "" on success, or a message explaining why not.
## Orders: {"type": "move_to_point", "point": Vector2}
##         {"type": "move_to_planet", "planet_id": int}
##         {"type": "jump", "system_id": int}
##         {"type": "stop"}
static func apply_order(galaxy: GalaxyData, ship: ShipData, order: Dictionary) -> String:
	if ship.in_hyperspace:
		return "Can't change course while in hyperspace."
	var system := galaxy.get_system(ship.system_id)
	match order.get("type", ""):
		"move_to_point":
			var point: Vector2 = order.get("point", ship.position)
			ship.clear_course()
			ship.orbiting_planet_id = -1
			ship.destination = point
			ship.has_destination = true
		"move_to_planet":
			var planet := system.get_planet(int(order.get("planet_id", -1)))
			if planet == null:
				return "Unknown planet."
			ship.clear_course()
			if ship.orbiting_planet_id == planet.id:
				return "" # Already parked there.
			ship.orbiting_planet_id = -1
			ship.target_planet_id = planet.id
			ship.has_destination = true
		"jump":
			var target_id := int(order.get("system_id", -1))
			var target := galaxy.get_system(target_id)
			if target == null:
				return "Unknown system."
			if target_id == ship.system_id:
				return "You are already in the %s system." % target.name
			var distance := galaxy.distance_between(ship.system_id, target_id)
			if distance > ship.jump_range:
				return "%s is out of jump range (%.1f pc, your range is %.1f pc)." % [target.name, distance, ship.jump_range]
			if distance * FUEL_PER_PARSEC > ship.fuel:
				return "Not enough fuel to reach %s (need %.1f, have %.1f)." % [target.name, distance * FUEL_PER_PARSEC, ship.fuel]
			ship.clear_course()
			ship.orbiting_planet_id = -1
			ship.jump_target_system_id = target_id
			ship.has_destination = true
		"stop":
			ship.clear_course()
		_:
			return "Unknown order."
	return ""


## Advances the galaxy by one day. Returns the events that happened.
static func resolve_turn(galaxy: GalaxyData) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	galaxy.day += 1
	for system in galaxy.systems:
		for planet in system.planets:
			planet.advance(1)
	for ship in galaxy.ships:
		if not ship.is_player:
			NpcBrain.think(galaxy, ship)
	for ship in galaxy.ships:
		_resolve_ship(galaxy, ship, events)
	return events


## Where a ship leaves the system to jump toward another system: the hyperspace
## boundary, on the side facing the target system.
static func jump_exit_point(galaxy: GalaxyData, ship: ShipData) -> Vector2:
	var here := galaxy.get_system(ship.system_id)
	var there := galaxy.get_system(ship.jump_target_system_id)
	return (there.galaxy_pos - here.galaxy_pos).normalized() * here.jump_radius


## Days the ship needs to reach its current destination (0 if it has none).
static func days_to_destination(galaxy: GalaxyData, ship: ShipData) -> int:
	if not ship.has_destination or ship.speed <= 0.0:
		return 0
	var system := galaxy.get_system(ship.system_id)
	var target := ship.destination
	var stop_short := 0.0
	if ship.target_planet_id >= 0:
		var planet := system.get_planet(ship.target_planet_id)
		target = planet.position()
		stop_short = planet.radius + PLANET_ARRIVAL_MARGIN
	elif ship.jump_target_system_id >= 0:
		target = jump_exit_point(galaxy, ship)
	return maxi(1, ceili((ship.position.distance_to(target) - stop_short) / ship.speed))


## Days a jump between two systems takes in hyperspace.
static func jump_days(distance: float) -> int:
	return maxi(1, ceili(distance / JUMP_SPEED))


static func _resolve_ship(galaxy: GalaxyData, ship: ShipData, events: Array[Dictionary]) -> void:
	if ship.in_hyperspace:
		ship.jump_days_left -= 1
		if ship.jump_days_left <= 0:
			_exit_hyperspace(galaxy, ship, events)
		return

	var system := galaxy.get_system(ship.system_id)
	if ship.orbiting_planet_id >= 0:
		var orbited := system.get_planet(ship.orbiting_planet_id)
		ship.position = orbited.position() + ship.orbit_offset
		_service_at_planet(ship, orbited, events)
		return
	if not ship.has_destination:
		return

	var planet: PlanetData = null
	var target := ship.destination
	var stop_short := 0.0
	if ship.target_planet_id >= 0:
		planet = system.get_planet(ship.target_planet_id)
		target = planet.position()
		stop_short = planet.radius + PLANET_ARRIVAL_MARGIN
	elif ship.jump_target_system_id >= 0:
		target = jump_exit_point(galaxy, ship)

	var to_target := target - ship.position
	var distance := to_target.length()
	var direction := to_target / distance if distance > 0.001 else Vector2.from_angle(ship.heading)
	ship.heading = direction.angle()

	if distance - stop_short > ship.speed:
		ship.position += direction * ship.speed
		return

	# Arrives this turn.
	if planet != null:
		ship.position = target - direction * stop_short
		ship.orbit_offset = ship.position - target
		ship.orbiting_planet_id = planet.id
		ship.clear_course()
		events.append({"type": EVENT_ARRIVED_PLANET, "ship_id": ship.id, "planet_id": planet.id})
		_service_at_planet(ship, planet, events)
	elif ship.jump_target_system_id >= 0:
		ship.position = target
		_enter_hyperspace(galaxy, ship, events)
	else:
		ship.position = target
		ship.clear_course()
		events.append({"type": EVENT_ARRIVED_POINT, "ship_id": ship.id})


static func _enter_hyperspace(galaxy: GalaxyData, ship: ShipData, events: Array[Dictionary]) -> void:
	var target_id := ship.jump_target_system_id
	var distance := galaxy.distance_between(ship.system_id, target_id)
	var fuel_needed := distance * FUEL_PER_PARSEC
	if fuel_needed > ship.fuel or distance > ship.jump_range:
		ship.clear_course()
		events.append({"type": EVENT_JUMP_FAILED, "ship_id": ship.id, "system_id": target_id})
		return
	ship.fuel -= fuel_needed
	ship.in_hyperspace = true
	ship.jump_origin_system_id = ship.system_id
	ship.jump_days_left = jump_days(distance)
	ship.has_destination = false
	events.append({"type": EVENT_ENTERED_HYPERSPACE, "ship_id": ship.id, "system_id": target_id, "days": ship.jump_days_left})


static func _exit_hyperspace(galaxy: GalaxyData, ship: ShipData, events: Array[Dictionary]) -> void:
	var origin := galaxy.get_system(ship.jump_origin_system_id)
	var arrival := galaxy.get_system(ship.jump_target_system_id)
	var from_origin := (arrival.galaxy_pos - origin.galaxy_pos).normalized()
	# Appear on the arrival system's boundary, on the side facing where we came from.
	ship.system_id = arrival.id
	ship.position = -from_origin * arrival.jump_radius
	ship.heading = from_origin.angle()
	ship.in_hyperspace = false
	ship.jump_days_left = 0
	ship.jump_target_system_id = -1
	ship.jump_origin_system_id = -1
	ship.clear_course()
	events.append({"type": EVENT_ARRIVED_SYSTEM, "ship_id": ship.id, "system_id": arrival.id})


## Free refuelling at inhabited planets. Milestone 2 (trade) will make fuel cost money.
static func _service_at_planet(ship: ShipData, planet: PlanetData, events: Array[Dictionary]) -> void:
	if planet.inhabited and ship.fuel < ship.fuel_max:
		ship.fuel = ship.fuel_max
		if ship.is_player:
			events.append({"type": EVENT_REFUELED, "ship_id": ship.id, "planet_id": planet.id})
