extends Control
## The division map, X-COM's Geoscape for one LAPD division: compressed time, calls for service blinking
## on the map like UFO contacts, the patrol car driving to them, news and the monthly review.

const MAP_RECT := Rect2(8, 8, 448, 344)
const DISTRICT_COLORS := {
	"silver_lake": Color(0.36, 0.3, 0.46), "echo_park": Color(0.3, 0.42, 0.36), "historic_filipinotown": Color(0.46, 0.38, 0.28),
	"lafayette_park": Color(0.3, 0.36, 0.48), "macarthur_park": Color(0.44, 0.3, 0.3), "pico_union": Color(0.4, 0.4, 0.26),
}
## Streets: [name, from, to] on the unit square.
const SHORT_NAMES := {"silver_lake": "Silver Lake", "echo_park": "Echo Park", "historic_filipinotown": "Historic Filipinotown",
	"lafayette_park": "Lafayette Park", "macarthur_park": "Westlake", "pico_union": "Pico-Union"}
const STREETS := [
	["Sunset Blvd", Vector2(0.0, 0.14), Vector2(1.0, 0.1)], ["Temple St", Vector2(0.35, 0.33), Vector2(1.0, 0.36)],
	["Beverly Blvd", Vector2(0.0, 0.45), Vector2(1.0, 0.47)], ["W 6th St", Vector2(0.0, 0.55), Vector2(1.0, 0.57)],
	["Wilshire Blvd", Vector2(0.0, 0.62), Vector2(1.0, 0.64)], ["Olympic Blvd", Vector2(0.0, 0.84), Vector2(1.0, 0.85)],
	["Pico Blvd", Vector2(0.0, 0.94), Vector2(1.0, 0.95)], ["Hoover St", Vector2(0.2, 0.0), Vector2(0.24, 1.0)],
	["Alvarado St", Vector2(0.56, 0.0), Vector2(0.58, 1.0)], ["Union Ave", Vector2(0.74, 0.3), Vector2(0.76, 1.0)],
	["Echo Park Ave", Vector2(0.66, 0.0), Vector2(0.64, 0.3)],
]

var map_node: Control
var _list: ItemList
var _detail: Label
var _clock: Label
var _status: Label
var _respond2: Button
var _respond3: Button
var _selected := -1
var _blink := 0.0
var _modal: PanelContainer
var _speed_buttons := {}


func _ready() -> void:
	name = "Cityscape"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	UiKit.backdrop(self)
	map_node = Control.new()
	map_node.position = MAP_RECT.position
	map_node.size = MAP_RECT.size
	map_node.draw.connect(_draw_map)
	map_node.gui_input.connect(_map_input)
	add_child(map_node)
	_build_panel()
	Campaign.call_added.connect(func(_c): _refresh_list())
	Campaign.call_changed.connect(func(_c): _refresh_list())
	Campaign.car_arrived.connect(_on_arrived)
	Campaign.news.connect(func(t, x): _popup(t, x))
	Campaign.month_report.connect(_on_month)
	_refresh_list()
	if not Flow.last_notes.is_empty():
		var r := Flow.last_result
		_popup("Debrief: %s" % r.get("rating", ""), "\n".join(Flow.last_notes))
		Flow.last_notes = []
	elif Campaign.history.is_empty() and Campaign.calls.is_empty():
		_popup("PM watch, Rampart Division", "Roll call is over. You ride in 2A43 with your training officer, %s.\n\nCalls for service appear on the map. Pick one from the list and respond Code 2 (urgent, no lights) or Code 3 (lights and siren). Calls you leave waiting escalate, or go to another unit.\n\nUse the time controls to let the watch run. The game pauses when a priority call comes in." % Campaign.people[GameState.get_flag("fto", "ortega")].name)


func _build_panel() -> void:
	var col := VBoxContainer.new()
	col.position = Vector2(464, 8)
	col.custom_minimum_size = Vector2(168, 344)
	col.add_theme_constant_override("separation", 3)
	add_child(col)
	_clock = UiKit.label(col, "", UiKit.ACCENT, 10)
	_status = UiKit.para(col, "", 166, UiKit.MUTED)
	var speeds := GridContainer.new()
	speeds.columns = 4
	col.add_child(speeds)
	for s in ["pause", "5 sec", "1 min", "5 min", "30 min", "1 hour", "1 day"]:
		var sp: String = s
		var b := UiKit.button(speeds, "||" if s == "pause" else s, func(): Campaign.set_speed(sp))
		b.add_theme_font_size_override("font_size", 8)
		_speed_buttons[s] = b
	UiKit.label(col, "CALLS FOR SERVICE", UiKit.ACCENT)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(166, 70)
	_list.item_selected.connect(func(i): _select(int(_list.get_item_metadata(i))))
	col.add_child(_list)
	_detail = UiKit.para(col, "", 166)
	var resp := HBoxContainer.new()
	col.add_child(resp)
	_respond2 = UiKit.button(resp, "Respond Code 2", func(): _respond(2))
	_respond3 = UiKit.button(resp, "Code 3", func(): _respond(3))
	var nav := GridContainer.new()
	nav.columns = 3
	col.add_child(nav)
	UiKit.button(nav, "Station", func(): Flow.station())
	UiKit.button(nav, "Next shift", func(): Campaign.skip_to_next_shift())
	UiKit.button(nav, "Log", _show_history)
	UiKit.button(nav, "Save", func(): _popup("Saved", "Saved." if GameState.save_game() == OK else "Could not save."))
	UiKit.button(nav, "Main menu", func(): Flow.main_menu())


func _process(delta: float) -> void:
	_blink += delta
	map_node.queue_redraw()
	var duty := "ON DUTY" if Campaign.is_on_duty() else "Off duty"
	_clock.text = "%s  %s" % [GameState.date_text(), GameState.clock_text()]
	var car := Campaign.car
	var car_text: String = {"available": "available", "en_route": "en route Code %d" % int(car.code), "on_scene": "on scene",
		"busy": "booking and reports (%d min)" % int(car.get("busy_left", 0)), "returning": "returning"}.get(car.state, car.state)
	_status.text = "%s, PM watch. 2A43 %s.\nProbation month %d of %d. Overtime budget $%d." % [duty, car_text,
		Campaign.months_elapsed() + 1, Campaign.PROBATION_MONTHS, Campaign.overtime_budget]
	for s in _speed_buttons:
		_speed_buttons[s].add_theme_color_override("font_color", UiKit.ACCENT if Campaign.speed == s else UiKit.TEXT)
	var c := Campaign.get_call(_selected)
	var can: bool = not c.is_empty() and c.status == "pending" and car.state == "available" and Campaign.is_on_duty()
	_respond2.disabled = not can
	_respond3.disabled = not can


func _to_map(p: Vector2) -> Vector2:
	return p * MAP_RECT.size


func _draw_map() -> void:
	var font := ThemeDB.fallback_font
	map_node.draw_rect(Rect2(Vector2.ZERO, MAP_RECT.size), Color(0.09, 0.1, 0.13))
	for d in Campaign.DISTRICT_SHAPES:
		var pts := PackedVector2Array()
		for p in Campaign.DISTRICT_SHAPES[d]:
			pts.append(_to_map(Vector2(p[0], p[1])))
		var trust: int = int(GameState.community.get(d, 0))
		var col: Color = DISTRICT_COLORS[d]
		col = col.lerp(Color(0.3, 0.55, 0.35), clampf(trust * 0.08, 0, 0.5)) if trust > 0 else col.lerp(Color(0.6, 0.2, 0.2), clampf(-trust * 0.08, 0, 0.5))
		col.a = 0.55
		map_node.draw_colored_polygon(pts, col)
		var outline := pts.duplicate()
		outline.append(pts[0])
		map_node.draw_polyline(outline, Color(0.55, 0.58, 0.68, 0.6), 1.0)
		var center := Vector2.ZERO
		for p in pts:
			center += p
		center /= pts.size()
		var label_pos := center + Vector2(-80, 0)
		if d == "macarthur_park":
			label_pos = center + Vector2(-20, -24)
		map_node.draw_string(font, label_pos, SHORT_NAMES[d], HORIZONTAL_ALIGNMENT_CENTER, 160, 9, Color(0.9, 0.9, 0.95, 0.85))
	for s in STREETS:
		var a := _to_map(s[1])
		var b := _to_map(s[2])
		map_node.draw_line(a, b, Color(0.75, 0.75, 0.7, 0.35), 2.0)
		var horizontal := absf(b.x - a.x) > absf(b.y - a.y)
		var at := a.lerp(b, 0.02) + (Vector2(2, -2) if horizontal else Vector2(3, 10))
		map_node.draw_string(font, at, s[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.8, 0.8, 0.75, 0.6))
	var park := Rect2(_to_map(Vector2(0.58, 0.58)), _to_map(Vector2(0.1, 0.09)))
	map_node.draw_rect(park, Color(0.25, 0.45, 0.28, 0.85))
	map_node.draw_rect(Rect2(park.position + park.size * 0.25, park.size * 0.5), Color(0.25, 0.4, 0.6, 0.9))
	map_node.draw_string(font, park.position + Vector2(0, -3), "MacArthur Park", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.7, 0.9, 0.7))
	var hole := Rect2(_to_map(Vector2(0.6, 0.7)), _to_map(Vector2(0.08, 0.05)))
	map_node.draw_rect(hole, Color(0.3, 0.26, 0.2, 0.9))
	for i in 6:
		map_node.draw_line(hole.position + Vector2(i * 6, 0), hole.position + Vector2(i * 6 - 10, hole.size.y), Color(0.1, 0.08, 0.06), 1.0)
	map_node.draw_string(font, hole.position + Vector2(0, hole.size.y + 8), "The Hole", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.85, 0.7, 0.5))
	var st := _to_map(Campaign.STATION_POS)
	map_node.draw_rect(Rect2(st - Vector2(5, 5), Vector2(10, 10)), Color(0.3, 0.5, 0.95))
	map_node.draw_string(font, st + Vector2(7, 4), "Rampart Station", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.7, 0.8, 1))
	for c in Campaign.calls:
		if not c.status in ["pending", "assigned", "on_scene"]:
			continue
		var p := _to_map(c.pos)
		var col: Color = [Color(0.9, 0.9, 0.5), Color(1, 0.65, 0.3), Color(1, 0.4, 0.3), Color(1, 0.2, 0.2)][clampi(int(c.priority), 0, 3)]
		var r := 4.0 + (2.0 if fmod(_blink, 1.0) < 0.5 and c.status == "pending" else 0.0)
		map_node.draw_circle(p, r, col)
		if int(c.id) == _selected:
			map_node.draw_arc(p, 9, 0, TAU, 20, Color(1, 1, 1), 1.0)
		map_node.draw_string(font, p + Vector2(6, -4), String(c.type), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, col)
	var car := Campaign.car
	var cp := _to_map(car.pos)
	if car.state == "en_route":
		var target := Campaign.get_call(int(car.call))
		if not target.is_empty():
			map_node.draw_dashed_line(cp, _to_map(target.pos), Color(0.6, 0.8, 1, 0.7), 1.0, 3.0)
	map_node.draw_rect(Rect2(cp - Vector2(4, 3), Vector2(8, 6)), Color(0.05, 0.05, 0.07))
	map_node.draw_rect(Rect2(cp - Vector2(2, 3), Vector2(4, 6)), Color(0.95, 0.95, 0.95))
	if car.state == "en_route" and int(car.code) == 3 and fmod(_blink, 0.5) < 0.25:
		map_node.draw_rect(Rect2(cp - Vector2(3, 5), Vector2(3, 2)), Color(1, 0.2, 0.2))
		map_node.draw_rect(Rect2(cp - Vector2(0, 5), Vector2(3, 2)), Color(0.3, 0.4, 1))
	map_node.draw_string(font, cp + Vector2(6, 10), "2A43", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.85, 0.9, 1))


func _map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for c in Campaign.calls:
			if c.status in ["pending", "assigned"] and _to_map(c.pos).distance_to(event.position) < 10:
				_select(int(c.id))
				return


func _refresh_list() -> void:
	_list.clear()
	for c in Campaign.pending_calls():
		var age := int(Campaign.elapsed_minutes - float(c.created))
		_list.add_item("%s  %s (%dm)" % ["!" if int(c.priority) >= 3 else " ", c.label, age])
		_list.set_item_metadata(_list.item_count - 1, int(c.id))
	_select(_selected)


func _select(id: int) -> void:
	_selected = id
	var c := Campaign.get_call(id)
	if c.is_empty():
		_detail.text = "Select a call."
		return
	var age := int(Campaign.elapsed_minutes - float(c.created))
	_detail.text = "%s\n%s, %s\nPriority %d, waiting %d min. %s" % [c.label, c.address, Campaign.districts[c.district].label,
		int(c.priority), age, "Dispatch information is often wrong." if int(c.priority) >= 2 else ""]


func _respond(code: int) -> void:
	if Campaign.respond(_selected, code):
		Campaign.set_speed("5 sec")
		_refresh_list()


func _on_arrived(c: Dictionary) -> void:
	_modal_open("2A43 on scene", "%s\n%s\n\nYou and your partner get out of the car. Whatever dispatch said, this is what it is now." % [c.label, c.address],
		"Go in", func(): Flow.start_call(int(c.id)))


func _on_month(rep: Dictionary) -> void:
	var fr: Dictionary = rep.force_reviews
	var text := "Calls: %d (%d cleared, %d passed to other units, %d escalated)\nArrests: %d   Rounds fired: %d   Civilians hurt: %d\nScore: %+d\n\nUse of force: %d in policy, %d debriefs, %d disapprovals, %d out of policy\n\nEvaluation: %s\nOvertime budget granted: $%d\n%s" % [
		rep.calls, rep.cleared, rep.missed, rep.escalated, rep.arrests, rep.rounds, rep.harm, rep.score,
		fr.get("In policy", 0), fr.get("In policy, tactical debrief", 0), fr.get("Administrative disapproval", 0), fr.get("Out of policy", 0),
		rep.grade, rep.budget, rep.warning]
	_popup("Monthly review: %s" % rep.month, text)


func _show_history() -> void:
	var lines: Array = []
	for h in Campaign.history.slice(maxi(0, Campaign.history.size() - 14)):
		lines.append("%s  %s  %s" % [h.date, h.label, h.rating])
	_popup("Log", "\n".join(lines) if not lines.is_empty() else "Nothing yet.")


func _popup(title: String, text: String) -> void:
	_modal_open(title, text, "OK", func(): pass)


func _modal_open(title: String, text: String, button_text: String, cb: Callable) -> void:
	Campaign.set_speed("pause")
	if _modal:
		_modal.queue_free()
	_modal = PanelContainer.new()
	_modal.position = Vector2(110, 70)
	_modal.custom_minimum_size = Vector2(300, 0)
	add_child(_modal)
	var col := VBoxContainer.new()
	_modal.add_child(col)
	UiKit.label(col, title, UiKit.ACCENT, 11)
	UiKit.para(col, text, 290)
	var m := _modal
	UiKit.button(col, button_text, func():
		m.queue_free()
		cb.call())
