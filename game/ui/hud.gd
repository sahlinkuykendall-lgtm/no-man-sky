class_name Hud
extends CanvasLayer
## The in-space interface: status bar, info panel, message log, turn buttons,
## galaxy map and pause menu.
##
## Keys: Space = End Turn, Shift+Space = Auto (fly until arrival), M = galaxy map,
## Esc = menu, F = center camera on ship.

const MAX_LOG_LINES := 8

var _root: Control
var _status_label: RichTextLabel
var _info_label: RichTextLabel
var _log_label: RichTextLabel
var _log_lines: Array[String] = []
var _end_turn_button: Button
var _auto_button: Button
var _hyperspace_label: Label
var _galaxy_map: GalaxyMap
var _pause_menu: PanelContainer

var _selection_kind: String = ""
var _selection_id: int = -1


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE # Let clicks through to space.
	add_child(_root)
	_build_status_bar()
	_build_info_panel()
	_build_log()
	_build_turn_buttons()
	_build_hyperspace_label()
	_galaxy_map = GalaxyMap.new()
	_root.add_child(_galaxy_map)
	_build_pause_menu()

	EventBus.galaxy_loaded.connect(_on_galaxy_loaded)
	EventBus.turn_resolved.connect(_on_turn_resolved)
	EventBus.turn_ready.connect(_refresh)
	EventBus.player_order_changed.connect(_refresh)
	EventBus.selection_changed.connect(_on_selection_changed)
	EventBus.message_posted.connect(_add_message)
	_on_galaxy_loaded()


# --- Layout -----------------------------------------------------------------

func _build_status_bar() -> void:
	var panel := UiStyle.make_panel()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = 10
	panel.offset_right = -10
	panel.offset_top = 8
	_root.add_child(panel)
	_status_label = _rich_label()
	panel.add_child(_status_label)


func _build_info_panel() -> void:
	var panel := UiStyle.make_panel()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -300
	panel.offset_right = -10
	panel.offset_top = 64
	panel.custom_minimum_size = Vector2(290, 0)
	_root.add_child(panel)
	_info_label = _rich_label()
	panel.add_child(_info_label)


func _build_log() -> void:
	var panel := UiStyle.make_panel()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 10
	panel.offset_right = 520
	panel.offset_bottom = -10
	panel.offset_top = -150
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.add_theme_stylebox_override("panel", UiStyle.panel_style(Color(0.02, 0.03, 0.08, 0.6)))
	_root.add_child(panel)
	_log_label = _rich_label()
	_log_label.scroll_following = true
	panel.add_child(_log_label)


func _build_turn_buttons() -> void:
	var box := HBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	box.offset_left = -470
	box.offset_right = -10
	box.offset_top = -56
	box.offset_bottom = -10
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 8)
	_root.add_child(box)
	box.add_child(UiStyle.make_button("Galaxy Map (M)", _toggle_map, 130))
	_auto_button = UiStyle.make_button("Auto ▶▶", _toggle_auto, 100)
	_auto_button.toggle_mode = true
	_auto_button.tooltip_text = "Keep ending turns until you arrive (Shift+Space)"
	box.add_child(_auto_button)
	_end_turn_button = UiStyle.make_button("End Turn ▶  (Space)", TurnManager.end_turn, 180)
	box.add_child(_end_turn_button)


func _build_hyperspace_label() -> void:
	_hyperspace_label = UiStyle.make_label("", 28, Color(0.85, 0.7, 1.0))
	_hyperspace_label.set_anchors_preset(Control.PRESET_CENTER)
	_hyperspace_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hyperspace_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hyperspace_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_hyperspace_label.visible = false
	_root.add_child(_hyperspace_label)


func _build_pause_menu() -> void:
	_pause_menu = UiStyle.make_panel()
	_pause_menu.set_anchors_preset(Control.PRESET_CENTER)
	_pause_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pause_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	_pause_menu.custom_minimum_size = Vector2(260, 0)
	_pause_menu.visible = false
	_root.add_child(_pause_menu)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_pause_menu.add_child(column)
	var title := UiStyle.make_label("MENU", 22, UiStyle.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	column.add_child(UiStyle.make_button("Resume", _close_pause_menu))
	column.add_child(UiStyle.make_button("Save Game", _on_save_pressed))
	column.add_child(UiStyle.make_button("Load Game", _on_load_pressed))
	column.add_child(UiStyle.make_button("Main Menu", EventBus.return_to_menu_requested.emit))
	column.add_child(UiStyle.make_button("Quit to Desktop", func() -> void: get_tree().quit()))


func _close_pause_menu() -> void:
	_pause_menu.visible = false


func _on_save_pressed() -> void:
	SaveSystem.save_game()
	_close_pause_menu()


func _on_load_pressed() -> void:
	_close_pause_menu()
	if not SaveSystem.load_game():
		_add_message("No saved game found.", "warning")


func _rich_label() -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("default_color", UiStyle.TEXT)
	return label


# --- Updating ---------------------------------------------------------------

func _on_galaxy_loaded() -> void:
	_selection_kind = ""
	_selection_id = -1
	if GameState.has_game():
		var system := GameState.current_system()
		_add_message("Day %d. You are in the %s system. Click a planet to fly there, then press End Turn." % [GameState.galaxy.day, system.name], "info")
	_refresh()


func _on_turn_resolved(_day: int, events: Array[Dictionary]) -> void:
	var galaxy := GameState.galaxy
	var ship := GameState.player_ship()
	for event in events:
		if event.get("ship_id") != ship.id:
			continue
		match event["type"]:
			TurnResolver.EVENT_ARRIVED_PLANET:
				var planet := GameState.current_system().get_planet(event["planet_id"])
				_add_message("Arrived at %s." % planet.name, "good")
				_selection_kind = "planet"
				_selection_id = planet.id
				EventBus.selection_changed.emit("planet", planet.id)
			TurnResolver.EVENT_ARRIVED_POINT:
				_add_message("Arrived at destination.", "info")
			TurnResolver.EVENT_REFUELED:
				_add_message("Refueled.", "good")
			TurnResolver.EVENT_ENTERED_HYPERSPACE:
				_add_message("Entered hyperspace. %d day(s) to %s." % [event["days"], galaxy.get_system(event["system_id"]).name], "info")
			TurnResolver.EVENT_ARRIVED_SYSTEM:
				_add_message("Arrived in the %s system." % galaxy.get_system(event["system_id"]).name, "good")
			TurnResolver.EVENT_JUMP_FAILED:
				_add_message("Jump failed: not enough fuel or out of range.", "warning")
	_refresh()


func _on_selection_changed(kind: String, id: int) -> void:
	_selection_kind = kind
	_selection_id = id
	_refresh()


func _add_message(text: String, level: String = "info") -> void:
	var day := GameState.galaxy.day if GameState.has_game() else 0
	_log_lines.append("[color=#6f7c99]Day %d[/color]  [color=%s]%s[/color]" % [day, UiStyle.level_color(level).to_html(false), text])
	while _log_lines.size() > MAX_LOG_LINES:
		_log_lines.pop_front()
	_log_label.text = "\n".join(_log_lines)


func _refresh() -> void:
	if not GameState.has_game():
		return
	var galaxy := GameState.galaxy
	var ship := GameState.player_ship()
	_end_turn_button.disabled = TurnManager.is_resolving
	_auto_button.set_pressed_no_signal(TurnManager.auto_advance)
	_status_label.text = _status_text(galaxy, ship)
	_info_label.text = _info_text(galaxy, ship)
	_hyperspace_label.visible = ship.in_hyperspace
	if ship.in_hyperspace:
		_hyperspace_label.text = "IN HYPERSPACE\n→ %s\n%d day(s) remaining" % [galaxy.get_system(ship.jump_target_system_id).name, ship.jump_days_left]
	if _galaxy_map.visible:
		_galaxy_map.queue_redraw()


func _status_text(galaxy: GalaxyData, ship: ShipData) -> String:
	var location := "Hyperspace"
	if not ship.in_hyperspace:
		var system := galaxy.get_system(ship.system_id)
		var race := GameData.race(system.race_id)
		location = "%s system  [color=%s](%s)[/color]" % [system.name, race.get("color", "#fff"), race.get("name", "")]
	var fuel_color := "#ffbf59" if ship.fuel < ship.fuel_max * 0.3 else "#e0e8ff"
	return "[b]Day %d[/b]     %s     Fuel [color=%s]%.1f / %.0f[/color]     Jump range %.0f pc     %s" % [
		galaxy.day, location, fuel_color, ship.fuel, ship.fuel_max, ship.jump_range, _course_text(galaxy, ship)]


func _course_text(galaxy: GalaxyData, ship: ShipData) -> String:
	if ship.in_hyperspace:
		return "[color=#c9a6ff]Jumping to %s[/color]" % galaxy.get_system(ship.jump_target_system_id).name
	var system := galaxy.get_system(ship.system_id)
	if ship.orbiting_planet_id >= 0:
		return "[color=#80ff99]In orbit of %s[/color]" % system.get_planet(ship.orbiting_planet_id).name
	if not ship.has_destination:
		return "[color=#9aa8c8]Drifting[/color]"
	var days := TurnResolver.days_to_destination(galaxy, ship)
	if ship.target_planet_id >= 0:
		return "Flying to %s (%d day%s)" % [system.get_planet(ship.target_planet_id).name, days, "" if days == 1 else "s"]
	if ship.jump_target_system_id >= 0:
		return "[color=#c9a6ff]Heading to jump to %s (%d day%s to boundary)[/color]" % [galaxy.get_system(ship.jump_target_system_id).name, days, "" if days == 1 else "s"]
	return "Flying (%d day%s)" % [days, "" if days == 1 else "s"]


func _info_text(galaxy: GalaxyData, ship: ShipData) -> String:
	if ship.in_hyperspace:
		return "[b]Hyperspace[/b]\n[color=#9aa8c8]Nothing to see out here... yet.\nRift Runs arrive in a later milestone.[/color]"
	var system := galaxy.get_system(ship.system_id)
	match _selection_kind:
		"planet":
			var planet := system.get_planet(_selection_id)
			if planet:
				return _planet_text(planet)
		"ship":
			var other := galaxy.get_ship(_selection_id)
			if other and not other.in_hyperspace and other.system_id == ship.system_id:
				var race := GameData.race(other.race_id)
				return "[font_size=18][b]%s[/b][/font_size]\n[color=%s]%s[/color] %s\n\n[color=#9aa8c8]Hailing, trading and combat arrive in later milestones.[/color]" % [
					other.name, race.get("color", "#fff"), race.get("name", ""), other.role.capitalize()]
		"star":
			var star_type := GameData.star_type(system.star_type_id)
			return "[font_size=18][b]%s[/b][/font_size]\n%s\nPlanets: %d" % [system.name, star_type.get("name", ""), system.planets.size()]
	return "[font_size=18][b]Your ship[/b][/font_size]\nSpeed: %.0f per day\nFuel: %.1f / %.0f\nJump range: %.0f pc\n\n[color=#9aa8c8]Click a planet to fly to it.\nOpen the Galaxy Map (M) to jump to another system.[/color]" % [
		ship.speed, ship.fuel, ship.fuel_max, ship.jump_range]


func _planet_text(planet: PlanetData) -> String:
	var planet_type := GameData.planet_type(planet.type_id)
	var lines: Array[String] = []
	lines.append("[font_size=18][b]%s[/b][/font_size]" % planet.name)
	lines.append("%s world" % planet_type.get("name", "?"))
	if planet.inhabited:
		var race := GameData.race(planet.race_id)
		lines.append("[color=%s]%s[/color]  ·  Population %s million" % [race.get("color", "#fff"), race.get("name", ""), planet.population])
		lines.append("Economy: %s" % GameData.economy(planet.economy_id).get("name", "?"))
		lines.append("Government: %s" % GameData.government(planet.government_id).get("name", "?"))
		lines.append("Tech level: %d" % planet.tech_level)
		lines.append("\n[color=#9aa8c8]Trading arrives in Milestone 2.\nLanding in first person arrives in Milestone 8.[/color]")
	else:
		lines.append("[color=#9aa8c8]Uninhabited. Exploring the surface arrives in Milestone 8.[/color]")
	return "\n".join(lines)


# --- Input --------------------------------------------------------------------

func _toggle_map() -> void:
	if _galaxy_map.visible:
		_galaxy_map.close()
	else:
		_pause_menu.visible = false
		_galaxy_map.open()


func _toggle_auto() -> void:
	TurnManager.set_auto_advance(not TurnManager.auto_advance)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	match key.keycode:
		KEY_SPACE:
			if _galaxy_map.visible or _pause_menu.visible:
				return
			if key.shift_pressed:
				_toggle_auto()
			else:
				TurnManager.end_turn()
			get_viewport().set_input_as_handled()
		KEY_M:
			_toggle_map()
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if _galaxy_map.visible:
				_galaxy_map.close()
			else:
				_pause_menu.visible = not _pause_menu.visible
			get_viewport().set_input_as_handled()
