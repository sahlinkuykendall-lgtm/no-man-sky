class_name Economy
extends RefCounted
## Planet markets: what goods cost, how stock refills each day, and market events
## (famine, plague, ...). Pure logic, no nodes.
##
## A price is all of these multiplied together:
##   base price (goods.json)
##   x economy factor (farm worlds sell food cheap, industrial worlds sell technology cheap)
##   x tech level factor
##   x government and race factors (world.json, races.json)
##   x a small fixed "local quirk", so no two markets are exactly alike
##   x the current event (a famine makes food expensive, ...)
##   x supply: a market low on stock charges more, a flooded market pays less.
##
## Buying takes units out of a market and selling puts them in, so prices move while you
## trade and drift back to normal over the following days. Farming one route makes it fade.

const ELASTICITY := 0.45 ## How strongly stock levels move prices.
const SUPPLY_FACTOR_MIN := 0.4
const SUPPLY_FACTOR_MAX := 3.0
const SPREAD := 0.05 ## Markets sell 5% above and buy 5% below the middle price.
const BLACK_MARKET_MARKUP := 1.4 ## Illegal goods cost (and fetch) this much more.
const BLACK_MARKET_STOCK := 0.4 ## Black markets keep less stock than normal markets.
const RECOVERY_PER_DAY := 0.08 ## Share of the gap to normal stock that refills each day.
const EVENT_CHANCE_PER_DAY := 0.004 ## Per inhabited planet that has no event running.
const QUIRK := 0.1 ## Each planet's prices differ by up to +-10% for flavor.
const TECH_REFERENCE := 5 ## The tech level where the "tech" price factor is 1.

## Event returned by daily_update() when a market event starts.
## {"type", "system_id", "planet_id", "event_id"}. It has no "ship_id".
const EVENT_MARKET_EVENT := "market_event"


# --- Prices -----------------------------------------------------------------

## True if the good can only be traded on the black market here (and police confiscate it).
static func is_illegal(planet: PlanetData, good_id: String) -> bool:
	var government := GameData.government(planet.government_id)
	var race := GameData.race(planet.race_id)
	return government.get("illegal_goods", []).has(good_id) or race.get("illegal_goods", []).has(good_id)


## Everything except supply and demand: what the good costs here when stock is normal.
static func local_price(planet: PlanetData, good: Dictionary) -> float:
	var good_id: String = good.get("id", "")
	var price := float(good.get("base_price", 1))
	price *= float(good.get("economy", {}).get(planet.economy_id, 1.0))
	price *= maxf(0.3, 1.0 + float(good.get("tech", 0.0)) * (planet.tech_level - TECH_REFERENCE))
	price *= float(GameData.government(planet.government_id).get("prices", {}).get(good_id, 1.0))
	price *= float(GameData.race(planet.race_id).get("prices", {}).get(good_id, 1.0))
	price *= 1.0 + _quirk(planet, good_id)
	if planet.event_id != "":
		price *= float(GameData.market_event(planet.event_id).get("prices", {}).get(good_id, 1.0))
	if is_illegal(planet, good_id):
		price *= BLACK_MARKET_MARKUP
	return price


## How many units this market holds when nobody has traded for a while.
static func normal_stock(planet: PlanetData, good: Dictionary) -> int:
	var stock := float(good.get("stock", 50)) / float(good.get("economy", {}).get(planet.economy_id, 1.0))
	if is_illegal(planet, good.get("id", "")):
		stock *= BLACK_MARKET_STOCK
	return maxi(1, roundi(stock))


## The "middle" price of one unit when the market holds `stock` units.
static func mid_price(planet: PlanetData, good: Dictionary, stock: int) -> float:
	var ratio := float(normal_stock(planet, good)) / float(maxi(stock, 1))
	var supply := clampf(pow(ratio, ELASTICITY), SUPPLY_FACTOR_MIN, SUPPLY_FACTOR_MAX)
	return local_price(planet, good) * supply


## What the market charges for its next unit when it holds `stock` units (0 = sold out).
## Priced at the stock level *after* the sale, so selling it straight back always loses money.
static func buy_price_at(planet: PlanetData, good: Dictionary, stock: int) -> int:
	if stock <= 0:
		return 0
	return maxi(1, ceili(mid_price(planet, good, stock - 1) * (1.0 + SPREAD)))


## What the market pays for one more unit when it holds `stock` units.
static func sell_price_at(planet: PlanetData, good: Dictionary, stock: int) -> int:
	return maxi(1, floori(mid_price(planet, good, stock) * (1.0 - SPREAD)))


static func stock_of(planet: PlanetData, good_id: String) -> int:
	return int(planet.market_stock.get(good_id, 0))


static func buy_price(planet: PlanetData, good_id: String) -> int:
	return buy_price_at(planet, GameData.good(good_id), stock_of(planet, good_id))


static func sell_price(planet: PlanetData, good_id: String) -> int:
	return sell_price_at(planet, GameData.good(good_id), stock_of(planet, good_id))


## Current middle price compared with the galaxy-wide base price (1.0 = typical,
## 0.5 = half price). Used for "cheap here / pays well here" hints.
static func price_ratio(planet: PlanetData, good_id: String) -> float:
	var good := GameData.good(good_id)
	return mid_price(planet, good, stock_of(planet, good_id)) / float(good.get("base_price", 1))


## Credits per unit of fuel at this planet.
static func fuel_price(planet: PlanetData) -> int:
	return int(GameData.government(planet.government_id).get("fuel_price", 10))


# --- Setting up and updating markets -----------------------------------------

## Fills a newly inhabited planet's market. Uses its own random generator (from the
## planet's seed) so it never changes how the rest of the galaxy is generated.
static func init_market(planet: PlanetData) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([planet.planet_seed, "market"])
	planet.market_stock.clear()
	for good: Dictionary in GameData.goods():
		planet.market_stock[good["id"]] = maxi(1, roundi(normal_stock(planet, good) * rng.randf_range(0.6, 1.4)))


## Gives markets to inhabited planets that have none (for saves made before markets existed).
static func ensure_markets(galaxy: GalaxyData) -> void:
	for system in galaxy.systems:
		for planet in system.inhabited_planets():
			if planet.market_stock.is_empty():
				init_market(planet)


## Runs once per day: stock drifts back to normal, events tick down, and new events
## may start. Appends EVENT_MARKET_EVENT events for news.
static func daily_update(galaxy: GalaxyData, events: Array[Dictionary]) -> void:
	for system in galaxy.systems:
		for planet in system.inhabited_planets():
			_recover_stock(planet)
			if planet.event_id != "":
				planet.event_days_left -= 1
				if planet.event_days_left <= 0:
					planet.event_id = ""
					planet.event_days_left = 0
				continue
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([galaxy.galaxy_seed, galaxy.day, system.id, planet.id, "market"])
			if rng.randf() < EVENT_CHANCE_PER_DAY:
				var event := GameData.pick_weighted(rng, GameData.market_events())
				var days: Array = event.get("days", [7, 14])
				planet.event_id = event.get("id", "")
				planet.event_days_left = rng.randi_range(int(days[0]), int(days[1]))
				events.append({"type": EVENT_MARKET_EVENT, "system_id": system.id, "planet_id": planet.id, "event_id": planet.event_id})


static func _recover_stock(planet: PlanetData) -> void:
	for good: Dictionary in GameData.goods():
		var good_id: String = good["id"]
		var stock := stock_of(planet, good_id)
		var gap := normal_stock(planet, good) - stock
		if gap == 0:
			continue
		var change := roundi(gap * RECOVERY_PER_DAY)
		if change == 0:
			change = signi(gap)
		planet.market_stock[good_id] = stock + change


## A fixed number between -QUIRK and +QUIRK for this planet and good.
static func _quirk(planet: PlanetData, good_id: String) -> float:
	var roll := float(posmod(hash([planet.planet_seed, good_id]), 10000)) / 9999.0
	return (roll * 2.0 - 1.0) * QUIRK
