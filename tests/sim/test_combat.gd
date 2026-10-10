extends TestCase
## Weapons, pirates, loot, grippers and asteroids.


## A new galaxy with no NPCs (tests add the ones they need). The player is parked at an
## inhabited planet of their home system, which is Human with tech level 8.
func _galaxy() -> GalaxyData:
	var galaxy := GalaxyGenerator.generate(2024, GalaxyGenerator.DEFAULT_SYSTEM_COUNT, "human")
	for ship in galaxy.ships.duplicate():
		if not ship.is_player:
			galaxy.remove_ship(ship.id)
	for system in galaxy.systems:
		system.pirate_limit = 0 # No newcomers either.
		system.trader_limit = 0
	var planet := Trade.market_planet(galaxy, galaxy.player_ship())
	planet.race_id = "human"
	planet.tech_level = 8
	return galaxy


## Leaves orbit and parks the player in open space, away from the planets.
func _undock(galaxy: GalaxyData) -> ShipData:
	var ship := galaxy.player_ship()
	var system := galaxy.get_system(ship.system_id)
	ship.orbiting_planet_id = -1
	ship.clear_course()
	ship.position = Vector2(0.0, -system.jump_radius * 0.95)
	return ship


## A pirate built from a loadout in npcs.json, `offset` away from the player.
func _pirate(galaxy: GalaxyData, offset: Vector2, loadout_id: String = "raider") -> ShipData:
	var player := galaxy.player_ship()
	var loadout := GameData.find_by_id(NpcSpawner.settings()["pirates"], loadout_id)
	var pirate := ShipData.new()
	pirate.role = ShipData.ROLE_PIRATE
	pirate.name = "Test pirate"
	pirate.race_id = "skarn"
	pirate.system_id = player.system_id
	NpcSpawner.equip(pirate, loadout, "human")
	pirate.bounty = int(loadout["bounty"])
	pirate.position = player.position + offset
	return galaxy.add_ship(pirate)


func _attack(galaxy: GalaxyData, ship: ShipData, target: ShipData) -> void:
	assert_eq(TurnResolver.apply_order(galaxy, ship, {"type": "attack", "target_kind": "ship", "target_id": target.id}), "")


func _count(events: Array[Dictionary], type: String) -> int:
	return events.filter(func(event: Dictionary) -> bool: return event["type"] == type).size()


func test_weapons_only_fire_within_range() -> void:
	var galaxy := _galaxy()
	var ship := _undock(galaxy)
	var pirate := _pirate(galaxy, Vector2(400, 0))
	_attack(galaxy, ship, pirate)
	var events: Array[Dictionary] = []
	Combat.resolve(galaxy, events)
	assert_eq(_count(events, Combat.EVENT_SHOT), 0, "the pirate is out of laser range")
	pirate.position = ship.position + Vector2(150, 0)
	var hull_before := pirate.hull_hp
	Combat.resolve(galaxy, events)
	assert_eq(_count(events, Combat.EVENT_SHOT), 1)
	assert_true(pirate.hull_hp < hull_before, "the pirate should be damaged")
	assert_true(pirate.hull_hp >= hull_before - 12.0, "a pulse laser does at most 12 damage")
	assert_true(ship.weapons[0].condition < 100.0, "shooting wears the weapon")


func test_chasing_brings_the_target_into_range() -> void:
	var galaxy := _galaxy()
	var ship := _undock(galaxy)
	var pirate := _pirate(galaxy, Vector2(500, 0))
	pirate.weapons.clear() # A harmless pirate, so only the chase matters.
	_attack(galaxy, ship, pirate)
	var hit := false
	for i in 5:
		for event in TurnResolver.resolve_turn(galaxy):
			if event["type"] == Combat.EVENT_SHOT and event["ship_id"] == ship.id:
				hit = true
	assert_true(hit, "should have caught up with the pirate and fired")


func test_destroyed_pirates_leave_loot_and_pay_a_bounty() -> void:
	var galaxy := _galaxy()
	var ship := _undock(galaxy)
	var pirate := _pirate(galaxy, Vector2(200, 0))
	pirate.hull_hp = 1.0
	pirate.add_cargo("food", 10)
	var credits := ship.credits
	_attack(galaxy, ship, pirate)
	var events: Array[Dictionary] = []
	Combat.resolve(galaxy, events)
	assert_eq(galaxy.get_ship(pirate.id), null, "the pirate should be gone")
	assert_eq(_count(events, Combat.EVENT_SHIP_DESTROYED), 1)
	assert_eq(ship.credits, credits + pirate.bounty)
	assert_false(ship.has_target(), "nothing left to shoot at")
	var loot := galaxy.get_system(ship.system_id).loot
	assert_eq(loot.size(), 1, "the wreck should leave a cargo container")
	assert_true(loot[0].cargo.get("salvage", 0) > 0, "wrecks contain salvage")


func test_gripper_collects_loot_in_range() -> void:
	var galaxy := _galaxy()
	var ship := _undock(galaxy)
	var system := galaxy.get_system(ship.system_id)
	var container := system.add_loot(ship.position + Vector2(300, 0), {"minerals": 10})
	var events: Array[Dictionary] = []
	Combat.resolve(galaxy, events)
	assert_eq(ship.cargo_amount("minerals"), 0, "too far for the gripper")
	# Fly close, with only 3 tons of room left in the hold.
	ship.position = container.position + Vector2(50, 0)
	ship.add_cargo("food", ship.cargo_free() - 3)
	Combat.resolve(galaxy, events)
	assert_eq(ship.cargo_amount("minerals"), 3)
	assert_eq(container.cargo["minerals"], 7, "the rest stays in the container")
	assert_true(events.back()["left_behind"])
	# Make room and pick up the rest.
	ship.add_cargo("food", -20)
	Combat.resolve(galaxy, events)
	assert_eq(ship.cargo_amount("minerals"), 10)
	assert_true(system.loot.is_empty(), "an empty container disappears")


func test_loot_drifts_away_after_a_while() -> void:
	var galaxy := _galaxy()
	var system := galaxy.get_system(galaxy.player_ship().system_id)
	system.add_loot(Vector2(5000, 5000), {"food": 1})
	for i in LootData.LIFETIME_DAYS:
		Combat.daily_upkeep(galaxy)
	assert_true(system.loot.is_empty())


func test_planets_protect_ships_in_orbit() -> void:
	var galaxy := _galaxy()
	var ship := galaxy.player_ship() # In orbit of an inhabited planet.
	var pirate := _pirate(galaxy, Vector2(60, 0))
	var events: Array[Dictionary] = []
	NpcBrain.think(galaxy, pirate, events)
	assert_false(pirate.has_target(), "pirates don't attack ships under planetary protection")
	pirate.target_kind = Combat.TARGET_SHIP
	pirate.target_id = ship.id
	Combat.resolve(galaxy, events)
	assert_eq(_count(events, Combat.EVENT_SHOT), 0, "no shooting at protected ships")
	assert_ne(TurnResolver.apply_order(galaxy, pirate, {"type": "attack", "target_kind": "ship", "target_id": ship.id}), "")


func test_pirates_hunt_ships_they_spot() -> void:
	var galaxy := _galaxy()
	var ship := _undock(galaxy)
	var far_pirate := _pirate(galaxy, Vector2(2000, 0))
	var pirate := _pirate(galaxy, Vector2(300, 0))
	var events: Array[Dictionary] = []
	NpcBrain.think(galaxy, far_pirate, events)
	assert_false(far_pirate.has_target(), "too far away to notice us")
	NpcBrain.think(galaxy, pirate, events)
	assert_eq(pirate.target_id, ship.id)
	assert_true(pirate.pursue)
	assert_eq(events[0]["type"], Combat.EVENT_UNDER_ATTACK)
	var hull := ship.hull_hp
	for i in 3:
		TurnResolver.resolve_turn(galaxy)
	assert_true(ship.hull_hp < hull, "the pirate should have opened fire")


func test_ships_return_fire() -> void:
	var galaxy := _galaxy()
	var ship := _undock(galaxy)
	var pirate := _pirate(galaxy, Vector2(150, 0))
	_attack(galaxy, pirate, ship)
	Combat.resolve(galaxy, [])
	assert_eq(ship.target_id, pirate.id, "our weapons should lock onto the attacker")
	assert_false(ship.pursue, "returning fire doesn't change our course")
	var hull := pirate.hull_hp
	Combat.resolve(galaxy, [])
	assert_true(pirate.hull_hp < hull)


func test_traders_flee_to_a_planet() -> void:
	var galaxy := _galaxy()
	var ship := _undock(galaxy)
	var trader := NpcSpawner.spawn_trader(galaxy, galaxy.get_system(ship.system_id), RandomNumberGenerator.new())
	trader.orbiting_planet_id = -1
	trader.position = ship.position
	var pirate := _pirate(galaxy, Vector2(150, 0))
	_attack(galaxy, pirate, trader)
	Combat.resolve(galaxy, [])
	assert_true(trader.target_planet_id >= 0, "the trader should run for a planet")
	assert_ne(TurnResolver.apply_order(galaxy, ship, {"type": "attack", "target_kind": "ship", "target_id": trader.id}), "",
		"rangers may not attack peaceful ships")


func test_no_weapons_no_attack() -> void:
	var galaxy := _galaxy()
	var ship := _undock(galaxy)
	var pirate := _pirate(galaxy, Vector2(150, 0))
	ship.weapons.clear()
	assert_ne(TurnResolver.apply_order(galaxy, ship, {"type": "attack", "target_kind": "ship", "target_id": pirate.id}), "")


func test_destroyed_player_is_rescued() -> void:
	var galaxy := _galaxy()
	var ship := _undock(galaxy)
	var system := galaxy.get_system(ship.system_id)
	ship.add_cargo("food", 10)
	ship.credits = 1000
	ship.hull_hp = 1.0
	var wreck_position := ship.position
	var pirate := _pirate(galaxy, Vector2(150, 0))
	_attack(galaxy, pirate, ship)
	var events: Array[Dictionary] = []
	Combat.resolve(galaxy, events)
	assert_eq(_count(events, Combat.EVENT_RESCUED), 1)
	assert_true(Combat.is_protected(galaxy, ship), "towed to an inhabited planet")
	assert_eq(ship.credits, 800, "the rescue costs 20% of our credits")
	assert_eq(ship.cargo_used(), 0)
	assert_almost_eq(ship.hull_hp, ceilf(ship.hull_hp_max * Combat.RESCUE_HULL))
	assert_false(pirate.has_target())
	assert_eq(system.loot[0].cargo["food"], 10, "the cargo is left in a container")
	assert_eq(system.loot[0].position, wreck_position)


func test_asteroids_break_into_minerals_and_come_back() -> void:
	var galaxy := _galaxy()
	var ship := galaxy.player_ship()
	var belt: StarSystemData = null
	for system in galaxy.systems:
		if not system.asteroids.is_empty():
			belt = system
			break
	assert_true(belt != null, "some systems should have asteroid belts")
	var asteroid := belt.asteroids[0]
	ship.system_id = belt.id
	ship.orbiting_planet_id = -1
	ship.position = asteroid.position() + Vector2(100, 0)
	asteroid.hp = 5.0
	assert_eq(TurnResolver.apply_order(galaxy, ship, {"type": "attack", "target_kind": "asteroid", "target_id": asteroid.id}), "")
	var events: Array[Dictionary] = []
	Combat.resolve(galaxy, events)
	assert_false(asteroid.exists())
	assert_eq(_count(events, Combat.EVENT_ASTEROID_DESTROYED), 1)
	assert_eq(ship.cargo_amount("minerals"), asteroid.minerals, "the gripper picks up the minerals")
	for i in Combat.ASTEROID_RESPAWN_DAYS.y:
		Combat.daily_upkeep(galaxy)
	assert_true(asteroid.exists(), "broken asteroids are replaced")


func test_missiles_use_ammo_and_repairs_reload_them() -> void:
	var galaxy := _galaxy()
	var ship := galaxy.player_ship()
	var planet_id := ship.orbiting_planet_id
	_undock(galaxy)
	ship.weapons[0] = ItemData.make("dart_launcher", "human")
	var pirate := _pirate(galaxy, Vector2(300, 0))
	_attack(galaxy, ship, pirate)
	ship.pursue = false
	Combat.resolve(galaxy, [])
	assert_eq(ship.weapons[0].ammo, 5)
	ship.weapons[0].ammo = 0
	var events: Array[Dictionary] = []
	Combat.resolve(galaxy, events)
	assert_eq(events.filter(func(e: Dictionary) -> bool: return e["type"] == Combat.EVENT_SHOT and e["ship_id"] == ship.id).size(), 0,
		"an empty launcher can't fire")
	# Back at the planet, a repair reloads the launcher.
	ship.orbiting_planet_id = planet_id
	assert_true(Equipment.reload_cost(ship.weapons[0]) > 0)
	assert_eq(Shipyard.repair(galaxy, ship, []), "")
	assert_eq(ship.weapons[0].ammo, ship.weapons[0].max_ammo())


func test_fragment_weapons_hit_nearby_enemies() -> void:
	var galaxy := _galaxy()
	var ship := _undock(galaxy)
	ship.weapons[0] = ItemData.make("scatter_cannon", "human")
	var target := _pirate(galaxy, Vector2(120, 0))
	var neighbour := _pirate(galaxy, Vector2(150, 30))
	var bystander := _pirate(galaxy, Vector2(120, 400))
	var hulls := [target.hull_hp, neighbour.hull_hp, bystander.hull_hp]
	_attack(galaxy, ship, target)
	Combat.resolve(galaxy, [])
	assert_true(target.hull_hp < hulls[0])
	assert_true(neighbour.hull_hp < hulls[1], "splash damage")
	assert_true(hulls[1] - neighbour.hull_hp < hulls[0] - target.hull_hp, "splash does less damage")
	assert_almost_eq(bystander.hull_hp, hulls[2], 0.001, "too far for the splash")


func test_weapon_slots_buying_and_selling() -> void:
	var galaxy := _galaxy()
	var ship := galaxy.player_ship()
	ship.credits = 100000
	assert_ne(Shipyard.buy_item(galaxy, ship, "beam_lance", []), "", "the Courier's only weapon slot is taken")
	var cargo := ship.cargo_capacity
	var events: Array[Dictionary] = []
	assert_eq(TurnResolver.apply_order(galaxy, ship, {"type": "sell_weapon", "index": 0}, events), "")
	assert_true(ship.weapons.is_empty())
	assert_eq(ship.cargo_capacity, cargo + 5, "selling the laser frees its 5 tons")
	assert_eq(events[0]["type"], Shipyard.EVENT_SOLD_ITEM)
	assert_eq(Shipyard.buy_item(galaxy, ship, "beam_lance", []), "")
	# A Fighter has 3 weapon slots.
	assert_eq(Shipyard.buy_item(galaxy, ship, "fighter", []), "")
	assert_eq(Shipyard.buy_item(galaxy, ship, "pulse_laser", []), "")
	assert_eq(Shipyard.buy_item(galaxy, ship, "pulse_laser", []), "", "the same model twice is fine")
	assert_ne(Shipyard.buy_item(galaxy, ship, "dart_launcher", []), "", "all 3 slots are full")
	assert_ne(Shipyard.buy_item(galaxy, ship, "courier", []), "", "3 weapons don't fit on a Courier")


func test_pirates_come_back_over_time() -> void:
	var galaxy := GalaxyGenerator.generate(2024)
	var system: StarSystemData = null
	for candidate in galaxy.systems:
		if candidate.pirate_limit > 0:
			system = candidate
			break
	assert_true(system != null, "some systems should have pirates")
	for ship in galaxy.ships_in_system(system.id):
		if ship.is_pirate():
			galaxy.remove_ship(ship.id)
	for i in 400:
		galaxy.day += 1
		NpcSpawner.daily(galaxy)
	var pirates := galaxy.ships_in_system(system.id).filter(func(s: ShipData) -> bool: return s.is_pirate())
	assert_eq(pirates.size(), system.pirate_limit)


func test_pirates_stay_away_from_home_systems() -> void:
	var galaxy := GalaxyGenerator.generate(99)
	var pirate_count := 0
	for ship in galaxy.ships:
		if ship.is_pirate():
			pirate_count += 1
			var system := galaxy.get_system(ship.system_id)
			assert_false(system.is_home, "pirate in a home system")
			assert_true(ship.bounty > 0)
			assert_true(ship.hull_hp > 0.0 and not ship.weapons.is_empty())
			if ship.hull.type_id == "heavy_fighter":
				assert_true(NpcSpawner.danger(galaxy, system) >= 0.75, "warlords only far from home systems")
	assert_true(pirate_count > 10, "the galaxy should have pirates")


func test_a_fight_ends() -> void:
	var galaxy := _galaxy()
	var ship := _undock(galaxy)
	var pirate := _pirate(galaxy, Vector2(400, 0))
	var pirate_id := pirate.id
	_attack(galaxy, ship, pirate)
	var ended := false
	for i in 60:
		for event in TurnResolver.resolve_turn(galaxy):
			if event["type"] == Combat.EVENT_RESCUED or (event["type"] == Combat.EVENT_SHIP_DESTROYED and event["ship_id"] == pirate_id):
				ended = true
		if ended:
			break
	assert_true(ended, "one of the ships should have been destroyed")


func test_combat_state_survives_save_and_load() -> void:
	var galaxy := _galaxy()
	var ship := _undock(galaxy)
	var pirate := _pirate(galaxy, Vector2(150, 0))
	_attack(galaxy, ship, pirate)
	galaxy.get_system(ship.system_id).add_loot(Vector2(10, 20), {"salvage": 3})
	TurnResolver.resolve_turn(galaxy)
	var loaded := GalaxyData.from_dict(JSON.parse_string(JSON.stringify(galaxy.to_dict(), "", false, true)))
	assert_data_almost_eq(loaded.to_dict(), galaxy.to_dict(), 0.000001)
	assert_eq(loaded.player_ship().target_id, pirate.id)


func test_old_saves_get_weapons_and_pirates() -> void:
	var data := GalaxyGenerator.generate(2024).to_dict()
	data["save_version"] = 3
	for system: Dictionary in data["systems"]:
		for key: String in ["asteroids", "loot", "next_loot_id", "pirate_limit", "trader_limit"]:
			system.erase(key)
	var old_ships: Array = []
	for ship: Dictionary in data["ships"]:
		if ship["is_player"]:
			ship.erase("gripper")
			ship.erase("weapons")
			old_ships.append(ship)
		elif ship["role"] == ShipData.ROLE_TRADER:
			for key: String in ["hull", "engine", "fuel_tank", "gripper", "weapons"]:
				ship.erase(key)
			old_ships.append(ship)
	data["ships"] = old_ships
	var loaded := GalaxyData.from_dict(data)
	var player := loaded.player_ship()
	assert_eq(player.gripper.type_id, Equipment.STARTING_GRIPPER)
	assert_eq(player.weapons.size(), 1)
	var pirates := 0
	for ship in loaded.ships:
		assert_true(ship.hull != null, "every ship should have a hull now")
		if ship.is_pirate():
			pirates += 1
	assert_true(pirates > 0, "old saves should get pirates")
