extends SceneTree
## Plays the real game headlessly for a while (menu -> new game -> fly -> jump -> save/load
## -> back to menu) and fails if any script error or warning was logged.
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
	var hud: Node = main.get_node("Game").get_child(1)
	hud.call("_toggle_map")
	await _frames(3)
	hud.call("_toggle_map")
	_check(turn_manager.submit_order({"type": "jump", "system_id": target}), "jump order refused")
	var start_day: int = galaxy.day
	while galaxy.player_ship().system_id != target and galaxy.day < start_day + 60:
		turn_manager.set_auto_advance(true)
		await _wait_until(func() -> bool: return not turn_manager.auto_advance and not turn_manager.is_resolving, 30.0)
	_check(galaxy.player_ship().system_id == target, "never arrived in the target system")

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
