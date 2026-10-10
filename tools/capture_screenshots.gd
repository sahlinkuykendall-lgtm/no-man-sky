extends SceneTree
## Plays through a few screens and saves screenshots, so changes can be reviewed visually
## (useful for AI assistants without a screen).
##
## Usage (Linux, needs a display or xvfb-run):
##   xvfb-run -s "-screen 0 1280x720x24" godot --rendering-method gl_compatibility \
##       -s res://tools/capture_screenshots.gd -- <output folder>

var _out_dir := "user://screenshots"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await _frames(10)
	await _shot("01_main_menu")

	main.call("_on_new_game", 4242, "human")
	await _frames(20)
	await _shot("02_system_view")

	var game_state: Node = root.get_node("GameState")
	var turn_manager: Node = root.get_node("TurnManager")
	var galaxy: GalaxyData = game_state.galaxy
	var ship: ShipData = galaxy.player_ship()
	var system := galaxy.get_system(ship.system_id)
	var target := system.planets[-1] if system.planets[-1].id != ship.orbiting_planet_id else system.planets[0]
	root.get_node("EventBus").selection_changed.emit("planet", target.id)
	turn_manager.submit_order({"type": "move_to_planet", "planet_id": target.id})
	await _frames(5)
	await _shot("03_course_set")

	for i in 3:
		turn_manager.end_turn()
		await create_timer(1.1).timeout
	await _shot("04_after_three_turns")

	var hud: Node = main.get_node("Game").get_child(1)
	hud.call("_toggle_map")
	await _frames(5)
	await _shot("05_galaxy_map")
	hud.call("_toggle_map")

	var neighbour := -1
	for other in galaxy.systems:
		var d := galaxy.distance_between(ship.system_id, other.id)
		if other.id != ship.system_id and d <= ship.jump_range and d <= ship.fuel:
			neighbour = other.id
			break
	turn_manager.submit_order({"type": "jump", "system_id": neighbour})
	while not ship.in_hyperspace and galaxy.day < 80:
		turn_manager.end_turn()
		await create_timer(0.95).timeout
	await _frames(10)
	await _shot("06_hyperspace")
	quit(0)


func _shot(shot_name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	var path := _out_dir.path_join(shot_name + ".png")
	image.save_png(path)
	print("Saved ", path)


func _frames(count: int) -> void:
	for i in count:
		await process_frame
