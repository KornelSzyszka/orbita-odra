class_name UiKit
extends RefCounted
## Shared HUD styling (theme, panels, formatting helpers).

const ACCENT := Color(0.36, 0.84, 1.0)
const TEXT := Color(0.95, 0.97, 1.0)
const DIM := Color(0.70, 0.77, 0.87)      ## captions; >= 7:1 on PANEL_BG
const WARN := Color(1.0, 0.76, 0.30)
const BAD := Color(1.0, 0.45, 0.40)
const GOOD := Color(0.50, 1.0, 0.64)
const MOON := Color(0.82, 0.66, 1.0)
const PANEL_BG := Color(0.025, 0.045, 0.08)

## Type scale (logical px at the 1280x720 base viewport).
const FS_CAPTION := 13
const FS_BODY := 15
const FS_VALUE := 15
const FS_PRIMARY := 22
const FS_TITLE := 28


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = FS_BODY
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 1, 1))
	t.set_color("font_pressed_color", "Button", Color(1, 1, 1))
	t.set_color("font_hover_pressed_color", "Button", Color(1, 1, 1))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_constant("outline_size", "Label", 0)
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.09, 0.15, 0.23, 0.96)
	btn.border_color = Color(ACCENT, 0.5)
	btn.set_border_width_all(1)
	btn.set_corner_radius_all(6)
	btn.content_margin_left = 10
	btn.content_margin_right = 10
	btn.content_margin_top = 6
	btn.content_margin_bottom = 6
	var hov := btn.duplicate() as StyleBoxFlat
	hov.bg_color = Color(0.14, 0.24, 0.36, 0.98)
	hov.border_color = ACCENT
	var prs := btn.duplicate() as StyleBoxFlat
	prs.bg_color = Color(0.16, 0.45, 0.62, 1.0)
	prs.border_color = Color(0.7, 0.93, 1.0)
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover_pressed", "Button", prs)
	t.set_stylebox("hover", "Button", hov)
	t.set_stylebox("pressed", "Button", prs)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Color(1.0, 1.0, 1.0, 0.55)
	focus.set_border_width_all(1)
	focus.set_corner_radius_all(6)
	t.set_stylebox("focus", "Button", focus)
	var tip := StyleBoxFlat.new()
	tip.bg_color = Color(PANEL_BG, 0.97)
	tip.border_color = Color(ACCENT, 0.6)
	tip.set_border_width_all(1)
	tip.set_corner_radius_all(5)
	tip.set_content_margin_all(8)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", FS_CAPTION + 1)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.06, 0.09, 0.13, 1.0)
	bar_bg.set_corner_radius_all(4)
	var bar_fg := StyleBoxFlat.new()
	bar_fg.bg_color = ACCENT
	bar_fg.set_corner_radius_all(4)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fg)
	var tab_sel := StyleBoxFlat.new()
	tab_sel.bg_color = Color(0.14, 0.26, 0.38, 1.0)
	tab_sel.set_corner_radius_all(5)
	tab_sel.content_margin_left = 12
	tab_sel.content_margin_right = 12
	tab_sel.content_margin_top = 4
	tab_sel.content_margin_bottom = 4
	var tab_un := tab_sel.duplicate() as StyleBoxFlat
	tab_un.bg_color = Color(0.07, 0.11, 0.16, 1.0)
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)
	t.set_stylebox("tab_unselected", "TabContainer", tab_un)
	t.set_stylebox("tab_hovered", "TabContainer", tab_sel)
	t.set_stylebox("panel", "TabContainer", StyleBoxEmpty.new())
	return t


## Pin a control to an anchor point (0..1 of the parent) with a pixel offset;
## it sizes to its content and grows in the given directions.
static func pin(c: Control, ax: float, ay: float, ox: float, oy: float,
		grow_h: int, grow_v: int) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = ox
	c.offset_right = ox
	c.offset_top = oy
	c.offset_bottom = oy
	c.grow_horizontal = grow_h
	c.grow_vertical = grow_v


static func panel_style(alpha := 0.82) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(PANEL_BG, alpha)
	s.border_color = Color(ACCENT, 0.32)
	s.set_border_width_all(1)
	s.border_width_left = 3
	s.set_corner_radius_all(8)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


static func panel(alpha := 0.82) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(alpha))
	return p


static func label(text: String, size := 15, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func header(text: String) -> Label:
	var l := label(text, FS_CAPTION, ACCENT)
	l.uppercase = true
	return l


## Thin horizontal divider used between HUD sections.
static func divider() -> HSeparator:
	var sep := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = Color(ACCENT, 0.18)
	line.thickness = 1
	sep.add_theme_stylebox_override("separator", line)
	sep.add_theme_constant_override("separation", 6)
	return sep


## Small flat "chip" style (status pills, key hints).
static func chip_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(color, 0.16)
	s.border_color = Color(color, 0.55)
	s.set_border_width_all(1)
	s.set_corner_radius_all(10)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	return s


static func fmt_alt(m: float) -> String:
	if is_inf(m):
		return "∞"
	if absf(m) >= 10_000.0:
		return "%.2f km" % (m / 1000.0)
	return "%.0f m" % m


static func fmt_time(s: float) -> String:
	if s < 0.0 or is_inf(s) or is_nan(s):
		return "—"
	var si := int(s)
	if si >= 3600:
		return "%d:%02d:%02d" % [si / 3600, (si / 60) % 60, si % 60]
	return "%d:%02d" % [si / 60, si % 60]
