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

const JUMP_SPEED := 8.0 ## Parsecs per day in hyperspace for ships without an engine (NPCs).
const FUEL_PER_PARSEC := 1.0
const PLANET_ARRIVAL_MARGIN := 18.0 ## Ships park this far from a planet's surface.

# Event types returned by resolve_turn().
const EVENT_ARRIVED_PLANET := "arrived_planet"
const EVENT_ARRIVED_POINT := "arrived_point"
const EVENT_ENTERED_HYPERSPACE := "entered_hyperspace"
const EVENT_ARRIVED_SYSTEM := "arrived_system"
const EVENT_JUMP_FAILED := "jump_failed"
# Trading, market, shipyard, combat, law and comms events are listed in Trade, Economy,
# Shipyard, Combat, Law and Comms.

## Orders that need a planet's goodwill (refused while its race wants you).
const SERVICE_ORDERS: Array[String] = ["buy", "sell", "refuel", "buy_equipment", "repair", "sell_weapon"]


## Gives a ship a new order. Returns "" on success, or a message explaining why not.
## Orders that happen instantly (trading) add what happened to `events`.
## Orders: {"type": "move_to_point", "point": Vector2}
##         {"type": "move_to_planet", "planet_id": int}
##         {"type": "jump", "system_id": int}
##         {"type": "stop"}
##         {"type": "buy", "good_id": String, "quantity": int}  (while orbiting an inhabited planet)
##         {"type": "sell", "good_id": String, "quantity": int}
##         {"type": "refuel"}
##         {"type": "buy_equipment", "type_id": String}  (at a planet's shipyard)
##         {"type": "sell_weapon", "index": int}
##         {"type": "repair"}
##         {"type": "attack", "target_kind": "ship" or "asteroid", "target_id": int}
##         {"type": "cease_fire"}
##         {"type": "hail", "target_kind": "ship" or "planet", "target_id": int, "option": String} (see Comms)
static func apply_order(galaxy: GalaxyData, ship: ShipData, order: Dictionary, events: Array[Dictionary] = []) -> String:
	if ship.in_hyperspace:
		return "Can't change course while in hyperspace."
	var system := galaxy.get_system(ship.system_id)
	var order_type: String = order.get("type", "")
	if order_type in SERVICE_ORDERS:
		var refusal := Law.refusal(galaxy, ship) # Planets don't deal with pilots their race wants.
		if refusal != "":
			return refusal
	match order_type:
		"hail":
			return Comms.hail(galaxy, ship, str(order.get("target_kind", "")), int(order.get("target_id", -1)), str(order.get("option", "")), events)
		"buy":
			return Trade.buy(galaxy, ship, str(order.get("good_id", "")), int(order.get("quantity", 0)), events)
		"sell":
			return Trade.sell(galaxy, ship, str(order.get("good_id", "")), int(order.get("quantity", 0)), events)
		"refuel":
			return Trade.refuel(galaxy, ship, events)
		"buy_equipment":
			return Shipyard.buy_item(galaxy, ship, str(order.get("type_id", "")), events)
		"repair":
			return Shipyard.repair(galaxy, ship, events)
		"sell_weapon":
			return Shipyard.sell_weapon(galaxy, ship, int(order.get("index", -1)), events)
		"attack":
			return _order_attack(galaxy, ship, str(order.get("target_kind", "")), int(order.get("target_id", -1)))
		"cease_fire":
			ship.clear_target()
		"move_to_point":
			var point: Vector2 = order.get("point", ship.position)
			ship.clear_course()
			ship.pursue = false # Keep shooting at the target (if any), but stop chasing it.
			ship.orbiting_planet_id = -1
			ship.destination = point
			ship.has_destination = true
		"move_to_planet":
			var planet := system.get_planet(int(order.get("planet_id", -1)))
			if planet == null:
				return "Unknown planet."
			ship.clear_course()
			ship.pursue = false
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
				return "Not enough fuel to reach %s (need %.1f, have %.1f). Buy fuel at an inhabited planet." % [target.name, distance * FUEL_PER_PARSEC, ship.fuel]
			ship.clear_course()
			ship.pursue = false
			ship.orbiting_planet_id = -1
			ship.jump_target_system_id = target_id
			ship.has_destination = true
		"stop":
			ship.clear_course()
			ship.pursue = false
		_:
			return "Unknown order."
	return ""


## Sets the ship's weapons on a target and flies after it.
static func _order_attack(galaxy: GalaxyData, ship: ShipData, target_kind: String, target_id: int) -> String:
	if ship.weapons.is_empty():
		return "You have no weapons. Buy one at a shipyard."
	var system := galaxy.get_system(ship.system_id)
	match target_kind:
		Combat.TARGET_SHIP:
			var other := galaxy.get_ship(target_id)
			if other == null or other == ship or other.in_hyperspace or other.system_id != ship.system_id:
				return "That ship isn't here."
			if Combat.is_protected(galaxy, other):
				return "%s is protected by the defenses of the planet it orbits." % other.name
		Combat.TARGET_ASTEROID:
			var asteroid := system.get_asteroid(target_id)
			if asteroid == null or not asteroid.exists():
				return "That asteroid isn't here."
		_:
			return "Unknown target."
	ship.clear_course()
	ship.orbiting_planet_id = -1
	ship.target_kind = target_kind
	ship.target_id = target_id
	ship.pursue = true
	return ""


## Advances the galaxy by one day. Returns the events that happened.
static func resolve_turn(galaxy: GalaxyData) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	galaxy.day += 1
	for system in galaxy.systems:
		for planet in system.planets:
			planet.advance(1)
	Combat.daily_upkeep(galaxy)
	Economy.daily_update(galaxy, events)
	Law.daily(galaxy)
	for ship in galaxy.ships:
		if not ship.is_player:
			NpcBrain.think(galaxy, ship, events)
	for ship in galaxy.ships:
		_resolve_ship(galaxy, ship, events)
	Combat.resolve(galaxy, events) # Everyone has moved: now the weapons fire.
	NpcSpawner.daily(galaxy)
	News.record(galaxy, events)
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


## Days a jump between two systems takes in hyperspace (jump_speed comes from the engine).
static func jump_days(distance: float, jump_speed: float = JUMP_SPEED) -> int:
	return maxi(1, ceili(distance / maxf(jump_speed, 0.1)))


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
		_service_at_planet(ship, orbited)
		return
	if ship.pursue and Combat.target_exists(galaxy, ship):
		_chase_target(galaxy, ship, events)
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

	_wear(ship, "wear_per_flight_day", events) # A day of flying.
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
		if ship.is_player: # NPC police arrive in Milestone 5.
			Trade.police_scan(galaxy, ship, planet, events)
		_service_at_planet(ship, planet)
	elif ship.jump_target_system_id >= 0:
		ship.position = target
		_enter_hyperspace(galaxy, ship, events)
	else:
		ship.position = target
		ship.clear_course()
		events.append({"type": EVENT_ARRIVED_POINT, "ship_id": ship.id})


## Flies toward the ship's target, stopping once it is comfortably in weapon range.
static func _chase_target(galaxy: GalaxyData, ship: ShipData, events: Array[Dictionary]) -> void:
	var target := Combat.target_position(galaxy, ship)
	var to_target := target - ship.position
	var distance := to_target.length()
	if distance > 0.001:
		ship.heading = to_target.angle()
	var gap := distance - Combat.engage_distance(ship)
	if gap <= 0.0:
		return # Close enough: hold position and shoot.
	_wear(ship, "wear_per_flight_day", events)
	ship.position += to_target / distance * minf(gap, ship.speed)


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
	_wear(ship, "wear_per_jump", events) # Before working out the days, in case the engine just wore out.
	ship.jump_days_left = jump_days(distance, ship.jump_speed)
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


## Wears the ship's equipment and reports items that just became worn out.
static func _wear(ship: ShipData, use: String, events: Array[Dictionary]) -> void:
	for kind in Equipment.wear(ship, use):
		events.append({"type": Shipyard.EVENT_EQUIPMENT_WORN, "ship_id": ship.id, "kind": kind})


## NPC ships refuel for free at inhabited planets, and police and rangers are repaired
## there too (to keep NPCs simple). Players buy fuel and repairs with orders.
static func _service_at_planet(ship: ShipData, planet: PlanetData) -> void:
	if ship.is_player or not planet.inhabited or Law.is_wanted_by(ship, planet.race_id):
		return
	ship.fuel = ship.fuel_max
	if ship.is_lawful_fighter() and Equipment.total_repair_cost(ship) > 0:
		ship.hull_hp = ship.hull_hp_max
		for item in ship.equipment():
			item.condition = 100.0
			item.ammo = item.max_ammo()
		Equipment.apply_stats(ship)
