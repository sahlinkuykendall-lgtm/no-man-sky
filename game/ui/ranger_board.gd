class_name RangerBoard
extends Control
## The Ranger Corps board (R key): the ranking of all rangers by points (earned by
## destroying pirates, see Law.pirate_destroyed), your reputation, and the latest galactic
## news. It only reads the simulation.

const SHOWN_RANGERS := 10
const SHOWN_NEWS := 10

var _ranking_label: RichTextLabel
var _news_label: RichTextLabel


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.02, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UiStyle.make_panel()
	panel.add_theme_stylebox_override("panel", UiStyle.panel_style(Color(0.03, 0.05, 0.11, 0.98)))
	panel.custom_minimum_size = Vector2(900, 0)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var title := UiStyle.make_label("RANGER CORPS BOARD", 22, UiStyle.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	column.add_child(row)
	_ranking_label = _rich_label()
	_ranking_label.custom_minimum_size = Vector2(390, 0)
	row.add_child(_ranking_label)
	_news_label = _rich_label()
	_news_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_news_label)
	column.add_child(UiStyle.make_button("Close (R)", close))

	EventBus.turn_ready.connect(_refresh)
	EventBus.galaxy_loaded.connect(close)


func _rich_label() -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("default_color", UiStyle.TEXT)
	return label


func open() -> void:
	visible = true
	_refresh()


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func _refresh() -> void:
	if not visible or not GameState.has_game():
		return
	var galaxy := GameState.galaxy
	_ranking_label.text = _ranking_text(galaxy, GameState.player_ship())
	_news_label.text = _news_text(galaxy)


static func _ranking_text(galaxy: GalaxyData, player: ShipData) -> String:
	var lines: Array[String] = ["[b]Ranking[/b]  [color=#9aa8c8](points from destroyed pirates)[/color]"]
	var ranking := galaxy.ranger_ranking()
	for i in ranking.size():
		var ranger := ranking[i]
		if i >= SHOWN_RANGERS and not ranger.is_player:
			continue
		var line := "%2d. %s  ·  %d pts  ·  %d kill%s" % [i + 1, "You" if ranger.is_player else ranger.name,
			ranger.points, ranger.kills, "" if ranger.kills == 1 else "s"]
		if ranger.is_player:
			line = "[color=#80ff99][b]%s[/b][/color]" % line
		lines.append(line)
	lines.append("")
	var reputation := Law.reputation(player.karma)
	lines.append("Your reputation: [b]%s[/b] (karma %d)" % [reputation, player.karma])
	if player.wanted.is_empty():
		lines.append("[color=#80ff99]No race wants you.[/color]")
	else:
		var parts: Array[String] = []
		for race_id: String in player.wanted:
			parts.append("%s %s" % [GameData.race(race_id).get("name", "?"), UiStyle.credits(int(player.wanted[race_id]))])
		lines.append("[color=#ff8a6b]Wanted by: %s[/color]" % ", ".join(parts))
		lines.append("[color=#9aa8c8]Hail one of their planets to pay. Fines fade slowly over time.[/color]")
	return "\n".join(lines)


static func _news_text(galaxy: GalaxyData) -> String:
	var lines: Array[String] = ["[b]Galactic news[/b]"]
	if galaxy.news.is_empty():
		lines.append("[color=#9aa8c8]All quiet so far.[/color]")
	for item in galaxy.news.slice(0, SHOWN_NEWS):
		lines.append("[color=#6f7c99]Day %d[/color]  %s" % [int(item["day"]), item["text"]])
	return "\n".join(lines)
