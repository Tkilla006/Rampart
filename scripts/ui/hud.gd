class_name Hud
extends CanvasLayer
## Call sign, watch and clock, the radio line, interaction prompts and the pause marker.
## Stress is shown, never numbered: low Composure darkens the edges of the screen (tunnel vision).

const FONT_SIZE := 10
const TUNNEL_SHADER := """
shader_type canvas_item;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d * vec2(1.0, 0.72));
	float edge = smoothstep(0.62 - 0.32 * strength, 0.78, r);
	COLOR = vec4(0.0, 0.0, 0.0, edge * strength * 0.92);
}
"""

var _status: Label
var _radio: Label
var _prompt: Label
var _paused: Label
var _help: Label
var _tunnel: ColorRect


func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	_tunnel = ColorRect.new()
	_tunnel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tunnel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = TUNNEL_SHADER
	mat.shader = shader
	_tunnel.material = mat
	add_child(_tunnel)

	_status = _label(Vector2(8, 6))
	_radio = _label(Vector2(8, 38))
	_radio.add_theme_color_override("font_color", Color(0.6, 0.85, 0.65))
	_help = _label(Vector2(8, 0))
	_help.anchor_top = 1.0
	_help.anchor_bottom = 1.0
	_help.offset_top = -18
	_help.add_theme_color_override("font_color", Color(0.65, 0.66, 0.7))
	_help.text = "WASD / arrows or click: move   Shift: run   E: interact   Space: pause"

	_prompt = _label(Vector2.ZERO)
	_prompt.anchor_right = 1.0
	_prompt.offset_right = 0
	_prompt.anchor_top = 0.5
	_prompt.anchor_bottom = 0.5
	_prompt.offset_top = 36
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))

	_paused = _label(Vector2.ZERO)
	_paused.anchor_left = 1.0
	_paused.anchor_right = 1.0
	_paused.offset_left = -64
	_paused.offset_top = 6
	_paused.text = "PAUSED"
	_paused.add_theme_color_override("font_color", Color(0.95, 0.8, 0.35))
	_paused.visible = false

	GameState.clock_changed.connect(func(_m): refresh())
	GameState.composure_changed.connect(func(_v, _m): refresh())
	refresh()


func _label(pos: Vector2) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", FONT_SIZE)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	add_child(l)
	return l


func refresh() -> void:
	var watch_name: String = {"day": "Day watch", "pm": "PM watch", "morning": "Morning watch"}.get(GameState.watch, "")
	_status.text = "%s   %s\n%s   %s" % [GameState.call_sign, watch_name, GameState.date_text(), GameState.clock_text()]
	var o := GameState.officer
	var fraction := float(o.composure) / float(maxi(o.max_composure(), 1))
	# Tunnel vision begins below half Composure and closes in toward zero.
	var strength := clampf((0.5 - fraction) / 0.5, 0.0, 1.0)
	(_tunnel.material as ShaderMaterial).set_shader_parameter("strength", strength)


func radio(line: String) -> void:
	_radio.text = line


func prompt(text: String) -> void:
	_prompt.text = text
	_prompt.visible = text != ""


func show_help(value: bool) -> void:
	_help.visible = value


func set_paused(value: bool) -> void:
	_paused.visible = value
