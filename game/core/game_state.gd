extends Node
## Holds the current game world. Autoloaded as "GameState".
## Views read from here; changes go through TurnManager (orders) so the same flow
## works later for multiplayer, where the server owns the galaxy.

var galaxy: GalaxyData = null


func has_game() -> bool:
	return galaxy != null


func new_game(galaxy_seed: int, player_race_id: String = "human") -> void:
	set_galaxy(GalaxyGenerator.generate(galaxy_seed, GalaxyGenerator.DEFAULT_SYSTEM_COUNT, player_race_id))


func set_galaxy(new_galaxy: GalaxyData) -> void:
	galaxy = new_galaxy
	EventBus.galaxy_loaded.emit()


func clear() -> void:
	galaxy = null


func player_ship() -> ShipData:
	return galaxy.player_ship() if galaxy else null


func current_system() -> StarSystemData:
	var ship := player_ship()
	return galaxy.get_system(ship.system_id) if ship else null
