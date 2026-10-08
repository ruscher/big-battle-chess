class_name UiKit
extends RefCounted
## Small factory of themed widgets so screens stay short and consistent.
## Text passed as translation keys is translated automatically by Godot
## (and re-translated when the language changes).


static func title(text: String, size: int = 64, color: Color = UiTheme.GOLD) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiTheme.title_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.add_theme_constant_override("shadow_outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func label(text: String, size: int = 22, color: Color = UiTheme.PARCHMENT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func caption(text: String, size: int = 16) -> Label:
	var l := label(text, size, UiTheme.MUTED)
	l.add_theme_font_override("font", UiTheme.title_font())
	return l


static func button(text: String, on_pressed: Callable = Callable(), min_width: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", UiTheme.title_font())
	b.add_theme_font_size_override("font_size", 20)
	b.custom_minimum_size = Vector2(min_width, 48)
	b.focus_mode = Control.FOCUS_ALL
	if on_pressed.is_valid():
		b.pressed.connect(on_pressed)
	b.pressed.connect(func() -> void: Audio.ui("click"))
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			Audio.ui("hover"))
	b.focus_entered.connect(func() -> void: Audio.ui("hover"))
	return b


static func icon_button(glyph: String, tooltip: String, on_pressed: Callable) -> Button:
	var b := button(glyph, on_pressed, 54)
	b.tooltip_text = tooltip
	b.add_theme_font_override("font", UiTheme.body_font())
	b.add_theme_font_size_override("font_size", 24)
	return b


static func panel(min_size: Vector2 = Vector2.ZERO) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = min_size
	return p


static func vbox(sep: int = 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func separator() -> HSeparator:
	var s := HSeparator.new()
	s.custom_minimum_size = Vector2(0, 8)
	return s


## Label + OptionButton row. `items` are translation keys.
static func option_row(label_key: String, items: Array, selected: int, on_selected: Callable) -> HBoxContainer:
	var row := hbox(16)
	var l := label(label_key, 21)
	l.custom_minimum_size = Vector2(280, 0)
	row.add_child(l)
	var ob := OptionButton.new()
	ob.add_theme_font_size_override("font_size", 20)
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in items.size():
		ob.add_item(str(items[i]), i)
	ob.select(clampi(selected, 0, items.size() - 1))
	ob.item_selected.connect(on_selected)
	ob.item_selected.connect(func(_i: int) -> void: Audio.ui("click"))
	row.add_child(ob)
	return row


static func slider_row(label_key: String, value: float, min_v: float, max_v: float, step: float,
		on_changed: Callable, percent: bool = true) -> HBoxContainer:
	var row := hbox(16)
	var l := label(label_key, 21)
	l.custom_minimum_size = Vector2(280, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(220, 28)
	s.focus_mode = Control.FOCUS_ALL
	row.add_child(s)
	var v := label("", 19, UiTheme.MUTED)
	v.custom_minimum_size = Vector2(70, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var fmt := func(x: float) -> String: return ("%d%%" % roundi(x * 100.0)) if percent else ("%.2fx" % x)
	v.text = fmt.call(value)
	s.value_changed.connect(func(x: float) -> void:
		v.text = fmt.call(x)
		on_changed.call(x))
	row.add_child(v)
	return row


static func check_row(label_key: String, value: bool, on_toggled: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = label_key
	c.button_pressed = value
	c.add_theme_font_size_override("font_size", 21)
	c.toggled.connect(on_toggled)
	c.toggled.connect(func(_b: bool) -> void: Audio.ui("click"))
	return c


static func center_overlay(parent: Control, dim: float = 0.55) -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, dim)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	parent.add_child(root)
	return root


static func glyph(piece_type: int, color: int) -> String:
	const WHITE_GLYPHS := ["", "♙", "♘", "♗", "♖", "♕", "♔"]
	const BLACK_GLYPHS := ["", "♟", "♞", "♝", "♜", "♛", "♚"]
	return (WHITE_GLYPHS if color == Chess.WHITE else BLACK_GLYPHS)[clampi(piece_type, 0, 6)]


## Moves keyboard/gamepad focus to the first focusable descendant.
static func focus_first(node: Node) -> void:
	for c in node.find_children("*", "Control", true, false):
		var ctl := c as Control
		if ctl.focus_mode == Control.FOCUS_ALL and ctl.is_visible_in_tree() and not (ctl is Button and (ctl as Button).disabled):
			ctl.grab_focus.call_deferred()
			return
