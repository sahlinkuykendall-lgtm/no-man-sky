class_name ShipyardPanel
extends VBoxContainer
## The Shipyard tab of the planet screen: your ship's hull and equipment (with a Repair
## button), your weapons (with Sell buttons) and the hulls, equipment and weapons this
## planet sells.
##
## Like every view it only reads the simulation; purchases and repairs are sent as orders
## through TurnManager.submit_order().

const SHOP_HEIGHT := 250.0

var _planet: PlanetData = null
var _ship_label: RichTextLabel
var _repair_button: Button
var _weapons_box: VBoxContainer ## One row per installed weapon, with a Sell button.
var _shop_grid: GridContainer


func _ready() -> void:
	add_theme_constant_override("separation", 8)

	var ship_row := HBoxContainer.new()
	ship_row.add_theme_constant_override("separation", 12)
	add_child(ship_row)
	_ship_label = RichTextLabel.new()
	_ship_label.bbcode_enabled = true
	_ship_label.fit_content = true
	_ship_label.scroll_active = false
	_ship_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ship_label.add_theme_color_override("default_color", UiStyle.TEXT)
	ship_row.add_child(_ship_label)
	_repair_button = UiStyle.make_button("Repair", _on_repair, 190)
	_repair_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ship_row.add_child(_repair_button)
	_weapons_box = VBoxContainer.new()
	_weapons_box.add_theme_constant_override("separation", 2)
	add_child(_weapons_box)

	add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, SHOP_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_shop_grid = GridContainer.new()
	_shop_grid.columns = 6
	_shop_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shop_grid.add_theme_constant_override("h_separation", 14)
	_shop_grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(_shop_grid)

	var hint := UiStyle.make_label("Your old item is traded in when you buy a new one (weapons go into a free weapon slot instead). Heavier gear leaves less room for cargo. Gear wears out as you fly, jump and shoot; below 50% it loses power, so repair it here (this also reloads missiles). Veyari gear is light and lasts but costs more, Skarn gear is cheap but wears fast, Gorruk hulls are tough but heavy.", 13, UiStyle.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)


func show_planet(planet: PlanetData) -> void:
	_planet = planet
	refresh()


func refresh() -> void:
	if _planet == null or not GameState.has_game():
		return
	var ship := GameState.player_ship()
	_ship_label.text = _ship_text(ship)
	_rebuild_weapons(ship)
	var cost := Equipment.total_repair_cost(ship)
	_repair_button.disabled = cost <= 0
	_repair_button.text = "Nothing to repair" if cost <= 0 else "Repair all (%s)" % UiStyle.credits(cost)
	_rebuild_shop(ship)


func _ship_text(ship: ShipData) -> String:
	var lines: Array[String] = ["[b]Your ship[/b]   Cargo space %d t   Hull %d / %d" % [ship.cargo_capacity, roundi(ship.hull_hp), roundi(ship.hull_hp_max)]]
	for kind: String in Equipment.KINDS:
		var item := ship.slot(kind) # Weapons have no single slot; they are listed below.
		if item == null:
			continue
		var line := "%s: [b]%s[/b]   %s" % [Equipment.KIND_NAMES[kind], item.display_name(), Equipment.describe(item)]
		if kind != "hull":
			line += "   " + _condition_text(item.condition)
		lines.append(line)
	lines.append("Weapon slots: %d / %d used" % [ship.weapons.size(), Equipment.weapon_slots(ship.hull)])
	return "\n".join(lines)


## A row per weapon: what it is, its condition, and a button to sell it.
func _rebuild_weapons(ship: ShipData) -> void:
	for child in _weapons_box.get_children():
		_weapons_box.remove_child(child)
		child.queue_free()
	for i in ship.weapons.size():
		var weapon := ship.weapons[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_weapons_box.add_child(row)
		var label := RichTextLabel.new()
		label.bbcode_enabled = true
		label.fit_content = true
		label.scroll_active = false
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_color_override("default_color", UiStyle.TEXT)
		label.text = "Weapon %d: [b]%s[/b]   %s   %s" % [i + 1, weapon.display_name(), Equipment.describe(weapon), _condition_text(weapon.condition)]
		row.add_child(label)
		var value := Equipment.trade_in_value(weapon, weapon.condition)
		var button := UiStyle.make_button("Sell (+%s)" % UiStyle.credits(value), _on_sell_weapon.bind(i), 150)
		button.custom_minimum_size.y = 26
		row.add_child(button)


## Green when fine, orange when worn (losing power).
static func _condition_text(condition: float) -> String:
	var color := "#80ff99" if condition >= Equipment.WORN_CONDITION else "#ffbf59"
	return "[color=%s]%d%%[/color]" % [color, floori(condition)]


func _rebuild_shop(ship: ShipData) -> void:
	for child in _shop_grid.get_children():
		_shop_grid.remove_child(child)
		child.queue_free()
	for header: String in ["For sale", "Stats", "Weight", "Price", "You pay", ""]:
		_shop_grid.add_child(UiStyle.make_label(header, 14, UiStyle.TEXT_DIM))

	var last_kind := ""
	for item in Equipment.shop_items(_planet):
		var kind := item.kind()
		if kind != last_kind:
			last_kind = kind
			_add_section_title(Equipment.KIND_NAMES[kind] + "s")
		var current := ship.slot(kind) # null for weapons: they don't replace anything.
		var trade_in := Equipment.trade_in_value(current, Equipment.condition_of(ship, current)) if current != null else 0
		var cost := Equipment.price(item) - trade_in
		var owned := current != null and current.type_id == item.type_id and current.race_id == item.race_id

		var name_label := _cell(item.display_name())
		name_label.custom_minimum_size = Vector2(190, 0)
		name_label.tooltip_text = item.stats().get("description", "")
		name_label.mouse_filter = Control.MOUSE_FILTER_PASS
		_cell(Equipment.describe(item)).add_theme_color_override("font_color", UiStyle.TEXT_DIM)
		_cell("%d t" % Equipment.weight(item) if kind != "hull" else "-")
		_cell(UiStyle.credits(Equipment.price(item)))
		if owned:
			_cell("-")
		else:
			var pay_label := _cell(UiStyle.credits(cost) if cost >= 0 else "+" + UiStyle.credits(-cost))
			pay_label.add_theme_color_override("font_color", UiStyle.GOOD if cost <= ship.credits else UiStyle.WARNING)
		var no_slot := kind == "weapon" and ship.weapons.size() >= Equipment.weapon_slots(ship.hull)
		var button := UiStyle.make_button("Yours" if owned else ("No slot" if no_slot else "Buy"), _on_buy.bind(item.type_id), 70)
		button.custom_minimum_size.y = 28
		button.disabled = owned or no_slot or cost > ship.credits
		if no_slot:
			button.tooltip_text = "All weapon slots are full. Sell a weapon first."
		_shop_grid.add_child(button)


func _add_section_title(text: String) -> void:
	_shop_grid.add_child(UiStyle.make_label(text, 15, UiStyle.ACCENT))
	for i in _shop_grid.columns - 1:
		_shop_grid.add_child(Control.new())


func _cell(text: String) -> Label:
	var label := UiStyle.make_label(text, 15)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_shop_grid.add_child(label)
	return label


func _on_buy(type_id: String) -> void:
	TurnManager.submit_order({"type": "buy_equipment", "type_id": type_id})


func _on_sell_weapon(index: int) -> void:
	TurnManager.submit_order({"type": "sell_weapon", "index": index})


func _on_repair() -> void:
	TurnManager.submit_order({"type": "repair"})
