class_name UiTheme
extends RefCounted
## Dark-fantasy UI theme built in code: Cinzel for titles, EB Garamond for
## text, blackened steel panels with gold filigree borders. High contrast
## text and an always-visible focus frame for keyboard/gamepad navigation.

const GOLD := Color(0.96, 0.77, 0.4)
const GOLD_DIM := Color(0.62, 0.48, 0.25)
const PARCHMENT := Color(0.95, 0.9, 0.8)
const MUTED := Color(0.72, 0.68, 0.62)
const PANEL := Color(0.055, 0.045, 0.065, 0.9)
const PANEL_SOLID := Color(0.07, 0.06, 0.085, 0.97)
const DAWN := Color(0.62, 0.78, 1.0)
const UMBRAL := Color(0.95, 0.35, 0.4)
const DANGER := Color(1.0, 0.38, 0.32)

static var _theme: Theme
static var _title_font: Font
static var _body_font: Font
static var _bold_font: Font


static func title_font() -> Font:
	if _title_font == null:
		_title_font = _variation("res://assets/fonts/Cinzel-Variable.ttf", 700)
	return _title_font


static func body_font() -> Font:
	if _body_font == null:
		_body_font = _variation("res://assets/fonts/EBGaramond-Variable.ttf", 500)
	return _body_font


static func bold_font() -> Font:
	if _bold_font == null:
		_bold_font = _variation("res://assets/fonts/EBGaramond-Variable.ttf", 700)
	return _bold_font


static func _variation(path: String, weight: int) -> Font:
	var base: FontFile = load(path) if ResourceLoader.exists(path) else null
	if base == null:
		return ThemeDB.fallback_font
	var fv := FontVariation.new()
	fv.base_font = base
	var ts := TextServerManager.get_primary_interface()
	fv.variation_opentype = {ts.name_to_tag("wght"): weight}
	return fv


static func box(bg: Color, border: Color, border_w: int = 1, radius: int = 4, margin: float = 12.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	s.anti_aliasing = true
	return s


static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = 22

	t.set_color("font_color", "Label", PARCHMENT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.6))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 2)

	var panel := box(PANEL, GOLD_DIM, 1, 6, 18)
	panel.shadow_color = Color(0, 0, 0, 0.55)
	panel.shadow_size = 18
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)

	var normal := box(Color(0.1, 0.085, 0.11, 0.92), Color(0.42, 0.33, 0.2), 1, 3, 10)
	normal.content_margin_left = 22
	normal.content_margin_right = 22
	var hover := box(Color(0.2, 0.15, 0.1, 0.96), GOLD, 1, 3, 10)
	hover.content_margin_left = 22
	hover.content_margin_right = 22
	hover.shadow_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.25)
	hover.shadow_size = 8
	var pressed := box(Color(0.05, 0.04, 0.05, 0.98), GOLD, 2, 3, 10)
	pressed.content_margin_left = 22
	pressed.content_margin_right = 22
	var disabled := box(Color(0.08, 0.07, 0.08, 0.6), Color(0.25, 0.22, 0.2), 1, 3, 10)
	disabled.content_margin_left = 22
	disabled.content_margin_right = 22
	var focus := box(Color(0, 0, 0, 0), Color(1.0, 0.88, 0.55), 2, 4, 10)
	focus.expand_margin_left = 3
	focus.expand_margin_right = 3
	focus.expand_margin_top = 3
	focus.expand_margin_bottom = 3
	for cls in ["Button", "OptionButton", "CheckButton", "CheckBox", "MenuButton"]:
		t.set_stylebox("normal", cls, normal)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("hover_pressed", cls, pressed)
		t.set_stylebox("disabled", cls, disabled)
		t.set_stylebox("focus", cls, focus)
		t.set_color("font_color", cls, PARCHMENT)
		t.set_color("font_hover_color", cls, Color(1.0, 0.93, 0.75))
		t.set_color("font_pressed_color", cls, GOLD)
		t.set_color("font_focus_color", cls, Color(1.0, 0.93, 0.75))
		t.set_color("font_disabled_color", cls, Color(0.5, 0.47, 0.43))
	t.set_stylebox("normal", "CheckBox", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 3, 6))
	t.set_stylebox("hover", "CheckBox", box(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 0, 3, 6))
	t.set_stylebox("pressed", "CheckBox", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 3, 6))
	t.set_stylebox("hover_pressed", "CheckBox", box(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 0, 3, 6))

	var popup := box(PANEL_SOLID, GOLD_DIM, 1, 4, 8)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", box(Color(0.25, 0.18, 0.1), GOLD, 0, 2, 4))
	t.set_color("font_color", "PopupMenu", PARCHMENT)
	t.set_color("font_hover_color", "PopupMenu", Color(1, 0.93, 0.75))
	t.set_font_size("font_size", "PopupMenu", 21)

	var slider_track := box(Color(0.15, 0.12, 0.1), Color(0.35, 0.28, 0.18), 1, 3, 0)
	slider_track.content_margin_top = 4
	slider_track.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", slider_track)
	var fill := box(GOLD_DIM, GOLD, 1, 3, 0)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", box(GOLD, GOLD, 1, 3, 0))

	var tab_sel := box(Color(0.18, 0.13, 0.09, 0.95), GOLD, 1, 3, 10)
	var tab_unsel := box(Color(0.08, 0.07, 0.08, 0.85), Color(0.35, 0.28, 0.18), 1, 3, 10)
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)
	t.set_stylebox("tab_unselected", "TabContainer", tab_unsel)
	t.set_stylebox("tab_hovered", "TabContainer", hover)
	t.set_stylebox("panel", "TabContainer", box(Color(0.05, 0.04, 0.06, 0.85), GOLD_DIM, 1, 4, 18))
	t.set_color("font_selected_color", "TabContainer", GOLD)
	t.set_color("font_unselected_color", "TabContainer", MUTED)
	t.set_color("font_hovered_color", "TabContainer", PARCHMENT)
	t.set_font("font", "TabContainer", title_font())
	t.set_font_size("font_size", "TabContainer", 18)

	t.set_stylebox("panel", "ItemList", box(Color(0.04, 0.035, 0.05, 0.85), Color(0.35, 0.28, 0.18), 1, 3, 8))
	t.set_stylebox("selected", "ItemList", box(Color(0.25, 0.18, 0.1), GOLD, 1, 2, 4))
	t.set_stylebox("selected_focus", "ItemList", box(Color(0.3, 0.22, 0.12), GOLD, 1, 2, 4))
	t.set_stylebox("focus", "ItemList", focus)
	t.set_color("font_color", "ItemList", PARCHMENT)
	t.set_color("font_selected_color", "ItemList", Color(1, 0.93, 0.75))

	t.set_stylebox("normal", "LineEdit", box(Color(0.04, 0.035, 0.05, 0.9), Color(0.35, 0.28, 0.18), 1, 3, 8))
	t.set_stylebox("focus", "LineEdit", focus)
	t.set_color("font_color", "LineEdit", PARCHMENT)
	t.set_stylebox("normal", "TextEdit", box(Color(0.04, 0.035, 0.05, 0.9), Color(0.35, 0.28, 0.18), 1, 3, 8))
	t.set_color("font_color", "TextEdit", PARCHMENT)
	t.set_color("default_color", "RichTextLabel", PARCHMENT)
	t.set_font("bold_font", "RichTextLabel", bold_font())

	t.set_stylebox("panel", "TooltipPanel", box(PANEL_SOLID, GOLD_DIM, 1, 3, 8))
	t.set_color("font_color", "TooltipLabel", PARCHMENT)

	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 10)
	t.set_stylebox("separator", "HSeparator", box(GOLD_DIM, Color(0, 0, 0, 0), 0, 0, 0))
	_theme = t
	return t


static func clear_cache() -> void:
	_theme = null
	_title_font = null
	_body_font = null
	_bold_font = null
