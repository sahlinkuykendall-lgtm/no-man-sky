class_name MainMenu
extends Control
## Title screen: start a new galaxy (pick a race and an optional seed) or continue a save.

signal new_game_requested(galaxy_seed: int, race_id: String)
signal continue_requested

var _seed_input: LineEdit
var _race_picker: OptionButton
var _race_description: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color(0.012, 0.016, 0.04)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(380, 0)
	column.add_theme_constant_override("separation", 12)
	center.add_child(column)

	var title := UiStyle.make_label("PROJECT RANGER", 48, UiStyle.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var subtitle := UiStyle.make_label("Prototype: Milestone 1 (Galaxy & Turns)", 15, UiStyle.TEXT_DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(subtitle)
	column.add_child(HSeparator.new())

	column.add_child(UiStyle.make_label("Your race", 15, UiStyle.TEXT_DIM))
	_race_picker = OptionButton.new()
	_race_picker.focus_mode = Control.FOCUS_NONE
	for race: Dictionary in GameData.races():
		_race_picker.add_item(race["name"])
	_race_picker.item_selected.connect(func(_index: int) -> void: _update_race_description())
	column.add_child(_race_picker)
	_race_description = UiStyle.make_label("", 14, UiStyle.TEXT_DIM)
	_race_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_race_description)
	_update_race_description()

	column.add_child(UiStyle.make_label("Galaxy seed (leave empty for random)", 15, UiStyle.TEXT_DIM))
	_seed_input = LineEdit.new()
	_seed_input.placeholder_text = "random"
	column.add_child(_seed_input)

	column.add_child(UiStyle.make_button("New Game", _on_new_game))
	var continue_button := UiStyle.make_button("Continue", func() -> void: continue_requested.emit())
	continue_button.disabled = not SaveSystem.has_save()
	column.add_child(continue_button)
	column.add_child(UiStyle.make_button("Quit", func() -> void: get_tree().quit()))


func _update_race_description() -> void:
	var race: Dictionary = GameData.races()[_race_picker.selected]
	_race_description.text = race.get("description", "")


func _on_new_game() -> void:
	var text := _seed_input.text.strip_edges()
	var galaxy_seed := randi()
	if text != "":
		galaxy_seed = int(text) if text.is_valid_int() else text.hash()
	var race: Dictionary = GameData.races()[_race_picker.selected]
	new_game_requested.emit(galaxy_seed, race["id"])
