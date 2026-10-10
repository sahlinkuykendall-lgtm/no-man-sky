class_name NpcSpawner
extends RefCounted
## Creates NPC ships (traders and pirates) and replaces destroyed ones over time.
## Loadouts and numbers are in game/data/npcs.json. Pure logic.
##
## Each system has a normal number of traders and pirates (StarSystemData.trader_limit
## and pirate_limit). Home systems of the races have no pirates, and pirates get tougher
## the further a system is from any home system ("danger").

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


## Sets the normal number of traders and pirates of every system and creates them.
## Each system uses its own random generator, so this can also upgrade old saves.
static func populate(galaxy: GalaxyData) -> void:
	for system in galaxy.systems:
		var rng := _rng(galaxy, system, "populate")
		if not system.inhabited_planets().is_empty():
			system.trader_limit = rng.randi_range(2, 4)
		if not system.is_home:
			system.pirate_limit = rng.randi_range(0, 1) + (1 if rng.randf() < danger(galaxy, system) else 0)
		for i in system.trader_limit:
			spawn_trader(galaxy, system, rng)
		for i in system.pirate_limit:
			spawn_pirate(galaxy, system, rng, false)


## Once a day: destroyed pirates and traders are slowly replaced (newcomers arrive).
static func daily(galaxy: GalaxyData) -> void:
	var pirates := {} ## system id -> count
	var traders := {}
	for ship in galaxy.ships:
		if ship.is_player or ship.in_hyperspace:
			continue
		var counts := pirates if ship.is_pirate() else traders
		counts[ship.system_id] = int(counts.get(ship.system_id, 0)) + 1
	var chance := float(settings().get("respawn_chance", 0.04))
	for system in galaxy.systems:
		var rng := _rng(galaxy, system, "respawn")
		if int(pirates.get(system.id, 0)) < system.pirate_limit and rng.randf() < chance:
			spawn_pirate(galaxy, system, rng, true)
		if int(traders.get(system.id, 0)) < system.trader_limit and rng.randf() < chance:
			spawn_trader(galaxy, system, rng)


## A trader parked at one of the system's inhabited planets, with some cargo on board.
static func spawn_trader(galaxy: GalaxyData, system: StarSystemData, rng: RandomNumberGenerator) -> ShipData:
	var inhabited := system.inhabited_planets()
	if inhabited.is_empty():
		return null
	var loadout := GameData.pick_weighted(rng, settings().get("traders", []))
	var ship := ShipData.new()
	ship.role = ShipData.ROLE_TRADER
	ship.race_id = system.race_id
	ship.name = "%s %s" % [GameData.race(system.race_id).get("adjective", "Free"), loadout.get("name", "trader")]
	ship.system_id = system.id
	equip(ship, loadout, system.race_id)
	_fill_cargo(ship, loadout, rng)
	var home := inhabited[rng.randi_range(0, inhabited.size() - 1)]
	ship.orbiting_planet_id = home.id
	ship.orbit_offset = Vector2.from_angle(rng.randf() * TAU) * (home.radius + TurnResolver.PLANET_ARRIVAL_MARGIN)
	ship.position = home.position() + ship.orbit_offset
	ship.idle_days = rng.randi_range(0, 3)
	return galaxy.add_ship(ship)


## A pirate somewhere in the system (or arriving at its hyperspace boundary).
static func spawn_pirate(galaxy: GalaxyData, system: StarSystemData, rng: RandomNumberGenerator, at_boundary: bool) -> ShipData:
	var system_danger := danger(galaxy, system)
	var choices: Array = settings().get("pirates", []).filter(
		func(entry: Dictionary) -> bool: return float(entry.get("min_danger", 0.0)) <= system_danger)
	var loadout := GameData.pick_weighted(rng, choices)
	var races := GameData.races()
	var ship := ShipData.new()
	ship.role = ShipData.ROLE_PIRATE
	ship.race_id = races[rng.randi_range(0, races.size() - 1)].get("id", "human") # Renegades of any race.
	ship.name = "%s %s" % [loadout.get("name", "Pirate"), NameGenerator.new(rng).unique_name()]
	ship.system_id = system.id
	equip(ship, loadout, ship.race_id)
	ship.hull_hp = roundf(ship.hull_hp_max * float(loadout.get("hull_hp", 1.0))) # Battle-worn.
	ship.bounty = int(loadout.get("bounty", 0))
	_fill_cargo(ship, loadout, rng)
	var angle := rng.randf() * TAU
	var distance := system.jump_radius if at_boundary else system.jump_radius * rng.randf_range(0.35, 0.85)
	ship.position = Vector2.from_angle(angle) * distance
	ship.heading = angle + PI
	return galaxy.add_ship(ship)


## Builds the ship from a loadout (hull, engine, weapons), all made by one race.
static func equip(ship: ShipData, loadout: Dictionary, race_id: String) -> void:
	ship.hull = ItemData.make(str(loadout.get("hull", Equipment.STARTING_HULL)), race_id)
	ship.engine = ItemData.make(str(loadout.get("engine", Equipment.STARTING_ENGINE)), race_id)
	ship.fuel_tank = ItemData.make(Equipment.STARTING_FUEL_TANK, race_id)
	ship.weapons.clear()
	for weapon_id: String in loadout.get("weapons", []):
		ship.weapons.append(ItemData.make(weapon_id, race_id))
	ship.hull_hp = Equipment.armor(ship.hull)
	Equipment.apply_stats(ship)
	ship.fuel = ship.fuel_max


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


## A random generator for one system, seeded from the galaxy seed, the day and a purpose,
## so results never depend on what happens in other systems.
static func _rng(galaxy: GalaxyData, system: StarSystemData, purpose: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([galaxy.galaxy_seed, galaxy.day, system.id, purpose])
	return rng
