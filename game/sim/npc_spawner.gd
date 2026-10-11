class_name NpcSpawner
extends RefCounted
## Creates NPC ships (traders, pirates, police and rangers) and replaces destroyed ones
## over time. Loadouts and numbers are in game/data/npcs.json. Pure logic.
##
## Each system has a normal number of pirates and police (StarSystemData.pirate_limit and
## police_limit). Home systems of the races have no pirates, and pirates get tougher the
## further a system is from any home system ("danger"). Police patrol systems with a
## government (Law.police_count). Traders and rangers travel, so they are counted for the
## whole galaxy: each system adds a few traders to the total, and there are
## "ranger_count" NPC rangers (GalaxyData.ranger_limit).

## Goods NPC traders carry (nothing illegal, so the police leave them alone).
const TRADER_GOODS: Array[String] = ["food", "medicine", "alcohol", "minerals", "luxuries", "technology"]


static func settings() -> Dictionary:
	return GameData.npcs()


## How dangerous a system is: 0 at a race's home system, up to 1 far away from all of them.
static func danger(galaxy: GalaxyData, system: StarSystemData) -> float:
	var nearest := INF
	for other in galaxy.systems:
		if other.is_home:
			nearest = minf(nearest, system.galaxy_pos.distance_to(other.galaxy_pos))
	return clampf(nearest / float(settings().get("danger_distance", 30.0)), 0.0, 1.0)


## Sets the normal number of NPCs of every system and creates them.
## Each system uses its own random generator, so this can also upgrade old saves.
static func populate(galaxy: GalaxyData) -> void:
	for system in galaxy.systems:
		var rng := _rng(galaxy, system.id, "populate")
		if not system.inhabited_planets().is_empty():
			system.trader_limit = rng.randi_range(2, 4)
		if not system.is_home:
			system.pirate_limit = rng.randi_range(0, 1) + (1 if rng.randf() < danger(galaxy, system) else 0)
		system.police_limit = Law.police_count(system)
		for i in system.trader_limit:
			spawn_trader(galaxy, system, rng)
		for i in system.pirate_limit:
			spawn_pirate(galaxy, system, rng, false)
		for i in system.police_limit:
			spawn_police(galaxy, system, rng)
	galaxy.ranger_limit = int(settings().get("ranger_count", 10))
	var ranger_rng := _rng(galaxy, -1, "rangers")
	for i in galaxy.ranger_limit:
		spawn_ranger(galaxy, ranger_rng)


## Once a day: destroyed ships are slowly replaced (newcomers arrive).
static func daily(galaxy: GalaxyData) -> void:
	var pirates := {} ## system id -> count
	var police := {}
	var traders := {}
	var trader_total := 0
	var ranger_total := 0
	for ship in galaxy.ships:
		match ship.role:
			ShipData.ROLE_PIRATE:
				pirates[ship.system_id] = int(pirates.get(ship.system_id, 0)) + 1
			ShipData.ROLE_POLICE:
				police[ship.system_id] = int(police.get(ship.system_id, 0)) + 1
			ShipData.ROLE_TRADER:
				traders[ship.system_id] = int(traders.get(ship.system_id, 0)) + 1
				trader_total += 1
			ShipData.ROLE_RANGER:
				ranger_total += 1
	var trader_limit := 0
	for system in galaxy.systems:
		trader_limit += system.trader_limit

	var chance := float(settings().get("respawn_chance", 0.04))
	var pirate_chance := float(settings().get("pirate_respawn_chance", chance))
	for system in galaxy.systems:
		var rng := _rng(galaxy, system.id, "respawn")
		if int(pirates.get(system.id, 0)) < system.pirate_limit and rng.randf() < pirate_chance:
			spawn_pirate(galaxy, system, rng, true)
		if int(police.get(system.id, 0)) < system.police_limit and rng.randf() < chance:
			spawn_police(galaxy, system, rng)
		# New traders start where traders are missing, while the galaxy has too few.
		if trader_total < trader_limit and int(traders.get(system.id, 0)) < system.trader_limit and rng.randf() < chance:
			if spawn_trader(galaxy, system, rng) != null:
				trader_total += 1
	var ranger_rng := _rng(galaxy, -1, "rangers")
	if ranger_total < galaxy.ranger_limit and ranger_rng.randf() < chance:
		spawn_ranger(galaxy, ranger_rng)


## A trader parked at one of the system's inhabited planets, with some cargo and money.
static func spawn_trader(galaxy: GalaxyData, system: StarSystemData, rng: RandomNumberGenerator) -> ShipData:
	if system.inhabited_planets().is_empty():
		return null
	var loadout := GameData.pick_weighted(rng, settings().get("traders", []))
	var ship := _make_ship(ShipData.ROLE_TRADER, system.race_id, loadout, rng)
	ship.name = "%s %s" % [GameData.race(system.race_id).get("adjective", "Free"), loadout.get("name", "trader")]
	_fill_cargo(ship, loadout, rng)
	_park_at_planet(ship, system, rng)
	return galaxy.add_ship(ship)


## A pirate somewhere in the system (or arriving at its hyperspace boundary).
static func spawn_pirate(galaxy: GalaxyData, system: StarSystemData, rng: RandomNumberGenerator, at_boundary: bool) -> ShipData:
	var system_danger := danger(galaxy, system)
	var choices: Array = settings().get("pirates", []).filter(
		func(entry: Dictionary) -> bool: return float(entry.get("min_danger", 0.0)) <= system_danger)
	var loadout := GameData.pick_weighted(rng, choices)
	var races := GameData.races()
	var race_id: String = races[rng.randi_range(0, races.size() - 1)].get("id", "human") # Renegades of any race.
	var ship := _make_ship(ShipData.ROLE_PIRATE, race_id, loadout, rng)
	ship.name = "%s %s" % [loadout.get("name", "Pirate"), NameGenerator.new(rng).unique_name()]
	ship.hull_hp = roundf(ship.hull_hp_max * float(loadout.get("hull_hp", 1.0))) # Battle-worn.
	ship.bounty = int(loadout.get("bounty", 0))
	_fill_cargo(ship, loadout, rng)
	_place_in_space(ship, system, rng, at_boundary)
	return galaxy.add_ship(ship)


## A police ship of the system's race, starting near one of its inhabited planets.
static func spawn_police(galaxy: GalaxyData, system: StarSystemData, rng: RandomNumberGenerator) -> ShipData:
	var loadout := GameData.pick_weighted(rng, settings().get("police", []))
	var ship := _make_ship(ShipData.ROLE_POLICE, system.race_id, loadout, rng)
	ship.name = "%s %s" % [GameData.race(system.race_id).get("adjective", "Free"), loadout.get("name", "Patrol")]
	_place_in_space(ship, system, rng, false)
	var planets := system.inhabited_planets()
	if not planets.is_empty():
		var planet := planets[rng.randi_range(0, planets.size() - 1)]
		var distance := float(settings().get("police_guard_distance", 250.0)) * rng.randf_range(0.4, 1.0)
		ship.position = planet.position() + Vector2.from_angle(rng.randf() * TAU) * distance
	return galaxy.add_ship(ship)


## An NPC ranger, starting at a random inhabited planet anywhere in the galaxy.
static func spawn_ranger(galaxy: GalaxyData, rng: RandomNumberGenerator) -> ShipData:
	var homes: Array[StarSystemData] = []
	for system in galaxy.systems:
		if not system.inhabited_planets().is_empty():
			homes.append(system)
	if homes.is_empty():
		return null
	var system := homes[rng.randi_range(0, homes.size() - 1)]
	var races := GameData.races()
	var race_id: String = races[rng.randi_range(0, races.size() - 1)].get("id", "human")
	var loadout := GameData.pick_weighted(rng, settings().get("rangers", []))
	var ship := _make_ship(ShipData.ROLE_RANGER, race_id, loadout, rng)
	ship.name = "Ranger %s" % NameGenerator.new(rng).unique_name()
	_park_at_planet(ship, system, rng)
	return galaxy.add_ship(ship)


## Builds a ship from a loadout (hull, engine, weapons, shield, radar), all made by one race.
static func equip(ship: ShipData, loadout: Dictionary, race_id: String) -> void:
	ship.hull = ItemData.make(str(loadout.get("hull", Equipment.STARTING_HULL)), race_id)
	ship.engine = ItemData.make(str(loadout.get("engine", Equipment.STARTING_ENGINE)), race_id)
	ship.fuel_tank = ItemData.make(Equipment.STARTING_FUEL_TANK, race_id)
	ship.radar = ItemData.make(str(loadout.get("radar", Equipment.STARTING_RADAR)), race_id)
	ship.shield = null
	if loadout.has("shield"):
		ship.shield = ItemData.make(str(loadout["shield"]), race_id)
	ship.weapons.clear()
	for weapon_id: String in loadout.get("weapons", []):
		ship.weapons.append(ItemData.make(weapon_id, race_id))
	ship.hull_hp = Equipment.armor(ship.hull)
	Equipment.apply_stats(ship)
	ship.fuel = ship.fuel_max


static func _make_ship(role: String, race_id: String, loadout: Dictionary, rng: RandomNumberGenerator) -> ShipData:
	var ship := ShipData.new()
	ship.role = role
	ship.race_id = race_id
	equip(ship, loadout, race_id)
	var money: Array = loadout.get("credits", [0, 0])
	ship.credits = rng.randi_range(int(money[0]), int(money[1]))
	return ship


## Puts the ship in orbit of one of the system's inhabited planets.
static func _park_at_planet(ship: ShipData, system: StarSystemData, rng: RandomNumberGenerator) -> void:
	var inhabited := system.inhabited_planets()
	var home := inhabited[rng.randi_range(0, inhabited.size() - 1)]
	ship.system_id = system.id
	ship.orbiting_planet_id = home.id
	ship.orbit_offset = Vector2.from_angle(rng.randf() * TAU) * (home.radius + TurnResolver.PLANET_ARRIVAL_MARGIN)
	ship.position = home.position() + ship.orbit_offset
	ship.idle_days = rng.randi_range(0, 3)


## Puts the ship somewhere in the system's space (or on its hyperspace boundary).
static func _place_in_space(ship: ShipData, system: StarSystemData, rng: RandomNumberGenerator, at_boundary: bool) -> void:
	var angle := rng.randf() * TAU
	var distance := system.jump_radius if at_boundary else system.jump_radius * rng.randf_range(0.35, 0.85)
	ship.system_id = system.id
	ship.position = Vector2.from_angle(angle) * distance
	ship.heading = angle + PI


static func _fill_cargo(ship: ShipData, loadout: Dictionary, rng: RandomNumberGenerator) -> void:
	var amounts: Array = loadout.get("cargo", [0, 0])
	var units := mini(rng.randi_range(int(amounts[0]), int(amounts[1])), ship.cargo_free())
	if units <= 0:
		return
	var first := TRADER_GOODS[rng.randi_range(0, TRADER_GOODS.size() - 1)]
	var second := TRADER_GOODS[rng.randi_range(0, TRADER_GOODS.size() - 1)]
	var split := rng.randi_range(floori(units / 2.0), units)
	ship.add_cargo(first, split)
	ship.add_cargo(second, units - split)


## A random generator for one system (or -1 for the whole galaxy), seeded from the galaxy
## seed, the day and a purpose, so results never depend on what happens elsewhere.
static func _rng(galaxy: GalaxyData, system_id: int, purpose: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([galaxy.galaxy_seed, galaxy.day, system_id, purpose])
	return rng
