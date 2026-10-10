class_name Trade
extends RefCounted
## Buying, selling and refuelling at planets, police scans and the black market.
## Pure logic: called through TurnResolver.apply_order() (orders) and on arrival at planets.
##
## Contraband: a good is illegal on a planet if its government or race bans it
## (see Economy.is_illegal). Illegal goods can still be traded there, on the black market:
## pricier, and every deal risks a bust (fine + confiscation). Police may also scan ships
## arriving at a planet and confiscate any contraband on board.

## Fuel the Ranger Corps gives for free to pilots who can't afford any, so nobody is ever
## stranded. Every system has a neighbour within 13 parsecs, so this is always enough to
## jump somewhere.
const EMERGENCY_FUEL := 14.0

# Event types (each also has "ship_id" and "planet_id").
## {"good_id", "quantity" (+ bought / - sold), "credits" (+ paid / - received), "black_market"}
const EVENT_TRADED := "traded"
## A black-market deal was a police sting. {"good_id", "quantity" (+ buying / - selling,
## in which case the goods were confiscated), "fine"}
const EVENT_BUSTED := "busted"
## Police scanned the ship. {"fine", "confiscated": {good id: units}} (empty = all clear)
const EVENT_SCANNED := "scanned"
## Bought fuel. {"amount", "credits", "free_amount"}
const EVENT_REFUELED := "refueled"


## The inhabited planet the ship is parked at, or null if it can't trade right now.
static func market_planet(galaxy: GalaxyData, ship: ShipData) -> PlanetData:
	if ship.in_hyperspace or ship.orbiting_planet_id < 0:
		return null
	var planet := galaxy.get_system(ship.system_id).get_planet(ship.orbiting_planet_id)
	return planet if planet != null and planet.inhabited else null


## Buys up to `quantity` units (fewer if the hold, the wallet or the market runs out).
## `roll` is only for tests (0..1, the black-market bust roll); -1 means roll normally.
static func buy(galaxy: GalaxyData, ship: ShipData, good_id: String, quantity: int,
		events: Array[Dictionary], roll: float = -1.0) -> String:
	var planet := market_planet(galaxy, ship)
	if planet == null:
		return "You need to be in orbit of an inhabited planet to trade."
	var good := GameData.good(good_id)
	if good.is_empty():
		return "Unknown goods."
	if ship.cargo_free() <= 0:
		return "Your cargo hold is full."
	var stock := Economy.stock_of(planet, good_id)
	if stock <= 0:
		return "%s is sold out here." % good["name"]
	quantity = mini(quantity, ship.cargo_free())
	var bought := 0
	var total := 0
	while bought < quantity and stock - bought > 0:
		var price := Economy.buy_price_at(planet, good, stock - bought)
		if total + price > ship.credits:
			break
		total += price
		bought += 1
	if bought == 0:
		return "You can't afford any %s." % good["name"]

	if Economy.is_illegal(planet, good_id) and _busted(galaxy, ship, planet, good_id, bought, roll):
		# The deal was a sting: no goods, and a fine.
		var fine := _charge_fine(ship, planet, good, bought)
		events.append({"type": EVENT_BUSTED, "ship_id": ship.id, "planet_id": planet.id, "good_id": good_id, "quantity": bought, "fine": fine})
		return ""

	planet.market_stock[good_id] = stock - bought
	ship.credits -= total
	ship.add_cargo(good_id, bought)
	events.append({"type": EVENT_TRADED, "ship_id": ship.id, "planet_id": planet.id, "good_id": good_id,
		"quantity": bought, "credits": total, "black_market": Economy.is_illegal(planet, good_id)})
	return ""


## Sells up to `quantity` units of what the ship carries.
static func sell(galaxy: GalaxyData, ship: ShipData, good_id: String, quantity: int,
		events: Array[Dictionary], roll: float = -1.0) -> String:
	var planet := market_planet(galaxy, ship)
	if planet == null:
		return "You need to be in orbit of an inhabited planet to trade."
	var good := GameData.good(good_id)
	if good.is_empty():
		return "Unknown goods."
	quantity = mini(quantity, ship.cargo_amount(good_id))
	if quantity <= 0:
		return "You have no %s to sell." % good["name"]
	var stock := Economy.stock_of(planet, good_id)

	if Economy.is_illegal(planet, good_id) and _busted(galaxy, ship, planet, good_id, quantity, roll):
		# Caught: the goods are confiscated and you pay a fine.
		ship.add_cargo(good_id, -quantity)
		var fine := _charge_fine(ship, planet, good, quantity)
		events.append({"type": EVENT_BUSTED, "ship_id": ship.id, "planet_id": planet.id, "good_id": good_id, "quantity": -quantity, "fine": fine})
		return ""

	var total := 0
	for i in quantity:
		total += Economy.sell_price_at(planet, good, stock + i)
	planet.market_stock[good_id] = stock + quantity
	ship.credits += total
	ship.add_cargo(good_id, -quantity)
	events.append({"type": EVENT_TRADED, "ship_id": ship.id, "planet_id": planet.id, "good_id": good_id,
		"quantity": -quantity, "credits": -total, "black_market": Economy.is_illegal(planet, good_id)})
	return ""


## Fills the tank as far as the ship's credits allow.
static func refuel(galaxy: GalaxyData, ship: ShipData, events: Array[Dictionary]) -> String:
	var planet := market_planet(galaxy, ship)
	if planet == null:
		return "You need to be in orbit of an inhabited planet to refuel."
	var needed := ship.fuel_max - ship.fuel
	if needed < 0.05:
		return "Your tank is already full."
	var price := Economy.fuel_price(planet)
	var amount := minf(needed, float(ship.credits) / price)
	var cost := mini(ceili(amount * price - 0.0001), ship.credits)
	ship.fuel += amount
	ship.credits -= cost
	var free_amount := 0.0
	if ship.fuel < EMERGENCY_FUEL:
		free_amount = EMERGENCY_FUEL - ship.fuel
		ship.fuel = EMERGENCY_FUEL
	if amount < 0.05 and free_amount <= 0.0:
		return "You can't afford any fuel (%d cr per unit)." % price
	events.append({"type": EVENT_REFUELED, "ship_id": ship.id, "planet_id": planet.id, "amount": amount, "credits": cost, "free_amount": free_amount})
	return ""


## The illegal goods on board at this planet: {good id: units}.
static func contraband_on_board(ship: ShipData, planet: PlanetData) -> Dictionary:
	var found := {}
	for good_id: String in ship.cargo:
		if Economy.is_illegal(planet, good_id):
			found[good_id] = ship.cargo_amount(good_id)
	return found


## Police may scan a ship arriving at an inhabited planet. Contraband is confiscated and
## fined. Ships with an empty hold are waved through. `roll` is only for tests.
static func police_scan(galaxy: GalaxyData, ship: ShipData, planet: PlanetData,
		events: Array[Dictionary], roll: float = -1.0) -> void:
	if not planet.inhabited or ship.cargo_used() == 0:
		return
	if roll < 0.0:
		roll = _roll(galaxy, ship, ["police_scan", planet.id])
	if roll >= float(GameData.government(planet.government_id).get("scan_chance", 0.0)):
		return
	var found := contraband_on_board(ship, planet)
	var fine := 0
	for good_id: String in found:
		ship.add_cargo(good_id, -int(found[good_id]))
		fine += _charge_fine(ship, planet, GameData.good(good_id), int(found[good_id]))
	events.append({"type": EVENT_SCANNED, "ship_id": ship.id, "planet_id": planet.id, "fine": fine, "confiscated": found})


static func _busted(galaxy: GalaxyData, ship: ShipData, planet: PlanetData, good_id: String,
		quantity: int, roll: float) -> bool:
	if roll < 0.0:
		roll = _roll(galaxy, ship, ["black_market", planet.id, good_id, quantity, ship.credits])
	return roll < float(GameData.government(planet.government_id).get("black_market_risk", 0.0))


## Fines the ship for `quantity` units of contraband. Takes what it can if the pilot
## can't pay it all. Returns the amount paid.
static func _charge_fine(ship: ShipData, planet: PlanetData, good: Dictionary, quantity: int) -> int:
	var rate := float(GameData.government(planet.government_id).get("fine_rate", 0.5))
	var fine := mini(roundi(float(good.get("base_price", 0)) * quantity * rate), ship.credits)
	ship.credits -= fine
	return fine


## A deterministic random number 0..1 from the galaxy, day, ship and some extra context,
## so the same situation always gives the same result (saves and multiplayer stay in sync).
static func _roll(galaxy: GalaxyData, ship: ShipData, context: Array) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([galaxy.galaxy_seed, galaxy.day, ship.id] + context)
	return rng.randf()
