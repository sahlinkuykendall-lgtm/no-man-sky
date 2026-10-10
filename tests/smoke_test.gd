extends SceneTree
## Plays the real game headlessly for a while (menu -> new game -> trade -> shipyard -> fly -> jump ->
## fight a pirate -> pick up its wreck -> save/load -> back to menu) and fails if any script
## error or warning was logged.
##
## Usage: godot --headless -s res://tests/smoke_test.gd


class ErrorCounter extends Logger:
	var errors: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		var kind := "WARNING" if error_type == ERROR_TYPE_WARNING else "ERROR"
		errors.append("%s: %s %s (%s:%d in %s)" % [kind, rationale, code, file, line, function])

	func _log_message(_message: String, _error: bool) -> void:
		pass


const TIMEOUT_SECONDS := 90.0

var _counter := ErrorCounter.new()


func _initialize() -> void:
	OS.add_logger(_counter)
	# If a script error stops the test midway, the watchdog still ends it as a failure.
	create_timer(TIMEOUT_SECONDS).timeout.connect(_on_timeout)
	_run.call_deferred()


func _on_timeout() -> void:
	_counter.errors.append("Smoke test did not finish within %d seconds." % TIMEOUT_SECONDS)
	_finish()


func _run() -> void:
	var main: Node = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(5)
	var game_state: Node = root.get_node("GameState")
	var turn_manager: Node = root.get_node("TurnManager")
	var save_system: Node = root.get_node("SaveSystem")
	var event_bus: Node = root.get_node("EventBus")

	# Start a new game the way the menu does.
	main.call("_on_new_game", 4242, "lumari")
	await _frames(5)
	var galaxy: GalaxyData = game_state.galaxy
	var ship: ShipData = galaxy.player_ship()
	_check(ship != null, "no player ship")

	# Land on the starting planet, trade through the market screen, and take off again.
	var hud: Node = main.get_node("Game").get_child(1)
	hud.call("_toggle_planet_screen")
	await _frames(3)
	var planet_screen: Node = hud.get("_planet_screen")
	_check(planet_screen.call("is_open"), "planet screen did not open")
	var credits_before := ship.credits
	planet_screen.call("_submit", "buy", "food", 9999)
	await _frames(2)
	_check(ship.cargo_amount("food") > 0 and ship.credits < credits_before, "buying food failed")
	planet_screen.call("_submit", "sell", "food", 5) # Leaves room for a heavier fuel tank.
	planet_screen.call("_on_refuel") # Tank is full: should only post a message.
	await _frames(2)

	# Visit the shipyard: buy a better fuel tank and repair some wear.
	planet_screen.call("show_tab", "shipyard")
	await _frames(2)
	_check(planet_screen.call("current_tab") == "shipyard", "shipyard tab did not open")
	ship.credits += 20000
	ship.engine.condition = 60.0
	var shipyard: Node = planet_screen.get("_shipyard")
	shipyard.call("_on_buy", "long_range_tank")
	await _frames(2)
	_check(ship.fuel_tank.type_id == "long_range_tank", "buying a fuel tank failed")
	shipyard.call("_on_repair")
	await _frames(2)
	_check(ship.engine.condition >= 99.9, "repair failed")
	shipyard.call("_on_sell_weapon", 0)
	await _frames(2)
	_check(ship.weapons.is_empty(), "selling a weapon failed")
	shipyard.call("_on_buy", "pulse_laser")
	await _frames(2)
	_check(ship.weapons.size() == 1, "buying a weapon failed")
	planet_screen.call("show_tab", "market")
	await _frames(2)
	hud.call("_toggle_planet_screen")
	_check(not planet_screen.call("is_open"), "planet screen did not close")

	# Fly to another planet with Auto, then jump to a neighbouring system.
	var system := galaxy.get_system(ship.system_id)
	var other_planet := system.planets[0] if system.planets[0].id != ship.orbiting_planet_id else system.planets[-1]
	turn_manager.submit_order({"type": "move_to_planet", "planet_id": other_planet.id})
	turn_manager.set_auto_advance(true)
	await _wait_until(func() -> bool: return not turn_manager.auto_advance and not turn_manager.is_resolving, 40.0)

	var target := -1
	for other in galaxy.systems:
		var d := galaxy.distance_between(ship.system_id, other.id)
		if other.id != ship.system_id and d <= ship.jump_range and d <= ship.fuel:
			target = other.id
			break
	_check(target >= 0, "no reachable neighbour system")
	hud.call("_toggle_map")
	await _frames(3)
	hud.call("_toggle_map")
	_check(turn_manager.submit_order({"type": "jump", "system_id": target}), "jump order refused")
	var start_day: int = galaxy.day
	while galaxy.player_ship().system_id != target and galaxy.day < start_day + 60:
		turn_manager.set_auto_advance(true)
		await _wait_until(func() -> bool: return not turn_manager.auto_advance and not turn_manager.is_resolving, 30.0)
	_check(galaxy.player_ship().system_id == target, "never arrived in the target system")
	_check(galaxy.player_ship().cargo_amount("food") > 0, "cargo got lost on the way")

	# A raider shows up next to us. Select it, attack, and fight until one of us is done.
	var space_view: Node = main.get_node("Game").get_child(0)
	var system_here := galaxy.get_system(ship.system_id)
	for other in galaxy.ships_in_system(system_here.id):
		if other.is_pirate():
			galaxy.remove_ship(other.id) # Only our raider, so the test always plays the same way.
	system_here.pirate_limit = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pirate := NpcSpawner.spawn_pirate(galaxy, system_here, rng, false)
	for loadout: Dictionary in GameData.npcs()["pirates"]:
		if loadout["id"] == "raider":
			NpcSpawner.equip(pirate, loadout, pirate.race_id)
	pirate.hull_hp = 30.0 # Already battered: a short fight.
	pirate.add_cargo("food", 5)
	pirate.position = ship.position + Vector2(150, 0)
	space_view.call("_sync_ship_nodes")
	event_bus.selection_changed.emit("ship", pirate.id)
	await _frames(2)
	hud.call("_on_action_pressed")
	_check(ship.target_id == pirate.id, "attack order failed")
	var pirate_id := pirate.id
	var fight_start: int = galaxy.day
	while galaxy.get_ship(pirate_id) != null and galaxy.day < fight_start + 30 and ship.has_target():
		turn_manager.end_turn()
		await _wait_until(func() -> bool: return not turn_manager.is_resolving, 5.0)
	_check(galaxy.get_ship(pirate_id) == null, "the raider was not destroyed")
	await _frames(30) # Let the explosion play.

	# Fly to the wreck's cargo container and pick it up with the gripper.
	system_here = galaxy.get_system(ship.system_id)
	if not system_here.loot.is_empty():
		var container: LootData = system_here.loot[0]
		var cargo_before := ship.cargo_used()
		_check(turn_manager.submit_order({"type": "move_to_point", "point": container.position}), "flying to loot refused")
		turn_manager.set_auto_advance(true)
		await _wait_until(func() -> bool: return not turn_manager.auto_advance and not turn_manager.is_resolving, 30.0)
		_check(ship.cargo_used() > cargo_before, "gripper picked nothing up")

	# Click in space, save, load, and go back to the menu.
	main.get_node("Game").get_child(0).call("_on_left_click", Vector2(300, 300))
	turn_manager.end_turn()
	await _wait_until(func() -> bool: return not turn_manager.is_resolving, 5.0)
	_check(save_system.save_game("smoke_test"), "save failed")
	_check(save_system.load_game("smoke_test"), "load failed")
	DirAccess.remove_absolute(save_system.save_path("smoke_test"))
	await _frames(5)
	event_bus.return_to_menu_requested.emit()
	await _frames(5)

	print("Played to day %d." % galaxy.day)
	_finish()


func _finish() -> void:
	if _counter.errors.is_empty():
		print("Smoke test passed.")
		quit(0)
	else:
		for error in _counter.errors:
			printerr(error)
		printerr("Smoke test FAILED with %d problem(s)." % _counter.errors.size())
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_counter.errors.append("CHECK FAILED: " + message)


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _wait_until(condition: Callable, timeout_seconds: float) -> void:
	var waited := 0.0
	while not condition.call() and waited < timeout_seconds:
		await create_timer(0.05).timeout
		waited += 0.05
