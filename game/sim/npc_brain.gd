class_name NpcBrain
extends RefCounted
## Decides what NPC ships do each turn (docs/MASTER_DESIGN.md section 12).
##   Traders really trade. Arriving at a planet they sell what they carry. Before leaving
##   they look for the best deal they can reach (a good that is cheap here and sells well
##   at another planet, in this system or a nearby one), buy it and fly or jump there.
##   When attacked they run for the nearest inhabited planet (see Combat).
##   Pirates roam their system and attack traders and the player when they see them on
##   radar, unless the prey is protected in orbit of an inhabited planet. They give up
##   when the prey gets away or reaches safety. Pilots with very bad karma are left alone.
##   Police guard the planets of their system and attack pirates and anyone their race
##   wants (see Law).
##   Rangers hunt pirates: in their own system first, then in a nearby system that has
##   some. Police and rangers go to a planet to repair and refuel when they need to.
## Nobody attacks a ship they have a truce with (see Comms).

const CHANCE_TO_LEAVE_ORBIT := 0.35 ## Per day, once the minimum rest is over.
const MIN_REST_DAYS := 2
const PATROL_CHANCE_TO_MOVE := 0.5 ## Per day, for a pirate or police ship with nothing to do.
const TRADE_SYSTEMS := 4 ## Traders compare prices in this many nearby systems (plus their own).
const MIN_PROFIT := 0.1 ## Traders want to earn at least 10% on a deal.
const TRADER_BROKE := 400 ## A trader with less money and no cargo...
const TRADER_TOP_UP := 1500 ## ...gets this much from their trading company.
const LOW_FUEL := 15.0 ## Police and rangers refuel below this.
const RANGER_ROAM_CHANCE := 0.3 ## Per decision: a ranger with no pirates near moves on.


static func think(galaxy: GalaxyData, ship: ShipData, events: Array[Dictionary]) -> void:
	if ship.in_hyperspace:
		return
	Combat.forget_lost_target(galaxy, ship)
	# A random generator seeded from (galaxy, day, ship) keeps decisions deterministic,
	# so a saved game or a multiplayer client always gets the same result.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([galaxy.galaxy_seed, galaxy.day, ship.id])
	match ship.role:
		ShipData.ROLE_PIRATE:
			_think_pirate(galaxy, ship, rng, events)
		ShipData.ROLE_POLICE:
			_think_police(galaxy, ship, rng, events)
		ShipData.ROLE_RANGER:
			_think_ranger(galaxy, ship, rng, events)
		_:
			_think_trader(galaxy, ship, rng)


# --- Pirates, police and rangers -------------------------------------------------------

static func _think_pirate(galaxy: GalaxyData, ship: ShipData, rng: RandomNumberGenerator, events: Array[Dictionary]) -> void:
	# Pirates only fight the police back while the police are after them.
	if ship.target_kind == Combat.TARGET_SHIP and Combat.target_exists(galaxy, ship):
		var target := galaxy.get_ship(ship.target_id)
		if target.role == ShipData.ROLE_POLICE and target.target_id != ship.id:
			ship.clear_target()
	if _keep_fighting(galaxy, ship):
		return
	# Pirates hunt traders and the player, but stay away from planets the police guard.
	var guarded := Law.police_count(galaxy.get_system(ship.system_id)) > 0
	var engage := float(NpcSpawner.settings().get("police_engage_distance", 300.0))
	var prey := _spot_enemy(galaxy, ship, func(other: ShipData) -> bool:
		if guarded and near_inhabited_planet(galaxy, other, engage):
			return false
		return other.role == ShipData.ROLE_TRADER or (other.is_player and not Law.pirates_ignore(other)))
	if prey != null:
		_attack(ship, prey, events)
		return
	_patrol(galaxy, ship, rng, false, engage * 2.0 if guarded else 0.0)


static func _think_police(galaxy: GalaxyData, ship: ShipData, rng: RandomNumberGenerator, events: Array[Dictionary]) -> void:
	if _rest_or_service(galaxy, ship):
		if ship.orbiting_planet_id >= 0 and ship.idle_days == 0:
			_guard_planets(galaxy, ship, rng, true) # Rested: back on patrol.
		return
	# Police fight pirates that come close to their planets (and give up the chase once a
	# pirate is twice as far away), and pilots their race wants anywhere in the system (a
	# paid fine ends the chase).
	var engage := float(NpcSpawner.settings().get("police_engage_distance", 300.0))
	var is_enemy := func(other: ShipData) -> bool:
		if other.is_pirate():
			var chasing := ship.target_kind == Combat.TARGET_SHIP and ship.target_id == other.id
			return near_inhabited_planet(galaxy, other, engage * 2.0 if chasing else engage)
		return Law.is_wanted_by(other, ship.race_id)
	if ship.target_kind == Combat.TARGET_SHIP and not is_enemy.call(galaxy.get_ship(ship.target_id)):
		ship.clear_target()
	if _keep_fighting(galaxy, ship):
		return
	var enemy := _spot_enemy(galaxy, ship, is_enemy)
	if enemy != null:
		_attack(ship, enemy, events)
		return
	_guard_planets(galaxy, ship, rng, false)


## Police patrol close to the inhabited planets of their system (now and then, or always
## if `force`).
static func _guard_planets(galaxy: GalaxyData, ship: ShipData, rng: RandomNumberGenerator, force: bool) -> void:
	if not force and (ship.has_destination or rng.randf() > PATROL_CHANCE_TO_MOVE):
		return
	var planets := galaxy.get_system(ship.system_id).inhabited_planets()
	if planets.is_empty():
		_patrol(galaxy, ship, rng, force)
		return
	var planet := planets[rng.randi_range(0, planets.size() - 1)]
	var distance := float(NpcSpawner.settings().get("police_guard_distance", 250.0)) * rng.randf_range(0.4, 1.0)
	var point := planet.position() + Vector2.from_angle(rng.randf() * TAU) * distance
	TurnResolver.apply_order(galaxy, ship, {"type": "move_to_point", "point": point})


## True if the ship is within `distance` of an inhabited planet of its system.
static func near_inhabited_planet(galaxy: GalaxyData, ship: ShipData, distance: float) -> bool:
	return _near_planet_at(galaxy.get_system(ship.system_id), ship.position, distance)


static func _think_ranger(galaxy: GalaxyData, ship: ShipData, rng: RandomNumberGenerator, events: Array[Dictionary]) -> void:
	if _rest_or_service(galaxy, ship):
		if ship.orbiting_planet_id >= 0 and ship.idle_days == 0:
			_ranger_move_on(galaxy, ship, rng) # Rested: off hunting again.
		return
	if _keep_fighting(galaxy, ship):
		return
	var pirate := _spot_enemy(galaxy, ship, func(other: ShipData) -> bool: return other.is_pirate())
	if pirate != null:
		_attack(ship, pirate, events)
		return
	if not ship.has_destination:
		_ranger_move_on(galaxy, ship, rng)


## A ranger with nobody to fight: flies toward a pirate it heard about in this system, or
## jumps to a nearby system with pirates, or now and then just moves on.
static func _ranger_move_on(galaxy: GalaxyData, ship: ShipData, rng: RandomNumberGenerator) -> void:
	var nearest: ShipData = null
	for other in galaxy.ships_in_system(ship.system_id):
		if other.is_pirate() and not ship.has_truce_with(other.id) and \
				(nearest == null or other.position.distance_to(ship.position) < nearest.position.distance_to(ship.position)):
			nearest = other
	if nearest != null:
		TurnResolver.apply_order(galaxy, ship, {"type": "move_to_point", "point": nearest.position})
		return
	var pirates := {} ## system id -> pirates there
	for other in galaxy.ships:
		if other.is_pirate() and not other.in_hyperspace:
			pirates[other.system_id] = int(pirates.get(other.system_id, 0)) + 1
	var best_id := -1
	var reachable: Array[int] = []
	for system in galaxy.systems:
		var distance := galaxy.distance_between(ship.system_id, system.id)
		if system.id == ship.system_id or distance > minf(ship.jump_range, ship.fuel):
			continue
		reachable.append(system.id)
		if int(pirates.get(system.id, 0)) > int(pirates.get(best_id, 0)):
			best_id = system.id
	if best_id < 0 and not reachable.is_empty() and rng.randf() < RANGER_ROAM_CHANCE:
		best_id = reachable[rng.randi_range(0, reachable.size() - 1)]
	if best_id >= 0:
		TurnResolver.apply_order(galaxy, ship, {"type": "jump", "system_id": best_id})
	else:
		_patrol(galaxy, ship, rng, true)


## Police and rangers: rests a couple of days in orbit, and heads for a planet to repair
## and refuel (see TurnResolver._service_at_planet) when hurt or low on fuel. Returns true
## if the ship is busy with this today. A ship that just finished resting has idle_days 0.
static func _rest_or_service(galaxy: GalaxyData, ship: ShipData) -> bool:
	if ship.orbiting_planet_id >= 0:
		ship.idle_days += 1
		if ship.idle_days >= MIN_REST_DAYS:
			ship.idle_days = 0
		return true
	if ship.target_planet_id >= 0:
		return true # Already on the way.
	var system := galaxy.get_system(ship.system_id)
	var hurt := ship.hull_hp < ship.hull_hp_max * float(NpcSpawner.settings().get("ranger_repair_below", 0.5))
	if not hurt and ship.fuel >= LOW_FUEL:
		return false
	var planet := Combat.nearest_inhabited_planet(system, ship.position)
	if planet == null:
		ship.fuel = maxf(ship.fuel, Trade.EMERGENCY_FUEL) # The Ranger Corps helps out.
		return false
	ship.clear_target()
	ship.idle_days = 0
	TurnResolver.apply_order(galaxy, ship, {"type": "move_to_planet", "planet_id": planet.id})
	return true


## Keeps chasing the current target while it can be attacked and is not too far away.
static func _keep_fighting(galaxy: GalaxyData, ship: ShipData) -> bool:
	if ship.target_kind != Combat.TARGET_SHIP:
		return false
	var enemy := galaxy.get_ship(ship.target_id)
	if Combat.can_attack_ship(galaxy, ship, enemy) and not ship.has_truce_with(enemy.id) and \
			enemy.position.distance_to(ship.position) <= float(NpcSpawner.settings().get("give_up_range", 900.0)):
		ship.pursue = true
		return true
	ship.clear_target()
	return false


## The closest ship on radar that `is_enemy` accepts and that can be attacked.
static func _spot_enemy(galaxy: GalaxyData, ship: ShipData, is_enemy: Callable) -> ShipData:
	var best: ShipData = null
	var best_distance := Equipment.radar_range(ship)
	for other in galaxy.ships_in_system(ship.system_id):
		if other == ship or ship.has_truce_with(other.id) or not is_enemy.call(other):
			continue
		var distance := other.position.distance_to(ship.position)
		if distance <= best_distance and Combat.can_attack_ship(galaxy, ship, other):
			best = other
			best_distance = distance
	return best


static func _attack(ship: ShipData, enemy: ShipData, events: Array[Dictionary]) -> void:
	ship.clear_course()
	ship.target_kind = Combat.TARGET_SHIP
	ship.target_id = enemy.id
	ship.pursue = true
	events.append({"type": Combat.EVENT_UNDER_ATTACK, "ship_id": enemy.id, "attacker_id": ship.id})


## Drifts around the system now and then (always, if `force`). With `avoid` > 0 it tries
## to stay that far from inhabited planets (pirates keeping clear of the police).
static func _patrol(galaxy: GalaxyData, ship: ShipData, rng: RandomNumberGenerator, force: bool, avoid: float = 0.0) -> void:
	if not force and (ship.has_destination or rng.randf() > PATROL_CHANCE_TO_MOVE):
		return
	var system := galaxy.get_system(ship.system_id)
	var point := Vector2.ZERO
	for attempt in 8:
		point = Vector2.from_angle(rng.randf() * TAU) * system.jump_radius * rng.randf_range(0.3, 0.95)
		if avoid <= 0.0 or not _near_planet_at(system, point, avoid):
			break
	TurnResolver.apply_order(galaxy, ship, {"type": "move_to_point", "point": point})


static func _near_planet_at(system: StarSystemData, point: Vector2, distance: float) -> bool:
	for planet in system.inhabited_planets():
		if planet.position().distance_to(point) <= distance:
			return true
	return false


# --- Traders -----------------------------------------------------------------------

static func _think_trader(galaxy: GalaxyData, ship: ShipData, rng: RandomNumberGenerator) -> void:
	if Combat.is_protected(galaxy, ship):
		ship.clear_target() # Safe at a planet: the fight is over.
	if ship.has_destination:
		return
	var planet := Trade.market_planet(galaxy, ship)
	if planet == null:
		_continue_trip(galaxy, ship, rng) # Just arrived from hyperspace (or fled somewhere odd).
		return
	if ship.idle_days == 0:
		_sell_cargo(galaxy, ship, planet) # Just arrived: sell what we brought.
	ship.idle_days += 1
	if ship.idle_days < MIN_REST_DAYS or rng.randf() > CHANCE_TO_LEAVE_ORBIT:
		return
	ship.idle_days = 0
	_plan_trip(galaxy, ship, planet, rng)
	_continue_trip(galaxy, ship, rng)


static func _sell_cargo(galaxy: GalaxyData, ship: ShipData, planet: PlanetData) -> void:
	var ignored: Array[Dictionary] = [] # NPC deals don't need events.
	for good_id: String in ship.cargo.keys():
		if not Economy.is_illegal(planet, good_id):
			Trade.sell(galaxy, ship, good_id, ship.cargo_amount(good_id), ignored)
	if ship.plan_system_id == ship.system_id and ship.plan_planet_id == planet.id:
		ship.plan_system_id = -1
		ship.plan_planet_id = -1


## Picks where to go next and buys the goods for that trip.
static func _plan_trip(galaxy: GalaxyData, ship: ShipData, here: PlanetData, rng: RandomNumberGenerator) -> void:
	if ship.credits < TRADER_BROKE and ship.cargo_used() == 0:
		ship.credits += TRADER_TOP_UP
	var destinations := _trade_destinations(galaxy, ship)
	var deal := _best_deal(ship, here, destinations)
	if not deal.is_empty():
		var ignored: Array[Dictionary] = []
		Trade.buy(galaxy, ship, deal["good_id"], deal["units"], ignored)
		ship.plan_system_id = deal["system_id"]
		ship.plan_planet_id = deal["planet_id"]
		return
	# No good deal: try somewhere else (the cargo, if any, may sell better there).
	var others := destinations.filter(func(d: Dictionary) -> bool: return d["planet"] != here)
	if others.is_empty():
		ship.plan_system_id = -1
		return
	var choice: Dictionary = others[rng.randi_range(0, others.size() - 1)]
	ship.plan_system_id = choice["system_id"]
	ship.plan_planet_id = (choice["planet"] as PlanetData).id


## Heads for the planned planet: flies there in this system, or jumps to its system first.
static func _continue_trip(galaxy: GalaxyData, ship: ShipData, rng: RandomNumberGenerator) -> void:
	if ship.plan_system_id == ship.system_id:
		TurnResolver.apply_order(galaxy, ship, {"type": "move_to_planet", "planet_id": ship.plan_planet_id})
		return
	if ship.plan_system_id >= 0:
		if TurnResolver.apply_order(galaxy, ship, {"type": "jump", "system_id": ship.plan_system_id}) == "":
			return
		ship.plan_system_id = -1 # Can't get there any more.
	# No plan: visit a random inhabited planet here (or any planet, if there are none).
	var system := galaxy.get_system(ship.system_id)
	var choices := system.inhabited_planets()
	if choices.is_empty():
		choices = system.planets
	var target := choices[rng.randi_range(0, choices.size() - 1)]
	if target.id == ship.orbiting_planet_id:
		return
	ship.plan_system_id = system.id
	ship.plan_planet_id = target.id
	TurnResolver.apply_order(galaxy, ship, {"type": "move_to_planet", "planet_id": target.id})


## The inhabited planets a trader can reach on a tank of fuel: those in its own system and
## in the TRADE_SYSTEMS nearest systems. Each entry: {"system_id", "planet", "days"} with a
## rough number of days the trip takes.
static func _trade_destinations(galaxy: GalaxyData, ship: ShipData) -> Array[Dictionary]:
	var reach := minf(ship.jump_range, ship.fuel_max)
	var nearby: Array[StarSystemData] = []
	for system in galaxy.systems:
		if system.id != ship.system_id and galaxy.distance_between(ship.system_id, system.id) <= reach \
				and not system.inhabited_planets().is_empty():
			nearby.append(system)
	nearby.sort_custom(func(a: StarSystemData, b: StarSystemData) -> bool:
		return galaxy.distance_between(ship.system_id, a.id) < galaxy.distance_between(ship.system_id, b.id))
	nearby.resize(mini(nearby.size(), TRADE_SYSTEMS))
	nearby.push_front(galaxy.get_system(ship.system_id))
	var result: Array[Dictionary] = []
	for system in nearby:
		var days := 2.0
		if system.id != ship.system_id:
			days += 3.0 + TurnResolver.jump_days(galaxy.distance_between(ship.system_id, system.id), ship.jump_speed)
		for planet in system.inhabited_planets():
			result.append({"system_id": system.id, "planet": planet, "days": days})
	return result


## The most profitable load to buy here: {"good_id", "units", "system_id", "planet_id"}
## or {} if nothing earns at least MIN_PROFIT. Profit is weighed by the days of travel.
static func _best_deal(ship: ShipData, here: PlanetData, destinations: Array[Dictionary]) -> Dictionary:
	var best := {}
	var best_score := 0.0
	for good_id in NpcSpawner.TRADER_GOODS:
		var stock := Economy.stock_of(here, good_id)
		var cost := Economy.buy_price(here, good_id)
		if stock <= 0 or cost <= 0 or Economy.is_illegal(here, good_id):
			continue
		# Leave half the stock, so one trader doesn't empty a market.
		var units := mini(mini(ship.cargo_free(), floori(stock / 2.0)), floori(float(ship.credits) / cost))
		if units <= 0:
			continue
		for destination in destinations:
			var planet: PlanetData = destination["planet"]
			if planet == here or Economy.is_illegal(planet, good_id):
				continue
			var profit := Economy.sell_price(planet, good_id) - cost
			var score := float(profit * units) / float(destination["days"])
			if profit >= cost * MIN_PROFIT and score > best_score:
				best_score = score
				best = {"good_id": good_id, "units": units, "system_id": destination["system_id"], "planet_id": planet.id}
	return best
