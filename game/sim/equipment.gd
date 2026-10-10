class_name Equipment
extends RefCounted
## Rules for hulls and equipment: what they cost and weigh, how they wear out, and how
## they add up to a ship's stats. Pure logic, no nodes. The models are in equipment.json.
##
## How a ship's stats are worked out (apply_stats):
##   cargo space = hull size - weight of the engine and fuel tank
##   speed, jump range and hyperspace speed come from the engine
##   fuel capacity comes from the fuel tank
##   armor (max hull HP) comes from the hull
## Worn equipment (below 50% condition) loses power: at 0% it works at half strength.

const KINDS: Array[String] = ["hull", "engine", "fuel_tank"]
const KIND_NAMES := {"hull": "Hull", "engine": "Engine", "fuel_tank": "Fuel tank"}

const WORN_CONDITION := 50.0 ## Below this, equipment starts losing power.
const BROKEN_EFFICIENCY := 0.5 ## How well equipment works at 0% condition.
const TRADE_IN_RATE := 0.6 ## Shipyards buy your old item for up to 60% of its price.
const REPAIR_RATE := 0.35 ## Fixing an item from 0% to 100% costs 35% of its price.
const HULL_REPAIR_PER_POINT := 8.0 ## Credits per hull point (before the maker's price factor).

const STARTING_HULL := "courier"
const STARTING_ENGINE := "spark_drive"
const STARTING_FUEL_TANK := "standard_tank"


# --- Item values ---------------------------------------------------------------

## A manufacturing factor ("price", "weight", "wear" or "armor") of the race that built an item.
static func maker_factor(item: ItemData, factor: String) -> float:
	return float(GameData.race(item.race_id).get("manufacturing", {}).get(factor, 1.0))


## What a shipyard charges for this item new.
static func price(item: ItemData) -> int:
	return roundi(float(item.stats().get("price", 0)) * maker_factor(item, "price"))


## Tons of cargo space the item takes up (hulls weigh nothing: they *are* the space).
static func weight(item: ItemData) -> int:
	if item == null or item.kind() == "hull":
		return 0
	return roundi(float(item.stats().get("weight", 0)) * maker_factor(item, "weight"))


## Max hull HP of a hull.
static func armor(hull: ItemData) -> float:
	return roundf(float(hull.stats().get("armor", 0)) * maker_factor(hull, "armor"))


## 1.0 when the item is in good shape, falling to BROKEN_EFFICIENCY at 0% condition.
static func efficiency(item: ItemData) -> float:
	if item == null or item.condition >= WORN_CONDITION:
		return 1.0
	return lerpf(BROKEN_EFFICIENCY, 1.0, item.condition / WORN_CONDITION)


## What a shipyard pays for an item, given its condition (0-100).
static func trade_in_value(item: ItemData, condition: float) -> int:
	if item == null:
		return 0
	return roundi(price(item) * TRADE_IN_RATE * (0.4 + 0.6 * condition / 100.0))


## The condition used for selling: hulls use their HP, other items their own condition.
static func condition_of(ship: ShipData, item: ItemData) -> float:
	if item == ship.hull and ship.hull_hp_max > 0.0:
		return 100.0 * ship.hull_hp / ship.hull_hp_max
	return item.condition


static func repair_cost(item: ItemData) -> int:
	if item == null:
		return 0
	return ceili(price(item) * REPAIR_RATE * (100.0 - item.condition) / 100.0 - 0.0001)


static func hull_repair_cost(ship: ShipData) -> int:
	if ship.hull == null:
		return 0
	return ceili((ship.hull_hp_max - ship.hull_hp) * HULL_REPAIR_PER_POINT * maker_factor(ship.hull, "price") - 0.0001)


## The cost of repairing everything on the ship.
static func total_repair_cost(ship: ShipData) -> int:
	return hull_repair_cost(ship) + repair_cost(ship.engine) + repair_cost(ship.fuel_tank)


# --- Ship stats -----------------------------------------------------------------

## Cargo space a hull would leave with this engine and fuel tank.
static func cargo_space(hull: ItemData, engine: ItemData, fuel_tank: ItemData) -> int:
	if hull == null:
		return 0
	return int(hull.stats().get("size", 0)) - weight(engine) - weight(fuel_tank)


## Works out a ship's stats from its hull and equipment. Call after anything changes.
## Ships without a hull (NPCs, for now) keep their stats as they are.
static func apply_stats(ship: ShipData) -> void:
	if ship.hull == null:
		return
	ship.cargo_capacity = cargo_space(ship.hull, ship.engine, ship.fuel_tank)
	ship.hull_hp_max = armor(ship.hull)
	ship.hull_hp = minf(ship.hull_hp, ship.hull_hp_max)
	if ship.engine != null:
		var power := efficiency(ship.engine)
		var stats := ship.engine.stats()
		ship.speed = float(stats.get("speed", 100)) * power
		ship.jump_range = float(stats.get("jump_range", 10)) * power
		ship.jump_speed = float(stats.get("jump_speed", 8)) * power
	if ship.fuel_tank != null:
		ship.fuel_max = float(ship.fuel_tank.stats().get("capacity", 20)) * efficiency(ship.fuel_tank)
		ship.fuel = minf(ship.fuel, ship.fuel_max)


## Gives a ship the starting hull and equipment, all built by one race.
static func give_starting_kit(ship: ShipData, race_id: String) -> void:
	ship.hull = ItemData.make(STARTING_HULL, race_id)
	ship.engine = ItemData.make(STARTING_ENGINE, race_id)
	ship.fuel_tank = ItemData.make(STARTING_FUEL_TANK, race_id)
	ship.hull_hp = armor(ship.hull)
	apply_stats(ship)
	ship.fuel = ship.fuel_max


## Wears the ship's engine and fuel tank. `use` is "wear_per_flight_day" or "wear_per_jump"
## (the field in equipment.json). Returns the kinds of items that just became worn
## (dropped below WORN_CONDITION), so the player can be warned.
static func wear(ship: ShipData, use: String) -> Array[String]:
	var newly_worn: Array[String] = []
	for kind: String in ["engine", "fuel_tank"]:
		var item := ship.slot(kind)
		if item == null:
			continue
		var before := item.condition
		item.condition = maxf(0.0, item.condition - float(item.stats().get(use, 0.0)) * maker_factor(item, "wear"))
		if before >= WORN_CONDITION and item.condition < WORN_CONDITION:
			newly_worn.append(kind)
	apply_stats(ship)
	return newly_worn


# --- Shipyards -------------------------------------------------------------------

## The new items a planet's shipyard sells: every model up to the planet's tech level,
## built by the planet's race. Ordered hulls, engines, fuel tanks, cheapest first.
static func shop_items(planet: PlanetData) -> Array[ItemData]:
	var items: Array[ItemData] = []
	for entries: Array in [GameData.hulls(), GameData.engines(), GameData.fuel_tanks()]:
		for entry: Dictionary in entries:
			if int(entry.get("tech", 1)) <= planet.tech_level:
				items.append(ItemData.make(entry["id"], planet.race_id))
	return items


## One line describing an item's main stats, e.g. "Speed 200 · Jump 24 pc · Hyper 9 pc/day".
static func describe(item: ItemData) -> String:
	var stats := item.stats()
	match item.kind():
		"hull":
			var slots := int(stats.get("weapon_slots", 0))
			return "Size %d t · Armor %d · %d weapon slot%s" % [int(stats.get("size", 0)), int(armor(item)), slots, "" if slots == 1 else "s"]
		"engine":
			return "Speed %d · Jump %d pc · Hyper %d pc/day" % [int(stats.get("speed", 0)), int(stats.get("jump_range", 0)), int(stats.get("jump_speed", 0))]
		"fuel_tank":
			return "Fuel %d" % int(stats.get("capacity", 0))
	return ""
