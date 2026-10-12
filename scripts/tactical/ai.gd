class_name TacAI
extends RefCounted
## Suspects and civilians on their turn. Suspects act on disposition and state (design 6.5): the
## compliant stay put, the actively resisting run, the assaultive close in, the deadly shoot,
## and anyone whose resolve breaks surrenders or flees. Civilians freeze, hide or leave.

static func run_turn(m: TacMission) -> void:
	var gunfire := m.rounds_fired > 0 or m.force_log.size() > 0
	for u in m.suspects():
		if m.phase == TacMission.Phase.OVER:
			return
		if u.can_act():
			_suspect(m, u)
	for u in m.civilians():
		if m.phase == TacMission.Phase.OVER:
			return
		if u.can_act():
			_civilian(m, u, gunfire)
	m.check_end()


static func _visible_officers(m: TacMission, u: TacUnit) -> Array[TacUnit]:
	var out: Array[TacUnit] = []
	for o in m.officers():
		if o.is_active() and m.can_see(u, o):
			out.append(o)
	out.sort_custom(func(a, b): return a.pos.distance_to(u.pos) < b.pos.distance_to(u.pos))
	return out


static func _nearest_officer(m: TacMission, u: TacUnit) -> TacUnit:
	var best: TacUnit = null
	for o in m.officers():
		if o.is_active() and (best == null or o.pos.distance_to(u.pos) < best.pos.distance_to(u.pos)):
			best = o
	return best


static func _suspect(m: TacMission, u: TacUnit) -> void:
	var seen := _visible_officers(m, u)
	if not seen.is_empty():
		u.face(seen[0].pos)
	# Resolve breaks: surrender, or run if afraid of prison or deportation (design 6.5).
	var floor_morale := 10 if u.boosted else (18 if u.state == "gang_loyal" else 30)
	if u.morale < floor_morale and u.status == TacUnit.Status.ACTIVE:
		if u.state == "afraid_of_prison" and m.rng.randf() < 0.6:
			u.disposition = TacUnit.Disposition.ACTIVE
		else:
			m._surrender(u)
			return
	if u.state == "mental_health_crisis" and u.disposition <= TacUnit.Disposition.PASSIVE:
		if m.rng.randf() < 0.4:
			_wander(m, u)
		return
	match u.disposition:
		TacUnit.Disposition.COMPLIANT, TacUnit.Disposition.PASSIVE:
			return
		TacUnit.Disposition.ACTIVE:
			_flee(m, u)
		TacUnit.Disposition.ASSAULTIVE:
			_assault(m, u)
		TacUnit.Disposition.DEADLY:
			_deadly(m, u, seen)


static func _draw_hidden(m: TacMission, u: TacUnit) -> bool:
	if u.right_hand != "" or u.hidden_item == "" or not ItemDB.is_threat(u.hidden_item):
		return false
	if not u.spend(TacMission.DRAW_WEAPON_TU):
		return false
	u.right_hand = u.hidden_item
	u.hidden_item = ""
	u._stock(u.right_hand)
	m._emit({"type": "equip", "unit": u.id})
	if m.visible_to_officers(u):
		m.say("%s pulls a %s." % [u.name, ItemDB.get_item(u.right_hand).name.to_lower()])
		if m.basis != "exigent":
			m.basis = "probable_cause"
	# Drawing in view of officers is a threatening move: reaction fire can answer it.
	m._reaction_fire(u)
	return true


static func _deadly(m: TacMission, u: TacUnit, seen: Array[TacUnit]) -> void:
	if not seen.is_empty():
		_draw_hidden(m, u)
	var w := u.weapon()
	if w == "":
		_assault(m, u)
		return
	if ItemDB.get_item(w).kind == "melee":
		_assault(m, u)
		return
	var shots := 0
	while u.can_act() and shots < 3:
		seen = _visible_officers(m, u)
		if seen.is_empty():
			break
		var target: TacUnit = seen[0]
		var dist := Vector2(target.pos - u.pos).length()
		var modes: Dictionary = ItemDB.get_item(w)["modes"]
		var mode := "aimed" if dist > 6 and modes.has("aimed") and u.tu >= m.mode_tu(u, w, "aimed") else "snap"
		if int(u.ammo.get(w, 0)) <= 0 or u.tu < m.mode_tu(u, w, mode) or not m.line_of_fire(u, target):
			break
		m.fire(u, target, mode)
		shots += 1
	if shots == 0 and u.can_act():
		var o := _nearest_officer(m, u)
		if o == null:
			return
		var cover := _cover_spot(m, u, o)
		if cover != u.pos:
			var path := Pathfinder.find_path(m.map, u.pos, cover, m.occupied(u))
			m.move_unit(u, _affordable(m, u, path, m.mode_tu(u, w, "snap")))
		seen = _visible_officers(m, u)
		if not seen.is_empty() and u.tu >= m.mode_tu(u, w, "snap") and m.line_of_fire(u, seen[0]):
			m.fire(u, seen[0], "snap")


## A nearby cell with cover against the officer, within half the unit's time units.
static func _cover_spot(m: TacMission, u: TacUnit, threat: TacUnit) -> Vector2i:
	var reach := Pathfinder.reachable(m.map, u.pos, u.tu / 2, m.occupied(u))
	var best := u.pos
	var best_score := float(m.map.cover_against(u.pos, threat.pos)) * 10.0
	for c in reach.cost:
		var cv := float(m.map.cover_against(c, threat.pos)) * 10.0
		var score := cv - Vector2(c - threat.pos).length() * 0.2 - float(reach.cost[c]) * 0.05
		if score > best_score:
			best_score = score
			best = c
	return best


static func _affordable(m: TacMission, u: TacUnit, path: Array[Vector2i], keep: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var budget := u.tu - keep
	var prev := u.pos
	for c in path:
		var s := m.map.step_cost(prev, c)
		if s < 0 or s > budget:
			break
		budget -= s
		out.append(c)
		prev = c
	return out


static func _assault(m: TacMission, u: TacUnit) -> void:
	var target: TacUnit = null
	for o in m.units:
		if o == u or o.side == TacUnit.Side.SUSPECT or not o.is_active():
			continue
		if not m.can_see(u, o) and o.pos.distance_to(u.pos) > 6:
			continue
		if target == null or o.pos.distance_to(u.pos) < target.pos.distance_to(u.pos):
			target = o
	if target == null:
		_wander(m, u)
		return
	if target.pos.distance_to(u.pos) >= 1.5:
		var path := Pathfinder.find_path(m.map, u.pos, target.pos, m.occupied(u))
		if path.size() > 1:
			path.resize(path.size() - 1)
			m.move_unit(u, _affordable(m, u, path, 20))
	if not u.can_act() or target.pos.distance_to(u.pos) >= 1.5:
		return
	_draw_hidden(m, u)
	var w := u.weapon()
	if w != "" and ItemDB.get_item(w).kind == "melee":
		m.fire(u, target, "strike")
	else:
		m.punch(u, target)


static func _flee(m: TacMission, u: TacUnit) -> void:
	var goal := _escape_cell(m, u)
	var path := Pathfinder.find_path(m.map, u.pos, goal, m.occupied(u))
	if path.is_empty():
		return
	m.move_unit(u, _affordable(m, u, path, 0))


## The map edge cell that best leads away from the officers.
static func _escape_cell(m: TacMission, u: TacUnit) -> Vector2i:
	var best := u.pos
	var best_score := -INF
	var officer_cells: Array[Vector2i] = []
	for o in m.officers():
		if o.is_active():
			officer_cells.append(o.pos)
	for i in range(0, maxi(m.map.width, m.map.height), 2):
		for c in [Vector2i(i, 0), Vector2i(i, m.map.height - 1), Vector2i(0, i), Vector2i(m.map.width - 1, i)]:
			if not m.map.in_bounds(c) or m.map.object_blocks_move(c) or c in m.map.exit_zone:
				continue
			var away := 0.0
			for oc in officer_cells:
				away += Vector2(c - oc).length()
			var score := away / maxf(1.0, officer_cells.size()) * 1.5 - Vector2(c - u.pos).length()
			if score > best_score:
				best_score = score
				best = c
	return best


static func _wander(m: TacMission, u: TacUnit) -> void:
	var dirs := TacUnit.DIRS.duplicate()
	dirs.shuffle()
	for d in dirs:
		var c: Vector2i = u.pos + d
		if m.map.step_cost(u.pos, c) > 0 and not m.occupied(u).has(c):
			var p: Array[Vector2i] = [c]
			m.move_unit(u, p)
			return


static func _civilian(m: TacMission, u: TacUnit, gunfire: bool) -> void:
	if u.fatal_wounds > 0 or u.health < u.health_max * 0.6:
		return
	var danger: TacUnit = null
	for s in m.suspects():
		if s.is_threat() and (s.is_armed() or s.disposition >= TacUnit.Disposition.ASSAULTIVE) and s.pos.distance_to(u.pos) < 9:
			danger = s
			break
	if danger == null and not gunfire:
		if m.rng.randf() < 0.2:
			_wander(m, u)
		return
	if m.rng.randf() < 0.3:
		u.stance = TacUnit.Stance.KNEELING
		return
	var goal := _escape_cell(m, u)
	var path := Pathfinder.find_path(m.map, u.pos, goal, m.occupied(u))
	var steps := _affordable(m, u, path, 0)
	m.move_unit(u, steps)
	if m.map.is_edge(u.pos) and u.is_active():
		u.status = TacUnit.Status.FLED
		m._emit({"type": "status", "unit": u.id})
