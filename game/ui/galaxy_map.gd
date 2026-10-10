class_name GalaxyMap
extends Control
## Full-screen galaxy map: every star system, who controls it, and your jump range.
## Click a system to see its details, then "Set Jump Course" to travel there.

const MARGIN := 40.0
const SIDE_PANEL_WIDTH := 300.0
const SYSTEM_DOT := 6.0
const COLOR_RANGE := Color(0.45, 1.0, 0.6, 0.12)
const COLOR_RANGE_EDGE := Color(0.45, 1.0, 0.6, 0.5)
const COLOR_FUEL_EDGE := Color(1.0, 0.75, 0.35, 0.6)

var _hovered: int = -1
var _selected: int = -1
var _info_label: RichTextLabel
var _jump_button: Button

# Galaxy -> screen transform, recalculated every draw.
var _origin := Vector2.ZERO
var _scale := 1.0
var _bounds_min := Vector2.ZERO


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var panel := UiStyle.make_panel()
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -SIDE_PANEL_WIDTH
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	column.add_child(UiStyle.make_label("GALAXY MAP", 22, UiStyle.ACCENT))
	_info_label = RichTextLabel.new()
	_info_label.bbcode_enabled = true
	_info_label.fit_content = true
	_info_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_info_label)
	_jump_button = UiStyle.make_button("Set Jump Course", _on_jump_pressed)
	column.add_child(_jump_button)
	column.add_child(UiStyle.make_button("Close  (M / Esc)", close))
	column.add_child(_legend())


func open() -> void:
	_selected = -1
	visible = true
	_refresh_info()
	queue_redraw()


func close() -> void:
	visible = false


func _legend() -> Control:
	var box := VBoxContainer.new()
	box.add_child(UiStyle.make_label("Races", 14, UiStyle.TEXT_DIM))
	for race: Dictionary in GameData.races():
		var label := UiStyle.make_label("●  " + race["name"], 14, Color(race["color"]))
		box.add_child(label)
	box.add_child(UiStyle.make_label("Green circle: jump range\nOrange circle: fuel limit", 13, UiStyle.TEXT_DIM))
	return box


# --- Drawing --------------------------------------------------------------------

func _update_transform() -> void:
	var galaxy := GameState.galaxy
	_bounds_min = Vector2(INF, INF)
	var bounds_max := Vector2(-INF, -INF)
	for system in galaxy.systems:
		_bounds_min = _bounds_min.min(system.galaxy_pos)
		bounds_max = bounds_max.max(system.galaxy_pos)
	var area := Vector2(size.x - SIDE_PANEL_WIDTH - MARGIN * 2.0, size.y - MARGIN * 2.0)
	var extent := (bounds_max - _bounds_min).max(Vector2.ONE)
	_scale = minf(area.x / extent.x, area.y / extent.y)
	_origin = Vector2(MARGIN, MARGIN) + (area - extent * _scale) * 0.5


func galaxy_to_screen(galaxy_position: Vector2) -> Vector2:
	return _origin + (galaxy_position - _bounds_min) * _scale


func _draw() -> void:
	if not GameState.has_game():
		return
	_update_transform()
	var galaxy := GameState.galaxy
	var ship := GameState.player_ship()
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.015, 0.04, 0.97))

	var here := galaxy.get_system(ship.system_id)
	var here_screen := galaxy_to_screen(here.galaxy_pos)
	if not ship.in_hyperspace:
		draw_circle(here_screen, ship.jump_range * _scale, COLOR_RANGE)
		draw_arc(here_screen, ship.jump_range * _scale, 0.0, TAU, 96, COLOR_RANGE_EDGE, 1.5)
		if ship.fuel < ship.jump_range:
			draw_arc(here_screen, ship.fuel * _scale, 0.0, TAU, 96, COLOR_FUEL_EDGE, 1.5)

	# Hyperspace trip in progress.
	if ship.in_hyperspace:
		var from := galaxy_to_screen(galaxy.get_system(ship.jump_origin_system_id).galaxy_pos)
		var to := galaxy_to_screen(galaxy.get_system(ship.jump_target_system_id).galaxy_pos)
		draw_line(from, to, Color(0.75, 0.5, 1.0), 2.0)
		var total := TurnResolver.jump_days(galaxy.distance_between(ship.jump_origin_system_id, ship.jump_target_system_id))
		var progress := 1.0 - float(ship.jump_days_left) / total
		draw_circle(from.lerp(to, progress), 5.0, UiStyle.ACCENT)

	# Planned jump course.
	if ship.jump_target_system_id >= 0 and not ship.in_hyperspace:
		draw_dashed_line(here_screen, galaxy_to_screen(galaxy.get_system(ship.jump_target_system_id).galaxy_pos), Color(0.75, 0.5, 1.0), 2.0, 8.0)

	if _selected >= 0 and _selected != ship.system_id:
		draw_line(here_screen, galaxy_to_screen(galaxy.get_system(_selected).galaxy_pos), Color(1, 1, 1, 0.35), 1.0)

	for system in galaxy.systems:
		var screen := galaxy_to_screen(system.galaxy_pos)
		var color := Color(GameData.race(system.race_id).get("color", "#ffffff"))
		var radius := SYSTEM_DOT * (1.5 if system.is_home else 1.0)
		draw_circle(screen, radius, color)
		if system.id == _hovered:
			draw_arc(screen, radius + 4.0, 0.0, TAU, 32, Color.WHITE, 1.5)
		if system.id == _selected:
			draw_arc(screen, radius + 7.0, 0.0, TAU, 32, UiStyle.WARNING, 2.0)
		if system.id == ship.system_id and not ship.in_hyperspace:
			draw_arc(screen, radius + 10.0, 0.0, TAU, 32, UiStyle.ACCENT, 2.0)
		var text_color := Color.WHITE if system.id == _hovered or system.id == _selected else UiStyle.TEXT_DIM
		draw_string(font, screen + Vector2(radius + 4.0, 4.0), system.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, text_color)


# --- Input ----------------------------------------------------------------------

func _system_at(screen_position: Vector2) -> int:
	var best := -1
	var best_distance := 14.0
	for system in GameState.galaxy.systems:
		var d := galaxy_to_screen(system.galaxy_pos).distance_to(screen_position)
		if d < best_distance:
			best_distance = d
			best = system.id
	return best


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hovered := _system_at(event.position)
		if hovered != _hovered:
			_hovered = hovered
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_selected = _system_at(event.position)
		_refresh_info()
		queue_redraw()
		accept_event()


func _refresh_info() -> void:
	var galaxy := GameState.galaxy
	var ship := GameState.player_ship()
	_jump_button.disabled = true
	if _selected < 0:
		_info_label.text = "[color=#9aa8c8]Click a star system to see details.\n\nYou can jump to systems inside the green circle if you have enough fuel.[/color]"
		return
	var system := galaxy.get_system(_selected)
	var race := GameData.race(system.race_id)
	var lines: Array[String] = []
	lines.append("[font_size=20][b]%s[/b][/font_size]" % system.name)
	lines.append("[color=%s]%s territory[/color]%s" % [race.get("color", "#fff"), race.get("name", "?"), " (capital)" if system.is_home else ""])
	lines.append("Star: %s" % GameData.star_type(system.star_type_id).get("name", "?"))
	lines.append("Planets: %d (%d inhabited)" % [system.planets.size(), system.inhabited_planets().size()])
	if _selected == ship.system_id:
		lines.append("\n[color=#73ccff]You are here.[/color]")
	elif ship.in_hyperspace:
		lines.append("\n[color=#ffbf59]You are in hyperspace.[/color]")
	else:
		var distance := galaxy.distance_between(ship.system_id, _selected)
		lines.append("\nDistance: %.1f pc" % distance)
		lines.append("Hyperspace: %d days" % TurnResolver.jump_days(distance))
		lines.append("Fuel needed: %.1f (you have %.1f)" % [distance * TurnResolver.FUEL_PER_PARSEC, ship.fuel])
		if distance > ship.jump_range:
			lines.append("[color=#ffbf59]Out of jump range (%.1f pc).[/color]" % ship.jump_range)
		elif distance * TurnResolver.FUEL_PER_PARSEC > ship.fuel:
			lines.append("[color=#ffbf59]Not enough fuel. Refuel at an inhabited planet.[/color]")
		else:
			_jump_button.disabled = false
	_info_label.text = "\n".join(lines)


func _on_jump_pressed() -> void:
	if _selected < 0:
		return
	if TurnManager.submit_order({"type": "jump", "system_id": _selected}):
		var target_name := GameState.galaxy.get_system(_selected).name
		EventBus.message_posted.emit("Course set: fly to the hyperspace boundary, then jump to %s." % target_name, "info")
		close()
