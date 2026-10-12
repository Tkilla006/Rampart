extends Node2D
## Title screen over the Westlake corner: new probation, continue, quick battle, the prologue.

var _types: OptionButton


func _ready() -> void:
	name = "MainMenu"
	var street := StreetMap.new()
	add_child(street)
	var cam := Camera2D.new()
	cam.position = Iso.ground_to_screen(Iso.tile_to_ground(Vector2(7.5, 7.5)))
	cam.zoom = Vector2(0.75, 0.75)
	add_child(cam)
	cam.make_current()
	var ui := CanvasLayer.new()
	add_child(ui)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.035, 0.05, 0.62)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(shade)
	var col := VBoxContainer.new()
	col.position = Vector2(36, 40)
	col.custom_minimum_size = Vector2(240, 0)
	col.add_theme_constant_override("separation", 5)
	ui.add_child(col)
	UiKit.label(col, "RAMPART", UiKit.ACCENT, 28)
	UiKit.label(col, "Rampart Division, Los Angeles, 2010", UiKit.MUTED, 9)
	UiKit.label(col, "", UiKit.TEXT)
	UiKit.button(col, "New probation", func(): Flow.go(Flow.CREATION))
	var cont := UiKit.button(col, "Continue", _continue)
	cont.disabled = not FileAccess.file_exists(GameState.SAVE_PATH)
	UiKit.button(col, "Prologue: The Back Seat", func(): Flow.go(Flow.PROLOGUE))
	var row := HBoxContainer.new()
	col.add_child(row)
	_types = OptionButton.new()
	for t in Campaign.call_types:
		_types.add_item(Campaign.call_types[t].label)
		_types.set_item_metadata(_types.item_count - 1, t)
	row.add_child(_types)
	UiKit.button(row, "Quick battle", func(): Flow.start_skirmish(String(_types.get_selected_metadata())))
	UiKit.button(col, "Quit", func(): get_tree().quit())
	UiKit.label(col, "", UiKit.TEXT)
	UiKit.para(col, "An 18+ CRPG. Graphic violence, death, addiction, trauma and police misconduct.", 240, UiKit.MUTED)


func _continue() -> void:
	if GameState.load_game() == OK and Campaign.active:
		Flow.cityscape()
