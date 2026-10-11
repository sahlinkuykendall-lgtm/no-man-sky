class_name HailWindow
extends Control
## The window for talking to another ship or a planet ("hailing", see Comms in
## game/sim/comms.gd). Shows who you are talking to, their last answer and one button per
## thing you can say. Opened with "Hail (H)" for the selected ship or planet. No time passes
## while it is open.
##
## Like every view, it only reads the simulation: each button sends a "hail" order through
## TurnManager.submit_order(), and the answer comes back as a Comms.EVENT_HAIL event.

var _target_kind: String = ""
var _target_id: int = -1
var _title_label: RichTextLabel
var _info_label: RichTextLabel
var _reply_label: RichTextLabel
var _options_box: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

	# Darkens the space view and blocks clicks to it while the window is open.
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.02, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UiStyle.make_panel()
	panel.add_theme_stylebox_override("panel", UiStyle.panel_style(Color(0.03, 0.05, 0.11, 0.97)))
	panel.custom_minimum_size = Vector2(480, 0)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	_title_label = _rich_label()
	column.add_child(_title_label)
	_info_label = _rich_label()
	column.add_child(_info_label)
	column.add_child(HSeparator.new())
	_reply_label = _rich_label()
	_reply_label.custom_minimum_size = Vector2(450, 60)
	column.add_child(_reply_label)
	column.add_child(HSeparator.new())
	_options_box = VBoxContainer.new()
	_options_box.add_theme_constant_override("separation", 6)
	column.add_child(_options_box)
	column.add_child(UiStyle.make_button("Close (Esc)", close))

	EventBus.order_events.connect(_on_order_events)
	EventBus.message_posted.connect(_on_message_posted)
	EventBus.galaxy_loaded.connect(close)


func _rich_label() -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("default_color", UiStyle.TEXT)
	return label


# --- Opening and closing ------------------------------------------------------

## Opens a channel to a ship or planet (Comms.TARGET_SHIP or Comms.TARGET_PLANET).
func open(target_kind: String, target_id: int) -> void:
	_target_kind = target_kind
	_target_id = target_id
	visible = true
	_reply_label.text = "[color=#9aa8c8]Channel open. What do you want to say?[/color]"
	_refresh()


func close() -> void:
	visible = false
	_target_kind = ""
	_target_id = -1


func is_open() -> bool:
	return visible


# --- Updating -------------------------------------------------------------------

func _refresh() -> void:
	if not visible or not GameState.has_game():
		return
	var galaxy := GameState.galaxy
	var ship := GameState.player_ship()
	for child in _options_box.get_children():
		child.queue_free()
	if not _target_here(galaxy, ship):
		_title_label.text = "[font_size=20][b]Channel closed[/b][/font_size]"
		_info_label.text = ""
		_reply_label.text = "[color=#9aa8c8]Nobody is answering any more.[/color]"
		return
	_title_label.text = "[font_size=20][b]Hailing %s[/b][/font_size]" % _target_name(galaxy, ship)
	_info_label.text = _target_info(galaxy, ship)
	for option in Comms.options(galaxy, ship, _target_kind, _target_id):
		var label: String = Comms.OPTION_NAMES.get(option, option.capitalize())
		if option == "bribe":
			label += " (%s)" % UiStyle.credits(Comms.bribe_cost(ship))
		elif option == "pay_fine":
			var race_id := galaxy.get_system(ship.system_id).get_planet(_target_id).race_id
			label += " (%s)" % UiStyle.credits(int(ship.wanted.get(race_id, 0)))
		var button := UiStyle.make_button(label, _send.bind(option))
		button.tooltip_text = _option_hint(option)
		_options_box.add_child(button)


## True while the ship or planet we are talking to is still in the player's system.
func _target_here(galaxy: GalaxyData, ship: ShipData) -> bool:
	if ship.in_hyperspace:
		return false
	if _target_kind == Comms.TARGET_PLANET:
		return galaxy.get_system(ship.system_id).get_planet(_target_id) != null
	var other := galaxy.get_ship(_target_id)
	return other != null and not other.in_hyperspace and other.system_id == ship.system_id


func _target_name(galaxy: GalaxyData, ship: ShipData) -> String:
	if _target_kind == Comms.TARGET_PLANET:
		return galaxy.get_system(ship.system_id).get_planet(_target_id).name
	return galaxy.get_ship(_target_id).name


## "Skarn police · greedy, cowardly" and similar.
func _target_info(galaxy: GalaxyData, ship: ShipData) -> String:
	var race_id := ""
	var role := "planet"
	if _target_kind == Comms.TARGET_PLANET:
		race_id = galaxy.get_system(ship.system_id).get_planet(_target_id).race_id
	else:
		var other := galaxy.get_ship(_target_id)
		race_id = other.race_id
		role = "pirate (renegade)" if other.is_pirate() else other.role
	var race := GameData.race(race_id)
	var text := "[color=%s]%s[/color] %s" % [race.get("color", "#fff"), race.get("name", ""), role]
	var personality: Dictionary = race.get("personality", {})
	var traits: Array[String] = []
	if float(personality.get("greed", 0.5)) >= 0.7:
		traits.append("greedy")
	if float(personality.get("courage", 0.5)) >= 0.7:
		traits.append("brave")
	elif float(personality.get("courage", 0.5)) <= 0.35:
		traits.append("timid")
	if float(personality.get("helpful", 0.5)) >= 0.7:
		traits.append("helpful")
	if not traits.is_empty():
		text += "  ·  [color=#9aa8c8]%s are known to be %s[/color]" % [race.get("name", ""), ", ".join(traits)]
	if Law.is_wanted_by(ship, race_id):
		text += "\n[color=#ff8a6b]The %s want you: fine %s.[/color]" % [race.get("name", ""), UiStyle.credits(int(ship.wanted[race_id]))]
	return text


static func _option_hint(option: String) -> String:
	match option:
		"news":
			return "Ask for a tip about prices or pirates."
		"help":
			return "Ask them to join your attack on the pirate you are targeting."
		"demand":
			return "Force them to drop half their cargo. This is a crime (extortion)!"
		"bribe":
			return "Pay them to leave you alone for a few days."
		"threaten":
			return "Tell them to back off. Works if your ship is clearly stronger."
		"surrender":
			return "Hand over half your cargo so they let you go."
		"pay_fine":
			return "Pay what you owe so their planets deal with you again."
	return ""


func _send(option: String) -> void:
	if TurnManager.is_resolving:
		return
	TurnManager.submit_order({"type": "hail", "target_kind": _target_kind, "target_id": _target_id, "option": option})


func _on_order_events(events: Array[Dictionary]) -> void:
	if not visible:
		return
	for event in events:
		if event["type"] == Comms.EVENT_HAIL and event["target_kind"] == _target_kind and event["target_id"] == _target_id:
			var color := "#80ff99" if event["accepted"] else "#ffbf59"
			_reply_label.text = "[color=%s]\"%s\"[/color]" % [color, event["reply"]]
	_refresh()


## Hails that can't be made (out of range, no money...) come back as warning messages.
func _on_message_posted(text: String, level: String) -> void:
	if visible and level == "warning":
		_reply_label.text = "[color=#ff8a6b]%s[/color]" % text
		_refresh()

