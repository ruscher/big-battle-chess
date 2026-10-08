class_name CinematicOverlay
extends Control
## Full-screen presentation layer: fades between board and arena, impact
## flashes (respecting "reduce flashes"), letterbox bars, animated title
## cards and the skip / speed-up hint shown during cinematics.

var _fade: ColorRect
var _flash: ColorRect
var _bars: Array[ColorRect] = []
var _title: Label
var _subtitle: Label
var _hint: Label
var _fade_tween: Tween
var _title_tween: Tween
var _flash_tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_left = 0.0
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 1.0
		bar.anchor_bottom = 0.0 if top else 1.0
		bar.offset_top = 0.0 if top else 0.0
		bar.offset_bottom = 0.0
		add_child(bar)
		_bars.append(bar)
	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_flash.material = add_mat
	add_child(_flash)

	var title_box := VBoxContainer.new()
	title_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title_box.anchor_top = 0.62
	title_box.anchor_bottom = 0.62
	title_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title_box)
	_title = UiKit.title("", 72)
	_title.add_theme_constant_override("outline_size", 10)
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_title.modulate.a = 0.0
	title_box.add_child(_title)
	_subtitle = UiKit.caption("", 22)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.modulate.a = 0.0
	title_box.add_child(_subtitle)

	_hint = UiKit.caption("HINT_SKIP_CINEMATIC", 17)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.offset_top = -34
	_hint.offset_bottom = -12
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.modulate.a = 0.0
	add_child(_hint)

	_fade = ColorRect.new()
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)


## Fades the screen to `alpha` (1 = covered). Await the returned signal.
func fade(alpha: float, duration: float, color: Color = Color(0, 0, 0)) -> Signal:
	if _fade_tween:
		_fade_tween.kill()
	_fade.color = Color(color.r, color.g, color.b, _fade.color.a)
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade, "color:a", alpha, maxf(duration, 0.01))
	return _fade_tween.finished


func flash(strength: float, color: Color) -> void:
	if strength <= 0.01:
		return
	if _flash_tween:
		_flash_tween.kill()
	_flash.color = Color(color.r, color.g, color.b, clampf(strength, 0.0, 0.8))
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash, "color:a", 0.0, 0.35).set_ease(Tween.EASE_OUT)


func letterbox(enabled: bool) -> void:
	var h := size.y * 0.1 if enabled else 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_bars[0], "offset_bottom", h, 0.45).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_bars[1], "offset_top", -h, 0.45).set_trans(Tween.TRANS_CUBIC)
	var hint_tw := create_tween()
	hint_tw.tween_property(_hint, "modulate:a", 0.75 if enabled else 0.0, 0.5)


## style: "matchup" (gold, upper) or "finisher" (large, faction colour).
func show_title(key: String, style: String, color: Color, subtitle_key: String = "") -> void:
	if _title_tween:
		_title_tween.kill()
	_title.text = tr(key)
	_subtitle.text = tr(subtitle_key) if not subtitle_key.is_empty() else ""
	var big := style == "finisher"
	_title.add_theme_font_size_override("font_size", 84 if big else 56)
	_title.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.35) if big else UiTheme.GOLD)
	_title.pivot_offset = _title.size * 0.5
	_title.scale = Vector2(1.25, 1.25)
	_title.modulate.a = 0.0
	_title_tween = create_tween()
	_title_tween.set_parallel(true)
	_title_tween.tween_property(_title, "modulate:a", 1.0, 0.25)
	_title_tween.tween_property(_title, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_title_tween.tween_property(_subtitle, "modulate:a", 1.0, 0.4).set_delay(0.2)
	_title_tween.chain().tween_interval(1.6)
	_title_tween.chain().set_parallel(true)
	_title_tween.tween_property(_title, "modulate:a", 0.0, 0.5)
	_title_tween.tween_property(_subtitle, "modulate:a", 0.0, 0.5)
