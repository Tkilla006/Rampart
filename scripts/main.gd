extends Node2D
## Vertical slice: the first car check on a Westlake corner (event ST-06, The Back Seat).
## Walk the block, check the Crown Vic, and the choice you make there is written to GameState.

## Real seconds per game minute while the world is running.
const SECONDS_PER_MINUTE := 2.0

@onready var street: StreetMap = $Street
@onready var hud: Hud = $Hud
@onready var dialogue: DialogueBox = $Dialogue

var officer: OfficerActor
var camera: Camera2D
var _clock := 0.0
var _near := {}


func _ready() -> void:
	officer = OfficerActor.new()
	officer.name = "Officer"
	officer.map = street
	street.actors.add_child(officer)
	var spawn: Dictionary = street.data.get("spawn", {})
	officer.place(street.spawn_ground(), spawn.get("facing", "down"))
	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	officer.add_child(camera)
	camera.make_current()
	dialogue.finished.connect(_on_dialogue_finished)
	hud.radio("Dispatch: 2A43, show yourselves in service when your car check is done.")


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	_clock += delta
	while _clock >= SECONDS_PER_MINUTE:
		_clock -= SECONDS_PER_MINUTE
		GameState.advance_minutes(1)
	_near = street.interactable_near(officer.ground)
	if _near.is_empty() or GameState.is_event_completed(_near.event):
		hud.prompt("")
	else:
		hud.prompt("[E] %s" % _near.label)


func _unhandled_input(event: InputEvent) -> void:
	if dialogue.is_open():
		return
	if event.is_action_pressed("pause"):
		_set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and not get_tree().paused:
		if not _near.is_empty() and not GameState.is_event_completed(_near.event):
			_start_event(_near.event)
			get_viewport().set_input_as_handled()


func _start_event(event_id: String) -> void:
	if not EventLibrary.has_scene(event_id):
		push_warning("No playable scene for %s yet" % event_id)
		return
	hud.prompt("")
	hud.show_help(false)
	get_tree().paused = true
	dialogue.play(EventLibrary.scene_for(event_id))


func _on_dialogue_finished(event_id: String) -> void:
	get_tree().paused = false
	hud.show_help(true)
	if GameState.is_event_completed(event_id):
		hud.radio("2A43: Show us in service.")


func _set_paused(value: bool) -> void:
	get_tree().paused = value
	hud.set_paused(value)
