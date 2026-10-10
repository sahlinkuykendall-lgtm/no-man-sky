class_name PlanetScreen
extends Control
## The screen you see after landing on an inhabited planet. Two tabs: the Market (buy and
## sell goods) and the Shipyard (ShipyardPanel: hulls, equipment, repairs). Fuel is sold at
## the bottom of both. Opened with "Land (L)" while in orbit. No time passes while it is open.
##
## Like every view, it only reads the simulation. Trades are sent as orders through
## TurnManager.submit_order(), exactly as a multiplayer client would send them.

const BUTTON_WIDTH := 70.0

var _planet: PlanetData = null
var _title_label: RichTextLabel
var _status_label: RichTextLabel
var _refuel_button: Button
var _market_tab_button: Button
var _shipyard_tab_button: Button
var _market_box: VBoxContainer
var _shipyard: ShipyardPanel
## good id -> {"name": Label, "buy": Label, "sell": Label, "stock": Label, "hold": Label,
##             "buy_one": Button, "buy_max": Button, "sell_one": Button, "sell_all": Button}
var _rows: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

	# Darkens the space view and blocks clicks to it while the screen is open.
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

	_title_label = _rich_label()
	column.add_child(_title_label)
	column.add_child(_build_tabs())
	column.add_child(HSeparator.new())

	_market_box = VBoxContainer.new()
	_market_box.add_theme_constant_override("separation", 10)
	column.add_child(_market_box)
	_market_box.add_child(_build_market_grid())
	var hint := UiStyle.make_label("Prices move as you trade and recover over the next days. Buy where goods are cheap (green) and sell where they pay well (green).\nGoods marked BLACK MARKET are illegal here: pricier, every deal risks a fine, and police may scan ships that arrive.", 13, UiStyle.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_market_box.add_child(hint)

	_shipyard = ShipyardPanel.new()
	_shipyard.visible = false
	column.add_child(_shipyard)
	column.add_child(HSeparator.new())

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	column.add_child(footer)
	_status_label = _rich_label()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_status_label)
	_refuel_button = UiStyle.make_button("Refuel", _on_refuel, 170)
	footer.add_child(_refuel_button)
	footer.add_child(UiStyle.make_button("Take off (Esc)", close, 140))

	EventBus.player_order_changed.connect(_refresh)
	EventBus.galaxy_loaded.connect(close)


func _build_tabs() -> HBoxContainer:
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	_market_tab_button = UiStyle.make_button("Market", show_tab.bind("market"), 140)
	_shipyard_tab_button = UiStyle.make_button("Shipyard", show_tab.bind("shipyard"), 140)
	for button: Button in [_market_tab_button, _shipyard_tab_button]:
		button.toggle_mode = true
		button.button_group = group
		tabs.add_child(button)
	_market_tab_button.button_pressed = true
	return tabs


## Switches between the "market" and "shipyard" tabs.
func show_tab(tab: String) -> void:
	_market_box.visible = tab == "market"
	_shipyard.visible = tab == "shipyard"
	_market_tab_button.set_pressed_no_signal(tab == "market")
	_shipyard_tab_button.set_pressed_no_signal(tab == "shipyard")
	_refresh()


func current_tab() -> String:
	return "shipyard" if _shipyard.visible else "market"


func _build_market_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 10
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	for header: String in ["Goods", "Typical", "Buy at", "Sell at", "Market", "In hold", "", "", "", ""]:
		grid.add_child(UiStyle.make_label(header, 14, UiStyle.TEXT_DIM))
	for good: Dictionary in GameData.goods():
		var good_id: String = good["id"]
		var row := {}
		var name_label := _cell(grid, good["name"])
		name_label.custom_minimum_size = Vector2(220, 0)
		row["name"] = name_label
		_cell(grid, str(int(good["base_price"]))).add_theme_color_override("font_color", UiStyle.TEXT_DIM)
		for key: String in ["buy", "sell", "stock", "hold"]:
			row[key] = _cell(grid, "")
		row["buy_one"] = _trade_button(grid, "Buy 1", "buy", good_id, 1)
		row["buy_max"] = _trade_button(grid, "Buy Max", "buy", good_id, 9999)
		row["sell_one"] = _trade_button(grid, "Sell 1", "sell", good_id, 1)
		row["sell_all"] = _trade_button(grid, "Sell All", "sell", good_id, 9999)
		_rows[good_id] = row
	return grid


func _cell(grid: GridContainer, text: String) -> Label:
	var label := UiStyle.make_label(text, 15)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grid.add_child(label)
	return label


func _trade_button(grid: GridContainer, text: String, order_type: String, good_id: String, quantity: int) -> Button:
	var button := UiStyle.make_button(text, _submit.bind(order_type, good_id, quantity), BUTTON_WIDTH)
	button.custom_minimum_size.y = 28
	grid.add_child(button)
	return button


func _rich_label() -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.add_theme_color_override("default_color", UiStyle.TEXT)
	return label


# --- Opening and closing ------------------------------------------------------

func open(planet: PlanetData) -> void:
	_planet = planet
	visible = true
	_shipyard.show_planet(planet)
	_refresh()


func close() -> void:
	visible = false
	_planet = null


func is_open() -> bool:
	return visible


# --- Actions -------------------------------------------------------------------

func _submit(order_type: String, good_id: String, quantity: int) -> void:
	TurnManager.submit_order({"type": order_type, "good_id": good_id, "quantity": quantity})


func _on_refuel() -> void:
	TurnManager.submit_order({"type": "refuel"})


# --- Updating ------------------------------------------------------------------

func _refresh() -> void:
	if not visible or not GameState.has_game():
		return
	var ship := GameState.player_ship()
	# Close if the ship is no longer parked at this planet.
	if _planet == null or Trade.market_planet(GameState.galaxy, ship) != _planet:
		close()
		return
	_title_label.text = _title_text()
	if _market_box.visible:
		for good: Dictionary in GameData.goods():
			_refresh_row(ship, good)
	else:
		_shipyard.refresh()

	_status_label.text = "Credits [b][color=#80ff99]%s[/color][/b]     Cargo %d / %d     Fuel %.1f / %.0f" % [
		UiStyle.credits(ship.credits), ship.cargo_used(), ship.cargo_capacity, ship.fuel, ship.fuel_max]
	var price := Economy.fuel_price(_planet)
	var full_cost := ceili((ship.fuel_max - ship.fuel) * price - 0.0001)
	_refuel_button.disabled = ship.fuel_max - ship.fuel < 0.05
	_refuel_button.text = "Tank full" if _refuel_button.disabled else "Refuel (%s)" % UiStyle.credits(full_cost)
	_refuel_button.tooltip_text = "Fuel costs %d cr per unit here. 1 unit = 1 parsec of jumping." % price


func _refresh_row(ship: ShipData, good: Dictionary) -> void:
	var good_id: String = good["id"]
	var row: Dictionary = _rows[good_id]
	var base := float(good["base_price"])
	var stock := Economy.stock_of(_planet, good_id)
	var buy := Economy.buy_price_at(_planet, good, stock)
	var sell := Economy.sell_price_at(_planet, good, stock)
	var illegal := Economy.is_illegal(_planet, good_id)
	var held := ship.cargo_amount(good_id)

	var name_label: Label = row["name"]
	name_label.text = good["name"] + ("  (BLACK MARKET)" if illegal else "")
	name_label.add_theme_color_override("font_color", UiStyle.WARNING if illegal else UiStyle.TEXT)
	_set_price(row["buy"], buy, buy > 0 and buy < base * 0.85, buy > base * 1.25)
	_set_price(row["sell"], sell, sell > base * 1.15, sell < base * 0.75)
	(row["stock"] as Label).text = str(stock)
	(row["hold"] as Label).text = str(held) if held > 0 else "-"

	var can_buy := stock > 0 and ship.cargo_free() > 0 and ship.credits >= buy
	(row["buy_one"] as Button).disabled = not can_buy
	(row["buy_max"] as Button).disabled = not can_buy
	(row["sell_one"] as Button).disabled = held == 0
	(row["sell_all"] as Button).disabled = held == 0


## Green = a good deal, orange = a bad one.
func _set_price(label: Label, price: int, good_deal: bool, bad_deal: bool) -> void:
	label.text = str(price) if price > 0 else "sold out"
	var color := UiStyle.TEXT
	if good_deal:
		color = UiStyle.GOOD
	elif bad_deal:
		color = UiStyle.WARNING
	label.add_theme_color_override("font_color", color)


func _title_text() -> String:
	var race := GameData.race(_planet.race_id)
	var text := "[font_size=24][b]%s[/b][/font_size]   [color=%s]%s[/color]  ·  %s  ·  %s  ·  Tech level %d" % [
		_planet.name, race.get("color", "#fff"), race.get("name", ""),
		GameData.economy(_planet.economy_id).get("name", "?"),
		GameData.government(_planet.government_id).get("name", "?"), _planet.tech_level]
	if _planet.event_id != "":
		var event := GameData.market_event(_planet.event_id)
		text += "\n[color=#ffbf59]%s! (%d more day%s)[/color]" % [event.get("name", ""), _planet.event_days_left, "" if _planet.event_days_left == 1 else "s"]
	return text
