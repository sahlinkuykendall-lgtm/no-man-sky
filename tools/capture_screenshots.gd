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
	var game_state: Node = root.get_node("GameState")
	var turn_manager: Node = root.get_node("TurnManager")
	var galaxy: GalaxyData = game_state.galaxy
	var ship: ShipData = galaxy.player_ship()
	root.get_node("EventBus").selection_changed.emit("planet", ship.orbiting_planet_id)
	await _frames(20)
	await _shot("02_system_view")

	var hud: Node = main.get_node("Game").get_child(1)
	hud.call("_toggle_planet_screen")
	var planet_screen: Node = hud.get("_planet_screen")
	planet_screen.call("_submit", "buy", "minerals", 12)
	await _frames(5)
	await _shot("03_planet_market")
	ship.engine.condition = 42.0 # Show some wear so the Repair button has work to do.
	ship.hull_hp -= 15.0
	planet_screen.call("show_tab", "shipyard")
	await _frames(5)
	await _shot("03b_shipyard")
	planet_screen.call("show_tab", "market")
	hud.call("_toggle_planet_screen")

	var system := galaxy.get_system(ship.system_id)
	var target := system.planets[-1] if system.planets[-1].id != ship.orbiting_planet_id else system.planets[0]
	root.get_node("EventBus").selection_changed.emit("planet", target.id)
	turn_manager.submit_order({"type": "move_to_planet", "planet_id": target.id})
	await _frames(5)
	await _shot("04_course_set")

	for i in 3:
		turn_manager.end_turn()
		await create_timer(1.1).timeout
	await _shot("05_after_three_turns")
	root.get_node("EventBus").selection_changed.emit("", -1)
	await _frames(5)
	await _shot("05b_your_ship")

	hud.call("_toggle_map")
	await _frames(5)
	await _shot("06_galaxy_map")
	hud.call("_toggle_map")

	# Combat: a pirate shows up next to us. Zoom in, look at it, attack it.
	var space_view: Node = main.get_node("Game").get_child(0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var pirate := NpcSpawner.spawn_pirate(galaxy, galaxy.get_system(ship.system_id), rng, false)
	for loadout: Dictionary in GameData.npcs()["pirates"]:
		if loadout["id"] == "marauder":
			NpcSpawner.equip(pirate, loadout, pirate.race_id)
	pirate.hull_hp = 45.0
	pirate.position = ship.position + Vector2(260, -90)
	pirate.heading = PI
	space_view.call("_sync_ship_nodes")
	space_view.call("_apply_animation", 1.0)
	(space_view.get("_camera") as Camera3D).size = 32.0
	space_view.call("_center_on_player")
	root.get_node("EventBus").selection_changed.emit("ship", pirate.id)
	await _frames(5)
	await _shot("08_pirate_info")
	hud.call("_on_action_pressed")
	for i in 2:
		turn_manager.end_turn()
		await create_timer(0.5).timeout
		space_view.call("_center_on_player")
		await _shot("09_combat_%d" % i)
		await create_timer(0.7).timeout
	pirate.hull_hp = 4.0
	turn_manager.end_turn()
	await create_timer(0.85).timeout
	await _shot("10_explosion")
	await create_timer(0.6).timeout
	var loot_system := galaxy.get_system(ship.system_id)
	if not loot_system.loot.is_empty():
		root.get_node("EventBus").selection_changed.emit("loot", loot_system.loot[0].id)
	await _frames(5)
	await _shot("11_loot")

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
	await _shot("07_hyperspace")
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
