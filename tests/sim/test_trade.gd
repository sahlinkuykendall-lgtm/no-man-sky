extends TestCase
## Buying, selling, refuelling, police scans and the black market.


## A new galaxy, with the player parked at an inhabited planet of their home system.
func _galaxy() -> GalaxyData:
	return GalaxyGenerator.generate(2024)


func _market(galaxy: GalaxyData) -> PlanetData:
	return Trade.market_planet(galaxy, galaxy.player_ship())


func test_player_starts_with_money_and_an_empty_hold() -> void:
	var galaxy := _galaxy()
	var ship := galaxy.player_ship()
	assert_eq(ship.credits, GalaxyGenerator.PLAYER_START_CREDITS)
	assert_eq(ship.cargo_capacity, Equipment.cargo_space(ship.hull, ship.equipment()))
	assert_true(ship.cargo_capacity >= 50, "starting hold too small")
	assert_eq(ship.cargo_used(), 0)
	assert_true(_market(galaxy) != null, "player should start at a planet with a market")


func test_buying_moves_goods_money_and_stock() -> void:
	var galaxy := _galaxy()
	var ship := galaxy.player_ship()
	var planet := _market(galaxy)
	planet.government_id = "republic" # Food is legal everywhere; keep the test predictable.
	var stock := Economy.stock_of(planet, "food")
	var price := Economy.buy_price(planet, "food")
	var events: Array[Dictionary] = []
	assert_eq(TurnResolver.apply_order(galaxy, ship, {"type": "buy", "good_id": "food", "quantity": 1}, events), "")
	assert_eq(ship.cargo_amount("food"), 1)
	assert_eq(ship.credits, GalaxyGenerator.PLAYER_START_CREDITS - price)
	assert_eq(Economy.stock_of(planet, "food"), stock - 1)
	assert_eq(events.size(), 1)
	assert_eq(events[0]["type"], Trade.EVENT_TRADED)
	assert_eq(events[0]["credits"], price)


func test_buying_is_limited_by_hold_money_and_stock() -> void:
	var galaxy := _galaxy()
	var ship := galaxy.player_ship()
	var planet := _market(galaxy)
	planet.government_id = "republic"
	# The hold.
	ship.credits = 1000000
	Trade.buy(galaxy, ship, "food", 9999, [])
	assert_eq(ship.cargo_used(), ship.cargo_capacity, "should fill the hold")
	assert_ne(Trade.buy(galaxy, ship, "minerals", 1, []), "", "a full hold can't take more")
	# The money.
	ship.cargo.clear()
	ship.credits = 100
	Trade.buy(galaxy, ship, "food", 9999, [])
	assert_true(ship.credits >= 0 and ship.credits < Economy.buy_price(planet, "food"), "should spend as much as possible, never more")
	ship.credits = 0
	assert_ne(Trade.buy(galaxy, ship, "food", 1, []), "", "can't buy without money")
	# The stock.
	ship.cargo.clear()
	ship.cargo_capacity = 100000
	ship.credits = 100000000
	Trade.buy(galaxy, ship, "luxuries", 99999, [])
	assert_eq(Economy.stock_of(planet, "luxuries"), 0, "should buy the market out")
	assert_ne(Trade.buy(galaxy, ship, "luxuries", 1, []), "", "sold out")


func test_selling_pays_and_floods_the_market() -> void:
	var galaxy := _galaxy()
	var ship := galaxy.player_ship()
	var planet := _market(galaxy)
	planet.government_id = "republic"
	ship.add_cargo("minerals", 20)
	var price_before := Economy.sell_price(planet, "minerals")
	var credits_before := ship.credits
	assert_eq(TurnResolver.apply_order(galaxy, ship, {"type": "sell", "good_id": "minerals", "quantity": 9999}), "")
	assert_eq(ship.cargo_amount("minerals"), 0)
	assert_true(ship.credits > credits_before, "should have been paid")
	assert_true(Economy.sell_price(planet, "minerals") < price_before, "selling should lower the price")
	assert_ne(Trade.sell(galaxy, ship, "minerals", 1, []), "", "nothing left to sell")


func test_no_trading_away_from_inhabited_planets() -> void:
	var galaxy := _galaxy()
	var ship := galaxy.player_ship()
	TurnResolver.apply_order(galaxy, ship, {"type": "move_to_point", "point": ship.position + Vector2(500, 0)})
	assert_ne(TurnResolver.apply_order(galaxy, ship, {"type": "buy", "good_id": "food", "quantity": 1}), "")
	assert_ne(TurnResolver.apply_order(galaxy, ship, {"type": "refuel"}), "")


func test_refuel_costs_money() -> void:
	var galaxy := _galaxy()
	var ship := galaxy.player_ship()
	var planet := _market(galaxy)
	ship.fuel = 20.0
	var cost := ceili(10.0 * Economy.fuel_price(planet))
	assert_eq(TurnResolver.apply_order(galaxy, ship, {"type": "refuel"}), "")
	assert_almost_eq(ship.fuel, ship.fuel_max, 0.001)
	assert_eq(ship.credits, GalaxyGenerator.PLAYER_START_CREDITS - cost)
	assert_ne(TurnResolver.apply_order(galaxy, ship, {"type": "refuel"}), "", "tank already full")


func test_broke_pilots_get_emergency_fuel() -> void:
	var galaxy := _galaxy()
	var ship := galaxy.player_ship()
	ship.fuel = 0.0
	ship.credits = 0
	var events: Array[Dictionary] = []
	assert_eq(Trade.refuel(galaxy, ship, events), "")
	assert_almost_eq(ship.fuel, Trade.EMERGENCY_FUEL, 0.001)
	assert_eq(ship.credits, 0)


func test_police_confiscate_contraband_and_fine() -> void:
	var galaxy := _galaxy()
	var ship := galaxy.player_ship()
	var planet := _market(galaxy)
	planet.government_id = "dictatorship"
	planet.race_id = "human"
	ship.add_cargo("weapons", 5)
	ship.add_cargo("food", 5)
	var events: Array[Dictionary] = []
	Trade.police_scan(galaxy, ship, planet, events, 0.0)
	assert_eq(ship.cargo_amount("weapons"), 0, "weapons should be confiscated")
	assert_eq(ship.cargo_amount("food"), 5, "legal goods are kept")
	assert_true(ship.credits < GalaxyGenerator.PLAYER_START_CREDITS, "should be fined")
	assert_eq(events[0]["type"], Trade.EVENT_SCANNED)
	# A missed scan (roll above the chance) does nothing.
	ship.add_cargo("weapons", 5)
	events.clear()
	Trade.police_scan(galaxy, ship, planet, events, 0.99)
	assert_eq(ship.cargo_amount("weapons"), 5)
	assert_true(events.is_empty())


func test_black_market_trades_illegal_goods_at_a_risk() -> void:
	var galaxy := _galaxy()
	var ship := galaxy.player_ship()
	var planet := _market(galaxy)
	planet.government_id = "republic"
	planet.race_id = "human"
	planet.market_stock["narcotics"] = 10
	# A safe deal.
	var events: Array[Dictionary] = []
	assert_eq(Trade.buy(galaxy, ship, "narcotics", 2, events, 0.99), "")
	assert_eq(ship.cargo_amount("narcotics"), 2)
	assert_true(events[0]["black_market"], "should be a black-market deal")
	# A sting while selling: goods confiscated and a fine.
	var credits_before := ship.credits
	events.clear()
	assert_eq(Trade.sell(galaxy, ship, "narcotics", 2, events, 0.0), "")
	assert_eq(ship.cargo_amount("narcotics"), 0)
	assert_true(ship.credits < credits_before, "should be fined")
	assert_eq(events[0]["type"], Trade.EVENT_BUSTED)


func test_police_scan_on_arrival() -> void:
	# Fly back and forth between two planets carrying contraband: sooner or later the
	# police scan us (the chance per arrival at a dictatorship is 60%).
	var galaxy := _galaxy()
	var ship := galaxy.player_ship()
	var system := galaxy.get_system(ship.system_id)
	for planet in system.planets:
		planet.inhabited = true
		planet.government_id = "dictatorship"
		planet.race_id = "human"
	if system.planets.size() < 2:
		return
	ship.add_cargo("weapons", 3)
	var scanned := false
	for trip in 6:
		var target := system.planets[trip % 2]
		TurnResolver.apply_order(galaxy, ship, {"type": "move_to_planet", "planet_id": target.id})
		for i in 40:
			for event in TurnResolver.resolve_turn(galaxy):
				if event["type"] == Trade.EVENT_SCANNED and event.get("ship_id") == ship.id:
					scanned = true
			if ship.orbiting_planet_id == target.id:
				break
		if scanned:
			break
	assert_true(scanned, "never scanned in 6 arrivals")
	assert_eq(ship.cargo_amount("weapons"), 0, "weapons should be confiscated")


func test_old_saves_get_markets_and_money() -> void:
	var galaxy := _galaxy()
	var data := galaxy.to_dict()
	data["save_version"] = 1
	for system: Dictionary in data["systems"]:
		for planet: Dictionary in system["planets"]:
			planet.erase("market_stock")
	for ship: Dictionary in data["ships"]:
		ship.erase("credits")
		ship.erase("cargo_capacity")
	var loaded := GalaxyData.from_dict(data)
	assert_eq(loaded.player_ship().credits, GalaxyGenerator.PLAYER_START_CREDITS)
	assert_eq(loaded.player_ship().cargo_capacity, galaxy.player_ship().cargo_capacity)
	assert_false(_market(loaded).market_stock.is_empty(), "markets should be created")
