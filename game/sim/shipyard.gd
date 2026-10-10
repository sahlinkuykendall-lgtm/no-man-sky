class_name Shipyard
extends RefCounted
## Buying hulls and equipment and repairing them at a planet's shipyard.
## Pure logic: called through TurnResolver.apply_order(). Every inhabited planet has a
## shipyard (see Equipment.shop_items for what it sells).

## Pilots who can't afford repairs get their engine and fuel tank patched up to this
## condition for free by the Ranger Corps, so a worn-out ship never strands anyone.
const EMERGENCY_CONDITION := Equipment.WORN_CONDITION

# Event types (each also has "ship_id" and "planet_id").
## Bought an item. {"type_id", "race_id", "price", "trade_in", "credits" (+ paid / - received)}
const EVENT_BOUGHT_ITEM := "bought_item"
## Repaired the ship. {"credits", "free" (true if the Ranger Corps helped)}
const EVENT_REPAIRED := "repaired"
## An item dropped below WORN_CONDITION and is losing power. {"kind"}
const EVENT_EQUIPMENT_WORN := "equipment_worn"


## Buys a new item for the matching slot. The old item is traded in (its value is taken
## off the price). Fails if the ship can't pay or the new gear leaves too little cargo space.
static func buy_item(galaxy: GalaxyData, ship: ShipData, type_id: String, events: Array[Dictionary]) -> String:
	var planet := Trade.market_planet(galaxy, ship)
	if planet == null:
		return "You need to be in orbit of an inhabited planet to visit a shipyard."
	var kind := GameData.item_kind(type_id)
	if kind == "":
		return "Unknown item."
	if int(GameData.item_type(type_id).get("tech", 1)) > planet.tech_level:
		return "This shipyard can't build that (tech level too low)."
	if ship.hull == null:
		return "This ship can't be refitted."

	var new_item := ItemData.make(type_id, planet.race_id)
	var old_item := ship.slot(kind)
	if old_item != null and old_item.type_id == type_id and old_item.race_id == planet.race_id:
		return "You already have this. Use Repair to fix it up."
	var trade_in := Equipment.trade_in_value(old_item, Equipment.condition_of(ship, old_item)) if old_item != null else 0
	var item_price := Equipment.price(new_item)
	var cost := item_price - trade_in
	if cost > ship.credits:
		return "You need %d cr more." % (cost - ship.credits)

	# Check the cargo still fits with the new hull or the heavier equipment.
	var hull := new_item if kind == "hull" else ship.hull
	var engine := new_item if kind == "engine" else ship.engine
	var fuel_tank := new_item if kind == "fuel_tank" else ship.fuel_tank
	var space := Equipment.cargo_space(hull, engine, fuel_tank)
	if space < ship.cargo_used():
		return "Not enough room: this leaves %d tons for cargo and you carry %d. Sell some cargo first." % [space, ship.cargo_used()]
	if space < 0:
		return "That doesn't fit in your hull."

	ship.set_slot(kind, new_item)
	ship.credits -= cost
	Equipment.apply_stats(ship)
	if kind == "hull":
		ship.hull_hp = ship.hull_hp_max # A brand-new hull.
	events.append({"type": EVENT_BOUGHT_ITEM, "ship_id": ship.id, "planet_id": planet.id, "type_id": type_id,
		"race_id": planet.race_id, "price": item_price, "trade_in": trade_in, "credits": cost})
	return ""


## Repairs the hull, engine and fuel tank, as far as the ship's credits allow.
static func repair(galaxy: GalaxyData, ship: ShipData, events: Array[Dictionary]) -> String:
	var planet := Trade.market_planet(galaxy, ship)
	if planet == null:
		return "You need to be in orbit of an inhabited planet to visit a shipyard."
	var total := Equipment.total_repair_cost(ship)
	if total <= 0:
		return "Nothing needs repairing."

	# Pay for as much of the repair as we can afford (everything, if we can).
	var share := minf(1.0, float(ship.credits) / float(total))
	var paid := mini(ceili(total * share - 0.0001), ship.credits)
	ship.hull_hp += (ship.hull_hp_max - ship.hull_hp) * share
	for kind: String in ["engine", "fuel_tank"]:
		var item := ship.slot(kind)
		if item != null:
			item.condition += (100.0 - item.condition) * share
	ship.credits -= paid

	# The Ranger Corps patches up pilots who couldn't pay for everything.
	var free := false
	if share < 1.0:
		for kind: String in ["engine", "fuel_tank"]:
			var item := ship.slot(kind)
			if item != null and item.condition < EMERGENCY_CONDITION:
				item.condition = EMERGENCY_CONDITION
				free = true
	if paid <= 0 and not free:
		return "You can't afford any repairs."
	Equipment.apply_stats(ship)
	events.append({"type": EVENT_REPAIRED, "ship_id": ship.id, "planet_id": planet.id, "credits": paid, "free": free})
	return ""
