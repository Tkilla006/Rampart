extends Node
## The strategic layer, ported from X-COM's Geoscape: the division map runs in compressed time,
## calls for service appear like UFO sightings, your car is the interceptor, the station is the base,
## the roster is your squad, and the monthly review stands in for the funding council (design section 8).

signal call_added(call: Dictionary)
signal call_changed(call: Dictionary)
signal car_arrived(call: Dictionary)
signal news(title: String, text: String)
signal month_report(report: Dictionary)
signal game_over(ending: Dictionary)
signal story_event(entry: Dictionary)
signal day_off_request(request: Dictionary)
signal scene_ready(call: Dictionary)

const CALL_TYPES := "res://data/strategic/call_types.json"
const PEOPLE := "res://data/strategic/people.json"
const CREATION := "res://data/strategic/creation.json"
const REASONS := "res://data/strategic/day_off_reasons.json"
const SCHEDULE := "res://data/strategic/story_schedule.json"

## Officer energy (0-6) and reliability, in the This Is the Police mold, tuned for Rampart.
const MAX_ENERGY := 6
const TIRED_ENERGY := 1
const REST_PER_DAY := 3
const ACCIDENT_EXHAUSTED := 0.10
const ACCIDENT_TIRED := 0.03
const ACCIDENT_HUNGOVER := 0.06
const DAY_OFF_CHANCE := 0.06

## X-COM time compression: game seconds per real second.
const SPEEDS := {"pause": 0, "5 sec": 5, "1 min": 60, "5 min": 300, "30 min": 1800, "1 hour": 3600, "1 day": 86400}

## Placeholder calendar (design 18 leaves the opening open): first shift Monday, March 1, 2010,
## PM watch, which puts the April quake, May Day and the summer on the clock.
const START := {"year": 2010, "month": 3, "day": 1}
const SHIFT_START := 14 * 60 + 30
const SHIFT_LENGTH := 10 * 60
const DUTY_DAYS := [1, 2, 3, 4]  # Monday to Thursday; Friday to Sunday off.
const CALL_MINUTES := 38.0
const PROBATION_MONTHS := 18

## Division geography on a unit square (x west to east, y north to south). Stylized, not surveyed.
const DISTRICT_SHAPES := {
	"silver_lake": [[0.0, 0.0], [0.42, 0.0], [0.42, 0.3], [0.0, 0.38]],
	"echo_park": [[0.42, 0.0], [1.0, 0.0], [1.0, 0.32], [0.42, 0.3]],
	"historic_filipinotown": [[0.42, 0.3], [1.0, 0.32], [1.0, 0.55], [0.5, 0.52]],
	"lafayette_park": [[0.0, 0.38], [0.42, 0.3], [0.5, 0.52], [0.45, 0.7], [0.0, 0.72]],
	"macarthur_park": [[0.5, 0.52], [1.0, 0.55], [1.0, 0.75], [0.45, 0.7]],
	"pico_union": [[0.0, 0.72], [0.45, 0.7], [1.0, 0.75], [1.0, 1.0], [0.0, 1.0]],
}
const STATION_POS := Vector2(0.7, 0.56)
const DIVISION_KM := Vector2(3.8, 2.6)

var active := false
var speed := "pause"
var call_types := {}
var districts := {}
var people := {}
var creation := {}
var roster := {}
var calls: Array = []
var car := {"id": "2A43", "pos": STATION_POS, "state": "available", "call": -1, "code": 2, "eta": 0.0, "from": STATION_POS}
var crew: Array[String] = ["player"]
var backup_crew: Array[String] = []
var elapsed_minutes := 0.0
var month_stats := {}
var history: Array = []
var overtime_budget := 200
var probation_rating := 0
var poor_months := 0
var ending := {}
var difficulty := {"ironman": false, "call_pressure": 1.0}
var fired_events := {}
var _pending_mission: TacMission = null
var _pending_call := {}
var _accum := 0.0
var _next_call_in := 30.0
var _next_id := 1
var rng := RandomNumberGenerator.new()
var volume := {}
var reasons: Array = []
var schedule: Array = []
var fired_story := {}
var _was_on_duty := false


func _ready() -> void:
	rng.randomize()
	_load_data()
	process_mode = Node.PROCESS_MODE_ALWAYS


func _load_data() -> void:
	var ct: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CALL_TYPES))
	call_types = ct.types
	districts = ct.districts
	people = JSON.parse_string(FileAccess.get_file_as_string(PEOPLE)).officers
	creation = JSON.parse_string(FileAccess.get_file_as_string(CREATION))
	volume = ct.get("volume", {})
	reasons = JSON.parse_string(FileAccess.get_file_as_string(REASONS)).reasons
	schedule = JSON.parse_string(FileAccess.get_file_as_string(SCHEDULE)).schedule


# ---------------------------------------------------------------- new game

## Starts a probation with the player's officer (already on GameState) and the assigned FTO.
func new_campaign(player_profile: Dictionary, fto_key: String) -> void:
	active = true
	speed = "pause"
	calls.clear()
	history.clear()
	fired_events.clear()
	ending = {}
	poor_months = 0
	probation_rating = 0
	overtime_budget = 200
	elapsed_minutes = 0.0
	_next_call_in = 25.0
	GameState.date = START.duplicate()
	GameState.minutes = SHIFT_START
	GameState.watch = "pm"
	roster.clear()
	roster["player"] = player_profile.duplicate(true)
	roster["player"]["key"] = "player"
	for k in people:
		var p: Dictionary = people[k].duplicate(true)
		p["key"] = k
		p["injured_days"] = 0
		roster[k] = p
	roster["player"]["injured_days"] = 0
	for k in roster:
		var r: Dictionary = roster[k]
		r["energy"] = int(r.get("energy", MAX_ENERGY))
		r["laziness"] = int(r.get("laziness", 0))
		r["drinker"] = bool(r.get("drinker", false))
		r["happiness"] = int(r.get("happiness", 7))
		r["happiness_threshold"] = int(r.get("happiness_threshold", 4))
		r["off_days"] = 0
		r["hungover"] = false
	roster["player"]["drinker"] = "bottle_problem" in player_profile.get("traits", [])
	fired_story.clear()
	_was_on_duty = false
	crew = ["player", fto_key]
	backup_crew = ["bailey", "duquette"]
	GameState.set_flag("fto", fto_key)
	car = {"id": "2A43", "pos": STATION_POS, "state": "available", "call": -1, "code": 2, "eta": 0.0, "from": STATION_POS}
	_reset_month()


func _reset_month() -> void:
	month_stats = {"calls": 0, "cleared": 0, "missed": 0, "arrests": 0, "score": 0, "rounds": 0, "civilian_harm": 0,
		"force_reviews": {"In policy": 0, "In policy, tactical debrief": 0, "Administrative disapproval": 0, "Out of policy": 0},
		"escalated": 0, "month": GameState.date.month, "year": GameState.date.year}


# ---------------------------------------------------------------- clock

func is_on_duty() -> bool:
	var wd := weekday()
	var m := GameState.minutes
	return wd in DUTY_DAYS and m >= SHIFT_START and m < SHIFT_START + SHIFT_LENGTH \
		or (wd - 1 + 7) % 7 in DUTY_DAYS and m < (SHIFT_START + SHIFT_LENGTH) - 24 * 60


func weekday() -> int:
	var t := Time.get_unix_time_from_datetime_dict({"year": GameState.date.year, "month": GameState.date.month, "day": GameState.date.day, "hour": 12})
	return Time.get_datetime_dict_from_unix_time(t).weekday


func set_speed(s: String) -> void:
	speed = s


func _process(delta: float) -> void:
	if not active or speed == "pause" or not is_cityscape():
		return
	var seconds := float(SPEEDS[speed]) * delta
	_accum += seconds / 60.0
	while _accum >= 1.0 and speed != "pause":
		_accum -= 1.0
		advance_minute()


func is_cityscape() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.name == "Cityscape"


## One game minute of the division: calls appear and escalate, the car drives, the calendar turns.
func advance_minute() -> void:
	var before_month: int = GameState.date.month
	var before_day: int = GameState.date.day
	GameState.advance_minutes(1)
	elapsed_minutes += 1.0
	if GameState.date.day != before_day:
		_new_day()
	if GameState.date.month != before_month:
		_monthly_review()
	if not active:
		return
	var on := is_on_duty()
	if on and not _was_on_duty:
		_start_shift()
	elif not on and _was_on_duty:
		_end_shift()
	_was_on_duty = on
	if on:
		_next_call_in -= 1.0 * float(difficulty.call_pressure) * volume_multiplier()
		if _next_call_in <= 0:
			spawn_call()
			_next_call_in = rng.randf_range(0.5, 1.5) * CALL_MINUTES
	_update_calls()
	_update_car()


## How busy the watch is: weekday, paydays and the probation ramp.
func volume_multiplier() -> float:
	var m := 1.0
	var wd: Array = volume.get("weekday", [1, 1, 1, 1, 1, 1, 1])
	m *= float(wd[weekday()])
	if int(GameState.date.day) in [1, 15]:
		m *= float(volume.get("payday", 1.0))
	m *= 1.0 + float(volume.get("month_ramp", 0.0)) * months_elapsed()
	return m


func days_elapsed() -> int:
	var t0 := Time.get_unix_time_from_datetime_dict({"year": START.year, "month": START.month, "day": START.day, "hour": 12})
	var t1 := Time.get_unix_time_from_datetime_dict({"year": GameState.date.year, "month": GameState.date.month, "day": GameState.date.day, "hour": 12})
	return int((t1 - t0) / 86400)


# ---------------------------------------------------------------- personnel: energy and reliability

## Roll call: who is late, who is hungover, who wants the day off (This Is the Police style personnel).
func _start_shift() -> void:
	for k in crew + backup_crew:
		var r: Dictionary = roster.get(k, {})
		if r.is_empty():
			continue
		r.hungover = false
		var unhappy := int(r.happiness) < int(r.happiness_threshold)
		if bool(r.drinker) and (unhappy or int(r.energy) <= 2) and rng.randf() < 0.35:
			r.hungover = true
			news.emit("Roll call", "%s shows up hungover." % _display(k))
		var late := 0.08 * int(r.laziness) * (2.0 if unhappy else 1.0)
		if k in crew and k != "player" and rng.randf() < late and car.state == "available":
			car.state = "busy"
			car.busy_left = 30.0
			news.emit("Roll call", "%s is late. 2A43 can't go in service for half an hour." % _display(k))
	_day_off_requests()
	_story_check()


## End of watch: everyone who worked loses energy.
func _end_shift() -> void:
	for k in crew:
		var r: Dictionary = roster.get(k, {})
		if not r.is_empty():
			r.energy = maxi(0, int(r.energy) - 1)
			r.hungover = false


func _day_off_requests() -> void:
	for k in crew + backup_crew:
		if k == "player" or rng.randf() >= DAY_OFF_CHANCE:
			continue
		var reason: Dictionary = reasons[rng.randi_range(0, reasons.size() - 1)]
		day_off_request.emit({"key": k, "name": _display(k), "reason": reason.text, "severe": reason.severe})
		return


func answer_day_off(key: String, granted: bool, severe: bool) -> void:
	var r: Dictionary = roster.get(key, {})
	if r.is_empty():
		return
	if granted:
		r.off_days = 1
		r.happiness = mini(10, int(r.happiness) + 1)
		r.energy = mini(MAX_ENERGY, int(r.energy) + 1)
	else:
		r.happiness = maxi(0, int(r.happiness) - (4 if severe else 2))
		GameState.change_relationship(key, "approval", -2 if severe else -1)


func is_available(key: String) -> bool:
	var r: Dictionary = roster.get(key, {})
	return int(r.get("injured_days", 0)) <= 0 and int(r.get("off_days", 0)) <= 0


func energy_label(key: String) -> String:
	var e := int(roster.get(key, {}).get("energy", MAX_ENERGY))
	return ["Exhausted", "Tired", "Worn", "Worn", "Rested", "Rested", "Fresh"][clampi(e, 0, 6)]


func _display(key: String) -> String:
	if key == "player":
		return GameState.officer.display_name
	return String(roster.get(key, {}).get("name", key))


## Responding Code 3 with a tired or hungover crew risks a crash on the way.
func accident_chance() -> float:
	var worst := 0.0
	for k in available_crew():
		var r: Dictionary = roster[k]
		var c := 0.0
		if int(r.energy) <= 0:
			c = ACCIDENT_EXHAUSTED
		elif int(r.energy) <= TIRED_ENERGY:
			c = ACCIDENT_TIRED
		if bool(r.get("hungover", false)):
			c = maxf(c, ACCIDENT_HUNGOVER)
		worst = maxf(worst, c)
	return worst


## Fixed story beats from design 17 come up on their day (story_schedule.json).
func _story_check() -> void:
	var day := days_elapsed()
	for entry in schedule:
		var id: String = entry.event
		if fired_story.has(id) or GameState.is_event_completed(id) or int(entry.day) > day:
			continue
		if entry.has("fto") and GameState.get_flag("fto", "") != entry.fto:
			continue
		if entry.has("requires_any") and not Array(entry.requires_any).any(func(f): return GameState.has_flag(f)):
			continue
		fired_story[id] = true
		story_event.emit(entry)
		return


## The player picked a branch on a story card: record it, set the flags it implies.
func resolve_story(entry: Dictionary, choice: String) -> Array[String]:
	var notes: Array[String] = []
	var id: String = entry.event
	GameState.complete_event(id, choice)
	for f in entry.get("always_flags", []):
		GameState.set_flag(f)
	var cf: Dictionary = entry.get("choice_flags", {})
	for needle in cf:
		if String(needle).to_lower() in choice.to_lower():
			GameState.set_flag(cf[needle])
	if entry.has("check"):
		var ck: Dictionary = entry.check
		if not ck.has("fto") or GameState.get_flag("fto", "") == ck.fto:
			var res := GameState.officer.check_skill(ck.skill, 0, rng)
			notes.append("%s: %s" % [String(ck.skill).capitalize(), res.describe()])
			if res.success:
				GameState.set_flag(ck.flag)
	if entry.has("composure"):
		GameState.change_composure(int(entry.composure))
	return notes


## Splits an event's branches text from design 17 into choices for a story card.
static func branch_choices(branches: String) -> Array[String]:
	var out: Array[String] = []
	var text := branches.trim_suffix(".")
	for part in text.split(";"):
		var p := part.strip_edges()
		p = p.replace(", or ", ", ").replace(" or ", ", ")
		for bit in p.split(", "):
			var b := bit.strip_edges()
			if b.length() > 2:
				out.append(b.substr(0, 1).to_upper() + b.substr(1))
	if out.size() > 5:
		out.resize(5)
	if out.is_empty():
		out.append("Continue")
	return out


func skip_to_next_shift() -> void:
	var guard := 0
	while not is_on_duty() and guard < 24 * 60 * 4 and active:
		advance_minute()
		guard += 1


func _new_day() -> void:
	var working := is_on_duty() or weekday() in DUTY_DAYS
	for k in roster:
		var r: Dictionary = roster[k]
		if int(r.get("off_days", 0)) > 0:
			r.off_days = int(r.off_days) - 1
		if not working or not k in crew:
			r.energy = mini(MAX_ENERGY, int(r.get("energy", MAX_ENERGY)) + REST_PER_DAY)
		if int(r.get("injured_days", 0)) > 0:
			r["injured_days"] = int(r.injured_days) - 1
			if int(r.injured_days) == 0:
				news.emit("Back on duty", "%s is cleared to return to patrol." % r.name)
	if GameState.officer.composure < GameState.officer.max_composure():
		GameState.change_composure(2)
	_calendar_events()
	if months_elapsed() >= PROBATION_MONTHS:
		_end_game({"id": "probation_complete", "title": "Police Officer II",
			"text": "Eighteen months. You made it through probation."})


func months_elapsed() -> int:
	return (int(GameState.date.year) - START.year) * 12 + int(GameState.date.month) - START.month


## Dated calendar and world events from design 17.5 surface as news when the clock reaches them.
func _calendar_events() -> void:
	var key := "%d-%02d-%02d" % [GameState.date.year, GameState.date.month, GameState.date.day]
	var dated := {"2010-04-04": "CW-01", "2010-05-01": "CW-02", "2010-06-17": "CW-03", "2010-07-04": "CW-05",
		"2010-09-27": "CW-08", "2010-10-31": "CW-11", "2010-11-01": "CW-12", "2010-11-25": "CW-13",
		"2010-12-24": "CW-14", "2010-12-31": "CW-15"}
	if dated.has(key) and not fired_events.has(dated[key]):
		var e: Dictionary = EventLibrary.get_event(dated[key])
		fired_events[dated[key]] = true
		news.emit(e.title, e.what_happens)


# ---------------------------------------------------------------- calls

func _pick_weighted(weights: Dictionary) -> String:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var r := rng.randf() * total
	for k in weights:
		r -= float(weights[k])
		if r <= 0:
			return k
	return weights.keys()[0]


## A new call for service: district, type and the truth behind the dispatch information.
func spawn_call(type_id: String = "", district: String = "") -> Dictionary:
	if district == "":
		district = DISTRICT_SHAPES.keys()[rng.randi_range(0, DISTRICT_SHAPES.size() - 1)]
	if type_id == "":
		var w := {}
		for t in call_types:
			var ct: Dictionary = call_types[t]
			var dw: float = float(districts[district].weights.get(t, 1.0))
			w[t] = float(ct.weight) * dw * float(ct.watches.get(GameState.watch, 1.0))
		type_id = _pick_weighted(w)
	var t: Dictionary = call_types[type_id]
	# The worse truths behind a call get more likely as the probation goes on.
	var odds := {}
	var ramp := 1.0 + float(volume.get("danger_ramp", 0.0)) * months_elapsed()
	for i in t.truth.size():
		var danger := _truth_danger(t.truth[i])
		odds[str(i)] = float(t.truth[i].odds) * pow(ramp, maxi(0, danger - 3))
	var truth_index := int(_pick_weighted(odds))
	var false_alarm := rng.randf() < float(t.get("false_alarm", 0.0))
	# Misleading dispatch: some false alarms are flagged as pranks, and so are some real calls.
	var note := ""
	if false_alarm and rng.randf() < 0.5 or not false_alarm and rng.randf() < 0.12:
		note = "Caller hung up. Possible prank."
	var c := {
		"id": _next_id, "type": type_id, "label": t.label, "priority": int(t.priority), "district": district,
		"pos": _random_point(district), "created": elapsed_minutes, "status": "pending",
		"truth_index": truth_index, "address": _address(district), "false_alarm": false_alarm, "note": note,
	}
	_next_id += 1
	calls.append(c)
	month_stats.calls += 1
	call_added.emit(c)
	if speed != "pause" and int(c.priority) >= 2:
		speed = "pause"
	return c


static func _truth_danger(truth: Dictionary) -> int:
	var worst := 0
	for sp in truth.get("suspects", []):
		var d: int = {"compliant": 0, "passive": 1, "active": 2, "assaultive": 3, "deadly": 4}.get(sp.get("disposition", "passive"), 1)
		if sp.get("weapon") != null or sp.get("hidden") != null:
			d += 1
		worst = maxi(worst, d)
	return worst


func _random_point(district: String) -> Vector2:
	var poly := PackedVector2Array()
	for p in DISTRICT_SHAPES[district]:
		poly.append(Vector2(p[0], p[1]))
	for i in 60:
		var p := Vector2(rng.randf(), rng.randf())
		if Geometry2D.is_point_in_polygon(p, poly):
			return p
	return poly[0].lerp(poly[2], 0.5)


const STREETS := ["Alvarado St", "W 6th St", "Wilshire Blvd", "Union Ave", "Hoover St", "Temple St", "Beverly Blvd",
	"Pico Blvd", "Olympic Blvd", "Bonnie Brae St", "Burlington Ave", "Coronado St", "Echo Park Ave", "Rampart Blvd"]


func _address(_district: String) -> String:
	return "%d %s" % [rng.randi_range(2, 29) * 100 + rng.randi_range(0, 99), STREETS[rng.randi_range(0, STREETS.size() - 1)]]


func pending_calls() -> Array:
	return calls.filter(func(c): return c.status in ["pending", "assigned"])


func get_call(id: int) -> Dictionary:
	for c in calls:
		if int(c.id) == id:
			return c
	return {}


## The pending queue (design 8): calls that wait escalate; calls that wait too long go to other units.
func _update_calls() -> void:
	for c in calls:
		if c.status != "pending":
			continue
		var t: Dictionary = call_types[c.type]
		var age: float = elapsed_minutes - float(c.created)
		var esc: String = t.get("escalates_to") if t.get("escalates_to") != null else ""
		if esc != "" and age >= float(t.escalate_minutes) and not c.get("escalated", false):
			c.escalated = true
			c.type = esc
			c.label = call_types[esc].label + " (escalated)"
			c.priority = int(call_types[esc].priority)
			c.truth_index = 0
			c.created = elapsed_minutes
			month_stats.escalated += 1
			call_changed.emit(c)
			news.emit("Call escalated", "%s at %s turned into a %s while it waited." % [t.label, c.address, call_types[esc].label])
		elif age >= float(t.expire_minutes):
			c.status = "taken_by_other"
			month_stats.missed += 1
			GameState.change_reputation("community:%s" % c.district, -1)
			if rng.randf() < 0.15:
				GameState.change_reputation("squad", -1)
				news.emit("Unit hurt", "The unit that took the %s you passed on came back with an officer hurt." % c.label)
			call_changed.emit(c)


func respond(call_id: int, code: int) -> bool:
	var c := get_call(call_id)
	if c.is_empty() or car.state != "available" or not is_on_duty():
		return false
	c.status = "assigned"
	car.state = "en_route"
	car.call = call_id
	car.code = code
	car.from = car.pos
	# Code 3 (lights and siren) is faster; using it on a low-priority call is noted by command.
	var km := _distance_km(car.pos, c.pos)
	var kmh := 45.0 if code == 3 else 28.0
	car.eta = km / kmh * 60.0
	car.travelled = 0.0
	if code == 3 and int(c.priority) <= 1:
		GameState.change_reputation("command", -1)
	if code == 3 and rng.randf() < accident_chance():
		car.eta = float(car.eta) + 20.0
		var hurt: String = available_crew()[rng.randi_range(0, available_crew().size() - 1)]
		roster[hurt].injured_days = int(roster[hurt].get("injured_days", 0)) + 2
		GameState.change_reputation("command", -1)
		news.emit("Collision", "Running Code 3 on no sleep, 2A43 clips a car at %s. %s is hurt; you're twenty minutes late." % [c.address, _display(hurt)])
	call_changed.emit(c)
	return true


func _distance_km(a: Vector2, b: Vector2) -> float:
	var d := (b - a) * DIVISION_KM
	return absf(d.x) + absf(d.y)


func _update_car() -> void:
	if car.state == "en_route":
		car.travelled = float(car.get("travelled", 0.0)) + 1.0
		var c := get_call(int(car.call))
		var t := clampf(float(car.travelled) / maxf(float(car.eta), 0.5), 0.0, 1.0)
		car.pos = Vector2(car.from).lerp(c.pos, t)
		if t >= 1.0:
			car.state = "on_scene"
			c.status = "on_scene"
			speed = "pause"
			car_arrived.emit(c)
	elif car.state == "busy":
		car.busy_left = float(car.get("busy_left", 0.0)) - 1.0
		if float(car.busy_left) <= 0:
			car.state = "available"
			news.emit("2A43 clear", "Booking and reports done. 2A43 is back in service.")
	elif car.state == "returning":
		car.state = "available"


# ---------------------------------------------------------------- missions

func officer_record(key: String) -> Dictionary:
	return roster.get(key, {})


func officer_from_record(r: Dictionary) -> Officer:
	if r.get("key", "") == "player":
		return GameState.officer
	var o := Officer.new()
	for a in r.attributes:
		o.attributes[a] = int(r.attributes[a])
	for s in r.skills:
		o.skills[s] = int(r.skills[s])
	for h in r.get("habits", []):
		o.habits.append(Habit.make(h[0], int(h[1])))
	o.composure = o.max_composure()
	return o


func tac_unit_for(key: String) -> TacUnit:
	var r := officer_record(key)
	var o := officer_from_record(r)
	var extra := {"loadout": r.get("loadout", "patrol"), "rank": r.get("rank", "Police Officer I"),
		"traits": r.get("traits", []), "background": creation.backgrounds.get(r.get("background", ""), {}),
		"boosted": r.get("boosted", false), "hungover": r.get("hungover", false), "look": r.get("look", "officer"),
		"energy": int(r.get("energy", MAX_ENERGY))}
	var display: String = r.get("name", key)
	if key == "player":
		display = GameState.officer.display_name
	elif r.get("role", "") in ["fto", "squad", "classmate"]:
		display = display.split(" ")[-1].replace("\"", "")
	return TacUnit.from_officer(o, key, display, extra)


func available_crew() -> Array:
	return crew.filter(func(k): return is_available(k))


## Builds the battlescape for the call the car arrived at, from the true situation behind it.
func begin_mission(call_id: int) -> TacMission:
	var c := get_call(call_id)
	var t: Dictionary = call_types[c.type]
	var truth: Dictionary = t.truth[int(c.truth_index)].duplicate(true)
	if c.get("escalated", false):
		for s in truth.suspects:
			s.disposition = "assaultive" if s.disposition in ["passive", "active"] else s.disposition
	var squad: Array = []
	for k in available_crew():
		squad.append(tac_unit_for(k))
	if squad.is_empty():
		squad.append(tac_unit_for("player"))
	var backup: Array = []
	for k in backup_crew:
		if int(roster.get(k, {}).get("injured_days", 0)) <= 0:
			backup.append(tac_unit_for(k))
	var call := {"id": c.id, "type": c.type, "label": c.label, "map": t.map, "basis": t.basis, "truth": truth,
		"watch": GameState.watch, "district": c.district, "address": c.address}
	var m := MissionFactory.build(call, squad, 0, backup)
	m.difficulty = difficulty.duplicate()
	_pending_mission = m
	_pending_call = c
	return m


## The officers on scene for a text scene: name, Rampart character sheet, what they carry.
func scene_crew() -> Array:
	var out: Array = []
	for k in available_crew():
		var r: Dictionary = roster[k]
		var items: Array = []
		var l := ItemDB.loadout(r.get("loadout", "patrol"))
		items.append(l.get("right_hand", ""))
		items.append_array(l.get("belt", []))
		var o := officer_from_record(r)
		if bool(r.get("hungover", false)) or int(r.get("energy", MAX_ENERGY)) <= TIRED_ENERGY:
			# Hungover or exhausted: thinking goes first (design 5, Fatigue). Work on a copy.
			o = Officer.from_dict(o.to_dict())
			o.composure = o.max_composure() / 3
		out.append({"key": k, "name": _display(k), "officer": o, "items": items})
	return out


## Reading the scene on approach (design 8): Perception and Streetwise can tell dispatch got it wrong.
func approach_hint(call_id: int) -> String:
	var c := get_call(call_id)
	var best := 0
	for m in scene_crew():
		best = maxi(best, (m.officer as Officer).skill_chance("streetwise"))
	if not Check.make(best, rng).success:
		return ""
	if c.get("false_alarm", false):
		return "Rolling up, it's quiet. Nobody waiting, no crowd. This may be nothing."
	var t: Dictionary = call_types[c.type].truth[int(c.truth_index)]
	if t.has("true_label"):
		return "Something's off. This doesn't look like what dispatch said: %s." % String(t.true_label).to_lower()
	if _truth_danger(t) >= 4:
		return "People are running away from the address, not toward it."
	return ""


func call_scene(call_id: int) -> CallScene:
	var c := get_call(call_id)
	var data := CallScene.load_for(c.type)
	if data.is_empty():
		return null
	var cs := CallScene.new(data, c, scene_crew())
	cs.start()
	return cs


## A call settled on scene, without the battlescape: points, reputation, injuries, time, energy.
func apply_scene_result(call_id: int, r: Dictionary) -> Array[String]:
	var notes: Array[String] = []
	var c := get_call(call_id)
	var code: String = r.result
	var fx: Dictionary = CallScene.RESULT_EFFECTS[code]
	c.status = "cleared" if code != "escaped" else "lost"
	if r.get("note", "") != "":
		notes.append(r.note)
	month_stats.cleared += 1 if code != "escaped" else 0
	month_stats.arrests += 1 if code == "arrest" else 0
	month_stats.score += int(fx.score)
	if int(fx.squad) != 0:
		GameState.change_reputation("squad", int(fx.squad))
	if int(fx.community) != 0:
		GameState.change_reputation("community:%s" % c.district, int(fx.community))
	var injury := int(r.get("injury", 0))
	if injury > 0 and roster.has(r.get("officer", "")):
		var who: Dictionary = roster[r.officer]
		who.injured_days = int(who.get("injured_days", 0)) + CallScene.INJURY_DAYS[injury]
		who.happiness = maxi(0, int(who.happiness) - 1)
		notes.append("%s is %s: %d days of light duty." % [r.officer_name, CallScene.INJURY_NAMES[injury], CallScene.INJURY_DAYS[injury]])
	var fto: String = GameState.get_flag("fto", "")
	if fto != "":
		var approval := 1 if int(fx.score) >= 15 else (-1 if int(fx.score) < 0 else 0)
		GameState.change_relationship(fto, "approval", approval)
		GameState.change_reputation("fto", approval)
	var label: String = {"arrest": "Arrest", "cite": "Citation", "warn": "Warning", "report": "Report only", "hold_5150": "5150 hold",
		"cleared": "Cleared", "escaped": "Suspect escaped", "false_alarm": "False alarm"}.get(code, code)
	history.append({"date": GameState.date_text(), "label": "%s: %s" % [c.label, label], "score": fx.score,
		"rating": label, "success": code != "escaped"})
	_spend_call_time(int(fx.minutes))
	notes.append("%s. %d minutes on scene and paperwork." % [label, int(fx.minutes)])
	return notes


func _spend_call_time(minutes: int) -> void:
	car.state = "busy"
	car.busy_left = float(minutes)
	car.pos = STATION_POS if minutes >= 60 else car.pos
	if minutes >= 90:
		for k in available_crew():
			roster[k].energy = maxi(0, int(roster[k].energy) - 1)


func take_pending_mission() -> TacMission:
	var m := _pending_mission
	_pending_mission = null
	return m


## Folds a debrief back into the campaign: reputation, Composure, injuries, skills, flags, the clock.
func apply_result(result: Dictionary) -> Array[String]:
	var notes: Array[String] = []
	var c := get_call(int(result.call.get("id", -1)))
	if not c.is_empty():
		c.status = "cleared" if result.success else "lost"
	month_stats.cleared += 1 if result.success else 0
	month_stats.arrests += int(result.arrested)
	month_stats.score += int(result.score)
	month_stats.rounds += int(result.rounds_fired)
	month_stats.civilian_harm += int(result.civilians_hurt) + int(result.civilians_dead)
	history.append({"date": GameState.date_text(), "label": result.call.get("label", ""), "score": result.score,
		"rating": result.rating, "success": result.success})
	var district: String = result.call.get("district", "macarthur_park")
	# Reputation tracks (design 16).
	GameState.change_reputation("command", clampi(int(result.score) / 30, -3, 3))
	GameState.change_reputation("squad", 1 if int(result.arrested) > 0 else 0)
	var community := 1 if result.success and int(result.rounds_fired) == 0 else 0
	community -= int(result.civilians_hurt) + 2 * int(result.civilians_dead) + int(result.suspects_dead)
	if community != 0:
		GameState.change_reputation("community:%s" % district, community)
	if int(result.rounds_fired) > 0:
		GameState.change_reputation("media", -1)
	var fto: String = GameState.get_flag("fto", "")
	var worst := 0
	for r in result.reviews:
		month_stats.force_reviews[r.outcome] = int(month_stats.force_reviews.get(r.outcome, 0)) + 1
		worst = maxi(worst, int(r.severity))
	if fto != "":
		var approval: int = {"Excellent": 2, "Good": 1, "Fair": 0, "Poor": -1, "Terrible": -2}.get(result.rating, 0)
		if fto == "whitfield" and int(result.rounds_fired) > 0 and result.success:
			approval += 1
		if fto == "ortega" and worst >= 2:
			approval -= 2
		if fto == "arakawa" and int(result.suspects_dead) > 0:
			approval -= 2
		GameState.change_relationship(fto, "approval", approval)
		GameState.change_reputation("fto", approval)
	# Officers: injuries, Composure, trauma and skills gained from what they did (no XP for kills).
	var traumatic := int(result.civilians_dead) > 0 or int(result.suspects_dead) > 0
	for o in result.officers:
		var r: Dictionary = roster.get(o.key, {})
		if r.is_empty():
			continue
		r.happiness = clampi(int(r.get("happiness", 7)) + (1 if result.success else -1) - (1 if int(o.health) < int(o.health_max) else 0), 0, 10)
		if (traumatic or int(o.health) < int(o.health_max) / 2) and not bool(r.get("drinker", false)) and rng.randf() < 0.1:
			r.drinker = true
			notes.append("%s has started drinking after shifts." % o.name)
		var lost := int(o.health_max) - int(o.health)
		if lost > 0:
			r["injured_days"] = int(r.get("injured_days", 0)) + maxi(1, lost / 2)
			notes.append("%s: %d days of light duty." % [o.name, r.injured_days])
		var rec: Dictionary = o.record
		if o.key == "player":
			var shock := 3 + int(rec.get("damage_taken", 0)) / 4 + int(rec.get("shots", 0)) * 2
			GameState.change_composure(-shock)
			if int(rec.get("shots", 0)) > 0 and int(rec.get("hits", 0)) > 0:
				GameState.add_to_flag("ois_count")
				notes.append("Officer-involved shooting: you sit at a desk while Force Investigation reviews it.")
		var gains := {"defensive_tactics": rec.get("arrests", 0), "de_escalation": rec.get("commands", 0),
			"first_aid": rec.get("aid", 0)}
		for skill in gains:
			if int(gains[skill]) > 0 and rng.randf() < 0.25 + 0.1 * int(gains[skill]):
				var off := officer_from_record(r)
				var now := off.skill(skill)
				if now < 5:
					off.skills[skill] = now + 1
					if o.key != "player":
						r.skills[skill] = now + 1
					notes.append("%s improves at %s (%d)." % [o.name, skill.replace("_", " "), now + 1])
	# Time on scene and the paperwork after: booking eats the shift (design 6.2, 8).
	var minutes_used := int(result.turns) * 2 + 20 + int(result.arrested) * 75 + (60 if int(result.rounds_fired) > 0 else 0)
	_spend_call_time(minutes_used)
	car.pos = STATION_POS
	notes.append("Scene, booking and reports: %d minutes." % minutes_used)
	if difficulty.get("ironman", false):
		for o in result.officers:
			if o.key == "player" and o.status == "dead":
				_end_game({"id": "end_of_watch", "title": "End of Watch", "text": "Killed in the line of duty."})
	return notes


# ---------------------------------------------------------------- monthly review (the funding council)

func _monthly_review() -> void:
	var s := month_stats
	var rep := {
		"month": "%d-%02d" % [s.year, s.month], "calls": s.calls, "cleared": s.cleared, "missed": s.missed,
		"arrests": s.arrests, "score": s.score, "rounds": s.rounds, "harm": s.civilian_harm, "escalated": s.escalated,
		"force_reviews": s.force_reviews.duplicate(), "community": GameState.community.duplicate(),
		"reputation": GameState.reputation.duplicate(),
	}
	var rating: int = int(s.score) / 10 + int(s.cleared) - int(s.missed) - 3 * int(s.force_reviews.get("Out of policy", 0)) \
		- int(s.force_reviews.get("Administrative disapproval", 0)) + int(GameState.reputation.get("fto", 0)) / 3
	var grade := "Satisfactory"
	if rating >= 8:
		grade = "Outstanding"
	elif rating >= 3:
		grade = "Good"
	elif rating < -6:
		grade = "Failing"
	elif rating < 0:
		grade = "Needs improvement"
	rep["grade"] = grade
	var budget := clampi(150 + rating * 15, 50, 400)
	overtime_budget += budget
	rep["budget"] = budget
	poor_months = poor_months + 1 if grade == "Failing" else 0
	rep["warning"] = ""
	if poor_months == 1:
		rep.warning = "Your FTO's evaluations are failing. Another month like this and your probation is under review."
	month_report.emit(rep)
	history.append({"date": GameState.date_text(), "label": "Monthly review: %s" % grade, "score": s.score, "rating": grade, "success": grade != "Failing"})
	if poor_months >= 2:
		_end_game({"id": "washout", "title": "Washed out", "text": "Field training failed after extensions. The department lets you go."})
	_reset_month()


func _end_game(e: Dictionary) -> void:
	if not ending.is_empty():
		return
	ending = e
	active = false
	speed = "pause"
	game_over.emit(e)


# ---------------------------------------------------------------- station spending

## Range time (design 4, advancement): ammo out of your own pocket, a day off spent at the range.
func range_time() -> String:
	if overtime_budget < 60:
		return "Not enough money for range time."
	overtime_budget -= 60
	for i in 8 * 60:
		advance_minute()
	var o := GameState.officer
	if rng.randf() < 0.35 and o.skill("firearms") < 5:
		o.skills["firearms"] = o.skill("firearms") + 1
		return "Range day. Your grouping tightens: Firearms %d." % o.skill("firearms")
	return "Range day. Ammo spent, nothing much changes yet."


func set_loadout(key: String, loadout: String) -> void:
	if roster.has(key):
		roster[key]["loadout"] = loadout


# ---------------------------------------------------------------- save and load

func to_dict() -> Dictionary:
	var cs: Array = []
	for c in calls:
		var d: Dictionary = c.duplicate(true)
		d.pos = [c.pos.x, c.pos.y]
		cs.append(d)
	var cr: Dictionary = car.duplicate(true)
	cr.pos = [car.pos.x, car.pos.y]
	cr.from = [Vector2(car.from).x, Vector2(car.from).y]
	return {"active": active, "roster": roster.duplicate(true), "calls": cs, "car": cr, "crew": Array(crew),
		"backup_crew": Array(backup_crew), "elapsed": elapsed_minutes, "month_stats": month_stats.duplicate(true),
		"history": history.duplicate(true), "budget": overtime_budget, "poor_months": poor_months,
		"difficulty": difficulty.duplicate(), "fired_events": fired_events.duplicate(), "next_id": _next_id, "ending": ending,
		"fired_story": fired_story.duplicate(), "was_on_duty": _was_on_duty}


func from_dict(d: Dictionary) -> void:
	active = d.get("active", false)
	roster = d.get("roster", {}).duplicate(true)
	calls.clear()
	for c in d.get("calls", []):
		var cc: Dictionary = c.duplicate(true)
		cc.pos = Vector2(c.pos[0], c.pos[1])
		cc.id = int(c.id)
		calls.append(cc)
	car = d.get("car", car).duplicate(true)
	car.pos = Vector2(car.pos[0], car.pos[1])
	car.from = Vector2(car.from[0], car.from[1])
	crew.assign(d.get("crew", ["player"]))
	backup_crew.assign(d.get("backup_crew", []))
	elapsed_minutes = float(d.get("elapsed", 0.0))
	month_stats = d.get("month_stats", month_stats).duplicate(true)
	history = d.get("history", []).duplicate(true)
	overtime_budget = int(d.get("budget", 200))
	poor_months = int(d.get("poor_months", 0))
	difficulty = d.get("difficulty", difficulty).duplicate()
	fired_events = d.get("fired_events", {}).duplicate()
	_next_id = int(d.get("next_id", 1))
	ending = d.get("ending", {})
	fired_story = d.get("fired_story", {}).duplicate()
	_was_on_duty = d.get("was_on_duty", false)
	speed = "pause"
