extends Node
## Moves between screens: main menu, character creation, the prologue, the city map,
## the station, the battlescape and the endings.

const MAIN_MENU := "res://scenes/main_menu.tscn"
const CREATION := "res://scenes/creation.tscn"
const PROLOGUE := "res://scenes/prologue.tscn"
const CITYSCAPE := "res://scenes/cityscape.tscn"
const STATION := "res://scenes/station.tscn"
const BATTLESCAPE := "res://scenes/battlescape.tscn"
const ENDING := "res://scenes/ending.tscn"

var last_result := {}
var last_notes: Array[String] = []
var skirmish := false


func _ready() -> void:
	get_tree().root.theme = UiKit.theme()
	Campaign.game_over.connect(func(_e): go(ENDING))


func go(path: String) -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file.call_deferred(path)


func main_menu() -> void:
	go(MAIN_MENU)


func cityscape() -> void:
	go(CITYSCAPE)


func station() -> void:
	go(STATION)


func start_call(call_id: int) -> void:
	skirmish = false
	Campaign.begin_mission(call_id)
	go(BATTLESCAPE)


## A quick battle from the main menu: any call type, the player and the FTO, no campaign.
func start_skirmish(type_id: String) -> void:
	skirmish = true
	var t: Dictionary = Campaign.call_types[type_id]
	var truth: Dictionary = t.truth[randi_range(0, t.truth.size() - 1)]
	var squad: Array = [TacUnit.from_officer(GameState.officer, "player", GameState.officer.display_name, {"loadout": "taser"})]
	var fto: Dictionary = Campaign.people["ortega"]
	var o := Officer.new()
	for a in fto.attributes:
		o.attributes[a] = int(fto.attributes[a])
	for sk in fto.skills:
		o.skills[sk] = int(fto.skills[sk])
	o.composure = o.max_composure()
	squad.append(TacUnit.from_officer(o, "ortega", "Ortega", {"loadout": "patrol", "rank": "Police Officer III"}))
	var call := {"type": type_id, "label": t.label, "map": t.map, "basis": t.basis, "truth": truth,
		"watch": ["day", "pm", "morning"][randi_range(0, 2)], "district": "macarthur_park"}
	Campaign._pending_mission = MissionFactory.build(call, squad)
	go(BATTLESCAPE)


func mission_finished(result: Dictionary) -> void:
	last_result = result
	if skirmish or not Campaign.active:
		main_menu()
		return
	last_notes = Campaign.apply_result(result)
	cityscape()
