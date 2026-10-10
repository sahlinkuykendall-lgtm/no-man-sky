extends TestCase


func test_same_seed_gives_same_galaxy() -> void:
	var a := GalaxyGenerator.generate(1234)
	var b := GalaxyGenerator.generate(1234)
	assert_eq(JSON.stringify(a.to_dict()), JSON.stringify(b.to_dict()), "galaxies from the same seed differ")


func test_different_seeds_give_different_galaxies() -> void:
	var a := GalaxyGenerator.generate(1)
	var b := GalaxyGenerator.generate(2)
	assert_ne(JSON.stringify(a.to_dict()), JSON.stringify(b.to_dict()), "different seeds made identical galaxies")


func test_system_count_and_spacing() -> void:
	var galaxy := GalaxyGenerator.generate(42)
	assert_eq(galaxy.systems.size(), GalaxyGenerator.DEFAULT_SYSTEM_COUNT, "wrong number of systems")
	for a in galaxy.systems:
		for b in galaxy.systems:
			if a.id < b.id:
				assert_true(a.galaxy_pos.distance_to(b.galaxy_pos) >= GalaxyGenerator.MIN_SYSTEM_DISTANCE - 0.001,
					"systems %s and %s are too close" % [a.name, b.name])


func test_every_system_reachable_with_starting_jump_range() -> void:
	for seed_value in [7, 99, 2024]:
		var galaxy := GalaxyGenerator.generate(seed_value)
		var jump_range := galaxy.player_ship().jump_range
		var reached := {0: true}
		var frontier: Array[int] = [0]
		while not frontier.is_empty():
			var current: int = frontier.pop_back()
			for other in galaxy.systems:
				if not reached.has(other.id) and galaxy.distance_between(current, other.id) <= jump_range:
					reached[other.id] = true
					frontier.append(other.id)
		assert_eq(reached.size(), galaxy.systems.size(), "seed %d: some systems are unreachable" % seed_value)


func test_unique_system_names() -> void:
	var galaxy := GalaxyGenerator.generate(5)
	var names := {}
	for system in galaxy.systems:
		assert_false(names.has(system.name), "duplicate system name " + system.name)
		names[system.name] = true


func test_each_race_has_an_inhabited_home() -> void:
	var galaxy := GalaxyGenerator.generate(77)
	for race in GameData.races():
		var home := galaxy.home_system_of(race["id"])
		assert_true(home != null, "no home system for " + race["id"])
		if home:
			assert_false(home.inhabited_planets().is_empty(), "home of %s has no inhabited planet" % race["id"])


func test_planets_have_valid_orbits() -> void:
	var galaxy := GalaxyGenerator.generate(3)
	for system in galaxy.systems:
		assert_true(system.planets.size() >= 1 and system.planets.size() <= 6, "bad planet count in " + system.name)
		var last_orbit := 0.0
		for planet in system.planets:
			assert_true(planet.orbit_radius > last_orbit + planet.radius, "orbits overlap in " + system.name)
			last_orbit = planet.orbit_radius
		assert_true(system.jump_radius > last_orbit, "jump boundary inside planets in " + system.name)


func test_player_starts_at_home_for_chosen_race() -> void:
	var galaxy := GalaxyGenerator.generate(11, GalaxyGenerator.DEFAULT_SYSTEM_COUNT, "skarn")
	var ship := galaxy.player_ship()
	assert_true(ship != null and ship.is_player, "no player ship")
	assert_eq(ship.race_id, "skarn")
	assert_eq(ship.system_id, galaxy.home_system_of("skarn").id, "player not in home system")
	assert_true(ship.orbiting_planet_id >= 0, "player should start parked at a planet")
