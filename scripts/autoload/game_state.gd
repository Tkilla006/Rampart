extends Node
## Everything that persists across the probation: the officer, flags, reputation, relationships and the clock.
## Scripted events read and write this through apply_effect(), so they can be built as data.

signal flag_changed(flag: String, value: Variant)
signal reputation_changed(track: String, value: int)
signal composure_changed(value: int, max_value: int)
signal clock_changed(minutes: int)
signal event_completed(event_id: String)

const SAVE_PATH := "user://rampart_save.json"
const SAVE_VERSION := 1

## Reputation tracks from section 16. Community is per district.
const REPUTATION_TRACKS := ["fto", "squad", "command", "media", "federal"]
const DISTRICTS := [
	"macarthur_park", "pico_union", "echo_park", "historic_filipinotown", "lafayette_park", "silver_lake",
]

## Watches from section 14. Start times are the shift's arrival.
const WATCHES := {"day": 6 * 60, "pm": 14 * 60 + 30, "morning": 22 * 60 + 30}

## Placeholder start for the vertical slice: the PM watch from the section 8 example shift,
## Saturday, July 10, 2010. The real calendar starts at graduation (ST-01) once that is built.
const SLICE_START := {"year": 2010, "month": 7, "day": 10, "minutes": 14 * 60 + 30, "watch": "pm"}

var officer: Officer
var call_sign := "2A43"
var flags := {}
var reputation := {}
var community := {}
var relationships := {}
var completed_events := {}
var date := {}
var minutes := 0
var watch := "pm"
var paused := false


func _ready() -> void:
	new_game()


func new_game(start_officer: Officer = null) -> void:
	officer = start_officer if start_officer else Officer.sample_combat_veteran()
	flags.clear()
	completed_events.clear()
	relationships.clear()
	reputation.clear()
	community.clear()
	for t in REPUTATION_TRACKS:
		reputation[t] = 0
	for d in DISTRICTS:
		community[d] = 0
	date = {"year": SLICE_START.year, "month": SLICE_START.month, "day": SLICE_START.day}
	minutes = SLICE_START.minutes
	watch = SLICE_START.watch


# ---------------------------------------------------------------- flags

func has_flag(flag: String) -> bool:
	return bool(flags.get(flag, false))


func get_flag(flag: String, default: Variant = null) -> Variant:
	return flags.get(flag, default)


func set_flag(flag: String, value: Variant = true) -> void:
	flags[flag] = value
	flag_changed.emit(flag, value)


func add_to_flag(flag: String, amount: int = 1) -> void:
	set_flag(flag, int(flags.get(flag, 0)) + amount)


# ---------------------------------------------------------------- reputation and relationships

func change_reputation(track: String, delta: int) -> void:
	if track.begins_with("community:"):
		var district := track.trim_prefix("community:")
		assert(district in DISTRICTS, "Unknown district %s" % district)
		community[district] = int(community.get(district, 0)) + delta
		reputation_changed.emit(track, community[district])
		return
	assert(track in REPUTATION_TRACKS, "Unknown reputation track %s" % track)
	reputation[track] = int(reputation.get(track, 0)) + delta
	reputation_changed.emit(track, reputation[track])


## Relationship meters from section 13: spark, trust and strain per person; approval for colleagues.
func relationship(person: String) -> Dictionary:
	if not relationships.has(person):
		relationships[person] = {"approval": 0, "spark": 0, "trust": 0, "strain": 0, "stage": "acquaintance"}
	return relationships[person]


func change_relationship(person: String, meter: String, delta: int) -> void:
	var r := relationship(person)
	assert(r.has(meter) and meter != "stage", "Unknown relationship meter %s" % meter)
	r[meter] = int(r[meter]) + delta


# ---------------------------------------------------------------- composure

func change_composure(delta: int) -> void:
	officer.change_composure(delta)
	composure_changed.emit(officer.composure, officer.max_composure())


# ---------------------------------------------------------------- clock

func advance_minutes(amount: int) -> void:
	minutes += amount
	while minutes >= 24 * 60:
		minutes -= 24 * 60
		_next_day()
	clock_changed.emit(minutes)


func _next_day() -> void:
	var dt := Time.get_unix_time_from_datetime_dict({"year": date.year, "month": date.month, "day": date.day, "hour": 12})
	var next := Time.get_datetime_dict_from_unix_time(dt + 86400)
	date = {"year": next.year, "month": next.month, "day": next.day}


func clock_text() -> String:
	return "%02d%02d" % [minutes / 60, minutes % 60]


func date_text() -> String:
	var dt := Time.get_unix_time_from_datetime_dict({"year": date.year, "month": date.month, "day": date.day, "hour": 12})
	var wd: int = Time.get_datetime_dict_from_unix_time(dt).weekday
	var days := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return "%s %s %d, %d" % [days[wd], months[date.month - 1], date.day, date.year]


# ---------------------------------------------------------------- events

func is_event_completed(event_id: String) -> bool:
	return completed_events.has(event_id)


func complete_event(event_id: String, outcome: String = "") -> void:
	completed_events[event_id] = outcome
	event_completed.emit(event_id)


## Applies one effect from scene data. Supported effects:
##   {"set_flag": "name"} or {"set_flag": "name", "value": x}
##   {"add_flag": "name", "amount": n}
##   {"reputation": "squad" | "community:pico_union", "delta": n}
##   {"relationship": "ortega", "meter": "approval", "delta": n}
##   {"composure": n}
##   {"minutes": n}
##   {"complete_event": "ST-06", "outcome": "booked"}
func apply_effect(effect: Dictionary) -> void:
	if effect.has("set_flag"):
		set_flag(effect.set_flag, effect.get("value", true))
	elif effect.has("add_flag"):
		add_to_flag(effect.add_flag, int(effect.get("amount", 1)))
	elif effect.has("reputation"):
		change_reputation(effect.reputation, int(effect.delta))
	elif effect.has("relationship"):
		change_relationship(effect.relationship, effect.meter, int(effect.delta))
	elif effect.has("composure"):
		change_composure(int(effect.composure))
	elif effect.has("minutes"):
		advance_minutes(int(effect.minutes))
	elif effect.has("complete_event"):
		complete_event(effect.complete_event, effect.get("outcome", ""))
	else:
		push_error("Unknown effect: %s" % effect)


func apply_effects(effects: Array) -> void:
	for e in effects:
		apply_effect(e)


## Conditions used by scene data: {"flag": "x"}, {"not_flag": "x"}, {"event_done": "ST-05"}.
func meets(condition: Dictionary) -> bool:
	if condition.has("flag"):
		return has_flag(condition.flag)
	if condition.has("not_flag"):
		return not has_flag(condition.not_flag)
	if condition.has("event_done"):
		return is_event_completed(condition.event_done)
	push_error("Unknown condition: %s" % condition)
	return false


func meets_all(conditions: Array) -> bool:
	for c in conditions:
		if not meets(c):
			return false
	return true


# ---------------------------------------------------------------- save and load

func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"officer": officer.to_dict(),
		"call_sign": call_sign,
		"flags": flags.duplicate(true),
		"reputation": reputation.duplicate(),
		"community": community.duplicate(),
		"relationships": relationships.duplicate(true),
		"completed_events": completed_events.duplicate(),
		"date": date.duplicate(),
		"minutes": minutes,
		"watch": watch,
		"campaign": get_node("/root/Campaign").to_dict() if has_node("/root/Campaign") else {},
	}


func from_dict(d: Dictionary) -> void:
	officer = Officer.from_dict(d.officer)
	call_sign = d.get("call_sign", call_sign)
	flags = d.get("flags", {}).duplicate(true)
	reputation = d.get("reputation", {}).duplicate()
	community = d.get("community", {}).duplicate()
	relationships = d.get("relationships", {}).duplicate(true)
	completed_events = d.get("completed_events", {}).duplicate()
	var dd: Dictionary = d.get("date", date)
	date = {"year": int(dd.year), "month": int(dd.month), "day": int(dd.day)}
	minutes = int(d.get("minutes", minutes))
	watch = d.get("watch", watch)
	if has_node("/root/Campaign") and not d.get("campaign", {}).is_empty():
		get_node("/root/Campaign").from_dict(d.campaign)


func save_game(path: String = SAVE_PATH) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict(), "\t"))
	return OK


func load_game(path: String = SAVE_PATH) -> Error:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return ERR_PARSE_ERROR
	from_dict(parsed)
	return OK
