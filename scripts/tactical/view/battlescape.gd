class_name Battlescape
extends Node2D
## The tactical screen: an isometric battlescape with fog of war, the officers you command,
## path and hit previews, and playback of everything the rules engine reports.

signal finished(result: Dictionary)

const STEP_TIME := 0.08
const SHOT_TIME := 0.16
const WALLS_ANCHORS := "res://data/art/walls_anchors.json"
const PROPS_ANCHORS := "res://data/art/props_anchors.json"
const OBJECTS_ANCHORS := "res://data/art/objects_anchors.json"
const CAR_ANCHORS := "res://data/art/crown_vic_anchors.json"
const SEDAN_ANCHORS := "res://data/art/sedan_anchors.json"
const STREET_INDEX := "res://data/art/rampart_street_tiles_index.json"
const INTERIOR_INDEX := "res://data/art/rampart_interior_tiles_index.json"

enum Mode { MOVE, TARGET }

var mission: TacMission
var selected: TacUnit = null
var mode := Mode.MOVE
var target_mode := "snap"
var busy := false
var hover := Vector2i(-1, -1)

var ground: TileMapLayer
var fog: Node2D
var overlay: Node2D
var actors: Node2D
var effects: Node2D
var camera: Camera2D
var hud: TacticalHud
var menu: PopupMenu

var unit_views := {}
var wall_sprites := {}
var visual_sprites: Array = []
var _reach := {}
var _queue: Array = []
var _explored := {}
var _anchors := {}
var _menu_actions: Array = []
var _menu_target: TacUnit = null


func _ready() -> void:
	if mission == null:
		mission = Campaign.take_pending_mission()
	if mission == null:
		mission = demo_mission()
	_load_anchors()
	_build_layers()
	_build_map()
	for u in mission.units:
		_add_unit_view(u)
	hud = TacticalHud.new()
	hud.battlescape = self
	add_child(hud)
	menu = PopupMenu.new()
	menu.add_theme_font_size_override("font_size", 8)
	menu.id_pressed.connect(_on_menu)
	hud.add_child(menu)
	mission.start()
	_select(_first_ready_officer())
	_play(mission.take_events())
	if selected:
		camera.position = UnitView.cell_to_screen(selected.pos)


static func demo_mission() -> TacMission:
	var types: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/strategic/call_types.json")).types
	var t: Dictionary = types["211"]
	var call := {"type": "211", "label": t.label, "map": t.map, "basis": t.basis, "truth": t.truth[1], "watch": "pm"}
	var squad: Array = []
	var me := TacUnit.from_officer(GameState.officer, "player", "You", {"loadout": "taser", "rank": "Police Officer I"})
	squad.append(me)
	var fto := Officer.new()
	fto.attributes = {"fitness": 5, "nerve": 7, "perception": 6, "intellect": 7, "presence": 6, "empathy": 5}
	fto.skills = {"firearms": 3, "defensive_tactics": 3, "de_escalation": 3, "command_presence": 3, "first_aid": 2, "search": 3}
	fto.composure = fto.max_composure()
	squad.append(TacUnit.from_officer(fto, "ortega", "Ortega", {"loadout": "patrol", "rank": "Police Officer III"}))
	return MissionFactory.build(call, squad)


# ---------------------------------------------------------------- building the scene

func _load_anchors() -> void:
	for key in [WALLS_ANCHORS, PROPS_ANCHORS, OBJECTS_ANCHORS, CAR_ANCHORS, SEDAN_ANCHORS, STREET_INDEX, INTERIOR_INDEX]:
		_anchors[key] = JSON.parse_string(FileAccess.get_file_as_string(key))


func _build_layers() -> void:
	ground = TileMapLayer.new()
	ground.tile_set = load("res://art/tiles/rampart_battle_tileset.tres")
	add_child(ground)
	fog = Node2D.new()
	fog.z_index = 1
	fog.draw.connect(_draw_fog)
	add_child(fog)
	overlay = Node2D.new()
	overlay.z_index = 2
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)
	actors = Node2D.new()
	actors.y_sort_enabled = true
	actors.z_index = 3
	add_child(actors)
	effects = Node2D.new()
	effects.z_index = 4
	add_child(effects)
	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	add_child(camera)
	camera.make_current()


func _build_map() -> void:
	var m := mission.map
	var street: Dictionary = _anchors[STREET_INDEX]
	var interior: Dictionary = _anchors[INTERIOR_INDEX]
	for y in m.height:
		for x in m.width:
			var c := Vector2i(x, y)
			var t := m.get_floor(c)
			if interior.has(t):
				ground.set_cell(c, 1, Vector2i(interior[t][0], interior[t][1]))
			else:
				var a: Array = street.get(t, street["sidewalk"])
				ground.set_cell(c, 0, Vector2i(a[0], a[1]))
	for c in m.wall_n:
		_wall_sprite(c, "n")
	for c in m.wall_w:
		_wall_sprite(c, "w")
	for v in m.visuals:
		_visual_sprite(v)


func _wall_texture(w: Dictionary, axis: String) -> String:
	var material: String = w.material
	var kind: String = w.kind
	if material == "lowwall":
		kind = "plain"
	elif material == "storefront" and kind in ["plain", "window", "storefront"]:
		kind = "storefront"
	elif material == "drywall" and kind == "window":
		kind = "plain"
	return "%s_%s_%s" % [material, kind, axis]


func _wall_sprite(c: Vector2i, side: String) -> void:
	var w: Dictionary = mission.map.wall_n[c] if side == "n" else mission.map.wall_w[c]
	var axis := "x" if side == "n" else "y"
	var key := _wall_texture(w, axis)
	var s := Sprite2D.new()
	s.centered = false
	var start := Iso.tile_to_ground(Vector2(c))
	var mid := start + (Vector2(16, 0) if axis == "x" else Vector2(0, 16))
	var a: Array = _anchors[WALLS_ANCHORS][key].anchor_px
	s.position = Iso.ground_to_screen(mid).round()
	s.offset = (Iso.ground_to_screen(start) - Iso.ground_to_screen(mid) - Vector2(a[0], a[1])).round()
	s.texture = load("res://art/walls/%s.png" % key)
	s.set_meta("wall", w)
	s.set_meta("axis", axis)
	s.set_meta("key", key)
	actors.add_child(s)
	wall_sprites[[c, side]] = s


func _refresh_walls() -> void:
	for k in wall_sprites:
		var s: Sprite2D = wall_sprites[k]
		var key := _wall_texture(s.get_meta("wall"), s.get_meta("axis"))
		if key != s.get_meta("key"):
			s.set_meta("key", key)
			s.texture = load("res://art/walls/%s.png" % key)
			var start := Iso.tile_to_ground(Vector2(k[0]))
			var mid := start + (Vector2(16, 0) if s.get_meta("axis") == "x" else Vector2(0, 16))
			var a: Array = _anchors[WALLS_ANCHORS][key].anchor_px
			s.offset = (Iso.ground_to_screen(start) - Iso.ground_to_screen(mid) - Vector2(a[0], a[1])).round()


func _visual_sprite(v: Dictionary) -> void:
	var s := Sprite2D.new()
	s.centered = false
	var tex := ""
	var anchor := Vector2.ZERO
	var vname: String = v.name
	match String(v.kind):
		"vehicle":
			if vname == "crown_vic":
				var a: Dictionary = _anchors[CAR_ANCHORS][v.facing]
				tex = "res://art/vehicles/%s" % a.file
				anchor = Vector2(a.ground_center_px[0], a.ground_center_px[1])
			else:
				var key := "%s_%s" % [vname.trim_prefix("sedan_"), v.facing]
				var a: Dictionary = _anchors[SEDAN_ANCHORS][key]
				tex = "res://art/vehicles/%s" % a.file
				anchor = Vector2(a.ground_center_px[0], a.ground_center_px[1])
		"object":
			var a: Dictionary = _anchors[OBJECTS_ANCHORS][vname]
			tex = "res://art/props/%s.png" % vname
			anchor = Vector2(a.ground_anchor_px[0], a.ground_anchor_px[1])
		_:
			var table: Dictionary = _anchors[PROPS_ANCHORS] if _anchors[PROPS_ANCHORS].has(vname) else _anchors[OBJECTS_ANCHORS]
			var a: Dictionary = table[vname]
			tex = "res://art/props/%s.png" % vname
			anchor = Vector2(a.ground_anchor_px[0], a.ground_anchor_px[1])
	s.texture = load(tex)
	s.position = Iso.ground_to_screen(Iso.tile_to_ground(v.ground)).round()
	s.offset = -anchor.round()
	s.set_meta("cell", Vector2i(floor(v.ground.x), floor(v.ground.y)))
	actors.add_child(s)
	visual_sprites.append(s)


func _add_unit_view(u: TacUnit) -> void:
	var view := UnitView.new()
	view.setup(u)
	actors.add_child(view)
	unit_views[u.id] = view


# ---------------------------------------------------------------- selection and input

func _first_ready_officer() -> TacUnit:
	for o in mission.officers():
		if o.can_act():
			return o
	return null


func _select(u: TacUnit) -> void:
	if selected and unit_views.has(selected.id):
		unit_views[selected.id].selected = false
		unit_views[selected.id].queue_redraw()
	selected = u
	mode = Mode.MOVE
	if u:
		unit_views[u.id].selected = true
		unit_views[u.id].queue_redraw()
	_recompute_reach()
	if hud:
		hud.refresh()


func select_next() -> void:
	var list := mission.officers().filter(func(o): return o.can_act())
	if list.is_empty():
		return
	var i := list.find(selected)
	_select(list[(i + 1) % list.size()])
	center_on_selected()


func center_on_selected() -> void:
	if selected:
		camera.position = UnitView.cell_to_screen(selected.pos)


func _recompute_reach() -> void:
	_reach = {}
	if selected and selected.can_act() and mission.phase == TacMission.Phase.OFFICERS:
		_reach = mission.move_preview(selected)
	overlay.queue_redraw()


func mouse_cell() -> Vector2i:
	var g := Iso.screen_to_ground(get_global_mouse_position())
	return Vector2i(floor(g.x / Iso.TILE_UNITS), floor(g.y / Iso.TILE_UNITS))


func _process(delta: float) -> void:
	var pan := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if pan != Vector2.ZERO and not menu.visible:
		camera.position += pan * 320.0 * delta / camera.zoom.x
	var c := mouse_cell()
	if c != hover:
		hover = c
		overlay.queue_redraw()
		if hud:
			hud.update_hover()
	_fade_walls()


func _fade_walls() -> void:
	var points: Array[Vector2] = [get_global_mouse_position()]
	if selected:
		points.append(UnitView.cell_to_screen(selected.pos) + Vector2(0, -20))
	for k in wall_sprites:
		var s: Sprite2D = wall_sprites[k]
		var rect := Rect2(s.position + s.offset, s.texture.get_size())
		var fade := false
		for p in points:
			if rect.has_point(p) and p.y < s.position.y + 4:
				fade = true
				break
		s.modulate.a = 0.3 if fade else 1.0


func _unhandled_input(event: InputEvent) -> void:
	if busy or mission.phase != TacMission.Phase.OFFICERS:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom = (camera.zoom * 1.25).clamp(Vector2(0.5, 0.5), Vector2(3, 3))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom = (camera.zoom / 1.25).clamp(Vector2(0.5, 0.5), Vector2(3, 3))
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_left_click(mouse_cell())
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_right_click(mouse_cell())
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_N, KEY_TAB:
				select_next()
			KEY_K:
				act(func(): return mission.toggle_stance(selected))
			KEY_C:
				center_on_selected()
			KEY_R:
				act(func(): return mission.reload(selected))
			KEY_P:
				act(func(): return mission.pick_up(selected))
			KEY_I:
				hud.toggle_inventory()
			KEY_ENTER, KEY_KP_ENTER:
				end_turn()
			KEY_ESCAPE:
				mode = Mode.MOVE
				hud.refresh()
				overlay.queue_redraw()


func _left_click(c: Vector2i) -> void:
	if not mission.map.in_bounds(c) or selected == null:
		return
	var u := mission.unit_at(c)
	if u and u.is_officer() and u.can_act():
		_select(u)
		return
	if mode == Mode.TARGET:
		if u and u != selected and mission.visible_to_officers(u):
			var t := u
			act(func(): return mission.fire(selected, t, target_mode))
			mode = Mode.MOVE
		return
	if u and u != selected and mission.visible_to_officers(u):
		_open_menu(u)
		return
	if _reach.has("cost") and _reach.cost.has(c) and c != selected.pos:
		var path := Pathfinder.path_from(_reach, c)
		act(func(): return mission.move_unit(selected, path) > 0)


func _right_click(c: Vector2i) -> void:
	if selected == null or not mission.map.in_bounds(c):
		return
	var u := mission.unit_at(c)
	if u and (u != selected or u.fatal_wounds > 0) and (mission.visible_to_officers(u)):
		_open_menu(u)
		return
	act(func(): return mission.turn_unit(selected, c))


## Runs a rules action for the selected officer, then plays back what happened.
func act(f: Callable) -> void:
	if busy or selected == null:
		return
	f.call()
	_play(mission.take_events())


func end_turn() -> void:
	if busy or mission.phase != TacMission.Phase.OFFICERS:
		return
	hud.show_banner("Others are moving")
	mode = Mode.MOVE
	mission.end_officer_turn()
	_play(mission.take_events())


func set_target_mode(m: String) -> void:
	if selected == null or selected.weapon() == "":
		return
	target_mode = m
	mode = Mode.TARGET
	hud.refresh()
	overlay.queue_redraw()


# ---------------------------------------------------------------- the police action menu (design 6.1)

func _open_menu(target: TacUnit) -> void:
	if selected == null or not selected.can_act():
		return
	_menu_target = target
	_menu_actions = interaction_options(selected, target)
	menu.clear()
	menu.add_separator("%s  (%s, %s)" % [target.name, target.status_name(), target.wound_label().to_lower()])
	for i in _menu_actions.size():
		var a: Dictionary = _menu_actions[i]
		menu.add_item(a.label, i)
		if a.get("warn", "") != "":
			menu.set_item_tooltip(menu.get_item_index(i), a.warn)
		if a.get("disabled", false):
			menu.set_item_disabled(menu.get_item_index(i), true)
	menu.position = Vector2i(get_viewport().get_mouse_position())
	menu.reset_size()
	menu.popup()


## Every option shows its cost, its check chance and its legal basis; nothing is greyed out
## for lack of basis. With Law and Policy 2 or higher, a missing basis is flagged (design 6.1).
func interaction_options(u: TacUnit, t: TacUnit) -> Array:
	var out: Array = []
	var dist := Vector2(t.pos - u.pos).length()
	var adjacent := dist < 1.5
	var knows_law := u.officer != null and u.officer.skill("law_and_policy") >= 2
	var basis_tag: String = {"consensual": "Consensual", "reasonable_suspicion": "Reasonable suspicion",
		"probable_cause": "Probable cause", "exigent": "Exigent"}.get(mission.basis, "Consensual")
	if t.side != TacUnit.Side.OFFICER and t.is_active():
		var cmd_cost := "free" if not u.free_command_used else "%d TU" % TacMission.COMMAND_TU
		out.append({"label": "Command: \"Show me your hands!\"  [%s, %d%%]" % [cmd_cost, Check.display_odds(mission.command_chance(u, t))],
			"do": func(): return mission.command(u, t), "disabled": dist > TacMission.VOICE_RANGE})
		out.append({"label": "Calm down  [%d TU, %d%%]" % [TacMission.CALM_TU, Check.display_odds(mission.calm_chance(u, t))],
			"do": func(): return mission.calm(u, t), "disabled": dist > TacMission.CALM_RANGE})
	if t.side == TacUnit.Side.CIVILIAN and not t.is_down():
		out.append({"label": "Ask what happened  [8 TU, Interview]", "do": func(): return mission.ask_witness(u, t),
			"disabled": dist > TacMission.CALM_RANGE})
	if t.side == TacUnit.Side.SUSPECT and t.status != TacUnit.Status.DEAD:
		out.append({"label": "Run name and date of birth  [%d TU, Radio]" % TacMission.RADIO_TU,
			"do": func(): return mission.run_name(u, t)})
	var w := u.weapon()
	if w != "" and t.side != TacUnit.Side.OFFICER:
		var item := ItemDB.get_item(w)
		for mname in item.modes:
			var chance := mission.hit_chance(u, w, mname, t)
			var label := "%s (%s)  [%d TU, %d%%]" % [item.modes[mname].label, item.name.split(" (")[0], mission.mode_tu(u, w, mname), chance]
			var warn := ""
			if knows_law:
				var needed: int = {6: 4, 5: 3, 4: 2}.get(int(item.get("force", 3)), 0)
				if mission._perceived_threat(t, u) < needed:
					warn = "No threat that justifies this force"
					label = "! " + label
			var mm: String = mname
			out.append({"label": label, "warn": warn, "do": func(): return mission.fire(u, t, mm),
				"disabled": not mission.line_of_fire(u, t) and item.kind != "melee"})
	for b in u.belt:
		if ItemDB.is_weapon(b):
			var bb: String = b
			out.append({"label": "Draw %s  [%d TU]" % [ItemDB.get_item(b).name.split(" (")[0], TacMission.DRAW_TU],
				"do": func(): return mission.equip(u, bb)})
	if adjacent and t.side != TacUnit.Side.OFFICER and t.status != TacUnit.Status.DEAD:
		var frisk_basis: String = "Reasonable suspicion" if t.record.get("known_hidden", false) or mission.basis != "consensual" else basis_tag
		var frisk_label := "Pat-down  [%d TU, Search, %s]" % [TacMission.FRISK_TU, frisk_basis]
		if knows_law and frisk_basis == "Consensual" and t.status == TacUnit.Status.ACTIVE:
			frisk_label = "! " + frisk_label + " (no reasonable suspicion of a weapon)"
		out.append({"label": frisk_label, "do": func(): return mission.frisk(u, t)})
		if mission.can_handcuff(u, t):
			var pc: String = "Probable cause" if mission._has_probable_cause(t) else basis_tag
			var cuff_label := "Handcuff  [%d TU, %d%%, %s]" % [TacMission.CUFF_TU, mission.cuff_chance(u, t), pc]
			if knows_law and not mission._has_probable_cause(t):
				cuff_label = "! " + cuff_label + " (no probable cause)"
			out.append({"label": cuff_label, "do": func(): return mission.handcuff(u, t)})
	if adjacent and (t.fatal_wounds > 0 or t.status in [TacUnit.Status.DYING, TacUnit.Status.UNCONSCIOUS] or t.health < t.health_max):
		out.append({"label": "First aid  [%d TU, %d%%]" % [TacMission.AID_TU, mission.aid_chance(u, t)],
			"do": func(): return mission.first_aid(u, t)})
	return out


func _on_menu(id: int) -> void:
	if id < 0 or id >= _menu_actions.size():
		return
	var f: Callable = _menu_actions[id]["do"]
	act(f)


# ---------------------------------------------------------------- playback

func _play(events: Array) -> void:
	_queue.append_array(events)
	if not busy:
		_run_queue()


func _run_queue() -> void:
	busy = true
	while not _queue.is_empty():
		var e: Dictionary = _queue.pop_front()
		await _play_event(e)
	busy = false
	_sync_all()
	if mission.phase == TacMission.Phase.OFFICERS:
		hud.hide_banner()
		if selected == null or not selected.can_act():
			_select(_first_ready_officer())
	_recompute_reach()
	hud.refresh()


func _play_event(e: Dictionary) -> void:
	match String(e.type):
		"move":
			var v: UnitView = unit_views.get(e.unit)
			if v == null:
				return
			var seen := mission.officer_visible_cells()
			if v.unit.is_officer() or seen.has(e.to) or seen.has(e.from):
				v.visible = true
				v.set_walking(true)
				var tw := create_tween()
				tw.tween_property(v, "position", UnitView.cell_to_screen(e.to).round(), STEP_TIME)
				await tw.finished
				v.cell = e.to
				v.set_walking(false)
			else:
				v.snap_to(e.to)
		"shot":
			await _tracer(e)
		"damage":
			var v: UnitView = unit_views.get(e.unit)
			if v and _is_shown(v.unit):
				if int(e.amount) > 0:
					_float_text(v.position + Vector2(0, -50), "-%d" % int(e.amount), Color(1, 0.4, 0.35))
				elif int(e.stun) > 0:
					_float_text(v.position + Vector2(0, -50), "stun", Color(0.6, 0.8, 1))
		"message":
			hud.log_line(e.text)
		"spotted":
			hud.flash_spotted()
		"door", "terrain":
			_refresh_walls()
			_refresh_visuals()
		"spawn":
			var u := mission.unit_by_id(e.unit)
			if u and not unit_views.has(u.id):
				_add_unit_view(u)
		"turn":
			if e.phase == "officers":
				hud.hide_banner()
		"end":
			hud.show_debrief(e.result)
		_:
			var v: UnitView = unit_views.get(e.get("unit", -1))
			if v:
				v.refresh()
	fog.queue_redraw()


func _is_shown(u: TacUnit) -> bool:
	return u.is_officer() or mission.officer_visible_cells().has(u.pos) or u.status == TacUnit.Status.DEAD and _explored.has(u.pos)


func _tracer(e: Dictionary) -> void:
	var from := UnitView.cell_to_screen(e.from) + Vector2(0, -26)
	var to := UnitView.cell_to_screen(e.to) + Vector2(0, -22)
	var line := Line2D.new()
	line.width = 1.5
	var kind: String = e.get("kind", "firearm")
	line.default_color = Color(1, 0.92, 0.6) if kind == "firearm" else (Color(0.7, 0.85, 1) if kind == "less_lethal" else Color(1, 1, 1, 0.8))
	if kind == "melee":
		line.width = 3
	line.points = PackedVector2Array([from, to])
	effects.add_child(line)
	if kind == "firearm" and String(e.get("item", "")) != "":
		var flash := Polygon2D.new()
		flash.polygon = PackedVector2Array([from + Vector2(-3, 0), from + Vector2(0, -3), from + Vector2(3, 0), from + Vector2(0, 3)])
		flash.color = Color(1, 0.8, 0.3)
		effects.add_child(flash)
		get_tree().create_timer(SHOT_TIME * 0.5).timeout.connect(flash.queue_free)
	await get_tree().create_timer(SHOT_TIME).timeout
	line.queue_free()


func _float_text(pos: Vector2, text: String, col: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 9)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.position = pos - Vector2(10, 0)
	effects.add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position", l.position + Vector2(0, -16), 0.7)
	tw.tween_callback(l.queue_free)


func _sync_all() -> void:
	var seen := mission.officer_visible_cells()
	for c in seen:
		_explored[c] = true
	for id in unit_views:
		var v: UnitView = unit_views[id]
		var u := v.unit
		v.snap_to(u.pos)
		v.refresh()
		v.visible = not u.is_gone() and (u.is_officer() or seen.has(u.pos) or (u.is_down() and _explored.has(u.pos) and u.spotted))
	for s in visual_sprites:
		var c: Vector2i = s.get_meta("cell")
		var o := mission.map.object_at(c)
		if not o.is_empty() and int(o.hp) <= 0:
			s.visible = false
	fog.queue_redraw()
	overlay.queue_redraw()


func _refresh_visuals() -> void:
	for s in visual_sprites:
		var c: Vector2i = s.get_meta("cell")
		var o := mission.map.object_at(c)
		if not o.is_empty() and int(o.hp) <= 0 and not o.has("car"):
			s.visible = false


# ---------------------------------------------------------------- drawing

func _diamond(c: Vector2i, inset: float = 0.0) -> PackedVector2Array:
	var g := Iso.tile_to_ground(Vector2(c))
	var t := Iso.TILE_UNITS
	return PackedVector2Array([
		Iso.ground_to_screen(g + Vector2(inset, inset)), Iso.ground_to_screen(g + Vector2(t - inset, inset)),
		Iso.ground_to_screen(g + Vector2(t - inset, t - inset)), Iso.ground_to_screen(g + Vector2(inset, t - inset)),
	])


## Fog of war: unexplored ground is black, explored but unseen ground is dimmed, unlit night ground darker.
func _draw_fog() -> void:
	var seen := mission.officer_visible_cells()
	for c in seen:
		_explored[c] = true
	for y in mission.map.height:
		for x in mission.map.width:
			var c := Vector2i(x, y)
			var a := 0.0
			if not _explored.has(c):
				a = 0.82
			elif not seen.has(c):
				a = 0.5
			elif mission.map.night:
				a = clampf(0.55 - mission.map.light_at(c) * 0.55, 0.0, 0.5)
			if a > 0.0:
				fog.draw_colored_polygon(_diamond(c), Color(0.03, 0.03, 0.06, a))
	# Hide sprites standing on unexplored ground.
	for s in visual_sprites:
		var c: Vector2i = s.get_meta("cell")
		s.modulate = Color(1, 1, 1) if seen.has(c) else (Color(0.55, 0.55, 0.62) if _explored.has(c) else Color(0.2, 0.2, 0.25))
	for k in wall_sprites:
		var s: Sprite2D = wall_sprites[k]
		var c: Vector2i = k[0]
		var lit := seen.has(c) or seen.has(c - (Vector2i(0, 1) if k[1] == "n" else Vector2i(1, 0)))
		var known := _explored.has(c) or _explored.has(c - (Vector2i(0, 1) if k[1] == "n" else Vector2i(1, 0)))
		var base := Color(1, 1, 1) if lit else (Color(0.55, 0.55, 0.62) if known else Color(0.2, 0.2, 0.25))
		base.a = s.modulate.a
		s.modulate = base


func _draw_overlay() -> void:
	if selected == null or mission.phase != TacMission.Phase.OFFICERS:
		return
	if mode == Mode.MOVE and _reach.has("cost"):
		for c in _reach.cost:
			if c != selected.pos:
				overlay.draw_colored_polygon(_diamond(c, 3), Color(0.35, 0.6, 1.0, 0.1))
	if mission.map.in_bounds(hover):
		var col := Color(1, 1, 1, 0.8)
		var target := mission.unit_at(hover)
		if mode == Mode.TARGET:
			col = Color(1, 0.4, 0.3, 0.9)
		elif target and target != selected and mission.visible_to_officers(target):
			col = Color(1, 0.85, 0.4, 0.9)
		elif _reach.has("cost") and not _reach.cost.has(hover):
			col = Color(1, 0.4, 0.4, 0.6)
		var d := _diamond(hover, 1)
		d.append(d[0])
		overlay.draw_polyline(d, col, 1.0)
		if mode == Mode.MOVE and _reach.has("cost") and _reach.cost.has(hover) and target == null:
			var path := Pathfinder.path_from(_reach, hover)
			var prev := UnitView.cell_to_screen(selected.pos)
			for p in path:
				var nxt := UnitView.cell_to_screen(p)
				overlay.draw_line(prev, nxt, Color(0.6, 0.85, 1, 0.8), 1.0)
				prev = nxt
		if mode == Mode.TARGET and target and target != selected:
			overlay.draw_line(UnitView.cell_to_screen(selected.pos) + Vector2(0, -26), UnitView.cell_to_screen(hover) + Vector2(0, -22),
				Color(1, 0.4, 0.3, 0.7), 1.0)
