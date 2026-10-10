class_name UiStyle
extends RefCounted
## Shared colors and helpers so every screen looks the same.

const ACCENT := Color(0.45, 0.8, 1.0)
const TEXT := Color(0.88, 0.92, 1.0)
const TEXT_DIM := Color(0.6, 0.66, 0.8)
const GOOD := Color(0.5, 1.0, 0.6)
const WARNING := Color(1.0, 0.75, 0.35)
const PANEL_BG := Color(0.03, 0.05, 0.11, 0.86)


static func panel_style(background: Color = PANEL_BG) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = Color(ACCENT, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


static func make_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", panel_style())
	return panel


## Buttons never take keyboard focus, so Space always means "End Turn".
static func make_button(text: String, on_pressed: Callable, min_width: float = 0.0) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(min_width, 34)
	button.pressed.connect(on_pressed)
	return button


static func make_label(text: String = "", font_size: int = 16, color: Color = TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


static func level_color(level: String) -> Color:
	match level:
		"good":
			return GOOD
		"warning":
			return WARNING
	return TEXT


## 12500 -> "12,500 cr"
static func credits(amount: int) -> String:
	var digits := str(absi(amount))
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.right(3) + grouped
		digits = digits.left(digits.length() - 3)
	return "%s%s%s cr" % ["-" if amount < 0 else "", digits, grouped]
