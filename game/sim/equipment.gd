class_name Equipment
extends RefCounted
## Rules for hulls and equipment: what they cost and weigh, how they wear out, and how
## they add up to a ship's stats. Pure logic, no nodes. The models are in equipment.json.
##
## How a ship's stats are worked out (apply_stats):
##   cargo space = hull size - weight of everything installed
##   speed, jump range and hyperspace speed come from the engine
##   fuel capacity comes from the fuel tank
##   armor (max hull HP) comes from the hull
## Worn equipment (below 50% condition) loses power: at 0% it works at half strength.

## Every kind of item, in the order shops list them.
const KINDS: Array[String] = ["hull", "engine", "fuel_tank", "gripper", "weapon"]
const KIND_NAMES := {"hull": "Hull", "engine": "Engine", "fuel_tank": "Fuel tank", "gripper": "Gripper", "weapon": "Weapon"}
const WEAPON_TYPE_NAMES := {"energy": "Energy", "fragment": "Fragment", "missile": "Missile"}

const WORN_CONDITION := 50.0 ## Below this, equipment starts losing power.
const BROKEN_EFFICIENCY := 0.5 ## How well equipment works at 0% condition.
const TRADE_IN_RATE := 0.6 ## Shipyards buy your old item for up to 60% of its price.
const REPAIR_RATE := 0.35 ## Fixing an item from 0% to 100% costs 35% of its price.
const HULL_REPAIR_PER_POINT := 3.0 ## Credits per hull point (before the maker's price factor).

const STARTING_HULL := "courier"
const STARTING_ENGINE := "spark_drive"
const STARTING_FUEL_TANK := "standard_tank"
const STARTING_GRIPPER := "basic_gripper"
const STARTING_WEAPON := "pulse_laser"


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


## Cost of fixing an item to 100% and, for missile launchers, refilling its missiles.
static func repair_cost(item: ItemData) -> int:
	if item == null:
		return 0
	var fix := ceili(price(item) * REPAIR_RATE * (100.0 - item.condition) / 100.0 - 0.0001)
	return fix + reload_cost(item)


## Cost of refilling a missile launcher.
static func reload_cost(item: ItemData) -> int:
	var missing := item.max_ammo() - item.ammo
	if missing <= 0:
		return 0
	return roundi(missing * float(item.stats().get("ammo_price", 0)) * maker_factor(item, "price"))


static func hull_repair_cost(ship: ShipData) -> int:
	if ship.hull == null:
		return 0
	return ceili((ship.hull_hp_max - ship.hull_hp) * HULL_REPAIR_PER_POINT * maker_factor(ship.hull, "price") - 0.0001)


## The cost of repairing everything on the ship (and reloading its missiles).
static func total_repair_cost(ship: ShipData) -> int:
	var total := hull_repair_cost(ship)
	for item in ship.equipment():
		total += repair_cost(item)
	return total


# --- Weapons ---------------------------------------------------------------------

## "energy", "fragment" or "missile".
static func weapon_type(weapon: ItemData) -> String:
	return str(weapon.stats().get("type", "energy"))


static func weapon_range(weapon: ItemData) -> float:
	return float(weapon.stats().get("range", 0))


## [min, max] damage of one shot, lowered when the weapon is worn out.
static func weapon_damage(weapon: ItemData) -> Vector2:
	var damage: Array = weapon.stats().get("damage", [0, 0])
	return Vector2(float(damage[0]), float(damage[1])) * efficiency(weapon)


## Can the weapon fire? (Missile launchers need missiles.)
static func can_fire(weapon: ItemData) -> bool:
	return weapon.max_ammo() == 0 or weapon.ammo > 0


## The longest range of the ship's weapons (0 without weapons).
static func max_weapon_range(ship: ShipData) -> float:
	var longest := 0.0
	for weapon in ship.weapons:
		longest = maxf(longest, weapon_range(weapon))
	return longest


## The shortest range of the ship's weapons (0 without weapons).
static func min_weapon_range(ship: ShipData) -> float:
	var shortest := INF
	for weapon in ship.weapons:
		shortest = minf(shortest, weapon_range(weapon))
	return 0.0 if shortest == INF else shortest


static func weapon_slots(hull: ItemData) -> int:
	return int(hull.stats().get("weapon_slots", 0)) if hull != null else 0


## Wears a weapon after a shot.
static func wear_weapon(weapon: ItemData) -> void:
	var amount := float(weapon.stats().get("wear_per_shot", 0.0)) * maker_factor(weapon, "wear")
	weapon.condition = maxf(0.0, weapon.condition - amount)


static func gripper_range(ship: ShipData) -> float:
	if ship.gripper == null:
		return 0.0
	return float(ship.gripper.stats().get("range", 0)) * efficiency(ship.gripper)


# --- Ship stats -----------------------------------------------------------------

## Cargo space a hull would leave with these items installed.
static func cargo_space(hull: ItemData, items: Array[ItemData]) -> int:
	if hull == null:
		return 0
	var space := int(hull.stats().get("size", 0))
	for item in items:
		space -= weight(item)
	return space


## Works out a ship's stats from its hull and equipment. Call after anything changes.
## Ships without a hull (only in very old saves) keep their stats as they are.
static func apply_stats(ship: ShipData) -> void:
	if ship.hull == null:
		return
	ship.cargo_capacity = cargo_space(ship.hull, ship.equipment())
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
	ship.gripper = ItemData.make(STARTING_GRIPPER, race_id)
	ship.weapons.assign([ItemData.make(STARTING_WEAPON, race_id)])
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
## built by the planet's race. Ordered by kind (KINDS), cheapest first.
static func shop_items(planet: PlanetData) -> Array[ItemData]:
	var items: Array[ItemData] = []
	var lists := GameData.items_by_kind()
	for kind in KINDS:
		var entries: Array = lists[kind].duplicate()
		entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("price", 0)) < int(b.get("price", 0)))
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
		"gripper":
			return "Pick-up range %d" % int(stats.get("range", 0))
		"weapon":
			var damage: Array = stats.get("damage", [0, 0])
			var text := "%s · Damage %d-%d · Range %d" % [WEAPON_TYPE_NAMES.get(weapon_type(item), "?"), int(damage[0]), int(damage[1]), int(weapon_range(item))]
			if stats.has("splash"):
				text += " · Splash"
			if item.max_ammo() > 0:
				text += " · %d missiles" % item.max_ammo()
			return text
	return ""
