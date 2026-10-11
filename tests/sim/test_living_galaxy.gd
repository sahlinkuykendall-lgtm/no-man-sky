extends TestCase
## Milestone 5: shields, radar, karma and the law, police, rangers, NPC trading, hailing
## and the news.


## A new galaxy with no NPCs (tests add the ones they need). The player is parked at an
## inhabited Human planet of their home system, which is a republic (so it has police).
func _galaxy() -> GalaxyData:
	var galaxy := GalaxyGenerator.generate(2024, GalaxyGenerator.DEFAULT_SYSTEM_COUNT, "human")
	for ship in galaxy.ships.duplicate():
		if not ship.is_player:
			galaxy.remove_ship(ship.id)
	galaxy.ranger_limit = 0 # No newcomers either.
	for system in galaxy.systems:
		system.pirate_limit = 0
		system.trader_limit = 0
		system.police_limit = 0
	var planet := Trade.market_planet(galaxy, galaxy.player_ship())
	planet.race_id = "human"
	planet.government_id = "republic"
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


## An NPC of the given role (built from the first loadout of that role), `offset` from the player.
func _npc(galaxy: GalaxyData, role: String, offset: Vector2) -> ShipData:
	var player := galaxy.player_ship()
	var lists := {ShipData.ROLE_PIRATE: "pirates", ShipData.ROLE_TRADER: "traders", ShipData.ROLE_POLICE: "police", ShipData.ROLE_RANGER: "rangers"}
	var loadout: Dictionary = NpcSpawner.settings()[lists[role]][0]
	var ship := ShipData.new()
	ship.role = role
	ship.name = "Test " + role
	ship.race_id = "human"
	ship.system_id = player.system_id
	NpcSpawner.equip(ship, loadout, "human")
	ship.bounty = int(loadout.get("bounty", 0))
	ship.position = player.position + offset
	return galaxy.add_ship(ship)


func _attack(galaxy: GalaxyData, ship: ShipData, target: ShipData) -> void:
	assert_eq(TurnResolver.apply_order(galaxy, ship, {"type": "attack", "target_kind": "ship", "target_id": target.id}), "")


func _hail(galaxy: GalaxyData, ship: ShipData, target_kind: String, target_id: int, option: String) -> Dictionary:
	var events: Array[Dictionary] = []
	var error := TurnResolver.apply_order(galaxy, ship, {"type": "hail", "target_kind": target_kind, "target_id": target_id, "option": option}, events)
	assert_eq(error, "", "hail %s should be answered" % option)
	for event in events:
		if event["type"] == Comms.EVENT_HAIL:
			return event
	return {}


# --- Shields and radar ----------------------------------------------------------------

func test_shields_stop_part_of_every_hit() -> void:
	var galaxy := _galaxy()
	var ship := _undock(galaxy)
	var pirate := _npc(galaxy, ShipData.ROLE_PIRATE, Vector2(150, 0))
	pirate.shield = ItemData.make("bastion_shield", "human")
	_attack(galaxy, ship, pirate)
	var hull_before := pirate.hull_hp
	var events: Array[Dictionary] = []
	Combat.resolve(galaxy, events)
	var shot: Dictionary = events.filter(func(e: Dictionary) -> bool: return e["type"] == Combat.EVENT_SHOT and e["ship_id"] == ship.id)[0]
	assert_true(shot["blocked"] > 0, "the shield should stop part of the hit")
	assert_almost_eq(hull_before - pirate.hull_hp, float(shot["damage"]), 0.01, "only the rest hurts the hull")
	assert_true(pirate.shield.condition < 100.0, "stopping hits wears the shield")


func test_radar_decides_how_far_pirates_see() -> void:
	var galaxy := _galaxy()
	var ship := _undock(galaxy)
	var pirate := _npc(galaxy, ShipData.ROLE_PIRATE, Vector2(800, 0)) # Basic radar: 700.
	var events: Array[Dictionary] = []
	NpcBrain.think(galaxy, pirate, events)
	assert_false(pirate.has_target(), "the player is beyond the pirate's radar")
	pirate.radar = ItemData.make("long_radar", "human") # 1000.
	NpcBrain.think(galaxy, pirate, events)
	assert_eq(pirate.target_id, ship.id, "a better radar spots the player")
	assert_true(Equipment.radar_range(ship) >= 700.0, "the player starts with a basic radar")
	ship.radar = null
	assert_eq(Equipment.radar_range(ship), Equipment.NO_RADAR_RANGE)


# --- Karma and the law ----------------------------------------------------------------

func test_attacking_a_trader_is_a_crime() -> void:
	var galaxy := _galaxy()
	var ship := _undock(galaxy)
	var trader := _npc(galaxy, ShipData.ROLE_TRADER, Vector2(150, 0))
	_attack(galaxy, ship, trader)
	var events := TurnResolver.resolve_turn(galaxy)
	assert_true(ship.karma < 0, "karma goes down")
	assert_true(Law.is_wanted_by(ship, "human"), "the system's race wants the player")
	assert_true(events.any(func(e: Dictionary) -> bool: return e["type"] == Law.EVENT_CRIME), "a crime event")
	assert_true(galaxy.news[0]["text"].contains("police want"), "it makes the news")
	assert_eq(Law.reputation(-30), "Criminal")
	assert_eq(Law.reputation(0), "Neutral")


func test_crimes_in_lawless_systems_only_cost_karma() -> void:
	var galaxy := _galaxy()
	var ship := _undock(galaxy)
	for planet in galaxy.get_system(ship.system_id).planets:
		planet.government_id = "anarchy"
	var trader := _npc(galaxy, ShipData.ROLE_TRADER, Vector2(150, 0))
	_attack(galaxy, ship, trader)
	TurnResolver.resolve_turn(galaxy)
	assert_true(ship.karma < 0)
	assert_true(ship.wanted.is_empty(), "nobody to report it to")


func test_wanted_pilots_are_refused_and_unprotected_until_they_pay() -> void:
	var galaxy := _galaxy()
	var ship := galaxy.player_ship() # In orbit of a Human planet.
	var planet := Trade.market_planet(galaxy, ship)
	ship.wanted["human"] = 600
	assert_ne(TurnResolver.apply_order(galaxy, ship, {"type": "buy", "good_id": "food", "quantity": 1}), "", "no trading")
	assert_ne(TurnResolver.apply_order(galaxy, ship, {"type": "repair"}), "", "no repairs")
	assert_false(Combat.is_protected(galaxy, ship), "the planet's guns don't protect criminals")
	assert_true(Comms.options(galaxy, ship, Comms.TARGET_PLANET, planet.id).has("pay_fine"))
	var credits := ship.credits
	var reply := _hail(galaxy, ship, Comms.TARGET_PLANET, planet.id, "pay_fine")
	assert_true(reply["accepted"])
	assert_eq(ship.credits, credits - 600)
	assert_false(Law.is_wanted_by(ship, "human"))
	assert_true(Combat.is_protected(galaxy, ship))
	assert_eq(TurnResolver.apply_order(galaxy, ship, {"type": "buy", "good_id": "food", "quantity": 1}), "")


func test_fines_are_slowly_forgotten() -> void:
	var galaxy := _galaxy()
	var ship := galaxy.player_ship()
	ship.wanted["human"] = 100
	for i in 60:
		Law.daily(galaxy)
	assert_false(Law.is_wanted_by(ship, "human"))


func test_police_hunt_pirates_and_wanted_pilots() -> void:
	var galaxy := _galaxy()
	var ship := _undock(galaxy)
	var police := _npc(galaxy, ShipData.ROLE_POLICE, Vector2(300, 0))
	var events: Array[Dictionary] = []
	NpcBrain.think(galaxy, police, events)
	assert_false(police.has_target(), "an honest pilot is left alone")
	ship.wanted["human"] = 500
	NpcBrain.think(galaxy, police, events)
	assert_eq(police.target_id, ship.id, "police attack wanted pilots")
	ship.wanted.clear()
	var far_pirate := _npc(galaxy, ShipData.ROLE_PIRATE, Vector2(400, 0))
	NpcBrain.think(galaxy, police, events)
	assert_ne(police.target_id, far_pirate.id, "police guard their planets and leave pirates far from them alone")
	assert_ne(police.target_id, ship.id, "once the fine is paid, the police leave you alone")
	var planet := galaxy.get_system(ship.system_id).inhabited_planets()[0]
	police.position = planet.position() + Vector2(150, 0)
	var pirate := _npc(galaxy, ShipData.ROLE_PIRATE, Vector2.ZERO)
	pirate.position = planet.position() + Vector2(0, 200)
	NpcBrain.think(galaxy, police, events)
	assert_eq(police.target_id, pirate.id, "police attack pirates close to their planets")
	# And pirates don't hunt next to guarded planets.
	var trader := _npc(galaxy, ShipData.ROLE_TRADER, Vector2.ZERO)
	trader.position = planet.position() + Vector2(0, -150)
	trader.orbiting_planet_id = -1
	var lurker := _npc(galaxy, ShipData.ROLE_PIRATE, Vector2.ZERO)
	lurker.position = planet.position() + Vector2(0, -450)
	NpcBrain.think(galaxy, lurker, events)
	assert_ne(lurker.target_id, trader.id, "pirates stay away from traders near guarded planets")


func test_pirates_leave_notorious_pilots_alone() -> void:
	var galaxy := _galaxy()
	var ship := _undock(galaxy)
	var pirate := _npc(galaxy, ShipData.ROLE_PIRATE, Vector2(300, 0))
	ship.karma = -60
	NpcBrain.think(galaxy, pirate, [])
	assert_false(pirate.has_target())


func test_destroying_pirates_raises_karma_and_ranking() -> void:
	var galaxy := _galaxy()
	var ship := _undock(galaxy)
	var pirate := _npc(galaxy, ShipData.ROLE_PIRATE, Vector2(150, 0))
	pirate.hull_hp = 1.0
	_attack(galaxy, ship, pirate)
	Combat.resolve(galaxy, [])
	assert_true(ship.karma > 0)
	assert_eq(ship.kills, 1)
	assert_true(ship.points > 0)
	assert_eq(galaxy.ranger_ranking()[0], ship)


# --- NPC rangers and traders ------------------------------------------------------------

func test_rangers_hunt_pirates_and_earn_bounties() -> void:
	var galaxy := _galaxy()
	var ship := _undock(galaxy)
	var ranger := _npc(galaxy, ShipData.ROLE_RANGER, Vector2(0, 300))
	var pirate := _npc(galaxy, ShipData.ROLE_PIRATE, Vector2(0, 500))
	pirate.hull_hp = 1.0
	var events: Array[Dictionary] = []
	for i in 5:
		events.append_array(TurnResolver.resolve_turn(galaxy))
	assert_eq(galaxy.get_ship(pirate.id), null, "the ranger should destroy the pirate")
	assert_eq(ranger.kills, 1)
	assert_eq(ranger.credits >= pirate.bounty, true)
	assert_true(galaxy.news.any(func(item: Dictionary) -> bool: return item["text"].contains(ranger.name)), "it makes the news")
	assert_true(galaxy.ranger_ranking().has(ship))


func test_rangers_jump_to_systems_with_pirates() -> void:
	var galaxy := _galaxy()
	var ranger := _npc(galaxy, ShipData.ROLE_RANGER, Vector2(0, 200))
	var here := galaxy.get_system(ranger.system_id)
	var target: StarSystemData = null
	for system in galaxy.systems:
		if system != here and galaxy.distance_between(here.id, system.id) <= ranger.jump_range:
			target = system
			break
	var rng := RandomNumberGenerator.new()
	NpcSpawner.spawn_pirate(galaxy, target, rng, false)
	NpcBrain.think(galaxy, ranger, [])
	assert_eq(ranger.jump_target_system_id, target.id, "the ranger heads for the pirates")


func test_npc_traders_buy_low_and_sell_high() -> void:
	var galaxy := _galaxy()
	var system := galaxy.get_system(galaxy.player_ship().system_id)
	var trader := NpcSpawner.spawn_trader(galaxy, system, RandomNumberGenerator.new())
	trader.cargo.clear()
	trader.credits = 5000
	trader.idle_days = NpcBrain.MIN_REST_DAYS + 5
	var start_planet := Trade.market_planet(galaxy, trader)
	# Make technology dirt cheap here, so it is clearly the deal to make.
	start_planet.market_stock["technology"] = 2000
	var bought := false
	for i in 30:
		TurnResolver.resolve_turn(galaxy)
		if trader.cargo_amount("technology") > 0:
			bought = true
			break
	assert_true(bought, "the trader should buy the cheap technology")
	assert_true(trader.plan_planet_id >= 0, "and plan where to sell it")
	var credits_after_buying := trader.credits
	for i in 60:
		TurnResolver.resolve_turn(galaxy)
		if trader.cargo_amount("technology") == 0:
			break
	assert_eq(trader.cargo_amount("technology"), 0, "the trader should sell it somewhere")
	assert_true(trader.credits > credits_after_buying, "for a profit")


func test_npcs_respawn_over_time() -> void:
	var galaxy := _galaxy()
	galaxy.ranger_limit = 2
	galaxy.get_system(galaxy.player_ship().system_id).police_limit = 1
	for i in 300:
		TurnResolver.resolve_turn(galaxy)
	var roles := galaxy.ships.map(func(s: ShipData) -> String: return s.role)
	assert_true(roles.has(ShipData.ROLE_RANGER), "rangers arrive")
	assert_true(roles.has(ShipData.ROLE_POLICE), "police arrive")


# --- Hailing ---------------------------------------------------------------------------

func test_bribed_pirates_leave_you_alone() -> void:
	var galaxy := _galaxy()
	var ship := _undock(galaxy)
	ship.credits = 2000
	var pirate := _npc(galaxy, ShipData.ROLE_PIRATE, Vector2(300, 0))
	pirate.race_id = "skarn" # Greedy.
	var reply := {}
	# Answers are fixed for the day, so try on different days until one is accepted.
	for i in 10:
		reply = _hail(galaxy, ship, Comms.TARGET_SHIP, pirate.id, "bribe")
		if reply["accepted"]:
			break
		galaxy.day += 1
	assert_true(reply["accepted"], "a Skarn pirate takes bribes")
	assert_true(ship.credits < 2000, "the bribe costs money")
	NpcBrain.think(galaxy, pirate, [])
	assert_false(pirate.has_target(), "a bribed pirate doesn't attack")


func test_threats_work_on_weaker_pirates() -> void:
	var galaxy := _galaxy()
	var ship := _undock(galaxy)
	var pirate := _npc(galaxy, ShipData.ROLE_PIRATE, Vector2(300, 0))
	pirate.hull_hp = 5.0
	var reply := _hail(galaxy, ship, Comms.TARGET_SHIP, pirate.id, "threaten")
	assert_true(reply["accepted"], "a nearly dead pirate backs off")
	assert_true(pirate.has_truce_with(ship.id))
	var brute := _npc(galaxy, ShipData.ROLE_PIRATE, Vector2(-300, 0))
	brute.weapons.append(ItemData.make("wraith_torpedo", "human"))
	reply = _hail(galaxy, ship, Comms.TARGET_SHIP, brute.id, "threaten")
	assert_false(reply["accepted"], "a strong pirate laughs")
	assert_eq(brute.target_id, ship.id, "and attacks")


func test_surrendering_cargo_to_pirates() -> void:
	var galaxy := _galaxy()
	var ship := _undock(galaxy)
	ship.add_cargo("food", 20)
	var pirate := _npc(galaxy, ShipData.ROLE_PIRATE, Vector2(300, 0))
	_attack(galaxy, pirate, ship)
	var reply := _hail(galaxy, ship, Comms.TARGET_SHIP, pirate.id, "surrender")
	assert_true(reply["accepted"])
	assert_eq(ship.cargo_amount("food"), 10, "half the cargo is handed over")
	assert_eq(pirate.cargo_amount("food"), 10)
	assert_false(pirate.has_target(), "and the pirate stops attacking")


func test_demanding_cargo_from_traders_is_extortion() -> void:
	var galaxy := _galaxy()
	var ship := _undock(galaxy)
	var trader := _npc(galaxy, ShipData.ROLE_TRADER, Vector2(300, 0))
	trader.race_id = "skarn" # Not brave.
	trader.add_cargo("food", 30)
	var reply := {}
	for i in 10:
		reply = _hail(galaxy, ship, Comms.TARGET_SHIP, trader.id, "demand")
		if reply["accepted"]:
			break
		galaxy.day += 1
	assert_true(reply["accepted"], "a scared trader drops cargo")
	assert_eq(galaxy.get_system(ship.system_id).loot.size(), 1, "into a container")
	assert_true(Law.is_wanted_by(ship, "human"), "extortion is a crime")


func test_rangers_help_against_pirates() -> void:
	var galaxy := _galaxy()
	var ship := _undock(galaxy)
	var police := _npc(galaxy, ShipData.ROLE_POLICE, Vector2(200, 200))
	var pirate := _npc(galaxy, ShipData.ROLE_PIRATE, Vector2(300, 0))
	pirate.truce[ship.id] = 5 # Keep it from fighting the player first.
	_attack(galaxy, ship, pirate)
	var reply := _hail(galaxy, ship, Comms.TARGET_SHIP, police.id, "help")
	assert_true(reply["accepted"], "the police always help against pirates")
	assert_eq(police.target_id, pirate.id)


func test_news_and_planet_news() -> void:
	var galaxy := _galaxy()
	var ship := galaxy.player_ship()
	News.add(galaxy, "Something happened.")
	var reply := _hail(galaxy, ship, Comms.TARGET_PLANET, ship.orbiting_planet_id, "news")
	assert_true(reply["reply"].contains("Something happened."))
	var trader := _npc(galaxy, ShipData.ROLE_TRADER, Vector2(100, 0))
	reply = _hail(galaxy, ship, Comms.TARGET_SHIP, trader.id, "news")
	assert_true(reply["reply"] != "")
	for i in 50:
		News.add(galaxy, "Item %d" % i)
	assert_eq(galaxy.news.size(), News.MAX_ITEMS)
	assert_eq(galaxy.news[0]["text"], "Item 49", "newest first")


# --- Saves --------------------------------------------------------------------------

func test_living_galaxy_survives_save_and_load() -> void:
	var galaxy := GalaxyGenerator.generate(77)
	var ship := galaxy.player_ship()
	ship.karma = -7
	ship.wanted["gorruk"] = 300
	ship.shield = ItemData.make("deflector_shield", "human")
	Equipment.apply_stats(ship)
	for i in 5:
		TurnResolver.resolve_turn(galaxy)
	News.add(galaxy, "Hello")
	var some_npc: ShipData = galaxy.ships.filter(func(s: ShipData) -> bool: return not s.truce.is_empty() or s.role == ShipData.ROLE_RANGER)[0]
	some_npc.truce[ship.id] = 3
	var copy := GalaxyData.from_dict(JSON.parse_string(JSON.stringify(galaxy.to_dict())))
	assert_data_almost_eq(copy.to_dict(), galaxy.to_dict())
	assert_eq(copy.get_ship(some_npc.id).truce.get(ship.id), 3)
	assert_eq(copy.player_ship().shield.type_id, "deflector_shield")
	var roles := copy.ships.map(func(s: ShipData) -> String: return s.role)
	for role in [ShipData.ROLE_TRADER, ShipData.ROLE_POLICE, ShipData.ROLE_RANGER]:
		assert_true(roles.has(role), "the galaxy has %s ships" % role)


func test_old_saves_get_radar_police_and_rangers() -> void:
	var galaxy := GalaxyGenerator.generate(78)
	var data := galaxy.to_dict()
	data["save_version"] = 4
	data.erase("ranger_limit")
	for ship_dict: Dictionary in data["ships"]:
		ship_dict.erase("radar")
		ship_dict.erase("karma")
	data["ships"] = data["ships"].filter(func(d: Dictionary) -> bool: return d["is_player"] or d["role"] != ShipData.ROLE_RANGER)
	var loaded := GalaxyData.from_dict(JSON.parse_string(JSON.stringify(data)))
	assert_ne(loaded.player_ship().radar, null, "the player gets a radar")
	assert_true(loaded.ranger_limit > 0)
	assert_true(loaded.ships.any(func(s: ShipData) -> bool: return s.role == ShipData.ROLE_RANGER), "rangers are added")
