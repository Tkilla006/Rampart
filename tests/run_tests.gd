extends Node
## Headless test runner. Runs as a scene so the autoloads exist:
##   godot --headless --path . res://tests/run_tests.tscn
## Exits with code 1 if any assertion fails.

## Flags an event reads that no scripted event sets yet. Each is an open gap in design section 17.
const KNOWN_UNSET_FLAGS := {
	"saw_camera": "DC-04 reads it as coming from another FTO's passing mention; no event sets it yet",
}

var failures := 0
var passes := 0
var _current := ""


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var gs: Node = get_node("/root/GameState")
	var lib: Node = get_node("/root/EventLibrary")
	for t in [
		"checks", "officer_sample_build", "composure_and_stress", "habits", "creation_rules",
		"game_state", "save_load", "event_library", "scenes", "iso", "street_map", "back_seat_playthrough",
	]:
		_current = t
		gs.new_game()
		call("test_" + t, gs, lib)
	print("\n%d passed, %d failed" % [passes, failures])
	get_tree().quit(1 if failures > 0 else 0)


func expect(cond: bool, what: String) -> void:
	if cond:
		passes += 1
	else:
		failures += 1
		printerr("FAIL [%s] %s" % [_current, what])


func expect_eq(actual: Variant, expected: Variant, what: String) -> void:
	expect(actual == expected, "%s: expected %s, got %s" % [what, expected, actual])


# ---------------------------------------------------------------- section 4: checks

func test_checks(_gs, _lib) -> void:
	# The worked example: Perception 6, Evidence 2 = 50%; flashlight +5, trampled scene -15 -> 40%.
	expect_eq(Check.chance_for(6, 2), 50, "base chance")
	expect_eq(Check.chance_for(6, 2, 5 - 15), 40, "chance with modifiers")
	var c := Check.resolve(50, 5)
	expect(c.success and c.clean, "roll at 10% of chance is a clean success")
	c = Check.resolve(50, 6)
	expect(c.success and not c.clean, "roll just above 10% is a plain success")
	expect(Check.resolve(50, 50).success, "roll equal to chance succeeds")
	expect(not Check.resolve(50, 51).success, "roll above chance fails")
	expect(not Check.resolve(150, 95).success, "95 always fails")
	expect(not Check.resolve(150, 100).success, "100 always fails")
	expect(Check.resolve(150, 94).success, "94 can succeed")
	expect_eq(Check.display_odds(150), 94, "displayed odds cap at 94")
	expect_eq(Check.display_odds(-20), 0, "displayed odds floor at 0")
	expect_eq(Check.override_chance(7, 3, 2, 10), 35 + 30 - 20 - 10, "override formula")
	# Aim +20, a range modifier of -10, half cover (-20), stress 30, moving 20.
	expect_eq(Check.hit_chance(6, 3, 20, -10, 20, 30, 20), 30 + 30 + 20 - 10 - 20 - 30 - 20, "hit formula")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 200:
		var r := Check.roll_d100(rng)
		expect(r >= 1 and r <= 100, "d100 in range")


func test_officer_sample_build(_gs, _lib) -> void:
	var o := Officer.sample_combat_veteran()
	# Section 4 sample build percentages that follow the formula.
	expect_eq(o.skill_chance("command_presence"), 50, "Command Presence 50%")
	expect_eq(o.skill_chance("de_escalation"), 25, "De-escalation 25%")
	expect_eq(o.skill_chance("report_writing"), 30, "Report Writing 30%")
	# The design lists Firearms 80%, but Perception 6 and Firearms 3 give 60% by its own formula.
	expect_eq(o.skill_chance("firearms"), 60, "Firearms by formula")
	expect_eq(o.max_composure(), 21, "Composure = Nerve x 3")


# ---------------------------------------------------------------- section 5: composure and habits

func test_composure_and_stress(_gs, _lib) -> void:
	var o := Officer.sample_combat_veteran()
	expect_eq(o.composure_band(), Officer.ComposureBand.FULL, "starts full")
	o.composure = 11
	expect_eq(o.composure_band(), Officer.ComposureBand.ABOVE_HALF, "11 of 21 is not below half")
	expect_eq(o.stress_penalty("report_writing"), 0, "no penalty above half")
	o.composure = 10
	expect_eq(o.composure_band(), Officer.ComposureBand.BELOW_HALF, "10 of 21 is below half")
	expect_eq(o.stress_penalty("report_writing"), 10, "-10 to Intellect skills below half")
	expect_eq(o.stress_penalty("de_escalation"), 10, "-10 to Empathy skills below half")
	expect_eq(o.stress_penalty("firearms"), 0, "Firearms holds below half")
	o.composure = 5
	expect_eq(o.composure_band(), Officer.ComposureBand.BELOW_QUARTER, "5 of 21 is below a quarter")
	expect_eq(o.stress_penalty("report_writing"), 20, "-20 to Intellect skills below a quarter")
	expect_eq(o.stress_penalty("firearms"), 10, "-10 to Firearms below a quarter")
	expect_eq(o.stress_penalty("command_presence"), 0, "Presence skills unaffected")
	o.change_composure(-100)
	expect_eq(o.composure_band(), Officer.ComposureBand.ZERO, "zero")
	o.change_composure(100)
	expect_eq(o.composure, 21, "composure clamps to max")


func test_habits(_gs, _lib) -> void:
	expect_eq(Habit.mode_for(Officer.ComposureBand.FULL), Habit.Mode.INSTINCT, "instinct above half")
	expect_eq(Habit.mode_for(Officer.ComposureBand.BELOW_HALF), Habit.Mode.OVERRIDE_OTHERS, "override others below half")
	expect_eq(Habit.mode_for(Officer.ComposureBand.BELOW_QUARTER), Habit.Mode.FIRES, "fires below a quarter")
	expect_eq(Habit.mode_for(Officer.ComposureBand.FULL, true), Habit.Mode.FIRES, "surprise fires regardless")
	var o := Officer.sample_combat_veteran()
	var h := o.habit_named("engage_the_threat")
	expect(h != null, "veteran has Engage the Threat")
	expect_eq(h.override_chance(o), 35 + 30 - 10, "override at full composure")
	o.composure = 5
	expect_eq(h.override_chance(o), 35 + 30 - 10 - 10 - Habit.FIRES_OVERRIDE_PENALTY, "override below a quarter")
	h.reinforce(); h.reinforce(); h.reinforce()
	expect_eq(h.strength, Habit.MAX_STRENGTH, "strength caps at 3")
	h.weaken(); h.weaken(); h.weaken()
	expect_eq(h.strength, Habit.MIN_STRENGTH, "strength floors at 1")
	for name in Habit.CATALOG:
		expect(Officer.SKILL_ATTRIBUTE.has(Habit.CATALOG[name].skill), "%s override skill exists" % name)


func test_creation_rules(_gs, _lib) -> void:
	var ok := {"fitness": 4, "nerve": 4, "perception": 3, "intellect": 2, "presence": 1, "empathy": 1}
	expect(Officer.validate_creation(ok).is_empty(), "15 points under the cap is valid")
	expect(Officer.validate_creation(ok, {"fitness": 1}).is_empty(), "a +1 bonus to 7 is valid")
	expect(not Officer.validate_creation(ok, {"fitness": 2}).is_empty(), "7 + 2 exceeds 8")
	var over := {"fitness": 5, "nerve": 4, "perception": 2, "intellect": 2, "presence": 1, "empathy": 1}
	expect(not Officer.validate_creation(over).is_empty(), "8 before bonuses is invalid")
	var short := {"fitness": 4, "nerve": 4}
	expect(not Officer.validate_creation(short).is_empty(), "must spend all 15 points")


# ---------------------------------------------------------------- game state

func test_game_state(gs, _lib) -> void:
	expect(not gs.has_flag("calloway_noticed_you"), "flags start clear")
	gs.apply_effects([
		{"set_flag": "calloway_noticed_you"},
		{"add_flag": "ois_count"},
		{"add_flag": "ois_count"},
		{"reputation": "squad", "delta": 2},
		{"reputation": "community:pico_union", "delta": -1},
		{"relationship": "ortega", "meter": "approval", "delta": 3},
		{"composure": -4},
		{"complete_event": "ST-06", "outcome": "booked"},
	])
	expect(gs.has_flag("calloway_noticed_you"), "set_flag")
	expect_eq(gs.get_flag("ois_count"), 2, "add_flag counts")
	expect_eq(gs.reputation.squad, 2, "squad reputation")
	expect_eq(gs.community.pico_union, -1, "community reputation per district")
	expect_eq(gs.relationship("ortega").approval, 3, "relationship approval")
	expect_eq(gs.officer.composure, 17, "composure effect")
	expect(gs.is_event_completed("ST-06"), "event completed")
	expect(gs.meets({"flag": "calloway_noticed_you"}), "flag condition")
	expect(gs.meets({"not_flag": "pocketed_spark"}), "not_flag condition")
	expect(gs.meets({"event_done": "ST-06"}), "event_done condition")
	expect_eq(gs.clock_text(), "1430", "slice starts at PM watch roll call")
	expect_eq(gs.date_text(), "Sat Jul 10, 2010", "July 10, 2010 was a Saturday")
	gs.advance_minutes(10 * 60)
	expect_eq(gs.clock_text(), "0030", "clock wraps past midnight")
	expect_eq(gs.date_text(), "Sun Jul 11, 2010", "date advances")


func test_save_load(gs, _lib) -> void:
	var path := "user://test_save.json"
	gs.set_flag("pocketed_spark")
	gs.change_reputation("media", -3)
	gs.officer.composure = 9
	gs.complete_event("ST-06", "pocketed")
	expect_eq(gs.save_game(path), OK, "save")
	gs.new_game()
	expect(not gs.has_flag("pocketed_spark"), "new game clears flags")
	expect_eq(gs.load_game(path), OK, "load")
	expect(gs.has_flag("pocketed_spark"), "flag restored")
	expect_eq(gs.reputation.media, -3, "reputation restored")
	expect_eq(gs.officer.composure, 9, "composure restored")
	expect_eq(gs.officer.habit_named("engage_the_threat").strength, 1, "habits restored")
	expect_eq(gs.completed_events.get("ST-06"), "pocketed", "event outcome restored")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ---------------------------------------------------------------- section 17: events

func test_event_library(_gs, lib) -> void:
	expect_eq(lib.events.size(), 155, "155 scripted events")
	var expected := {"ST": 17, "MS": 32, "DC": 32, "PL": 26, "CW": 15, "SC": 21, "SW": 12}
	for code in expected:
		expect_eq(lib.in_category(code).size(), expected[code], "%s count" % code)
	var st06: Dictionary = lib.get_event("ST-06")
	expect_eq(st06.title, "The Back Seat", "ST-06 title")
	for f in ["calloway_noticed_you", "pocketed_spark", "skipped_car_check"]:
		expect(f in st06.sets_flags, "ST-06 sets %s" % f)
	expect_eq(lib.reading_flag("asked_temple_st"), ["MS-17"], "Peg's Story reads asked_temple_st")
	expect("ST-02" in lib.setting_flag("asked_temple_st"), "Reporting to Rampart sets asked_temple_st")
	expect_eq(lib.get_event("DC-21").content_warning, "suicide", "content warnings parsed")
	expect_eq(Array(lib.get_event("MS-08").acts).map(func(a): return int(a)), [1], "act parsed from section heading")
	# Every flag an event reads is set by some event, apart from the known gaps listed above.
	for id in lib.order:
		for f in lib.events[id].reads_flags:
			if not KNOWN_UNSET_FLAGS.has(f):
				expect(not lib.setting_flag(f).is_empty(), "%s reads %s, which some event sets" % [id, f])
	for f in KNOWN_UNSET_FLAGS:
		expect(lib.setting_flag(f).is_empty(), "%s is still unset; remove it from KNOWN_UNSET_FLAGS" % f)


func test_scenes(_gs, lib) -> void:
	expect(lib.scenes.size() >= 1, "at least one playable scene")
	for event_id in lib.scenes:
		var scene: Dictionary = lib.scenes[event_id]
		var problems: Array = lib.validate_scene(scene)
		expect(problems.is_empty(), "%s scene is well formed: %s" % [event_id, problems])
		# Flags a scene sets must be ones the design says the event sets.
		var designed: Array = lib.get_event(event_id).sets_flags
		for node in scene.nodes.values():
			var all_effects: Array = node.get("effects", []).duplicate()
			for choice in node.get("choices", []):
				all_effects.append_array(choice.get("effects", []))
			for e in all_effects:
				if e.has("set_flag"):
					expect(e.set_flag in designed, "%s sets designed flag %s" % [event_id, e.set_flag])
				if e.has("complete_event"):
					expect_eq(e.complete_event, event_id, "%s completes itself" % event_id)


# ---------------------------------------------------------------- world

func test_iso(_gs, _lib) -> void:
	var tm := TileMapLayer.new()
	tm.tile_set = load("res://art/tiles/rampart_street_tileset.tres")
	for t in [Vector2i(0, 0), Vector2i(3, 1), Vector2i(7, 12), Vector2i(14, 14)]:
		var center := Iso.ground_to_screen(Iso.tile_to_ground(Vector2(t) + Vector2(0.5, 0.5)))
		expect_eq(center, tm.map_to_local(t), "tile %s center matches TileMapLayer" % t)
	tm.free()
	for g in [Vector2(0, 0), Vector2(37.5, 12), Vector2(400, 77)]:
		expect(Iso.screen_to_ground(Iso.ground_to_screen(g)).is_equal_approx(g), "round trip %s" % g)
	var up := Iso.ground_to_screen(Iso.screen_dir_to_ground(Vector2.UP)) - Iso.ground_to_screen(Vector2.ZERO)
	expect(up.x == 0 and up.y < 0, "screen up maps to screen up")


func test_street_map(_gs, _lib) -> void:
	var map := StreetMap.new()
	add_child(map)
	expect_eq(map.size, Vector2i(15, 15), "map size")
	expect_eq(map.ground.get_used_cells().size(), 225, "every tile placed")
	var spawn := map.spawn_ground()
	expect(map.is_free(spawn), "spawn point is free")
	expect(not map.is_free(Iso.tile_to_ground(Vector2(2.6, 10.25))), "the patrol car blocks")
	expect(not map.is_free(Iso.tile_to_ground(Vector2(13.5, 13.5))), "the fenced lot blocks")
	expect(not map.is_free(Vector2(-10, 50)), "outside the map blocks")
	var near: Dictionary = map.interactable_near(spawn)
	expect_eq(near.get("event", ""), "ST-06", "the car check is in reach from the spawn")
	expect(map.interactable_near(Iso.tile_to_ground(Vector2(13, 3))).is_empty(), "nothing to use across the street")
	# Walk the officer straight at the car: it slides or stops at the car, never inside it.
	var officer := OfficerActor.new()
	officer.map = map
	map.actors.add_child(officer)
	officer.place(spawn, "up")
	var car_center := Iso.tile_to_ground(Vector2(2.6, 10.25))
	for i in 120:
		officer._try_move((car_center - officer.ground).normalized() * 2.0)
		expect(map.is_free(officer.ground, OfficerActor.BODY_RADIUS), "officer never enters a blocker")
	expect(officer.ground.distance_to(car_center) > 20.0, "officer stopped at the car")
	map.queue_free()


func test_back_seat_playthrough(gs, lib) -> void:
	var box := DialogueBox.new()
	add_child(box)
	box.play(lib.scene_for("ST-06"))
	expect(box.is_open(), "dialogue opens")
	var finished := [false]
	box.finished.connect(func(_id): finished[0] = true)
	var start: Dictionary = box.scene_data.nodes[box.current]
	box._choose(start.choices[0])
	expect_eq(box.current, "found", "searching the seat finds the baggie")
	var found: Dictionary = box.scene_data.nodes[box.current]
	var minutes_before: int = gs.minutes
	box._choose(found.choices[0])
	expect(gs.has_flag("calloway_noticed_you"), "booking it sets calloway_noticed_you")
	expect_eq(gs.completed_events.get("ST-06"), "booked", "outcome recorded")
	expect_eq(gs.minutes - minutes_before, 30, "booking takes time")
	box._finish()
	expect(finished[0] and not box.is_open(), "dialogue closes")
	box.queue_free()
