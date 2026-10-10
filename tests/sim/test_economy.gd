extends TestCase
## Prices, supply and demand, and market events.


func _planet(economy_id: String, government_id: String = "republic") -> PlanetData:
	var planet := PlanetData.new()
	planet.planet_seed = 777
	planet.inhabited = true
	planet.race_id = "human"
	planet.economy_id = economy_id
	planet.government_id = government_id
	planet.tech_level = 5
	Economy.init_market(planet)
	return planet


func test_every_inhabited_planet_has_a_market() -> void:
	var galaxy := GalaxyGenerator.generate(99)
	for system in galaxy.systems:
		for planet in system.planets:
			assert_eq(planet.market_stock.is_empty(), not planet.inhabited, "%s market mismatch" % planet.name)
	for good: Dictionary in GameData.goods():
		assert_true(int(good["base_price"]) > 0, "%s has no price" % good["id"])


func test_farm_worlds_sell_food_cheaper_than_industrial_worlds() -> void:
	var farm := _planet("agricultural")
	var factory := _planet("industrial")
	assert_true(Economy.buy_price(farm, "food") < Economy.buy_price(factory, "food"), "food should be cheaper on farm worlds")
	assert_true(Economy.buy_price(factory, "technology") < Economy.buy_price(farm, "technology"), "technology should be cheaper on industrial worlds")


func test_low_stock_raises_prices_and_high_stock_lowers_them() -> void:
	var planet := _planet("mixed")
	var good := GameData.good("minerals")
	var normal := Economy.normal_stock(planet, good)
	var scarce := Economy.mid_price(planet, good, int(normal / 4.0))
	var usual := Economy.mid_price(planet, good, normal)
	var flooded := Economy.mid_price(planet, good, normal * 4)
	assert_true(scarce > usual and usual > flooded, "price should fall as stock rises")


func test_buying_then_selling_straight_back_always_loses_money() -> void:
	var planet := _planet("mixed")
	for good: Dictionary in GameData.goods():
		for stock in [1, 2, 5, 40, 300]:
			var paid := Economy.buy_price_at(planet, good, stock)
			var received := Economy.sell_price_at(planet, good, stock - 1)
			assert_true(received < paid, "%s round trip at stock %d makes money (%d -> %d)" % [good["id"], stock, paid, received])


func test_stock_recovers_towards_normal() -> void:
	var galaxy := GalaxyGenerator.generate(12)
	var planet := galaxy.get_system(galaxy.player_ship().system_id).get_planet(galaxy.player_ship().orbiting_planet_id)
	var normal := Economy.normal_stock(planet, GameData.good("food"))
	planet.market_stock["food"] = 0
	for i in 60:
		TurnResolver.resolve_turn(galaxy)
	assert_true(absi(Economy.stock_of(planet, "food") - normal) <= 2, "food stock should be back near normal")


func test_contraband_depends_on_government_and_race() -> void:
	assert_false(Economy.is_illegal(_planet("mixed", "anarchy"), "narcotics"), "anarchy allows everything")
	assert_true(Economy.is_illegal(_planet("mixed", "republic"), "narcotics"))
	assert_true(Economy.is_illegal(_planet("mixed", "dictatorship"), "weapons"))
	assert_false(Economy.is_illegal(_planet("mixed", "monarchy"), "weapons"))
	var lumari := _planet("mixed", "anarchy")
	lumari.race_id = "lumari"
	assert_true(Economy.is_illegal(lumari, "alcohol"), "Lumari ban alcohol")


func test_market_events_change_prices_and_expire() -> void:
	var galaxy := GalaxyGenerator.generate(12)
	var planet := galaxy.get_system(galaxy.player_ship().system_id).get_planet(galaxy.player_ship().orbiting_planet_id)
	var before := Economy.price_ratio(planet, "medicine")
	planet.event_id = "plague"
	planet.event_days_left = 2
	assert_true(Economy.price_ratio(planet, "medicine") > before * 2.0, "plague should make medicine expensive")
	TurnResolver.resolve_turn(galaxy)
	TurnResolver.resolve_turn(galaxy)
	assert_eq(planet.event_id, "", "event should have ended")


func test_market_events_happen_over_time() -> void:
	var galaxy := GalaxyGenerator.generate(31)
	var started := 0
	for i in 40:
		for event in TurnResolver.resolve_turn(galaxy):
			if event["type"] == Economy.EVENT_MARKET_EVENT:
				started += 1
				var planet := galaxy.get_system(event["system_id"]).get_planet(event["planet_id"])
				assert_eq(planet.event_id, event["event_id"])
	assert_true(started > 0, "no market events in 40 days")
