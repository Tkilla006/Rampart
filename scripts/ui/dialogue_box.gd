class_name DialogueBox
extends CanvasLayer
## Plays a scene graph from data/scenes/: text, the rookie's portrait, and choices with visible odds.
## Effects on a choice go through GameState.apply_effects, so outcomes stay data.

signal finished(event_id: String)

const PORTRAIT_PATH := "res://art/characters/portraits/rookie_portrait_%s.png"
const FONT_SIZE := 10

var scene_data := {}
var current := ""
var rng := RandomNumberGenerator.new()

var _panel: PanelContainer
var _portrait: TextureRect
var _speaker: Label
var _text: Label
var _choices: VBoxContainer
var _last_check := ""


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	_build()
	hide_box()


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 8
	_panel.offset_right = -8
	_panel.offset_top = -132
	_panel.offset_bottom = -8
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.1, 0.97)
	style.border_color = Color(0.32, 0.36, 0.48)
	style.set_border_width_all(1)
	style.set_content_margin_all(8)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_panel.add_child(row)

	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(96, 96)
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(_portrait)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)

	_speaker = Label.new()
	_speaker.add_theme_font_size_override("font_size", FONT_SIZE)
	_speaker.add_theme_color_override("font_color", Color(0.85, 0.75, 0.45))
	col.add_child(_speaker)

	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_font_size_override("font_size", FONT_SIZE)
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_text)

	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 2)
	col.add_child(_choices)


func is_open() -> bool:
	return _panel.visible


func play(scene: Dictionary) -> void:
	scene_data = scene
	_last_check = ""
	_panel.visible = true
	_show(scene.start)


func hide_box() -> void:
	_panel.visible = false


func _show(node_id: String) -> void:
	current = node_id
	var node: Dictionary = scene_data.nodes[node_id]
	GameState.apply_effects(node.get("effects", []))
	_speaker.text = node.get("speaker", "")
	_speaker.visible = _speaker.text != ""
	var expression: String = node.get("portrait", "")
	_portrait.visible = expression != ""
	if expression != "":
		_portrait.texture = load(PORTRAIT_PATH % expression)
	_text.text = (_last_check + "\n" if _last_check != "" else "") + node.text
	_last_check = ""
	for c in _choices.get_children():
		c.queue_free()
	var shown := 0
	for choice in node.get("choices", []):
		if not GameState.meets_all(choice.get("requires", [])):
			continue
		shown += 1
		_add_button("%d. %s%s" % [shown, choice.text, _odds_suffix(choice)], _choose.bind(choice))
	if shown == 0:
		if node.has("next"):
			_add_button("Continue", _show.bind(node.next))
		else:
			_add_button("Close", _finish)
	_focus_first.call_deferred()


func _odds_suffix(choice: Dictionary) -> String:
	if not choice.has("check"):
		return ""
	var c: Dictionary = choice.check
	var chance := GameState.officer.skill_chance(c.skill, int(c.get("modifiers", 0)))
	return "  [%s %d%%]" % [c.skill.capitalize(), Check.display_odds(chance)]


func _choose(choice: Dictionary) -> void:
	GameState.apply_effects(choice.get("effects", []))
	if choice.has("check"):
		var c: Dictionary = choice.check
		var result := GameState.officer.check_skill(c.skill, int(c.get("modifiers", 0)), rng)
		_last_check = "%s: %s" % [c.skill.capitalize(), result.describe()]
		_show(choice.on_success if result.success else choice.on_failure)
	elif choice.has("next"):
		_show(choice.next)
	else:
		_finish()


func _finish() -> void:
	hide_box()
	finished.emit(scene_data.get("event", ""))


func _add_button(label: String, callback: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", FONT_SIZE)
	b.pressed.connect(callback)
	_choices.add_child(b)


func _focus_first() -> void:
	for c in _choices.get_children():
		if not c.is_queued_for_deletion():
			c.grab_focus()
			return


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_open() or not event.is_pressed() or event.is_echo():
		return
	var k := (event as InputEventKey).keycode
	if k >= KEY_1 and k <= KEY_9:
		var live := _choices.get_children().filter(func(c): return not c.is_queued_for_deletion())
		var i := k - KEY_1
		if i < live.size():
			live[i].pressed.emit()
			get_viewport().set_input_as_handled()
