extends Node
## Headless test runner. Runs as a scene so the autoloads exist:
##   godot --headless --path . res://tests/run_tests.tscn
## Exits with code 1 if any assertion fails.

## Flags an event reads that no scripted event sets yet. Each is an open gap in design section 17.
const KNOWN_UNSET_FLAGS := {
	"saw_camera": "DC-04 reads it as coming from another FTO's passing mention; no event sets it yet",
}

var campaign: Node
var failures := 0
var passes := 0
var _current := ""


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var gs: Node = get_node("/root/GameState")
	var lib: Node = get_node("/root/EventLibrary")
	campaign = get_node("/root/Campaign")
	for t in [
		"checks", "officer_sample_build", "composure_and_stress", "habits", "creation_rules",
		"game_state", "save_load", "event_library", "scenes", "iso", "street_map", "back_seat_playthrough",
		"tac_map_movement", "tac_line_of_sight", "tac_cover_and_hit_chance", "tac_reaction_fire",
		"tac_commands_and_arrest", "tac_less_lethal", "tac_bleeding", "tac_force_review", "tac_factory_and_fuzz",
		"creation_and_fto", "campaign_calls", "campaign_mission_result", "campaign_month_and_save",
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


# ---------------------------------------------------------------- tactical (X-COM layer)

func _squad(n: int = 2) -> Array:
	var out: Array = []
	for i in n:
		var o := Officer.sample_combat_veteran()
		out.append(TacUnit.from_officer(o, "officer_%d" % i, "Officer %d" % (i + 1), {"loadout": "taser"}))
	return out


func _open_mission(w: int = 12, h: int = 12) -> TacMission:
	var m := TacMission.new(1234)
	m.map = TacMap.new(w, h, "sidewalk")
	return m


func test_tac_map_movement(_gs, _lib) -> void:
	var map := TacMap.new(8, 8)
	expect_eq(map.step_cost(Vector2i(2, 2), Vector2i(3, 2)), 4, "straight step costs 4 TU")
	expect_eq(map.step_cost(Vector2i(2, 2), Vector2i(3, 3)), 6, "diagonal step costs 6 TU")
	map.set_wall(Vector2i(3, 2), "w", "brick")
	expect_eq(map.step_cost(Vector2i(2, 2), Vector2i(3, 2)), -1, "a wall blocks the step")
	expect_eq(map.step_cost(Vector2i(2, 2), Vector2i(3, 3)), -1, "no cutting a wall corner diagonally")
	map.wall_w[Vector2i(3, 2)].kind = "door"
	expect_eq(map.step_cost(Vector2i(2, 2), Vector2i(3, 2)), 8, "a closed door costs 4 more to open")
	expect(map.open_door(Vector2i(2, 2), Vector2i(3, 2)), "door opens")
	expect_eq(map.step_cost(Vector2i(2, 2), Vector2i(3, 2)), 4, "an open door is free")
	map.set_floor(Vector2i(5, 5), "rubble_heavy")
	expect_eq(map.step_cost(Vector2i(4, 5), Vector2i(5, 5)), 8, "heavy rubble costs extra")
	map.place_object("chainlink_fence", [Vector2i(6, 6)])
	expect_eq(map.step_cost(Vector2i(6, 5), Vector2i(6, 6)), 12, "climbing a fence costs extra")
	map.place_object("dumpster", [Vector2i(1, 6)])
	expect_eq(map.step_cost(Vector2i(1, 5), Vector2i(1, 6)), -1, "a dumpster blocks movement")
	var reach := Pathfinder.reachable(map, Vector2i(0, 0), 12, {})
	expect_eq(int(reach.cost[Vector2i(3, 0)]), 12, "three straight steps for 12 TU")
	expect(not reach.cost.has(Vector2i(4, 0)), "a fourth step is out of budget")
	var path := Pathfinder.find_path(map, Vector2i(0, 0), Vector2i(7, 7), {})
	expect(path.size() > 0 and path[-1] == Vector2i(7, 7), "A* finds a path across the map")
	expect(Pathfinder.path_cost(map, Vector2i(0, 0), path) > 0, "path has a TU cost")


func test_tac_line_of_sight(_gs, _lib) -> void:
	var map := TacMap.new(10, 10)
	expect(map.has_line_of_sight(Vector2i(1, 5), Vector2i(8, 5)), "clear street")
	for y in 10:
		map.set_wall(Vector2i(5, y), "w", "brick")
	expect(not map.has_line_of_sight(Vector2i(1, 5), Vector2i(8, 5)), "a brick wall blocks sight")
	map.wall_w[Vector2i(5, 5)].kind = "window"
	expect(map.has_line_of_sight(Vector2i(1, 5), Vector2i(8, 5)), "you can see through a window")
	expect(not map.wall_stops_rounds(map.wall_w[Vector2i(5, 5)]), "glass does not stop rounds")
	expect(map.wall_stops_rounds(map.wall_w[Vector2i(5, 4)]), "brick stops rounds")
	map.set_wall(Vector2i(5, 3), "w", "drywall")
	expect(not map.wall_stops_rounds(map.wall_w[Vector2i(5, 3)]), "drywall is concealment, not cover")
	map.place_object("dumpster", [Vector2i(3, 2)])
	expect(not map.has_line_of_sight(Vector2i(1, 2), Vector2i(4, 2)), "a dumpster blocks sight")
	var steps := map.trace(Vector2i(0, 0), Vector2i(3, 0))
	expect_eq(steps.size(), 3, "a straight trace crosses three cells")


func test_tac_cover_and_hit_chance(_gs, _lib) -> void:
	var m := _open_mission(16, 16)
	m.map.place_car(Vector2i(6, 4), "NW")
	var squad := _squad(1)
	var o: TacUnit = squad[0]
	m.add_unit(o, Vector2i(6, 12))
	o.facing = 0
	var s := TacUnit.make_npc(TacUnit.Side.SUSPECT, "Suspect", "suspect_hoodie", m.rng)
	m.add_unit(s, Vector2i(6, 3))
	expect_eq(m.map.cover_against(s.pos, o.pos), TacMap.Cover.FULL, "behind the engine block is full cover")
	expect_eq(m.map.cover_against(s.pos, Vector2i(2, 3)), TacMap.Cover.NONE, "flanked from the side: no cover")
	m.map.objects.clear()
	# Perception 6, Firearms 3 = 60; aimed +20; range 9 tiles: -15. No cover, full Composure.
	expect_eq(m.hit_chance(o, "glock22", "aimed", s), 60 + 20 - 15, "hit chance follows the design formula")
	o.stance = TacUnit.Stance.KNEELING
	expect_eq(m.hit_chance(o, "glock22", "aimed", s), 60 + 20 - 15 + TacMission.KNEEL_BONUS, "kneeling steadies the shot")
	o.stance = TacUnit.Stance.STANDING
	expect_eq(m.hit_chance(o, "glock22", "snap", s, true), 60 - 15 - TacMission.REACTION_PENALTY, "reaction shots take -10")
	m.map.night = true
	o.belt.erase("flashlight")
	expect_eq(m.hit_chance(o, "glock22", "snap", s), 60 - 15 - TacMission.DARK_PENALTY, "darkness without light -20")
	expect_eq(o.action_tu(50), int(ceil(o.tu_max * 0.5)), "TU costs are a share of maximum TU")


func test_tac_reaction_fire(_gs, _lib) -> void:
	var m := _open_mission(20, 20)
	var o: TacUnit = _squad(1)[0]
	o.right_hand = "glock22"
	o.reactions = 95
	m.add_unit(o, Vector2i(10, 15))
	o.facing = 0
	var civ := TacUnit.make_npc(TacUnit.Side.CIVILIAN, "Civilian", "civilian_clerk", m.rng)
	civ.reactions = 1
	m.add_unit(civ, Vector2i(10, 8))
	m.start()
	var p: Array[Vector2i] = [Vector2i(10, 9)]
	m.move_unit(civ, p)
	expect_eq(m.rounds_fired, 0, "officers never react to an unarmed civilian")
	var s := TacUnit.make_npc(TacUnit.Side.SUSPECT, "Gunman", "suspect_tracksuit", m.rng)
	s.reactions = 1
	s.disposition = TacUnit.Disposition.DEADLY
	s.give_weapon("suspect_pistol")
	m.add_unit(s, Vector2i(12, 8))
	p = [Vector2i(12, 9)]
	m.move_unit(s, p)
	expect(m.rounds_fired >= 1, "an armed, deadly suspect moving in view draws reaction fire")
	expect(o.record.reaction_shots >= 1, "reaction shot recorded")
	var events := m.take_events()
	expect(events.any(func(e): return e.type == "reaction"), "reaction event emitted")


func test_tac_commands_and_arrest(_gs, _lib) -> void:
	var m := _open_mission()
	var o: TacUnit = _squad(1)[0]
	m.add_unit(o, Vector2i(4, 5))
	o.facing = 2
	var s := TacUnit.make_npc(TacUnit.Side.SUSPECT, "Subject", "suspect_white_tee", m.rng)
	s.disposition = TacUnit.Disposition.PASSIVE
	s.morale = 60
	s.give_weapon("knife", false)
	m.add_unit(s, Vector2i(5, 5))
	m.basis = "probable_cause"
	m.start()
	var before := o.tu
	expect(m.command(o, s), "command issued")
	expect_eq(o.tu, before, "the first short command each turn is free")
	var tries := 0
	while s.status == TacUnit.Status.ACTIVE and tries < 10:
		o.tu = o.tu_max
		m.command(o, s)
		tries += 1
	expect(tries > 0 or s.status != TacUnit.Status.ACTIVE, "repeated commands break a passive subject's resolve")
	expect_eq(m.phase, TacMission.Phase.OVER, "with no threat left the scene is secured")
	expect_eq(s.status, TacUnit.Status.CUFFED, "back in Contact, the surrendered subject is cuffed")
	# Cuffing directly, before the scene ends: a second subject keeps the scene open.
	var m2 := _open_mission()
	var o2: TacUnit = _squad(1)[0]
	m2.add_unit(o2, Vector2i(4, 5))
	var a := TacUnit.make_npc(TacUnit.Side.SUSPECT, "A", "suspect_white_tee", m2.rng)
	a.status = TacUnit.Status.INCAPACITATED
	a.incapacitated_turns = 1
	m2.add_unit(a, Vector2i(5, 5))
	var b := TacUnit.make_npc(TacUnit.Side.SUSPECT, "B", "suspect_hoodie", m2.rng)
	b.disposition = TacUnit.Disposition.ACTIVE
	m2.add_unit(b, Vector2i(10, 10))
	m2.basis = "probable_cause"
	m2.start()
	var cuffed := false
	for i in 10:
		o2.tu = o2.tu_max
		m2.handcuff(o2, a)
		if a.status == TacUnit.Status.CUFFED:
			cuffed = true
			break
	expect(cuffed, "an incapacitated subject can be cuffed")
	expect_eq(o2.uses.get("handcuffs"), 1, "one pair of cuffs used")
	expect(m2.phase != TacMission.Phase.OVER, "the scene stays open while someone is still loose")
	var r := m.debrief(true, "test")
	expect(int(r.arrested) == 1 and int(r.score) > 0, "custody scores points")


func test_tac_less_lethal(_gs, _lib) -> void:
	var incapacitated := 0
	var blinded := 0
	for seed_value in range(1, 41):
		var m := TacMission.new(seed_value)
		m.map = TacMap.new(10, 10)
		var o: TacUnit = _squad(1)[0]
		m.add_unit(o, Vector2i(2, 5))
		o.facing = 2
		var s := TacUnit.make_npc(TacUnit.Side.SUSPECT, "Runner", "suspect_white_tee", m.rng)
		s.disposition = TacUnit.Disposition.ACTIVE
		m.add_unit(s, Vector2i(4, 5))
		o.right_hand = "taser_x26"
		m.fire(o, s, "snap")
		# A lone subject dropped by the Taser ends the scene and is cuffed.
		if s.status in [TacUnit.Status.INCAPACITATED, TacUnit.Status.CUFFED]:
			incapacitated += 1
		o.tu = o.tu_max
		var s2 := TacUnit.make_npc(TacUnit.Side.SUSPECT, "Other", "suspect_white_tee", m.rng)
		m.add_unit(s2, Vector2i(2, 6))
		o.right_hand = "oc_spray"
		m.fire(o, s2, "snap")
		if s2.blinded_turns > 0:
			blinded += 1
	expect(incapacitated > 10 and incapacitated < 40, "the Taser works often but not always (%d/40)" % incapacitated)
	expect(blinded > 10, "OC spray blinds (%d/40)" % blinded)
	var m2 := TacMission.new(5)
	m2.map = TacMap.new(10, 10)
	var o2: TacUnit = _squad(1)[0]
	m2.add_unit(o2, Vector2i(2, 5))
	expect_eq(int(o2.ammo.get("taser_x26", 0)), 1, "one Taser cartridge")
	var force_items := m2.force_log.size()
	expect_eq(force_items, 0, "no force logged yet")


func test_tac_bleeding(_gs, _lib) -> void:
	var m := _open_mission()
	var o: TacUnit = _squad(1)[0]
	m.add_unit(o, Vector2i(1, 1))
	var v := TacUnit.make_npc(TacUnit.Side.CIVILIAN, "Victim", "civilian_elder", m.rng)
	v.health = 2
	v.fatal_wounds = 2
	v.status = TacUnit.Status.UNCONSCIOUS
	m.add_unit(v, Vector2i(5, 5))
	var s := TacUnit.make_npc(TacUnit.Side.SUSPECT, "Suspect", "suspect_hoodie", m.rng)
	s.disposition = TacUnit.Disposition.PASSIVE
	m.add_unit(s, Vector2i(9, 9))
	m.start()
	m._end_of_round()
	expect_eq(v.status, TacUnit.Status.DYING, "bleeding wounds drain health until the victim is dying")
	for i in 3:
		m._end_of_round()
	expect_eq(v.status, TacUnit.Status.DEAD, "unaided, the dying bleed out in three turns")
	o.health = 0
	m._go_down(o)
	for i in 3:
		m._end_of_round()
	expect_eq(o.status, TacUnit.Status.UNCONSCIOUS, "standard mode: a fatal hit on an officer becomes a critical wound")
	var w := TacUnit.make_npc(TacUnit.Side.CIVILIAN, "Wounded", "civilian_nurse", m.rng)
	w.health = 10
	w.fatal_wounds = 1
	m.add_unit(w, Vector2i(1, 2))
	var aided := false
	for i in 10:
		o.status = TacUnit.Status.ACTIVE
		o.tu = o.tu_max
		m.first_aid(o, w)
		if w.fatal_wounds == 0:
			aided = true
			break
	expect(aided, "first aid stops the bleeding")


func test_tac_force_review(_gs, _lib) -> void:
	var r := TacMission.review_force_event({"force": 6, "actual": 4, "perceived": 4, "warned": 1, "target_status": "active"})
	expect_eq(r.outcome, "In policy", "a firearm against a deadly threat is in policy")
	r = TacMission.review_force_event({"force": 6, "actual": 1, "perceived": 1, "warned": 1, "target_status": "active"})
	expect_eq(r.outcome, "Out of policy", "a firearm against passive resistance is out of policy")
	r = TacMission.review_force_event({"force": 4, "actual": 1, "perceived": 1, "warned": 1, "target_status": "active"})
	expect_eq(r.outcome, "Administrative disapproval", "a Taser on passive resistance is one step too far")
	r = TacMission.review_force_event({"force": 4, "actual": 2, "perceived": 2, "warned": 0, "target_status": "active"})
	expect_eq(r.outcome, "In policy, tactical debrief", "force without a warning first gets a debrief")
	r = TacMission.review_force_event({"force": 6, "actual": 2, "perceived": 4, "warned": 1, "target_status": "active", "target_holding": "phone"})
	expect_eq(r.outcome, "In policy, tactical debrief", "a phone misread as a gun: legal, still the wrong call")
	r = TacMission.review_force_event({"force": 5, "actual": 0, "perceived": 0, "warned": 1, "target_status": "surrendered"})
	expect_eq(r.outcome, "Out of policy", "force on a subject who already surrendered")


func test_tac_factory_and_fuzz(_gs, _lib) -> void:
	var types: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/strategic/call_types.json")).types
	var ended := 0
	var total := 0
	for type_id in types:
		var t: Dictionary = types[type_id]
		for ti in t.truth.size():
			for seed_value in [11, 29]:
				total += 1
				var call := {"type": type_id, "label": t.label, "map": t.map, "basis": t.basis, "truth": t.truth[ti],
					"watch": "morning" if seed_value == 29 else "pm"}
				var m := MissionFactory.build(call, _squad(2), seed_value)
				expect(m.officers().size() == 2, "%s: two officers placed" % type_id)
				expect(m.suspects().size() == t.truth[ti].suspects.size(), "%s: suspects placed" % type_id)
				var cells := {}
				for u in m.units:
					expect(not cells.has(u.pos), "%s: no two units share a cell" % type_id)
					cells[u.pos] = true
					expect(m.map.in_bounds(u.pos) and not m.map.object_blocks_move(u.pos), "%s: units stand on open ground" % type_id)
				m.start()
				_play_randomly(m, 25)
				if m.phase == TacMission.Phase.OVER:
					ended += 1
	expect(ended > total / 3, "random play resolves most scenes (%d of %d)" % [ended, total])


## A crude player: close in, command, cuff, shoot only at visible deadly threats, aid the wounded.
func _play_randomly(m: TacMission, max_turns: int) -> void:
	for t in max_turns:
		if m.phase == TacMission.Phase.OVER:
			return
		for o in m.officers():
			if not o.can_act() or m.phase == TacMission.Phase.OVER:
				continue
			var target: TacUnit = null
			for s in m.suspects():
				if s.status in [TacUnit.Status.ACTIVE, TacUnit.Status.SURRENDERED, TacUnit.Status.INCAPACITATED, TacUnit.Status.UNCONSCIOUS]:
					if target == null or s.pos.distance_to(o.pos) < target.pos.distance_to(o.pos):
						target = s
			if target == null:
				break
			if target.is_active() and target.is_armed() and target.disposition == TacUnit.Disposition.DEADLY and m.can_see(o, target):
				if o.weapon() != "glock22" and "glock22" in o.belt:
					m.equip(o, "glock22")
				m.fire(o, target, "snap")
				continue
			if target.pos.distance_to(o.pos) >= 1.5:
				var path := Pathfinder.find_path(m.map, o.pos, target.pos, m.occupied(o))
				if path.size() > 1:
					path.resize(path.size() - 1)
					m.move_unit(o, path)
			if not o.can_act():
				continue
			if target.is_active():
				m.command(o, target)
			if target.pos.distance_to(o.pos) < 1.5:
				m.handcuff(o, target)
		m.take_events()
		if m.phase != TacMission.Phase.OVER:
			m.end_officer_turn()
		m.take_events()


# ---------------------------------------------------------------- strategic (Geoscape layer)

func _new_campaign(fto: String = "ortega") -> void:
	GameState.new_game(Officer.sample_combat_veteran())
	campaign.new_campaign({"name": "Test", "rank": "Police Officer I", "role": "player", "background": "combat_veteran",
		"traits": [], "loadout": "taser"}, fto)


func test_creation_and_fto(_gs, _lib) -> void:
	var c: Dictionary = campaign.creation
	var CreationScript = load("res://scripts/strategic/creation.gd")
	expect_eq(CreationScript.assign_fto(c.backgrounds.combat_veteran, "top"), "whitfield", "military backgrounds go to Whitfield")
	expect_eq(CreationScript.assign_fto(c.backgrounds.college, "top"), "ortega", "top of class goes to Ortega")
	expect_eq(CreationScript.assign_fto(c.backgrounds.college, "barely"), "arakawa", "barely passed goes to Arakawa")
	# The design's sample build: Boyle Heights native, combat veteran.
	var skills: Dictionary = c.academy_baseline.duplicate()
	for src in [c.backgrounds.combat_veteran.skills, c.origins.la_native.skills]:
		for k in src:
			skills[k] = int(skills.get(k, 0)) + int(src[k])
	expect_eq(int(skills.firearms), 3, "sample build Firearms 3")
	expect_eq(int(skills.defensive_tactics), 2, "sample build Defensive Tactics 2")
	expect_eq(int(skills.athletics), 2, "sample build Athletics 2")
	expect_eq(int(skills.streetwise), 2, "sample build Streetwise 2")
	expect_eq(int(c.origins.la_native.languages.spanish), 5, "sample build Spanish 5")
	for key in campaign.people:
		var r: Dictionary = campaign.people[key]
		var spent := {}
		for a in Officer.ATTRIBUTES:
			expect(int(r.attributes[a]) >= 1 and int(r.attributes[a]) <= 10, "%s %s in range" % [key, a])
		expect(ItemDB.loadout_ids().has(r.loadout), "%s has a known loadout" % key)


func test_campaign_calls(_gs, _lib) -> void:
	_new_campaign()
	expect(campaign.active, "probation under way")
	expect(campaign.is_on_duty(), "Monday 1430 is on duty (PM watch)")
	expect_eq(campaign.crew, ["player", "ortega"], "you ride with your FTO")
	var c: Dictionary = campaign.spawn_call("415", "pico_union")
	expect_eq(c.status, "pending", "a new call is pending")
	expect(Geometry2D.is_point_in_polygon(c.pos, PackedVector2Array(campaign.DISTRICT_SHAPES.pico_union.map(func(p): return Vector2(p[0], p[1])))), "the call sits inside its district")
	for i in 55:
		campaign.advance_minute()
	expect_eq(c.type, "245", "a 415 left waiting 50 minutes escalates into a 245")
	for i in 45:
		campaign.advance_minute()
	expect_eq(c.status, "taken_by_other", "a call left too long goes to another unit")
	expect(int(GameState.community.pico_union) < 0, "and the neighborhood notices")
	var d: Dictionary = campaign.spawn_call("211", "lafayette_park")
	expect(campaign.respond(int(d.id), 3), "respond Code 3")
	expect_eq(campaign.car.state, "en_route", "the car is en route")
	var arrived := [false]
	campaign.car_arrived.connect(func(_c): arrived[0] = true, CONNECT_ONE_SHOT)
	for i in 30:
		campaign.advance_minute()
		if arrived[0]:
			break
	expect(arrived[0], "the car arrives on scene")
	expect_eq(d.status, "on_scene", "call on scene")
	var types := {}
	for i in 300:
		types[campaign.spawn_call().type] = true
	expect(types.size() >= 7, "the call generator produces a spread of call types (%d)" % types.size())
	# Off duty: Friday, no calls come in.
	GameState.date = {"year": 2010, "month": 3, "day": 5}
	GameState.minutes = 12 * 60
	expect(not campaign.is_on_duty(), "Friday noon is off duty")
	campaign.skip_to_next_shift()
	expect(campaign.is_on_duty(), "skip to the next shift")
	expect_eq(campaign.weekday(), 1, "the next shift is Monday")


func test_campaign_mission_result(_gs, _lib) -> void:
	_new_campaign("whitfield")
	var c: Dictionary = campaign.spawn_call("5150", "macarthur_park")
	var m: TacMission = campaign.begin_mission(int(c.id))
	expect_eq(m.officers().size(), 2, "the crew of 2A43 responds")
	expect_eq(m.backup_pending.size(), 2, "backup units are standing by")
	expect(campaign.take_pending_mission() == m, "the pending mission is handed to the battlescape")
	var got := [{}]
	m.ended.connect(func(r): got[0] = r)
	m.start()
	_play_randomly(m, 30)
	if m.phase != TacMission.Phase.OVER:
		m.withdraw()
	var result: Dictionary = got[0]
	expect(not result.is_empty(), "the mission reports a result")
	var command_before: int = GameState.reputation.command
	var notes: Array = campaign.apply_result(result)
	expect(notes.size() > 0, "the debrief produces notes")
	expect_eq(campaign.car.state, "busy", "after a call the car is tied up with reports")
	expect(campaign.get_call(int(c.id)).status in ["cleared", "lost"], "the call is closed")
	expect(campaign.history.size() == 1, "the log records the call")
	expect(GameState.reputation.command != command_before or int(result.score) / 30 == 0, "command reputation moves with the score")


func test_campaign_month_and_save(_gs, _lib) -> void:
	_new_campaign()
	var reports := []
	campaign.month_report.connect(func(r): reports.append(r))
	GameState.date = {"year": 2010, "month": 3, "day": 31}
	GameState.minutes = 23 * 60 + 59
	campaign.advance_minute()
	expect_eq(reports.size(), 1, "a monthly review at the turn of the month")
	expect(reports[0].has("grade") and reports[0].has("budget"), "the review grades the month and sets the budget")
	campaign.spawn_call("459", "echo_park")
	campaign.roster.ortega.injured_days = 3
	var path := "user://test_campaign.json"
	expect_eq(GameState.save_game(path), OK, "save with the campaign")
	_new_campaign("arakawa")
	expect_eq(GameState.load_game(path), OK, "load")
	expect_eq(campaign.crew, ["player", "ortega"], "crew restored")
	expect_eq(int(campaign.roster.ortega.injured_days), 3, "injuries restored")
	expect(campaign.calls.any(func(c): return c.type == "459" and c.pos is Vector2), "calls restored with positions")
	expect_eq(GameState.date.month, 4, "date restored")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	campaign.active = false
