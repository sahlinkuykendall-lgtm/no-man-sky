extends TestCase
## Hulls, equipment, wear, repairs and the shipyard.


## A new galaxy, with the player parked at an inhabited planet of their home system.
## The planet is set to Human, tech level 8 so every item is for sale.
func _galaxy() -> GalaxyData:
	var galaxy := GalaxyGenerator.generate(2024, GalaxyGenerator.DEFAULT_SYSTEM_COUNT, "human")
	var planet := Trade.market_planet(galaxy, galaxy.player_ship())
	planet.race_id = "human"
	planet.tech_level = 8
	return galaxy


func test_starting_ship() -> void:
	var ship := _galaxy().player_ship()
	assert_eq(ship.hull.type_id, Equipment.STARTING_HULL)
	assert_eq(ship.engine.type_id, Equipment.STARTING_ENGINE)
	assert_eq(ship.fuel_tank.type_id, Equipment.STARTING_FUEL_TANK)
	assert_almost_eq(ship.speed, 170.0, 0.001)
	assert_almost_eq(ship.jump_range, 20.0, 0.001)
	assert_almost_eq(ship.fuel, 30.0, 0.001)
	assert_eq(ship.cargo_capacity, 90 - 12 - 8 - 3 - 5, "hull size minus the weight of the engine, tank, gripper and laser")
	assert_eq(ship.gripper.type_id, Equipment.STARTING_GRIPPER)
	assert_eq(ship.weapons.size(), 1)
	assert_almost_eq(ship.hull_hp, ship.hull_hp_max, 0.001)
	assert_true(ship.hull_hp_max > 0.0)


func test_every_race_starts_with_a_working_ship() -> void:
	for race: Dictionary in GameData.races():
		var ship := GalaxyGenerator.generate(7, 30, race["id"]).player_ship()
		assert_eq(ship.hull.race_id, race["id"])
		assert_true(ship.cargo_capacity >= 50, "%s starting hold too small" % race["id"])
		assert_true(ship.jump_range >= GalaxyGenerator.MAX_NEIGHBOR_DISTANCE, "%s can't reach neighbors" % race["id"])


func test_makers_change_price_weight_and_armor() -> void:
	var human := ItemData.make("pulse_drive", "human")
	var veyari := ItemData.make("pulse_drive", "veyari")
	var skarn := ItemData.make("pulse_drive", "skarn")
	assert_true(Equipment.price(veyari) > Equipment.price(human), "Veyari gear is pricier")
	assert_true(Equipment.price(skarn) < Equipment.price(human), "Skarn gear is cheaper")
	assert_true(Equipment.weight(veyari) < Equipment.weight(human), "Veyari gear is lighter")
	assert_true(Equipment.armor(ItemData.make("fighter", "gorruk")) > Equipment.armor(ItemData.make("fighter", "human")), "Gorruk hulls are tougher")


func test_flying_and_jumping_wear_the_engine() -> void:
	var ship := _galaxy().player_ship()
	Equipment.wear(ship, "wear_per_flight_day")
	assert_true(ship.engine.condition < 100.0, "flying should wear the engine")
	var before := ship.engine.condition
	Equipment.wear(ship, "wear_per_jump")
	assert_true(ship.engine.condition < before, "jumping should wear the engine")
	assert_true(ship.fuel_tank.condition < 100.0, "jumping should wear the tank")


func test_worn_equipment_loses_power() -> void:
	var ship := _galaxy().player_ship()
	ship.engine.condition = 51.0
	Equipment.apply_stats(ship)
	assert_almost_eq(ship.speed, 170.0, 0.001, "still fine above 50%")
	var worn := Equipment.wear(ship, "wear_per_jump")
	assert_true(worn.has("engine"), "should report the engine just wore out")
	ship.engine.condition = 0.0
	Equipment.apply_stats(ship)
	assert_almost_eq(ship.speed, 170.0 * Equipment.BROKEN_EFFICIENCY, 0.001, "a broken engine works at half power")


func test_a_trip_wears_the_ship_in_the_turn_resolver() -> void:
	var galaxy := _galaxy()
	var ship := galaxy.player_ship()
	TurnResolver.apply_order(galaxy, ship, {"type": "move_to_point", "point": ship.position + Vector2(1000, 0)})
	TurnResolver.resolve_turn(galaxy)
	assert_true(ship.engine.condition < 100.0)


func test_better_engines_jump_faster() -> void:
	assert_true(TurnResolver.jump_days(24.0, 12.0) < TurnResolver.jump_days(24.0, 8.0))


func test_buying_an_engine_trades_in_the_old_one() -> void:
	var galaxy := _galaxy()
	var ship := galaxy.player_ship()
	ship.credits = 100000
	var new_engine := ItemData.make("arc_drive", "human")
	var expected_cost := Equipment.price(new_engine) - Equipment.trade_in_value(ship.engine, 100.0)
	var events: Array[Dictionary] = []
	assert_eq(TurnResolver.apply_order(galaxy, ship, {"type": "buy_equipment", "type_id": "arc_drive"}, events), "")
	assert_eq(ship.engine.type_id, "arc_drive")
	assert_eq(ship.credits, 100000 - expected_cost)
	assert_almost_eq(ship.speed, 235.0, 0.001)
	assert_eq(ship.cargo_capacity, 90 - 18 - 8 - 3 - 5, "the heavier engine takes cargo space")
	assert_eq(events[0]["type"], Shipyard.EVENT_BOUGHT_ITEM)
	assert_ne(Shipyard.buy_item(galaxy, ship, "arc_drive", []), "", "can't buy the same item twice")


func test_buying_a_hull_keeps_the_equipment() -> void:
	var galaxy := _galaxy()
	var ship := galaxy.player_ship()
	ship.credits = 100000
	assert_eq(Shipyard.buy_item(galaxy, ship, "freighter", []), "")
	assert_eq(ship.hull.type_id, "freighter")
	assert_eq(ship.engine.type_id, Equipment.STARTING_ENGINE)
	assert_eq(ship.cargo_capacity, 180 - 12 - 8 - 3 - 5)
	assert_almost_eq(ship.hull_hp, ship.hull_hp_max, 0.001, "a new hull is undamaged")


func test_shipyard_limits() -> void:
	var galaxy := _galaxy()
	var ship := galaxy.player_ship()
	var planet := Trade.market_planet(galaxy, ship)
	# Money.
	ship.credits = 0
	assert_ne(Shipyard.buy_item(galaxy, ship, "zenith_drive", []), "", "can't buy without money")
	# Tech level.
	ship.credits = 1000000
	planet.tech_level = 2
	assert_ne(Shipyard.buy_item(galaxy, ship, "zenith_drive", []), "", "tech 2 shipyards don't sell tech 8 engines")
	assert_eq(Equipment.shop_items(planet).filter(func(item: ItemData) -> bool: return item.type_id == "zenith_drive").size(), 0)
	# Cargo space: a full hold can't take a heavier engine.
	planet.tech_level = 8
	ship.add_cargo("food", ship.cargo_capacity)
	assert_ne(Shipyard.buy_item(galaxy, ship, "zenith_drive", []), "", "heavier engine shouldn't fit with a full hold")
	# And not away from a planet.
	ship.cargo.clear()
	TurnResolver.apply_order(galaxy, ship, {"type": "move_to_point", "point": ship.position + Vector2(500, 0)})
	assert_ne(TurnResolver.apply_order(galaxy, ship, {"type": "buy_equipment", "type_id": "pulse_drive"}), "")
	assert_ne(TurnResolver.apply_order(galaxy, ship, {"type": "repair"}), "")


func test_repair_fixes_everything_for_a_price() -> void:
	var galaxy := _galaxy()
	var ship := galaxy.player_ship()
	ship.engine.condition = 40.0
	ship.fuel_tank.condition = 80.0
	ship.hull_hp = ship.hull_hp_max - 10.0
	Equipment.apply_stats(ship)
	var cost := Equipment.total_repair_cost(ship)
	var credits := ship.credits
	assert_true(cost > 0)
	assert_eq(TurnResolver.apply_order(galaxy, ship, {"type": "repair"}), "")
	assert_almost_eq(ship.engine.condition, 100.0, 0.001)
	assert_almost_eq(ship.fuel_tank.condition, 100.0, 0.001)
	assert_almost_eq(ship.hull_hp, ship.hull_hp_max, 0.001)
	assert_almost_eq(ship.speed, 170.0, 0.001, "repaired engine back to full power")
	assert_eq(ship.credits, credits - cost)
	assert_ne(Shipyard.repair(galaxy, ship, []), "", "nothing left to repair")


func test_broke_pilots_get_emergency_repairs() -> void:
	var galaxy := _galaxy()
	var ship := galaxy.player_ship()
	ship.engine.condition = 0.0
	ship.credits = 0
	var events: Array[Dictionary] = []
	assert_eq(Shipyard.repair(galaxy, ship, events), "")
	assert_almost_eq(ship.engine.condition, Shipyard.EMERGENCY_CONDITION, 0.001)
	assert_true(events[0]["free"])


func test_equipment_survives_save_and_load() -> void:
	var galaxy := _galaxy()
	galaxy.player_ship().engine.condition = 63.5
	var loaded := GalaxyData.from_dict(JSON.parse_string(JSON.stringify(galaxy.to_dict())))
	var ship := loaded.player_ship()
	assert_eq(ship.engine.type_id, Equipment.STARTING_ENGINE)
	assert_almost_eq(ship.engine.condition, 63.5, 0.001)
	assert_eq(ship.cargo_capacity, galaxy.player_ship().cargo_capacity)


func test_old_saves_get_the_starting_ship() -> void:
	var galaxy := _galaxy()
	var data := galaxy.to_dict()
	data["save_version"] = 2
	for ship: Dictionary in data["ships"]:
		for key: String in ["hull", "engine", "fuel_tank"]:
			ship.erase(key)
	var ship := GalaxyData.from_dict(data).player_ship()
	assert_eq(ship.hull.type_id, Equipment.STARTING_HULL)
	assert_eq(ship.engine.type_id, Equipment.STARTING_ENGINE)
	assert_true(ship.cargo_capacity > 0)
