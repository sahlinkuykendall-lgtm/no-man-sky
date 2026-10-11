class_name Hud
extends CanvasLayer
## The in-space interface: status bar (with your reputation and the latest news), info
## panel, message log, turn buttons, galaxy map, planet (trade) screen, hail window,
## Ranger Corps board and pause menu.
##
## Keys: Space = End Turn, Shift+Space = Auto (fly until arrival), M = galaxy map,
## L = land on the planet you orbit (trade), T = attack / cease fire on the selected
## ship or asteroid, H = hail the selected ship or planet, R = Ranger Corps board,
## Esc = menu, F = center camera on ship.

const MAX_LOG_LINES := 6
## Galactic news about market events reaches you from systems this close (parsecs).
const NEWS_RANGE := 40.0

var _root: Control
var _status_label: RichTextLabel
var _news_label: RichTextLabel ## Second status line: reputation, wanted, latest headline.
var _info_label: RichTextLabel
var _action_button: Button ## "Attack", "Cease fire" or "Shoot" for the selected thing.
var _action_order: Dictionary = {} ## The order the action button sends.
var _hail_button: Button
var _log_label: RichTextLabel
var _log_lines: Array[String] = []
var _end_turn_button: Button
var _auto_button: Button
var _land_button: Button
var _hyperspace_label: Label
var _galaxy_map: GalaxyMap
var _planet_screen: PlanetScreen
var _hail_window: HailWindow
var _ranger_board: RangerBoard
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
	_planet_screen = PlanetScreen.new()
	_root.add_child(_planet_screen)
	_hail_window = HailWindow.new()
	_root.add_child(_hail_window)
	_ranger_board = RangerBoard.new()
	_root.add_child(_ranger_board)
	_build_pause_menu()

	EventBus.galaxy_loaded.connect(_on_galaxy_loaded)
	EventBus.turn_resolved.connect(_on_turn_resolved)
	EventBus.turn_ready.connect(_refresh)
	EventBus.player_order_changed.connect(_refresh)
	EventBus.selection_changed.connect(_on_selection_changed)
	EventBus.message_posted.connect(_add_message)
	EventBus.order_events.connect(_on_order_events)
	_on_galaxy_loaded()


# --- Layout -----------------------------------------------------------------

func _build_status_bar() -> void:
	var panel := UiStyle.make_panel()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = 10
	panel.offset_right = -10
	panel.offset_top = 8
	_root.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	panel.add_child(column)
	_status_label = _rich_label()
	column.add_child(_status_label)
	_news_label = _rich_label()
	_news_label.add_theme_font_size_override("normal_font_size", 13)
	_news_label.add_theme_font_size_override("bold_font_size", 13)
	column.add_child(_news_label)


func _build_info_panel() -> void:
	var panel := UiStyle.make_panel()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -300
	panel.offset_right = -10
	panel.offset_top = 84
	panel.custom_minimum_size = Vector2(290, 0)
	_root.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	_info_label = _rich_label()
	column.add_child(_info_label)
	_action_button = UiStyle.make_button("", _on_action_pressed)
	_action_button.visible = false
	column.add_child(_action_button)
	_hail_button = UiStyle.make_button("Hail (H)", _open_hail_window)
	_hail_button.tooltip_text = "Talk to this ship or planet: ask for news or help, bargain or threaten"
	_hail_button.visible = false
	column.add_child(_hail_button)


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
	box.offset_left = -720
	box.offset_right = -10
	box.offset_top = -56
	box.offset_bottom = -10
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 8)
	_root.add_child(box)
	_land_button = UiStyle.make_button("Land (L)", _toggle_planet_screen, 110)
	_land_button.tooltip_text = "Land on the planet you are orbiting to trade and refuel"
	box.add_child(_land_button)
	box.add_child(UiStyle.make_button("Galaxy Map (M)", _toggle_map, 130))
	var board_button := UiStyle.make_button("Rangers (R)", _toggle_ranger_board, 110)
	board_button.tooltip_text = "The Ranger Corps ranking, your reputation and the galactic news"
	box.add_child(board_button)
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
	var ship := GameState.player_ship()
	# Warnings first, then the fighting, then everything else.
	for event in events:
		if event["type"] == Combat.EVENT_UNDER_ATTACK and event["ship_id"] == ship.id:
			_report_event(event)
	_report_shots(events)
	for event in events:
		match event["type"]:
			Economy.EVENT_MARKET_EVENT:
				_report_news(event)
			Combat.EVENT_SHOT, Combat.EVENT_UNDER_ATTACK:
				pass # Already reported above.
			Combat.EVENT_SHIP_DESTROYED:
				if event["killer_id"] == ship.id:
					_report_event(event)
				elif _was_targeting(events, ship, event["ship_id"]):
					_add_message("%s was destroyed by %s." % [event["name"], event.get("killer_name", "someone")], "good")
			_:
				if event.get("ship_id") == ship.id:
					_report_event(event)
	_refresh()


## One line per turn for the damage you dealt and one for the damage you took.
func _report_shots(events: Array[Dictionary]) -> void:
	var galaxy := GameState.galaxy
	var ship := GameState.player_ship()
	var names := {} ## ship id -> name (destroyed ships are already gone from the galaxy)
	for event in events:
		if event["type"] == Combat.EVENT_SHIP_DESTROYED:
			names[event["ship_id"]] = event["name"]
	var dealt := {} ## target name -> damage
	var taken := {} ## attacker name -> damage
	var blocked_by_them := 0 ## Damage their shields stopped.
	var blocked_by_you := 0 ## Damage your shield stopped.
	for event in events:
		if event["type"] != Combat.EVENT_SHOT:
			continue
		if event["ship_id"] == ship.id:
			var target_name := "an asteroid"
			if event["target_kind"] == Combat.TARGET_SHIP:
				target_name = _ship_name(galaxy, event["target_id"], names)
			dealt[target_name] = int(dealt.get(target_name, 0)) + int(event["damage"])
			blocked_by_them += int(event.get("blocked", 0))
		elif event["target_kind"] == Combat.TARGET_SHIP and event["target_id"] == ship.id:
			var attacker_name := _ship_name(galaxy, event["ship_id"], names)
			taken[attacker_name] = int(taken.get(attacker_name, 0)) + int(event["damage"])
			blocked_by_you += int(event.get("blocked", 0))
	var parts: Array[String] = []
	for target_name: String in dealt:
		parts.append("%s for %d" % [target_name, dealt[target_name]])
	if not parts.is_empty():
		var their_shields := " (their shields stopped %d)" % blocked_by_them if blocked_by_them > 0 else ""
		_add_message("You hit %s%s." % [", ".join(parts), their_shields], "info")
	parts.clear()
	for attacker_name: String in taken:
		parts.append("%s hit you for %d" % [attacker_name, taken[attacker_name]])
	if not parts.is_empty():
		var your_shield := " Your shield stopped %d." % blocked_by_you if blocked_by_you > 0 else ""
		_add_message("%s.%s Hull %d / %d." % [", ".join(parts), your_shield, roundi(ship.hull_hp), roundi(ship.hull_hp_max)], "warning")


## True if the player shot at that ship this turn (so they want to know who finished it).
static func _was_targeting(events: Array[Dictionary], ship: ShipData, target_id: int) -> bool:
	for event in events:
		if event["type"] == Combat.EVENT_SHOT and event["ship_id"] == ship.id \
				and event["target_kind"] == Combat.TARGET_SHIP and event["target_id"] == target_id:
			return true
	return false


static func _ship_name(galaxy: GalaxyData, ship_id: int, names: Dictionary) -> String:
	var other := galaxy.get_ship(ship_id)
	if other != null:
		return other.name
	return names.get(ship_id, "someone")


func _on_order_events(events: Array[Dictionary]) -> void:
	for event in events:
		_report_event(event)
	_refresh()


## Writes a log message about something that happened to the player's ship.
func _report_event(event: Dictionary) -> void:
	var galaxy := GameState.galaxy
	var system := GameState.current_system()
	match event["type"]:
		TurnResolver.EVENT_ARRIVED_PLANET:
			var planet := system.get_planet(event["planet_id"])
			if planet.inhabited:
				_add_message("Arrived at %s. Press L to land and trade." % planet.name, "good")
			else:
				_add_message("Arrived at %s." % planet.name, "good")
			_selection_kind = "planet"
			_selection_id = planet.id
			EventBus.selection_changed.emit("planet", planet.id)
		TurnResolver.EVENT_ARRIVED_POINT:
			_add_message("Arrived at destination.", "info")
		TurnResolver.EVENT_ENTERED_HYPERSPACE:
			_add_message("Entered hyperspace. %d day(s) to %s." % [event["days"], galaxy.get_system(event["system_id"]).name], "info")
		TurnResolver.EVENT_ARRIVED_SYSTEM:
			_add_message("Arrived in the %s system." % galaxy.get_system(event["system_id"]).name, "good")
		TurnResolver.EVENT_JUMP_FAILED:
			_add_message("Jump failed: not enough fuel or out of range.", "warning")
		Trade.EVENT_TRADED:
			var good_name: String = GameData.good(event["good_id"]).get("name", "?")
			var quantity: int = event["quantity"]
			var where := " on the black market" if event["black_market"] else ""
			if quantity > 0:
				_add_message("Bought %d %s for %s%s." % [quantity, good_name, UiStyle.credits(event["credits"]), where], "info")
			else:
				_add_message("Sold %d %s for %s%s." % [-quantity, good_name, UiStyle.credits(-int(event["credits"])), where], "good")
		Trade.EVENT_BUSTED:
			var busted_good: String = GameData.good(event["good_id"]).get("name", "?")
			var text := "BUSTED! Your black-market %s deal was a police sting. Fined %s." % [busted_good, UiStyle.credits(event["fine"])]
			if event["quantity"] < 0:
				text += " %d %s confiscated." % [-int(event["quantity"]), busted_good]
			_add_message(text, "warning")
		Trade.EVENT_SCANNED:
			var confiscated: Dictionary = event["confiscated"]
			if confiscated.is_empty():
				_add_message("Police scanned your cargo. All clear.", "info")
			else:
				var parts: Array[String] = []
				for good_id: String in confiscated:
					parts.append("%d %s" % [confiscated[good_id], GameData.good(good_id).get("name", "?")])
				_add_message("Police found contraband! Confiscated %s and fined %s." % [", ".join(parts), UiStyle.credits(event["fine"])], "warning")
		Trade.EVENT_REFUELED:
			var text := "Bought %.1f fuel for %s." % [event["amount"], UiStyle.credits(event["credits"])]
			if event["free_amount"] > 0.0:
				text += " The Ranger Corps added %.1f emergency fuel for free." % event["free_amount"]
			_add_message(text, "good")
		Shipyard.EVENT_BOUGHT_ITEM:
			var item := ItemData.make(event["type_id"], event["race_id"])
			var text := "Bought a %s for %s" % [item.display_name(), UiStyle.credits(event["price"])]
			if event["trade_in"] > 0:
				text += " (your old one traded in for %s)" % UiStyle.credits(event["trade_in"])
			_add_message(text + ".", "good")
		Shipyard.EVENT_REPAIRED:
			var text := "Ship repaired for %s." % UiStyle.credits(event["credits"])
			if event["free"]:
				text += " The Ranger Corps patched up your worn gear for free."
			_add_message(text, "good")
		Shipyard.EVENT_SOLD_ITEM:
			var sold := ItemData.make(event["type_id"], event["race_id"])
			_add_message("Sold your %s for %s." % [sold.display_name(), UiStyle.credits(event["credits"])], "good")
		Combat.EVENT_UNDER_ATTACK:
			var attacker := galaxy.get_ship(event["attacker_id"])
			var attacker_name := attacker.name if attacker != null else "A pirate"
			var advice := "Fight back (select it, T), hail it (H) or flee to an inhabited planet."
			if attacker != null and attacker.role == ShipData.ROLE_POLICE:
				advice = "The police are after you! Flee, fight back, or hail them (H) and offer a bribe."
			_add_message("%s is coming for you! %s" % [attacker_name, advice], "warning")
		Combat.EVENT_SHIP_DESTROYED:
			var text := "You destroyed %s!" % event["name"]
			if event["bounty"] > 0:
				text += " The Ranger Corps pays a bounty of %s." % UiStyle.credits(event["bounty"])
			_add_message(text + " Its wreck left a cargo container.", "good")
		Law.EVENT_CRIME:
			_add_message(_crime_text(event), "warning")
		Law.EVENT_FINE_PAID:
			_add_message("You paid your fine of %s. The %s will deal with you again." % [
				UiStyle.credits(event["credits"]), GameData.race(event["race_id"]).get("name", "?")], "good")
		Comms.EVENT_HAIL:
			var reply := str(event["reply"]).replace("\n", " / ")
			_add_message("%s: \"%s\"" % [_hail_target_name(galaxy, event), reply], "good" if event["accepted"] else "info")
		Combat.EVENT_ASTEROID_DESTROYED:
			_add_message("The asteroid broke up into %d minerals. Fly close to pick them up." % event["minerals"], "good")
		Combat.EVENT_COLLECTED:
			var parts: Array[String] = []
			for good_id: String in event["cargo"]:
				parts.append("%d %s" % [event["cargo"][good_id], GameData.good(good_id).get("name", "?")])
			var text := "Your gripper picked up %s." % ", ".join(parts)
			if event["left_behind"]:
				text += " Your hold is full, so some cargo was left behind."
			_add_message(text, "good")
		Combat.EVENT_RESCUED:
			var rescue_system := galaxy.get_system(event["rescue_system_id"])
			var text := "Your ship was destroyed! The Ranger Corps towed the wreck to %s and charged %s." % [
				rescue_system.get_planet(event["planet_id"]).name, UiStyle.credits(event["fee"])]
			if event["lost_cargo"] > 0:
				text += " Your cargo (%d t) was left in a container where you were hit." % event["lost_cargo"]
			_add_message(text + " Repair your hull at the shipyard.", "warning")
		Shipyard.EVENT_EQUIPMENT_WORN:
			_add_message("Your %s is worn out and losing power. Repair it at a shipyard." % str(Equipment.KIND_NAMES[event["kind"]]).to_lower(), "warning")


## "You attacked the peaceful X. That's a crime! The Skarn fine you 250 cr." and similar.
static func _crime_text(event: Dictionary) -> String:
	var verbs := {Law.CRIME_ASSAULT: "You attacked", Law.CRIME_MURDER: "You destroyed", Law.CRIME_EXTORTION: "You robbed"}
	var text := "%s the peaceful %s. That's a crime!" % [verbs.get(event["crime"], "You attacked"), event["victim_name"]]
	if event["fine"] > 0:
		var race_name: String = GameData.race(event["race_id"]).get("name", "?")
		text += " The %s fine you %s" % [race_name, UiStyle.credits(event["fine"])]
		if event["newly_wanted"]:
			text += ". You are WANTED: their police will hunt you and their planets won't deal with you until you pay"
		text += "."
	else:
		text += " Nobody enforces the law here, but your reputation suffers."
	return text


static func _hail_target_name(galaxy: GalaxyData, event: Dictionary) -> String:
	if event["target_kind"] == Comms.TARGET_PLANET:
		var planet := galaxy.get_system(galaxy.player_ship().system_id).get_planet(event["target_id"])
		return planet.name if planet != null else "The planet"
	var other := galaxy.get_ship(event["target_id"])
	return other.name if other != null else "The ship"


## Galactic news about a market event, if it happened close enough to matter.
func _report_news(event: Dictionary) -> void:
	var galaxy := GameState.galaxy
	var ship := GameState.player_ship()
	var here := ship.jump_origin_system_id if ship.in_hyperspace else ship.system_id
	if galaxy.distance_between(here, event["system_id"]) > NEWS_RANGE:
		return
	var system := galaxy.get_system(event["system_id"])
	var planet := system.get_planet(event["planet_id"])
	var news: String = GameData.market_event(event["event_id"]).get("news", "Something happened on %s.")
	_add_message("NEWS: " + news % ("%s (%s system)" % [planet.name, system.name]), "info")


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
	_land_button.disabled = Trade.market_planet(galaxy, ship) == null or TurnManager.is_resolving
	_status_label.text = _status_text(galaxy, ship)
	_news_label.text = _news_line(galaxy, ship)
	_info_label.text = _info_text(galaxy, ship)
	_update_action_button(galaxy, ship)
	_hail_button.visible = not _hail_target().is_empty()
	_hail_button.disabled = TurnManager.is_resolving
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
	var hull_color := "#ff6b5b" if ship.hull_hp < ship.hull_hp_max * 0.35 else "#e0e8ff"
	return "[b]Day %d[/b]    %s    [color=#80ff99]%s[/color]    Hull [color=%s]%d/%d[/color]    Cargo %d/%d    Fuel [color=%s]%.1f/%.0f[/color]    %s" % [
		galaxy.day, location, UiStyle.credits(ship.credits), hull_color, roundi(ship.hull_hp), roundi(ship.hull_hp_max),
		ship.cargo_used(), ship.cargo_capacity, fuel_color, ship.fuel, ship.fuel_max, _course_text(galaxy, ship)]


## Your Ranger rank and reputation, any fines you owe, and the latest headline.
func _news_line(galaxy: GalaxyData, ship: ShipData) -> String:
	var rank := galaxy.ranger_ranking().find(ship) + 1
	var text := "Ranger rank #%d    Reputation [b]%s[/b]" % [rank, Law.reputation(ship.karma)]
	if not ship.wanted.is_empty():
		var here := "" if ship.in_hyperspace else galaxy.get_system(ship.system_id).race_id
		var color := "#ff6b5b" if ship.wanted.has(here) else "#ffbf59"
		text += "    [color=%s]WANTED (fines %s)[/color]" % [color, UiStyle.credits(ship.total_fines())]
	if not galaxy.news.is_empty():
		var latest: Dictionary = galaxy.news[0]
		text += "    [color=#9aa8c8]NEWS, day %d: %s[/color]" % [int(latest["day"]), latest["text"]]
	return text


func _course_text(galaxy: GalaxyData, ship: ShipData) -> String:
	if ship.in_hyperspace:
		return "[color=#c9a6ff]Jumping to %s[/color]" % galaxy.get_system(ship.jump_target_system_id).name
	var system := galaxy.get_system(ship.system_id)
	if ship.pursue and Combat.target_exists(galaxy, ship):
		return "[color=#ff8a6b]Attacking %s[/color]" % _target_name(galaxy, ship)
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
			if other and Equipment.on_radar(ship, other):
				return _ship_text(galaxy, ship, other)
		"asteroid":
			var asteroid := system.get_asteroid(_selection_id)
			if asteroid and asteroid.exists():
				return _asteroid_text(ship, asteroid)
		"loot":
			var container := system.get_loot(_selection_id)
			if container:
				return _loot_text(ship, container)
		"star":
			var star_type := GameData.star_type(system.star_type_id)
			return "[font_size=18][b]%s[/b][/font_size]\n%s\nPlanets: %d" % [system.name, star_type.get("name", ""), system.planets.size()]
	return "[font_size=18][b]Your ship[/b][/font_size]\n%s\nSpeed %.0f/day · Jump %.0f pc (%.0f pc/day)\n%s\n\n[color=#9aa8c8]Click a planet to fly to it. Land (L) to trade, buy gear and repair.\nClick a pirate (red) or an asteroid, then Attack (T).\nClick a ship or planet, then Hail (H) to talk.\nGalaxy Map (M) to jump to another system.[/color]" % [
		_equipment_text(ship), ship.speed, ship.jump_range, ship.jump_speed, _cargo_text(ship)]


## Hull and equipment with their condition (orange when worn out).
func _equipment_text(ship: ShipData) -> String:
	if ship.hull == null:
		return ""
	var lines: Array[String] = ["%s  (hull %d / %d)" % [ship.hull.display_name(), roundi(ship.hull_hp), roundi(ship.hull_hp_max)]]
	var items: Array[ItemData] = ship.equipment()
	for item in items:
		var color := "#e0e8ff" if item.condition >= Equipment.WORN_CONDITION else "#ffbf59"
		var line := "%s  [color=%s]%d%%[/color]" % [item.stats().get("name", "?"), color, floori(item.condition)]
		if item.max_ammo() > 0:
			line += "  (%d/%d missiles)" % [item.ammo, item.max_ammo()]
		lines.append(line)
	if ship.weapons.is_empty():
		lines.append("[color=#ffbf59]No weapons[/color]")
	return "\n".join(lines)


## Info about another ship: who they are, how damaged, how dangerous.
func _ship_text(galaxy: GalaxyData, ship: ShipData, other: ShipData) -> String:
	var race := GameData.race(other.race_id)
	var lines: Array[String] = ["[font_size=18][b]%s[/b][/font_size]" % other.name]
	if other.is_pirate():
		lines.append("[color=#ff6b5b]Pirate[/color] ([color=%s]%s[/color] renegade)" % [race.get("color", "#fff"), race.get("name", "")])
	else:
		lines.append("[color=%s]%s[/color] %s" % [race.get("color", "#fff"), race.get("name", ""), other.role.capitalize()])
	if other.hull != null:
		lines.append("%s  ·  Hull %d / %d" % [other.hull.stats().get("name", "?"), roundi(other.hull_hp), roundi(other.hull_hp_max)])
	if other.shield != null:
		lines.append("%s (stops %d%% of damage)" % [other.shield.stats().get("name", "?"), roundi(Equipment.shield_absorb(other) * 100.0)])
	if other.role == ShipData.ROLE_RANGER:
		lines.append("Ranger rank #%d  ·  %d pts  ·  %d kills" % [galaxy.ranger_ranking().find(other) + 1, other.points, other.kills])
	var weapon_names: Array[String] = []
	for weapon in other.weapons:
		weapon_names.append(str(weapon.stats().get("name", "?")))
	lines.append("Weapons: %s" % (", ".join(weapon_names) if not weapon_names.is_empty() else "none"))
	if other.bounty > 0:
		lines.append("Bounty: [color=#80ff99]%s[/color]" % UiStyle.credits(other.bounty))
	lines.append(_distance_text(ship, other.position))
	if other.target_kind == Combat.TARGET_SHIP and other.target_id == ship.id:
		lines.append("[color=#ff6b5b]It is attacking you![/color]")
	elif other.target_kind == Combat.TARGET_SHIP and Combat.target_exists(galaxy, other):
		lines.append("[color=#ffbf59]Fighting %s[/color]" % galaxy.get_ship(other.target_id).name)
	if other.has_truce_with(ship.id):
		lines.append("[color=#80ff99]Leaving you alone for %d more days[/color]" % int(other.truce[ship.id]))
	if Combat.is_protected(galaxy, other):
		lines.append("[color=#9aa8c8]Protected by the defenses of the planet it orbits.[/color]")
	elif not other.is_pirate():
		lines.append("[color=#9aa8c8]A peaceful ship. Attacking it is a crime: a fine, worse karma and the police on your tail.[/color]")
	return "\n".join(lines)


func _asteroid_text(ship: ShipData, asteroid: AsteroidData) -> String:
	return "[font_size=18][b]Asteroid[/b][/font_size]\nRock %d / %d\nBreaks into about %d minerals\n%s\n[color=#9aa8c8]Shoot it, then pick up the minerals with your gripper.[/color]" % [
		roundi(asteroid.hp), roundi(asteroid.hp_max), asteroid.minerals, _distance_text(ship, asteroid.position())]


func _loot_text(ship: ShipData, container: LootData) -> String:
	var lines: Array[String] = ["[font_size=18][b]Cargo container[/b][/font_size]"]
	for good_id: String in container.cargo:
		lines.append("  %d %s" % [container.cargo[good_id], GameData.good(good_id).get("name", "?")])
	lines.append("Drifts away in %d day%s" % [container.days_left, "" if container.days_left == 1 else "s"])
	lines.append("Distance %.0f" % ship.position.distance_to(container.position))
	lines.append("[color=#9aa8c8]Fly within %.0f to pick it up with your gripper.[/color]" % Equipment.gripper_range(ship))
	return "\n".join(lines)


## "Distance 230 (in range)" for the player's weapons.
func _distance_text(ship: ShipData, at: Vector2) -> String:
	var distance := ship.position.distance_to(at)
	var weapon_range := Equipment.max_weapon_range(ship)
	if weapon_range <= 0.0:
		return "Distance %.0f" % distance
	if distance <= weapon_range:
		return "Distance %.0f [color=#80ff99](in weapon range)[/color]" % distance
	return "Distance %.0f [color=#9aa8c8](weapon range %.0f)[/color]" % [distance, weapon_range]


func _target_name(galaxy: GalaxyData, ship: ShipData) -> String:
	if ship.target_kind == Combat.TARGET_SHIP:
		return galaxy.get_ship(ship.target_id).name
	return "an asteroid"


## Shows Attack / Shoot / Cease fire for the selected ship or asteroid.
func _update_action_button(galaxy: GalaxyData, ship: ShipData) -> void:
	_action_order = {}
	var kind := ""
	if not ship.in_hyperspace:
		if _selection_kind == "ship":
			var other := galaxy.get_ship(_selection_id)
			if other != null and other != ship and Equipment.on_radar(ship, other):
				kind = Combat.TARGET_SHIP
		elif _selection_kind == "asteroid":
			var asteroid := galaxy.get_system(ship.system_id).get_asteroid(_selection_id)
			if asteroid != null and asteroid.exists():
				kind = Combat.TARGET_ASTEROID
	if kind != "" and ship.target_kind == kind and ship.target_id == _selection_id:
		_action_order = {"type": "cease_fire"}
		_action_button.text = "Cease fire (T)"
	elif kind != "":
		_action_order = {"type": "attack", "target_kind": kind, "target_id": _selection_id}
		_action_button.text = "Shoot asteroid (T)"
		if kind == Combat.TARGET_SHIP:
			var peaceful := not galaxy.get_ship(_selection_id).is_pirate()
			_action_button.text = "Attack: a crime! (T)" if peaceful else "Attack (T)"
	_action_button.visible = not _action_order.is_empty()
	_action_button.disabled = TurnManager.is_resolving


func _on_action_pressed() -> void:
	if _action_order.is_empty() or TurnManager.is_resolving:
		return
	var order := _action_order
	if TurnManager.submit_order(order) and order["type"] == "attack":
		var ship := GameState.player_ship()
		_add_message("Attacking %s. Your ship chases it and fires when in range. Press End Turn." % _target_name(GameState.galaxy, ship), "info")


func _cargo_text(ship: ShipData) -> String:
	var lines: Array[String] = ["Cargo: %d / %d" % [ship.cargo_used(), ship.cargo_capacity]]
	for good: Dictionary in GameData.goods():
		var amount := ship.cargo_amount(good["id"])
		if amount > 0:
			lines.append("  %d %s" % [amount, good["name"]])
	return "\n".join(lines)


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
		lines.append(_market_summary(planet))
		var ship := GameState.player_ship()
		if ship.orbiting_planet_id == planet.id and not ship.in_hyperspace:
			lines.append("\n[color=#80ff99]In orbit. Press L to land and trade.[/color]")
		else:
			lines.append("\n[color=#9aa8c8]Fly here to land and trade.[/color]")
	else:
		lines.append("[color=#9aa8c8]Uninhabited. Exploring the surface arrives in Milestone 8.[/color]")
	return "\n".join(lines)


## Market hints for the info panel: what is cheap, what pays well, what is illegal.
func _market_summary(planet: PlanetData) -> String:
	var goods: Array = GameData.goods().duplicate()
	goods.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return Economy.price_ratio(planet, a["id"]) < Economy.price_ratio(planet, b["id"]))
	var cheap: Array[String] = []
	var dear: Array[String] = []
	var illegal: Array[String] = []
	for good: Dictionary in goods:
		var ratio := Economy.price_ratio(planet, good["id"])
		if ratio < 0.85 and cheap.size() < 3:
			cheap.append(good["name"])
		if Economy.is_illegal(planet, good["id"]):
			illegal.append(good["name"])
	goods.reverse()
	for good: Dictionary in goods:
		if Economy.price_ratio(planet, good["id"]) > 1.15 and dear.size() < 3:
			dear.append(good["name"])
	var lines: Array[String] = [""]
	if planet.event_id != "":
		lines.append("[color=#ffbf59]%s! (%d days left)[/color]" % [GameData.market_event(planet.event_id).get("name", ""), planet.event_days_left])
	lines.append("[color=#80ff99]Cheap here:[/color] %s" % (", ".join(cheap) if not cheap.is_empty() else "nothing special"))
	lines.append("[color=#ffbf59]Pays well:[/color] %s" % (", ".join(dear) if not dear.is_empty() else "nothing special"))
	if not illegal.is_empty():
		lines.append("[color=#ff8a6b]Illegal:[/color] %s" % ", ".join(illegal))
	return "\n".join(lines)


# --- Input --------------------------------------------------------------------

func _toggle_map() -> void:
	if _planet_screen.is_open() or _hail_window.is_open() or _ranger_board.is_open():
		return
	if _galaxy_map.visible:
		_galaxy_map.close()
	else:
		_pause_menu.visible = false
		_galaxy_map.open()


## The {"kind", "id"} the Hail button talks to: the selected ship (on radar) or
## inhabited planet. Empty if there's nobody to hail.
func _hail_target() -> Dictionary:
	if not GameState.has_game():
		return {}
	var galaxy := GameState.galaxy
	var ship := GameState.player_ship()
	if ship.in_hyperspace:
		return {}
	if _selection_kind == "ship":
		var other := galaxy.get_ship(_selection_id)
		if other != null and other != ship and Equipment.on_radar(ship, other):
			return {"kind": Comms.TARGET_SHIP, "id": _selection_id}
	elif _selection_kind == "planet":
		var planet := galaxy.get_system(ship.system_id).get_planet(_selection_id)
		if planet != null and planet.inhabited:
			return {"kind": Comms.TARGET_PLANET, "id": _selection_id}
	return {}


func _open_hail_window() -> void:
	if _any_window_open() or TurnManager.is_resolving:
		return
	var target := _hail_target()
	if target.is_empty():
		_add_message("Select a ship on your radar or an inhabited planet first, then hail it (H).", "warning")
		return
	TurnManager.set_auto_advance(false)
	_hail_window.open(target["kind"], target["id"])


func _toggle_ranger_board() -> void:
	if _ranger_board.is_open():
		_ranger_board.close()
	elif not _any_window_open():
		_ranger_board.open()


## True while a full-screen window (map, planet, hail, board or menu) is open.
func _any_window_open() -> bool:
	return _galaxy_map.visible or _pause_menu.visible or _planet_screen.is_open() \
			or _hail_window.is_open() or _ranger_board.is_open()


func _toggle_planet_screen() -> void:
	if _planet_screen.is_open():
		_planet_screen.close()
		return
	if _any_window_open() or TurnManager.is_resolving:
		return
	var planet := Trade.market_planet(GameState.galaxy, GameState.player_ship())
	if planet == null:
		_add_message("Fly to an inhabited planet first, then land to trade.", "warning")
		return
	TurnManager.set_auto_advance(false)
	_planet_screen.open(planet)


func _toggle_auto() -> void:
	TurnManager.set_auto_advance(not TurnManager.auto_advance)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	match key.keycode:
		KEY_SPACE:
			if _any_window_open():
				return
			if key.shift_pressed:
				_toggle_auto()
			else:
				TurnManager.end_turn()
			get_viewport().set_input_as_handled()
		KEY_M:
			_toggle_map()
			get_viewport().set_input_as_handled()
		KEY_L:
			_toggle_planet_screen()
			get_viewport().set_input_as_handled()
		KEY_T:
			if not _any_window_open():
				_on_action_pressed()
			get_viewport().set_input_as_handled()
		KEY_H:
			_open_hail_window()
			get_viewport().set_input_as_handled()
		KEY_R:
			_toggle_ranger_board()
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if _planet_screen.is_open():
				_planet_screen.close()
			elif _hail_window.is_open():
				_hail_window.close()
			elif _ranger_board.is_open():
				_ranger_board.close()
			elif _galaxy_map.visible:
				_galaxy_map.close()
			else:
				_pause_menu.visible = not _pause_menu.visible
			get_viewport().set_input_as_handled()
