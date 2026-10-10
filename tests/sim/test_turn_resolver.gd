extends TestCase


func _galaxy() -> GalaxyData:
	return GalaxyGenerator.generate(555)


func test_day_advances_and_planets_orbit() -> void:
	var galaxy := _galaxy()
	var planet := galaxy.systems[0].planets[0]
	var angle_before := planet.orbit_angle
	TurnResolver.resolve_turn(galaxy)
	assert_eq(galaxy.day, 2, "day should advance by one")
	assert_almost_eq(wrapf(planet.orbit_angle - angle_before, -PI, PI), planet.orbit_speed, 0.0001, "planet did not orbit")


func test_ship_moves_at_most_its_speed() -> void:
	var galaxy := _galaxy()
	var ship := galaxy.player_ship()
	var start := ship.position
	assert_eq(TurnResolver.apply_order(galaxy, ship, {"type": "move_to_point", "point": start + Vector2(1000, 0)}), "")
	TurnResolver.resolve_turn(galaxy)
	assert_almost_eq(ship.position.distance_to(start), ship.speed, 0.01, "ship should move exactly its speed")
	assert_eq(ship.orbiting_planet_id, -1, "ship should have left orbit")


func test_ship_arrives_at_point() -> void:
	var galaxy := _galaxy()
	var ship := galaxy.player_ship()
	var target := ship.position + Vector2(ship.speed * 2.5, 0)
	TurnResolver.apply_order(galaxy, ship, {"type": "move_to_point", "point": target})
	assert_eq(TurnResolver.days_to_destination(galaxy, ship), 3)
	var arrived := false
	for i in 3:
		for event in TurnResolver.resolve_turn(galaxy):
			if event["type"] == TurnResolver.EVENT_ARRIVED_POINT and event["ship_id"] == ship.id:
				arrived = true
	assert_true(arrived, "no arrival event")
	assert_true(ship.position.distance_to(target) < 0.01, "ship not at target")
	assert_false(ship.has_destination, "course should be cleared after arrival")


func test_ship_reaches_and_follows_moving_planet() -> void:
	var galaxy := _galaxy()
	var ship := galaxy.player_ship()
	var system := galaxy.get_system(ship.system_id)
	var target: PlanetData = null
	for planet in system.planets:
		if planet.id != ship.orbiting_planet_id:
			target = planet
			break
	if target == null:
		return # Single-planet system: nothing to test with this seed.
	TurnResolver.apply_order(galaxy, ship, {"type": "move_to_planet", "planet_id": target.id})
	for i in 60:
		TurnResolver.resolve_turn(galaxy)
		if ship.orbiting_planet_id == target.id:
			break
	assert_eq(ship.orbiting_planet_id, target.id, "ship never reached the planet")
	TurnResolver.resolve_turn(galaxy)
	assert_almost_eq(ship.position.distance_to(target.position()), target.radius + TurnResolver.PLANET_ARRIVAL_MARGIN, 0.01,
		"ship should stay parked next to the planet as it orbits")


func test_jump_rejected_when_out_of_range() -> void:
	var galaxy := _galaxy()
	var ship := galaxy.player_ship()
	var far_system := -1
	for system in galaxy.systems:
		if galaxy.distance_between(ship.system_id, system.id) > ship.jump_range:
			far_system = system.id
			break
	assert_true(far_system >= 0, "test galaxy should have a far system")
	assert_ne(TurnResolver.apply_order(galaxy, ship, {"type": "jump", "system_id": far_system}), "", "far jump should be refused")
	assert_false(ship.has_destination)


func test_full_jump_to_neighbor_system() -> void:
	var galaxy := _galaxy()
	var ship := galaxy.player_ship()
	var origin := ship.system_id
	var target := -1
	for system in galaxy.systems:
		var d := galaxy.distance_between(origin, system.id)
		if system.id != origin and d <= ship.jump_range and d <= ship.fuel:
			target = system.id
			break
	assert_true(target >= 0, "no neighbor in range")
	var fuel_before := ship.fuel
	assert_eq(TurnResolver.apply_order(galaxy, ship, {"type": "jump", "system_id": target}), "")
	var entered := false
	var arrived := false
	for i in 80:
		for event in TurnResolver.resolve_turn(galaxy):
			if event.get("ship_id") != ship.id:
				continue
			if event["type"] == TurnResolver.EVENT_ENTERED_HYPERSPACE:
				entered = true
			if event["type"] == TurnResolver.EVENT_ARRIVED_SYSTEM:
				arrived = true
		if arrived:
			break
	assert_true(entered, "never entered hyperspace")
	assert_true(arrived, "never arrived")
	assert_eq(ship.system_id, target, "ended up in the wrong system")
	assert_false(ship.in_hyperspace)
	assert_almost_eq(ship.fuel, fuel_before - galaxy.distance_between(origin, target) * TurnResolver.FUEL_PER_PARSEC, 0.01, "wrong fuel use")
	assert_almost_eq(ship.position.length(), galaxy.get_system(target).jump_radius, 0.01, "should arrive on the system boundary")


func test_cannot_change_course_in_hyperspace() -> void:
	var galaxy := _galaxy()
	var ship := galaxy.player_ship()
	ship.in_hyperspace = true
	assert_ne(TurnResolver.apply_order(galaxy, ship, {"type": "stop"}), "")


func test_npc_traders_move_around() -> void:
	var galaxy := _galaxy()
	var npc: ShipData = null
	for ship in galaxy.ships:
		if not ship.is_player:
			npc = ship
			break
	assert_true(npc != null, "no NPC ships generated")
	var moved := false
	for i in 30:
		TurnResolver.resolve_turn(galaxy)
		if npc.has_destination:
			moved = true
	assert_true(moved, "NPC trader never left orbit in 30 days")


func test_simulation_is_deterministic() -> void:
	var a := _galaxy()
	var b := _galaxy()
	for i in 25:
		TurnResolver.resolve_turn(a)
		TurnResolver.resolve_turn(b)
	assert_eq(JSON.stringify(a.to_dict()), JSON.stringify(b.to_dict()), "same galaxy + same turns should give the same result")
