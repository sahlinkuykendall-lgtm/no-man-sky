extends TestCase


func test_galaxy_survives_save_and_load() -> void:
	var galaxy := GalaxyGenerator.generate(321)
	for i in 10:
		TurnResolver.resolve_turn(galaxy)
	var saved := JSON.stringify(galaxy.to_dict(), "", false, true)
	var loaded := GalaxyData.from_dict(JSON.parse_string(saved))
	# Tiny float differences are expected (JSON number parsing), so compare with a tolerance.
	assert_data_almost_eq(loaded.to_dict(), galaxy.to_dict(), 0.000001, "loaded galaxy differs from saved galaxy")
	assert_eq(loaded.player_ship().id, galaxy.player_ship().id)


func test_loaded_galaxy_keeps_simulating_identically() -> void:
	var galaxy := GalaxyGenerator.generate(8)
	var loaded := GalaxyData.from_dict(JSON.parse_string(JSON.stringify(galaxy.to_dict(), "", false, true)))
	for i in 15:
		TurnResolver.resolve_turn(galaxy)
		TurnResolver.resolve_turn(loaded)
	assert_eq(loaded.day, galaxy.day)
	assert_almost_eq(loaded.player_ship().position.x, galaxy.player_ship().position.x, 0.01)
	assert_almost_eq(loaded.systems[3].planets[0].orbit_angle, galaxy.systems[3].planets[0].orbit_angle, 0.0001)
