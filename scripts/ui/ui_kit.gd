class_name UiKit
extends RefCounted
## Shared look for menus and panels: dark panels, small type, amber highlights.

const BG := Color(0.07, 0.08, 0.11)
const PANEL := Color(0.1, 0.11, 0.15, 0.97)
const BORDER := Color(0.32, 0.36, 0.48)
const ACCENT := Color(0.95, 0.82, 0.48)
const TEXT := Color(0.86, 0.87, 0.9)
const MUTED := Color(0.62, 0.64, 0.7)


static func theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 9
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL
	panel.border_color = BORDER
	panel.set_border_width_all(1)
	panel.set_content_margin_all(6)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.16, 0.18, 0.24)
	btn.border_color = Color(0.3, 0.33, 0.42)
	btn.set_border_width_all(1)
	btn.content_margin_left = 5
	btn.content_margin_right = 5
	btn.content_margin_top = 2
	btn.content_margin_bottom = 2
	var hover := btn.duplicate()
	hover.bg_color = Color(0.24, 0.26, 0.34)
	hover.border_color = ACCENT
	var pressed := btn.duplicate()
	pressed.bg_color = Color(0.3, 0.27, 0.18)
	var disabled := btn.duplicate()
	disabled.bg_color = Color(0.12, 0.12, 0.15)
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("focus", "Button", hover)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", Color(0.4, 0.4, 0.45))
	t.set_color("font_color", "Label", TEXT)
	t.set_font_size("font_size", "Button", 9)
	t.set_font_size("font_size", "Label", 9)
	t.set_font_size("font_size", "OptionButton", 9)
	t.set_font_size("font_size", "LineEdit", 9)
	t.set_font_size("font_size", "PopupMenu", 9)
	t.set_font_size("font_size", "ItemList", 9)
	t.set_font_size("font_size", "TabContainer", 9)
	t.set_font_size("normal_font_size", "RichTextLabel", 9)
	return t


static func label(parent: Node, text: String, color: Color = TEXT, size: int = 9) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l


static func para(parent: Node, text: String, width: float, color: Color = TEXT) -> Label:
	var l := label(parent, text, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0)
	return l


static func button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


static func panel(parent: Node, rect: Rect2) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = rect.position
	p.size = rect.size
	p.custom_minimum_size = rect.size
	parent.add_child(p)
	return p


static func backdrop(parent: Node) -> ColorRect:
	var r := ColorRect.new()
	r.color = BG
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(r)
	return r
