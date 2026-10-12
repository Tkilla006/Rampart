class_name TacMission
extends RefCounted
## The battlescape rules: X-COM's turn structure (the officers' turn, then everyone else's), time units,
## line of sight and fog of war, aimed and snap fire with stray rounds, reaction fire, morale and panic,
## carried into Rampart's police procedure: commands, less-lethal force, cuffs, first aid, backup,
## and a use-of-force review of every application of force (design sections 6.1 to 6.5).
##
## Every rule call appends presentation events to `events`; the battlescape view plays them back.

signal ended(result: Dictionary)

enum Phase { OFFICERS, OTHERS, OVER }

const SIGHT_DAY := 20.0
const SIGHT_NIGHT := 9.0
const SIGHT_FLASHLIGHT := 12.0
const VIEW_CONE_COS := 0.62
const VOICE_RANGE := 9.0
const CALM_RANGE := 4.0
const REACTION_PENALTY := 10
const KNEEL_BONUS := 10
const TARGET_KNEEL_PENALTY := 10
const DARK_PENALTY := 20
const BLIND_PENALTY := 40
const MAX_SHOT_RANGE := 30.0
const COMMAND_TU := 4
const CALM_TU := 15
const FRISK_TU := 15
const CUFF_TU := 20
const AID_TU := 25
const RADIO_TU := 8
const PICKUP_TU := 6
const DRAW_TU := 4
const RELOAD_TU := 15
const DRAW_WEAPON_TU := 8

var map: TacMap
var units: Array[TacUnit] = []
var rng := RandomNumberGenerator.new()
var turn := 1
var phase := Phase.OFFICERS
var events: Array = []
var log_lines: Array[String] = []
var call := {}
var basis := "consensual"
var ground_items := {}
var force_log: Array = []
var stray_rounds: Array = []
var rounds_fired := 0
var weapons_recovered := 0
var contraband_recovered := 0
var backup_turn := -1
var backup_called := false
var backup_pending: Array = []
var withdrawn := false
var difficulty := {"ironman": false}
var objectives: Array = []
var _next_id := 1
var _seen_officers := {}
var _visible_cache := {}


func _init(seed_value: int = 0) -> void:
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value


# ---------------------------------------------------------------- setup

func add_unit(u: TacUnit, at: Vector2i) -> TacUnit:
	u.id = _next_id
	_next_id += 1
	u.pos = at
	units.append(u)
	_visible_cache.clear()
	return u


func officers() -> Array[TacUnit]:
	return units.filter(func(u): return u.side == TacUnit.Side.OFFICER)


func suspects() -> Array[TacUnit]:
	return units.filter(func(u): return u.side == TacUnit.Side.SUSPECT)


func civilians() -> Array[TacUnit]:
	return units.filter(func(u): return u.side == TacUnit.Side.CIVILIAN)


func unit_at(c: Vector2i) -> TacUnit:
	for u in units:
		if u.pos == c and not u.is_gone():
			return u
	return null


func unit_by_id(uid: int) -> TacUnit:
	for u in units:
		if u.id == uid:
			return u
	return null


## Cells that block movement: anyone still standing on the map. Downed bodies can be stepped past.
func occupied(except: TacUnit = null) -> Dictionary:
	var occ := {}
	for u in units:
		if u != except and not u.is_gone() and u.status != TacUnit.Status.DEAD:
			occ[u.pos] = true
	return occ


func start() -> void:
	for u in units:
		u.start_turn()
	_emit({"type": "turn", "turn": turn, "phase": "officers"})
	say("Turn %d. Officers' move." % turn)
	_update_spotting()


# ---------------------------------------------------------------- events and log

func _emit(e: Dictionary) -> void:
	events.append(e)


func say(text: String) -> void:
	log_lines.append(text)
	_emit({"type": "message", "text": text})


func take_events() -> Array:
	var out := events
	events = []
	return out


# ---------------------------------------------------------------- vision

func sight_range(viewer: TacUnit, target_cell: Vector2i) -> float:
	if viewer.blinded_turns > 0:
		return 2.0
	if not map.night:
		return SIGHT_DAY
	var r := SIGHT_NIGHT
	if "night_owl" in viewer.traits:
		r += 3.0
	if map.is_lit(target_cell):
		return SIGHT_DAY
	if viewer.has_item("flashlight") and viewer.is_officer():
		r = maxf(r, SIGHT_FLASHLIGHT)
	return r


func can_see_cell(viewer: TacUnit, c: Vector2i) -> bool:
	if viewer.is_down() or viewer.is_gone():
		return false
	var d := Vector2(c - viewer.pos)
	var dist := d.length()
	if dist <= 1.5:
		return map.has_line_of_sight(viewer.pos, c)
	if dist > sight_range(viewer, c):
		return false
	var f := Vector2(TacUnit.DIRS[viewer.facing]).normalized()
	if f.dot(d.normalized()) < VIEW_CONE_COS:
		return false
	return map.has_line_of_sight(viewer.pos, c)


func can_see(viewer: TacUnit, target: TacUnit) -> bool:
	if target.is_gone():
		return false
	return can_see_cell(viewer, target.pos)


## All cells the officers can currently see (the fog of war).
func officer_visible_cells() -> Dictionary:
	if _visible_cache.has("officers"):
		return _visible_cache["officers"]
	var vis := {}
	for o in officers():
		if o.is_down() or o.is_gone():
			continue
		var r := int(ceil(maxf(SIGHT_DAY, SIGHT_FLASHLIGHT)))
		for y in range(maxi(0, o.pos.y - r), mini(map.height, o.pos.y + r + 1)):
			for x in range(maxi(0, o.pos.x - r), mini(map.width, o.pos.x + r + 1)):
				var c := Vector2i(x, y)
				if not vis.has(c) and can_see_cell(o, c):
					vis[c] = true
	_visible_cache["officers"] = vis
	return vis


func invalidate_vision() -> void:
	_visible_cache.clear()


func visible_to_officers(u: TacUnit) -> bool:
	if u.is_officer():
		return true
	return officer_visible_cells().has(u.pos)


## Marks newly seen suspects and civilians. Returns the units spotted for the first time.
func _update_spotting() -> Array[TacUnit]:
	invalidate_vision()
	var vis := officer_visible_cells()
	var fresh: Array[TacUnit] = []
	for u in units:
		if u.is_officer() or u.is_gone():
			continue
		var seen := vis.has(u.pos)
		if seen and not u.spotted:
			fresh.append(u)
			if u.side == TacUnit.Side.SUSPECT:
				_emit({"type": "spotted", "unit": u.id})
				var what := " with a %s" % ItemDB.get_item(u.right_hand).name.to_lower() if u.is_armed() else ""
				say("Suspect spotted%s." % what)
				if u.is_armed() and basis != "probable_cause":
					basis = "probable_cause" if ItemDB.is_lethal(u.right_hand) or u.disposition >= TacUnit.Disposition.ASSAULTIVE else basis
		u.spotted = seen
	return fresh


# ---------------------------------------------------------------- movement

func move_preview(u: TacUnit) -> Dictionary:
	return Pathfinder.reachable(map, u.pos, u.tu - u.reserved_tu(), occupied(u))


## Walks a unit along a path one step at a time. Movement stops when the unit runs out of TU,
## spots someone new, is hit by reaction fire, or is blocked. Returns the number of steps taken.
func move_unit(u: TacUnit, path: Array[Vector2i]) -> int:
	if not u.can_act():
		return 0
	var steps := 0
	for c in path:
		if not u.can_act():
			break
		var cost := map.step_cost(u.pos, c)
		if cost < 0 or occupied(u).has(c):
			break
		var reserve := u.reserved_tu() if u.is_officer() else 0
		if u.tu - cost < reserve:
			if steps == 0:
				say("Not enough time units.")
			break
		var from := u.pos
		if map.open_door(from, c):
			_emit({"type": "door", "a": from, "b": c})
		u.tu -= cost
		u.face(c)
		u.pos = c
		steps += 1
		_emit({"type": "move", "unit": u.id, "from": from, "to": c})
		invalidate_vision()
		if u.is_officer():
			_rushing_in(u)
			var fresh := _update_spotting()
			if fresh.any(func(f): return f.side == TacUnit.Side.SUSPECT):
				_reaction_fire(u)
				break
		_reaction_fire(u)
		if u.side != TacUnit.Side.OFFICER and map.is_edge(u.pos) and u.disposition >= TacUnit.Disposition.ACTIVE and u.is_threat():
			u.status = TacUnit.Status.FLED
			_emit({"type": "status", "unit": u.id})
			say("%s got away." % _label(u))
			break
	if steps > 0:
		_update_spotting()
	check_end()
	return steps


## Design 6.5: rushing in raises a subject's disposition.
func _rushing_in(o: TacUnit) -> void:
	for s in suspects():
		if s.is_threat() and s.pos.distance_to(o.pos) < 1.5 and s.disposition >= TacUnit.Disposition.PASSIVE \
				and s.disposition < TacUnit.Disposition.DEADLY:
			if rng.randf() < 0.25:
				s.disposition += 1
				say("%s tenses up as you close in (%s)." % [_label(s), s.disposition_name()])


func turn_unit(u: TacUnit, toward: Vector2i) -> bool:
	var cost := u.turn_cost(toward)
	if not u.spend(cost):
		return false
	u.face(toward)
	_emit({"type": "face", "unit": u.id})
	invalidate_vision()
	if u.is_officer():
		_update_spotting()
	return true


func toggle_stance(u: TacUnit) -> bool:
	if not u.can_act() or not u.spend(u.stance_cost()):
		return false
	u.stance = TacUnit.Stance.STANDING if u.stance == TacUnit.Stance.KNEELING else TacUnit.Stance.KNEELING
	_emit({"type": "stance", "unit": u.id})
	return true


# ---------------------------------------------------------------- shooting

func mode_tu(u: TacUnit, weapon_id: String, mode: String) -> int:
	return u.action_tu(int(ItemDB.get_item(weapon_id)["modes"][mode]["tu"]))


## Stress from design 6.3, up to -30, from morale (Composure for officers).
func stress_penalty(u: TacUnit) -> int:
	var p := int(clampf((100 - u.morale) * 0.3, 0.0, 30.0))
	if u.is_officer() and u.officer:
		p = maxi(p, u.officer.stress_penalty("firearms") + (10 if u.morale < 50 else 0))
	if "steady_hands" in u.traits:
		p /= 2
	return mini(p, 30)


## Hit chance (design 6.3): (Perception x 5) + (Firearms x 10) + aim + range - cover - stress - movement - light.
func hit_chance(u: TacUnit, weapon_id: String, mode: String, target: TacUnit, reaction: bool = false) -> int:
	var item := ItemDB.get_item(weapon_id)
	var m: Dictionary = item["modes"][mode]
	var dist := Vector2(target.pos - u.pos).length()
	if item["kind"] == "melee":
		var skill := u.officer.skill("defensive_tactics") if u.officer else 2
		return clampi(55 + skill * 8 + int(m.get("aim", 0)) - (20 if target.can_act() and target.disposition >= TacUnit.Disposition.ACTIVE else 0), 5, 95)
	var c := u.accuracy + int(m.get("aim", 0)) + ItemDB.range_modifier(weapon_id, dist)
	c -= TacMap.COVER_PENALTY[map.cover_against(target.pos, u.pos)]
	c -= stress_penalty(u)
	if reaction:
		c -= REACTION_PENALTY
	if map.night and not map.is_lit(target.pos) and not (u.is_officer() and u.has_item("flashlight") and dist <= SIGHT_FLASHLIGHT):
		c -= DARK_PENALTY
	if u.stance == TacUnit.Stance.KNEELING:
		c += KNEEL_BONUS
	if target.stance == TacUnit.Stance.KNEELING and dist > 5:
		c -= TARGET_KNEEL_PENALTY
	if u.blinded_turns > 0:
		c -= BLIND_PENALTY
	if dist > ItemDB.max_range(weapon_id):
		return 0
	return clampi(c, 0, Check.AUTO_FAIL_FROM - 1)


## Whether anything that stops rounds stands between shooter and target, short of the target's own cover.
func line_of_fire(u: TacUnit, target: TacUnit) -> bool:
	if not map.has_line_of_sight(u.pos, target.pos) and Vector2(target.pos - u.pos).length() > 1.5:
		return false
	for s in map.trace(u.pos, target.pos):
		var c: Vector2i = s.cell
		if c == target.pos:
			return true
		var near_target := Vector2(c - target.pos).length() < 1.5
		if map._crossing_blocked(s.from, c, s.corner, map.wall_stops_rounds) and not near_target:
			return false
		var o := map.object_at(c)
		if not o.is_empty() and bool(o.stops) and int(o.hp) > 0 and not near_target:
			return false
	return true


## Fire a weapon mode at a target: firearms, less-lethal and melee.
func fire(u: TacUnit, target: TacUnit, mode: String, reaction: bool = false) -> bool:
	var weapon_id := u.weapon()
	if weapon_id == "" or target == null or target == u:
		return false
	var item := ItemDB.get_item(weapon_id)
	if not item["modes"].has(mode):
		mode = item["modes"].keys()[0]
	var cost := mode_tu(u, weapon_id, mode)
	if "pair_one_action" in u.background and mode == "pair":
		cost = mode_tu(u, weapon_id, "snap")
	if not u.can_act() or u.tu < cost:
		return false
	var dist := Vector2(target.pos - u.pos).length()
	if item["kind"] == "melee" and dist > 1.5:
		say("Too far for that.")
		return false
	if dist > ItemDB.max_range(weapon_id) and item["kind"] != "melee":
		say("Out of range.")
		return false
	if item.has("capacity") and int(u.ammo.get(weapon_id, 0)) <= 0:
		if weapon_id == "taser_x26" and dist <= 1.5:
			return drive_stun(u, target)
		say("%s is empty." % item.name)
		return false
	u.spend(cost)
	u.face(target.pos)
	_emit({"type": "face", "unit": u.id})
	_log_force(u, target, weapon_id, int(item.get("force", 3)))
	var shots := int(item["modes"][mode].get("shots", 1))
	for i in shots:
		if not target.is_active() and target.status != TacUnit.Status.SURRENDERED and i > 0:
			break
		var chance := hit_chance(u, weapon_id, mode, target, reaction)
		if i > 0:
			chance += int(item["modes"][mode].get("follow_up", 0))
		_resolve_shot(u, target, weapon_id, chance)
	_after_violence(u)
	check_end()
	return true


func _resolve_shot(u: TacUnit, target: TacUnit, weapon_id: String, chance: int) -> void:
	var item := ItemDB.get_item(weapon_id)
	var kind: String = item["kind"]
	if item.has("capacity"):
		u.ammo[weapon_id] = int(u.ammo.get(weapon_id, 0)) - 1
	if kind == "firearm":
		rounds_fired += 1 if u.is_officer() else 0
		u.record.shots += 1
		if rng.randf() < float(item.get("malfunction", 0.0)):
			say("%s's %s malfunctions." % [_label(u), item.name])
			_emit({"type": "shot", "unit": u.id, "from": u.pos, "to": u.pos, "kind": kind, "hit": false})
			return
	var roll := Check.roll_d100(rng)
	var res := Check.resolve(chance, roll)
	if res.success:
		u.record.hits += 1
		_emit({"type": "shot", "unit": u.id, "from": u.pos, "to": target.pos, "kind": kind, "hit": true, "item": weapon_id})
		_apply_hit(u, target, weapon_id)
		return
	if kind == "melee":
		_emit({"type": "shot", "unit": u.id, "from": u.pos, "to": target.pos, "kind": kind, "hit": false, "item": weapon_id})
		say("%s misses %s." % [_label(u), _label(target)])
		return
	if weapon_id == "taser_x26" or weapon_id == "oc_spray":
		_emit({"type": "shot", "unit": u.id, "from": u.pos, "to": target.pos, "kind": kind, "hit": false, "item": weapon_id})
		say("%s misses with the %s." % [_label(u), item.name])
		return
	_stray_round(u, target, weapon_id, chance)


## A miss still goes somewhere (design 6.3): it deviates and travels on until something stops it.
func _stray_round(u: TacUnit, target: TacUnit, weapon_id: String, chance: int) -> void:
	var spread := 1.0 + (100.0 - chance) / 40.0
	var aim_point := Vector2(target.pos) + Vector2(rng.randf_range(-spread, spread), rng.randf_range(-spread, spread))
	if aim_point.round() == Vector2(target.pos):
		aim_point += Vector2(signf(rng.randf() - 0.5), signf(rng.randf() - 0.5))
	var end_cell := Vector2i(aim_point.round())
	if end_cell == u.pos:
		end_cell = target.pos + Vector2i(1, 0)
	var landed := u.pos
	var outcome := "lands in the street"
	for s in map.trace(u.pos, end_cell, MAX_SHOT_RANGE):
		var c: Vector2i = s.cell
		if not map.in_bounds(c):
			outcome = "carries off the block"
			break
		landed = c
		var crossing_wall := map.edge_between(s.from, c) if not s.corner else {}
		if map._crossing_blocked(s.from, c, s.corner, func(w): return not w.is_empty()):
			var note := map.damage_edge(s.from, c, 20) if not s.corner else ""
			if map._crossing_blocked(s.from, c, s.corner, map.wall_stops_rounds):
				outcome = "hits a wall" + (" (%s)" % note if note != "" else "")
				landed = s.from
				break
			if not crossing_wall.is_empty() and crossing_wall.kind == "broken" and note == "glass breaks":
				outcome = "goes through a window"
				_emit({"type": "terrain", "a": s.from, "b": c})
			elif note != "":
				_emit({"type": "terrain", "a": s.from, "b": c})
		var o := map.object_at(c)
		if not o.is_empty() and int(o.hp) > 0:
			map.damage_object(c, 15)
			if bool(o.stops):
				outcome = "hits the %s" % String(o.name).replace("_", " ")
				break
		var victim := unit_at(c)
		if victim and victim != u and victim != target and not victim.is_gone() and rng.randf() < 0.55:
			outcome = "hits %s" % _label(victim)
			_emit({"type": "shot", "unit": u.id, "from": u.pos, "to": c, "kind": "firearm", "hit": true, "item": weapon_id})
			_apply_hit(u, victim, weapon_id)
			stray_rounds.append({"by": u.id, "cell": c, "outcome": outcome, "victim": victim.id})
			say("%s misses %s; the round %s." % [_label(u), _label(target), outcome])
			return
	_emit({"type": "shot", "unit": u.id, "from": u.pos, "to": landed, "kind": "firearm", "hit": false, "item": weapon_id})
	if u.is_officer():
		stray_rounds.append({"by": u.id, "cell": landed, "outcome": outcome, "interior": map.is_interior(landed)})
	say("%s misses %s; the round %s." % [_label(u), _label(target), outcome])


func _apply_hit(u: TacUnit, target: TacUnit, weapon_id: String) -> void:
	var item := ItemDB.get_item(weapon_id)
	var dist := Vector2(target.pos - u.pos).length()
	match weapon_id:
		"taser_x26":
			var probe := int(item.probe_chance)
			if target.look in ["suspect_hoodie", "suspect_flannel"]:
				probe -= 25
			if rng.randi_range(1, 100) > probe:
				say("Only one Taser probe connects; %s keeps going." % _label(target))
				return
			if target.boosted and rng.randf() < 0.5:
				say("%s shrugs off the Taser." % _label(target))
				return
			_incapacitate(target, int(item.incapacitate_turns))
			target.morale -= 30
			say("Taser hit. %s goes rigid and drops." % _label(target))
			return
		"oc_spray":
			_blind(target, int(item.blind_turns))
			target.morale -= 20
			say("OC spray in %s's face." % _label(target))
			for other in units:
				if other != target and other.pos.distance_to(target.pos) < 1.5 and rng.randf() < 0.4:
					_blind(other, 1)
					say("The spray catches %s too." % _label(other))
			return
	var dmg := int(item.get("damage", 0))
	var stun_amount := int(item.get("stun", 0))
	if weapon_id == "beanbag870" and dist < float(item.get("min_safe_range", 2)):
		dmg = int(item.get("close_damage", dmg))
		say("Beanbag fired at very close range.")
	_damage(target, dmg, String(item.get("damage_type", "ballistic")), stun_amount, u)
	if bool(item.get("knockdown", false)) and target.is_active():
		target.knocked_down = true
		target.morale -= 25


## An unarmed blow: a punch, a shove, a tackle (suspects only).
func punch(u: TacUnit, target: TacUnit) -> bool:
	if not u.can_act() or u.pos.distance_to(target.pos) >= 1.5 or not u.spend(u.action_tu(20)):
		return false
	u.face(target.pos)
	_log_force(u, target, "hands", 3)
	_emit({"type": "shot", "unit": u.id, "from": u.pos, "to": target.pos, "kind": "melee", "hit": true, "item": "hands"})
	var chance := 50 + (25 if u.boosted else 0) - (15 if target.stance == TacUnit.Stance.KNEELING else 0)
	if Check.resolve(chance, Check.roll_d100(rng)).success:
		say("%s strikes %s." % [_label(u), _label(target)])
		_damage(target, 4 if not u.boosted else 10, "impact", 10 if not u.boosted else 18, u)
	else:
		say("%s swings at %s and misses." % [_label(u), _label(target)])
	return true


func drive_stun(u: TacUnit, target: TacUnit) -> bool:
	var cost := u.action_tu(20)
	if not u.spend(cost):
		return false
	_log_force(u, target, "taser_x26", 4)
	var chance := hit_chance(u, "baton", "strike", target)
	if Check.resolve(chance, Check.roll_d100(rng)).success:
		_damage(target, 1, "electric", int(ItemDB.get_item("taser_x26").drive_stun), u)
		say("Drive stun on %s." % _label(target))
	else:
		say("%s twists away from the drive stun." % _label(target))
	_after_violence(u)
	return true


func _blind(t: TacUnit, turns: int) -> void:
	t.blinded_turns = maxi(t.blinded_turns, turns)
	_emit({"type": "status", "unit": t.id})


func _incapacitate(t: TacUnit, turns: int) -> void:
	if t.status == TacUnit.Status.ACTIVE:
		t.status = TacUnit.Status.INCAPACITATED
		t.incapacitated_turns = turns
		_emit({"type": "status", "unit": t.id})


## Damage, X-COM style: 50-150% of the weapon's power, minus armor; heavy hits cause bleeding wounds.
func _damage(t: TacUnit, amount: int, damage_type: String, stun_amount: int, by: TacUnit) -> void:
	var dealt := 0
	if amount > 0:
		var rolled := int(round(amount * rng.randf_range(0.5, 1.5)))
		dealt = maxi(0, rolled - t.armor_value(damage_type))
	var stunned := stun_amount
	if t.boosted:
		stunned /= 2
	t.health -= dealt
	t.stun += stunned
	t.record.damage_taken += dealt
	if damage_type in ["ballistic", "edged"] and dealt >= 8:
		t.fatal_wounds += 1 if dealt < 20 else 2
	_emit({"type": "damage", "unit": t.id, "amount": dealt, "stun": stunned})
	var label := _label(t)
	if dealt == 0 and stunned == 0:
		say("%s is hit; the vest stops it." % label if t.armor != "" else "%s is hit but unhurt." % label)
	if t.health <= 0:
		_go_down(t)
	elif t.stun >= t.health and t.status == TacUnit.Status.ACTIVE:
		t.status = TacUnit.Status.UNCONSCIOUS
		say("%s is knocked out." % label)
		_emit({"type": "status", "unit": t.id})
	elif dealt > 0:
		say("%s is hit: %s." % [label, t.wound_label().to_lower()])
	if t.is_active():
		t.morale -= 15 + dealt / 2
	_morale_shock(t)


func _go_down(t: TacUnit) -> void:
	t.health = mini(t.health, 0)
	if t.status == TacUnit.Status.DEAD:
		return
	t.status = TacUnit.Status.DYING
	t.dying_turns = TacUnit.BLEED_OUT_TURNS
	say("%s is down and dying. First aid within %d turns." % [_label(t), t.dying_turns])
	_emit({"type": "status", "unit": t.id})


## Everyone who sees someone go down or get hurt loses morale (X-COM), scaled by their bravery.
func _morale_shock(victim: TacUnit) -> void:
	for w in units:
		if w == victim or not w.is_active() or not can_see(w, victim) and w.pos.distance_to(victim.pos) > 4:
			continue
		var loss := 5 + (100 - w.bravery) / 10
		if victim.is_down() and victim.side == w.side:
			loss += 10
		if w.is_officer() and "iron_stomach" in w.traits:
			loss /= 2
		if w.is_officer() and w.background.get("calm_with_gore", false):
			loss /= 2
		w.morale = maxi(0, w.morale - loss)


func _after_violence(actor: TacUnit) -> void:
	for c in civilians():
		if c.is_active() and c.pos.distance_to(actor.pos) < 10:
			c.morale = maxi(0, c.morale - 10)
	invalidate_vision()


# ---------------------------------------------------------------- reaction fire

## X-COM reaction fire, with police triggers (design 6.3 hold aim): officers fire only on a visible
## deadly threat, Taser runners in range, or misread a lookalike object when their Composure is gone.
func _reaction_fire(mover: TacUnit) -> void:
	if not mover.is_active():
		return
	for r in units:
		if r == mover or not r.can_act() or r.side == mover.side or not can_see(r, mover):
			continue
		var w := r.weapon()
		if w == "":
			continue
		var trigger := _reaction_trigger(r, mover)
		if trigger == "":
			continue
		var mode: String = "snap" if ItemDB.get_item(w)["modes"].has("snap") else ItemDB.get_item(w)["modes"].keys()[0]
		if r.tu < mode_tu(r, w, mode):
			continue
		var r_score := r.reactions * float(r.tu) / float(maxi(r.tu_max, 1))
		var m_score := mover.reactions * float(mover.tu) / float(maxi(mover.tu_max, 1))
		if r.officer and r.officer.habit_named("engage_the_threat"):
			r_score += 10 * r.officer.habit_named("engage_the_threat").strength
		if r_score <= m_score:
			continue
		if trigger == "misread":
			say("%s sees something in %s's hand and fires." % [_label(r), _label(mover)])
		else:
			say("Reaction fire from %s." % _label(r))
		_emit({"type": "reaction", "unit": r.id})
		r.record.reaction_shots += 1
		fire(r, mover, mode, true)
		if not mover.is_active():
			return


func _reaction_trigger(r: TacUnit, mover: TacUnit) -> String:
	var dist := Vector2(mover.pos - r.pos).length()
	if r.is_officer():
		if mover.side == TacUnit.Side.CIVILIAN:
			return ""
		if mover.is_armed() and mover.disposition >= TacUnit.Disposition.ASSAULTIVE:
			var deadly: bool = ItemDB.get_item(mover.right_hand).kind == "firearm" or dist <= 5.0
			if deadly and ItemDB.is_lethal(r.weapon()):
				return "weapon"
			if ItemDB.get_item(r.weapon()).kind == "less_lethal" and dist <= ItemDB.max_range(r.weapon()):
				return "weapon"
		if r.weapon() == "taser_x26" and mover.disposition == TacUnit.Disposition.ACTIVE and dist <= 5.0 \
				and int(r.ammo.get("taser_x26", 0)) > 0:
			return "runner"
		if mover.holds_lookalike() and r.morale < 25 and rng.randf() < 0.35 and ItemDB.is_lethal(r.weapon()):
			return "misread"
		return ""
	if r.side == TacUnit.Side.SUSPECT and r.disposition == TacUnit.Disposition.DEADLY and mover.is_officer():
		if ItemDB.get_item(r.weapon()).kind == "firearm":
			return "weapon"
	return ""


# ---------------------------------------------------------------- police actions

func command_cost(u: TacUnit) -> int:
	return 0 if not u.free_command_used else COMMAND_TU


func command_chance(u: TacUnit, target: TacUnit) -> int:
	var c := u.officer.skill_chance("command_presence") if u.officer else 40
	if "silver_tongue" in u.traits:
		c += 10
	if "big_mouth" in u.traits:
		c -= 10
	if target.state == "mental_health_crisis":
		c -= 30
	if target.state == "gang_loyal":
		c -= 10
	if target.boosted:
		c -= 15
	return clampi(c, 0, Check.AUTO_FAIL_FROM - 1)


## "Show me your hands! Get on the ground!" The first short command each turn is free (design 6.3).
func command(u: TacUnit, target: TacUnit) -> bool:
	if not u.can_act() or target.side == TacUnit.Side.OFFICER or not target.is_active():
		return false
	if Vector2(target.pos - u.pos).length() > VOICE_RANGE:
		say("Too far to be heard.")
		return false
	var cost := command_cost(u)
	if not u.spend(cost):
		return false
	u.free_command_used = true
	u.record.commands += 1
	_log_force(u, target, "command", 2)
	var res := Check.make(command_chance(u, target), rng)
	_emit({"type": "command", "unit": u.id, "target": target.id, "success": res.success})
	if not res.success:
		say("%s shouts commands; %s doesn't comply." % [_label(u), _label(target)])
		if target.state == "gang_loyal" and rng.randf() < 0.3 and target.disposition < TacUnit.Disposition.DEADLY:
			target.disposition += 1
		return true
	var drop := rng.randi_range(15, 30) + (10 if res.clean else 0)
	target.morale -= drop
	if target.side == TacUnit.Side.CIVILIAN:
		say("%s moves back as ordered." % _label(target))
		target.morale = maxi(target.morale, 30)
		return true
	if target.morale < 25 or (target.morale < 55 and target.disposition <= TacUnit.Disposition.ACTIVE) \
			or target.disposition <= TacUnit.Disposition.PASSIVE and target.morale < 70:
		_surrender(target)
	else:
		say("%s hesitates (%s)." % [_label(target), target.morale_label().to_lower()])
	check_end()
	return true


func calm_chance(u: TacUnit, target: TacUnit) -> int:
	var c := u.officer.skill_chance("de_escalation") if u.officer else 40
	if "silver_tongue" in u.traits:
		c += 10
	if "temper" in u.traits:
		c -= 10
	if target.state == "mental_health_crisis":
		c += 10
	for o in officers():
		if o.key == "ortega" and o.is_active() and o.pos.distance_to(target.pos) <= CALM_RANGE + 2:
			c += 15
	if u.key == "arakawa":
		c += 20
	if target.disposition == TacUnit.Disposition.DEADLY:
		c -= 20
	return clampi(c, 0, Check.AUTO_FAIL_FROM - 1)


## De-escalation: lowers a subject's disposition one step and their resolve (design 6.1, 6.5).
func calm(u: TacUnit, target: TacUnit) -> bool:
	if not u.can_act() or not target.is_active() or target.side == TacUnit.Side.OFFICER:
		return false
	if Vector2(target.pos - u.pos).length() > CALM_RANGE:
		say("Get closer to talk.")
		return false
	if not u.spend(CALM_TU):
		return false
	u.record.commands += 1
	var res := Check.make(calm_chance(u, target), rng)
	_emit({"type": "command", "unit": u.id, "target": target.id, "success": res.success})
	if res.success:
		target.disposition = maxi(0, target.disposition - (2 if res.clean else 1)) as TacUnit.Disposition
		target.morale -= 15
		say("%s talks %s down a step (%s)." % [_label(u), _label(target), target.disposition_name()])
		if target.side == TacUnit.Side.SUSPECT and target.disposition <= TacUnit.Disposition.PASSIVE and target.morale < 60:
			_surrender(target)
	else:
		say("%s tries to calm %s. It doesn't land." % [_label(u), _label(target)])
	check_end()
	return true


func _surrender(t: TacUnit) -> void:
	t.status = TacUnit.Status.SURRENDERED
	t.stance = TacUnit.Stance.KNEELING
	if t.right_hand != "" and ItemDB.is_threat(t.right_hand):
		_drop_item(t, t.right_hand)
		say("%s drops the %s and gets on the ground." % [_label(t), ItemDB.get_item(t.right_hand).name.to_lower()])
		t.right_hand = ""
	else:
		say("%s puts their hands up and gets on the ground." % _label(t))
	_emit({"type": "status", "unit": t.id})


func _drop_item(t: TacUnit, item: String) -> void:
	if not ground_items.has(t.pos):
		ground_items[t.pos] = []
	ground_items[t.pos].append(item)
	_emit({"type": "item", "cell": t.pos})


func can_handcuff(u: TacUnit, target: TacUnit) -> bool:
	if target.side == TacUnit.Side.OFFICER or target.status in [TacUnit.Status.CUFFED, TacUnit.Status.DEAD, TacUnit.Status.FLED]:
		return false
	return u.pos.distance_to(target.pos) < 1.5 and u.has_item("handcuffs") and int(u.uses.get("handcuffs", 0)) > 0


func cuff_chance(u: TacUnit, target: TacUnit) -> int:
	var c := u.officer.skill_chance("defensive_tactics", 20) if u.officer else 50
	if target.status != TacUnit.Status.ACTIVE:
		c += 30
	else:
		c -= 10 * maxi(0, target.disposition - 1)
	if u.background.get("detainee_control", false):
		c += 10
	return clampi(c, 5, Check.AUTO_FAIL_FROM - 1)


## The arrest sequence (design 6.2), compressed into one action: control, cuff, double-lock.
func handcuff(u: TacUnit, target: TacUnit) -> bool:
	if not u.can_act() or not can_handcuff(u, target) or not u.spend(CUFF_TU):
		return false
	u.face(target.pos)
	var res := Check.make(cuff_chance(u, target), rng)
	if not res.success:
		say("%s pulls away from the cuffs." % _label(target))
		if target.status == TacUnit.Status.ACTIVE and target.disposition < TacUnit.Disposition.DEADLY and rng.randf() < 0.5:
			target.disposition += 1
		return true
	var lawful := _has_probable_cause(target)
	target.status = TacUnit.Status.CUFFED
	target.stance = TacUnit.Stance.KNEELING
	u.uses["handcuffs"] = int(u.uses.get("handcuffs", 1)) - 1
	u.record.arrests += 1
	if target.right_hand != "" and target.right_hand != "phone":
		_drop_item(target, target.right_hand)
		target.right_hand = ""
	_emit({"type": "status", "unit": target.id})
	say("%s is in custody%s." % [_label(target), "" if lawful else " (no probable cause on record)"])
	if not lawful:
		force_log.append({"actor": u.id, "target": target.id, "item": "arrest", "force": 3, "actual": 0, "perceived": 0, "warned": 0, "unlawful_arrest": true, "target_status": "active"})
	check_end()
	return true


func _has_probable_cause(t: TacUnit) -> bool:
	if basis in ["probable_cause", "exigent"]:
		return true
	return t.disposition >= TacUnit.Disposition.ASSAULTIVE or t.record.get("found_contraband", false) or t.record.get("attacked", false)


## Pat-down (design 6.1): reveals hidden weapons and contraband by depth, one Search roll.
func frisk(u: TacUnit, target: TacUnit) -> bool:
	if not u.can_act() or u.pos.distance_to(target.pos) >= 1.5 or not u.spend(FRISK_TU):
		return false
	var c := u.officer.skill_chance("search", 10) if u.officer else 50
	if Check.make(c, rng).success and target.hidden_item != "":
		var item := target.hidden_item
		target.hidden_item = ""
		var d := ItemDB.get_item(item)
		say("Pat-down turns up a %s." % d.name.to_lower())
		if d.kind in ["firearm", "melee"]:
			weapons_recovered += 1
		elif d.kind == "contraband":
			contraband_recovered += 1
			target.record["found_contraband"] = true
		u.ground_items.append(item)
	else:
		say("The pat-down finds nothing.")
	var suspicion: bool = target.record.get("known_hidden", false) or target.record.get("parole", false) or target.record.get("warrant", false)
	if basis == "consensual" and not suspicion and target.disposition <= TacUnit.Disposition.PASSIVE and not target.status in [TacUnit.Status.CUFFED]:
		force_log.append({"actor": u.id, "target": target.id, "item": "frisk", "force": 3, "actual": target.disposition, "perceived": target.disposition, "warned": 0, "no_basis": true, "target_status": target.status_name()})
	return true


func aid_chance(u: TacUnit, target: TacUnit) -> int:
	var c := u.officer.skill_chance("first_aid", 20) if u.officer else 40
	if u.background.get("calm_with_gore", false):
		c += 10
	return clampi(c, 5, Check.AUTO_FAIL_FROM - 1)


## First aid: pressure, tourniquet, CPR. Stops bleeding and stabilizes the dying, suspects included.
func first_aid(u: TacUnit, target: TacUnit) -> bool:
	if not u.can_act() or u.pos.distance_to(target.pos) >= 1.5 or target.status == TacUnit.Status.DEAD:
		return false
	if int(u.uses.get("first_aid_kit", 0)) <= 0 and not u.has_item("first_aid_kit"):
		u.uses["first_aid_kit"] = u.uses.get("first_aid_kit", 1)
	if not u.spend(AID_TU):
		return false
	u.record.aid += 1
	var res := Check.make(aid_chance(u, target), rng)
	if res.success:
		target.fatal_wounds = 0
		target.health = maxi(target.health, 1) + (6 if res.clean else 3)
		target.health = mini(target.health, target.health_max)
		if target.status == TacUnit.Status.DYING:
			target.status = TacUnit.Status.UNCONSCIOUS
			say("%s stabilizes %s." % [_label(u), _label(target)])
		else:
			say("%s stops %s's bleeding." % [_label(u), _label(target)])
		target.record["aided"] = true
	else:
		target.fatal_wounds = maxi(0, target.fatal_wounds - 1)
		say("%s works on %s; the bleeding slows." % [_label(u), _label(target)])
	_emit({"type": "status", "unit": target.id})
	return true


## Ask a witness what happened (design 6.1): a good statement points out hidden weapons,
## which gives reasonable suspicion for a pat-down.
func ask_witness(u: TacUnit, witness: TacUnit) -> bool:
	if not u.can_act() or witness.side != TacUnit.Side.CIVILIAN or witness.is_down():
		return false
	if Vector2(witness.pos - u.pos).length() > CALM_RANGE or not u.spend(8):
		return false
	var c := u.officer.skill_chance("interview") if u.officer else 40
	if not Check.make(c, rng).success:
		say("%s: \"I didn't see anything.\"" % _label(witness))
		return true
	for s in suspects():
		if s.is_threat() and s.hidden_item != "" and ItemDB.is_threat(s.hidden_item):
			s.record["known_hidden"] = true
			if basis == "consensual":
				basis = "reasonable_suspicion"
			say("%s: \"The %s has a %s on him.\"" % [_label(witness), s.name.to_lower(), ItemDB.get_item(s.hidden_item).name.to_lower()])
			return true
	var label: String = call.get("truth", {}).get("true_label", "")
	say("%s: \"%s\"" % [_label(witness), "It's not what they told you. " + label if label != "" else "He's been like this all day."])
	return true


## Run a name through dispatch (design 6.1): a warrant hit is instant probable cause.
func run_name(u: TacUnit, target: TacUnit) -> bool:
	if not u.can_act() or target.side != TacUnit.Side.SUSPECT or not u.spend(RADIO_TU):
		return false
	if target.record.get("ran", false):
		say("Already ran %s." % _label(target))
		return true
	target.record["ran"] = true
	var c := u.officer.skill_chance("radio_and_dispatch") if u.officer else 50
	if not Check.make(c, rng).success:
		say("Dispatch: say again, 2A43? The return is garbled.")
		target.record["ran"] = false
		return true
	if rng.randf() < 0.3:
		target.record["warrant"] = true
		target.record["attacked"] = true
		basis = "probable_cause"
		say("Dispatch: %s comes back with a felony warrant." % _label(target))
	elif rng.randf() < 0.3:
		say("Dispatch: %s is on parole, search conditions." % _label(target))
		target.record["parole"] = true
		if basis == "consensual":
			basis = "reasonable_suspicion"
	else:
		say("Dispatch: no wants, no warrants on %s." % _label(target))
	return true


## Radio for backup; "officer needs help" brings two units fast (design 6.5).
func request_backup(u: TacUnit, emergency: bool = false) -> bool:
	if backup_called or not u.can_act() or not u.spend(RADIO_TU):
		return false
	var c := u.officer.skill_chance("radio_and_dispatch", 20) if u.officer else 50
	var delay := 2 if emergency else 4
	if not Check.make(c, rng).success:
		delay += 1
	if u.background.get("clean_radio", false):
		delay -= 1
	backup_called = true
	backup_turn = turn + maxi(1, delay)
	say("%s: Rampart, %s. Backup ETA %d turns." % [_label(u), "officer needs help" if emergency else "requesting backup", backup_turn - turn])
	return true


func pick_up(u: TacUnit) -> bool:
	var items: Array = ground_items.get(u.pos, [])
	if items.is_empty() or not u.can_act() or not u.spend(PICKUP_TU):
		return false
	for item in items:
		var d := ItemDB.get_item(item)
		if d.kind in ["firearm", "melee"]:
			weapons_recovered += 1
		elif d.kind == "contraband":
			contraband_recovered += 1
		u.ground_items.append(item)
	say("%s makes the scene safe: %s bagged as evidence." % [_label(u), ", ".join(items.map(func(i): return ItemDB.get_item(i).name.to_lower()))])
	ground_items.erase(u.pos)
	_emit({"type": "item", "cell": u.pos})
	return true


## Switches the item in hand with one on the belt (drawing a weapon is reviewed, design 6.3).
func equip(u: TacUnit, item: String) -> bool:
	if not u.can_act() or not item in u.belt or not u.spend(DRAW_TU):
		return false
	u.belt.erase(item)
	if u.right_hand != "":
		u.belt.append(u.right_hand)
	u.right_hand = item
	if u.is_officer() and ItemDB.is_lethal(item):
		u.record["drew_firearm"] = true
	_emit({"type": "equip", "unit": u.id})
	return true


func reload(u: TacUnit) -> bool:
	var w := u.weapon()
	if w == "" or not ItemDB.get_item(w).has("capacity"):
		return false
	var spare_key := "%s_spare" % w
	if int(u.uses.get(spare_key, 0)) <= 0 or not u.spend(RELOAD_TU):
		return false
	u.uses[spare_key] = int(u.uses[spare_key]) - 1
	u.ammo[w] = int(ItemDB.get_item(w).capacity)
	say("%s reloads." % _label(u))
	return true


# ---------------------------------------------------------------- force review

func _threat_level(t: TacUnit, observer: TacUnit) -> int:
	if t.status != TacUnit.Status.ACTIVE:
		return 0
	if t.is_armed():
		var dist := Vector2(t.pos - observer.pos).length()
		if ItemDB.get_item(t.right_hand).kind == "firearm" and t.disposition >= TacUnit.Disposition.ACTIVE:
			return 4
		if dist <= 5.0 and t.disposition >= TacUnit.Disposition.ASSAULTIVE:
			return 4
		return maxi(3, t.disposition)
	return mini(t.disposition, 3)


func _perceived_threat(t: TacUnit, observer: TacUnit) -> int:
	var actual := _threat_level(t, observer)
	if t.status == TacUnit.Status.ACTIVE and t.holds_lookalike() and observer.morale < 25:
		return 4
	return actual


func _log_force(u: TacUnit, t: TacUnit, item: String, level: int) -> void:
	if t.side == TacUnit.Side.OFFICER:
		return
	if u.side != TacUnit.Side.OFFICER:
		# Assaulting anyone gives officers probable cause to arrest (design 6.2).
		u.record["attacked"] = true
		return
	var warned := int(t.record.get("warned_by_%d" % u.id, 0))
	if item == "command":
		t.record["warned_by_%d" % u.id] = warned + 1
		return
	u.record.force += 1
	force_log.append({"actor": u.id, "target": t.id, "item": item, "force": level, "actual": _threat_level(t, u),
		"perceived": _perceived_threat(t, u), "warned": warned, "target_status": t.status_name(),
		"target_holding": t.right_hand, "distance": snappedf(Vector2(t.pos - u.pos).length(), 0.1)})


## The use-of-force review (design 6.5): each application of force is judged on the threat at that
## moment, as it was and as the officer perceived it, and on warnings given first.
static func review_force_event(e: Dictionary) -> Dictionary:
	if e.get("unlawful_arrest", false):
		return {"outcome": "Administrative disapproval", "severity": 2, "reason": "arrest without probable cause"}
	if e.get("no_basis", false):
		return {"outcome": "Administrative disapproval", "severity": 2, "reason": "pat-down without reasonable suspicion"}
	var force: int = int(e.force)
	var actual: int = int(e.actual)
	var perceived: int = int(e.perceived)
	if e.get("target_status", "active") in ["surrendered", "in custody", "unconscious", "incapacitated", "dying"]:
		return {"outcome": "Out of policy", "severity": 3, "reason": "force on a subject who was already controlled"}
	var needed := {6: 4, 5: 3, 4: 2, 3: 1}
	var required: int = needed.get(force, 0)
	if perceived < required:
		if force == 6 or required - perceived >= 2:
			return {"outcome": "Out of policy", "severity": 3, "reason": "force far beyond the threat"}
		return {"outcome": "Administrative disapproval", "severity": 2, "reason": "force one step beyond the threat"}
	if actual < perceived:
		return {"outcome": "In policy, tactical debrief", "severity": 1,
			"reason": "the threat was perceived, not real (%s)" % String(e.get("target_holding", "")).replace("_", " ")}
	if int(e.warned) == 0 and actual < 4:
		return {"outcome": "In policy, tactical debrief", "severity": 1, "reason": "no warning before force"}
	return {"outcome": "In policy", "severity": 0, "reason": "force matched the threat"}


# ---------------------------------------------------------------- turns

func end_officer_turn() -> void:
	if phase != Phase.OFFICERS:
		return
	phase = Phase.OTHERS
	_emit({"type": "turn", "turn": turn, "phase": "others"})
	for u in units:
		if u.side != TacUnit.Side.OFFICER:
			u.start_turn()
	TacAI.run_turn(self)
	_end_of_round()
	if phase == Phase.OVER:
		return
	turn += 1
	phase = Phase.OFFICERS
	for u in officers():
		u.start_turn()
	_emit({"type": "turn", "turn": turn, "phase": "officers"})
	say("Turn %d." % turn)
	_arrive_backup()
	_panic_checks()
	_update_spotting()
	check_end()


## Bleeding, bleed-out, recovery from Taser and OC, morale recovery (X-COM fatal wounds).
func _end_of_round() -> void:
	for u in units:
		if u.is_gone() or u.status == TacUnit.Status.DEAD:
			continue
		if u.fatal_wounds > 0 and u.status != TacUnit.Status.DYING:
			u.health -= u.fatal_wounds
			if u.health <= 0:
				_go_down(u)
		if u.status == TacUnit.Status.DYING:
			u.dying_turns -= 1
			if u.dying_turns <= 0:
				if u.is_officer() and not difficulty.get("ironman", false):
					u.status = TacUnit.Status.UNCONSCIOUS
					u.health = 0
					say("%s is critically wounded and unconscious." % _label(u))
				else:
					u.status = TacUnit.Status.DEAD
					say("%s has died." % _label(u))
					_morale_shock(u)
				_emit({"type": "status", "unit": u.id})
		if u.status == TacUnit.Status.INCAPACITATED:
			u.incapacitated_turns -= 1
			if u.incapacitated_turns <= 0:
				u.status = TacUnit.Status.ACTIVE
				_emit({"type": "status", "unit": u.id})
		if u.blinded_turns > 0:
			u.blinded_turns -= 1
		if u.stun > 0 and u.status != TacUnit.Status.UNCONSCIOUS:
			u.stun = maxi(0, u.stun - 2)
		if u.is_active():
			u.morale = mini(100, u.morale + 4)
	check_end()


## X-COM panic, Rampart style: at zero Composure the body picks from its Habits (design 5).
func _panic_checks() -> void:
	for o in officers():
		if not o.can_act() or o.morale >= 50:
			continue
		var chance := (50 - o.morale) * 2
		if rng.randi_range(1, 100) > chance:
			continue
		o.record.panicked += 1
		var visible_threat: TacUnit = null
		for s in suspects():
			if s.is_threat() and s.is_armed() and can_see(o, s):
				visible_threat = s
				break
		var casualty: TacUnit = null
		for c in units:
			if c.side != TacUnit.Side.SUSPECT and c.is_down() and c.status != TacUnit.Status.DEAD:
				casualty = c
				break
		var habit := ""
		if o.officer:
			for h in o.officer.habits:
				habit = h.name if habit == "" else habit
				if h.name == "engage_the_threat" and visible_threat:
					habit = h.name
					break
				if h.name == "run_to_the_wounded" and casualty:
					habit = h.name
					break
		match habit:
			"engage_the_threat":
				if visible_threat:
					say("%s's training takes over: Engage the Threat." % _label(o))
					fire(o, visible_threat, "pair" if ItemDB.get_item(o.weapon()).modes.has("pair") else "snap")
					continue
			"run_to_the_wounded":
				if casualty:
					say("%s runs to the wounded." % _label(o))
					var path := Pathfinder.find_path(map, o.pos, casualty.pos, occupied(o))
					if path.size() > 1:
						path.resize(path.size() - 1)
					move_unit(o, path)
					continue
			"cover_first":
				say("%s goes to cover." % _label(o))
				o.stance = TacUnit.Stance.KNEELING
				o.tu = o.tu / 2
				continue
			"book_answer":
				say("%s hesitates, looking for the procedure." % _label(o))
				o.tu = o.tu / 2
				continue
		say("%s freezes." % _label(o))
		o.tu = 0


func _arrive_backup() -> void:
	if backup_turn < 0 or turn < backup_turn:
		return
	backup_turn = -1
	var spots: Array[Vector2i] = []
	for c in map.officer_start:
		if unit_at(c) == null:
			spots.append(c)
	for entry in backup_pending:
		if spots.is_empty():
			break
		var u: TacUnit = entry
		add_unit(u, spots.pop_front())
		u.start_turn()
		_emit({"type": "spawn", "unit": u.id})
	if not backup_pending.is_empty():
		say("Backup arrives.")
	backup_pending.clear()


# ---------------------------------------------------------------- end

func check_end() -> bool:
	if phase == Phase.OVER:
		return true
	var officers_up := officers().filter(func(o): return o.is_active())
	if officers_up.is_empty():
		_finish(false, "All officers are down.")
		return true
	if suspects().all(func(s): return not s.is_threat()):
		_finish(true, "Scene secured.")
		return true
	return false


func withdraw() -> void:
	withdrawn = true
	_finish(false, "Officers withdrew to wait for SWAT.")


func _finish(success: bool, reason: String) -> void:
	if phase == Phase.OVER:
		return
	phase = Phase.OVER
	# Back to Contact (design 6.5): surrendered and unconscious subjects are cuffed once the threat is over.
	for s in suspects():
		if s.status in [TacUnit.Status.SURRENDERED, TacUnit.Status.UNCONSCIOUS, TacUnit.Status.INCAPACITATED]:
			s.status = TacUnit.Status.CUFFED
		elif s.status == TacUnit.Status.ACTIVE and not success:
			s.status = TacUnit.Status.FLED
	for u in units:
		if u.status == TacUnit.Status.DYING:
			u.status = TacUnit.Status.UNCONSCIOUS if u.is_officer() else TacUnit.Status.DEAD
	# The RA takes the wounded nobody treated; some don't make it.
	for c in civilians():
		if c.fatal_wounds > 0 and not c.record.get("aided", false) and c.status != TacUnit.Status.DEAD:
			if rng.randf() < 0.3:
				c.status = TacUnit.Status.DEAD
				say("%s dies before the RA arrives." % _label(c))
	if success:
		for items in ground_items.values():
			for item in items:
				var d := ItemDB.get_item(item)
				if d.kind in ["firearm", "melee"]:
					weapons_recovered += 1
	say(reason)
	var result := debrief(success, reason)
	_emit({"type": "end", "result": result})
	ended.emit(result)


## X-COM style mission score and Rampart's review.
func debrief(success: bool, reason: String) -> Dictionary:
	var lines: Array = []
	var score := 0
	var add := func(label: String, count: int, each: int) -> void:
		if count != 0:
			lines.append({"label": label, "count": count, "points": count * each})
	var arrested := suspects().filter(func(s): return s.status == TacUnit.Status.CUFFED).size()
	var fled := suspects().filter(func(s): return s.status == TacUnit.Status.FLED).size()
	var suspects_dead := suspects().filter(func(s): return s.status == TacUnit.Status.DEAD).size()
	var civ_hurt := civilians().filter(func(c): return c.record.damage_taken > 0 and c.status != TacUnit.Status.DEAD).size()
	var civ_dead := civilians().filter(func(c): return c.status == TacUnit.Status.DEAD).size()
	var civ_aided := civilians().filter(func(c): return c.record.get("aided", false)).size()
	var off_hurt := officers().filter(func(o): return o.record.damage_taken > 0 and o.status == TacUnit.Status.ACTIVE).size()
	var off_down := officers().filter(func(o): return o.status in [TacUnit.Status.UNCONSCIOUS, TacUnit.Status.DYING]).size()
	var off_dead := officers().filter(func(o): return o.status == TacUnit.Status.DEAD).size()
	add.call("Suspects in custody", arrested, 30)
	add.call("Suspects who got away", fled, -20)
	add.call("Suspects killed", suspects_dead, -15)
	add.call("Civilians given aid", civ_aided, 15)
	add.call("Civilians injured", civ_hurt, -20)
	add.call("Civilians killed", civ_dead, -60)
	add.call("Officers injured", off_hurt, -10)
	add.call("Officers critically wounded", off_down, -25)
	add.call("Officers killed", off_dead, -100)
	add.call("Weapons recovered", weapons_recovered, 10)
	add.call("Contraband recovered", contraband_recovered, 5)
	add.call("Rounds fired", rounds_fired, -2)
	var bad_strays := stray_rounds.filter(func(s): return s.get("interior", false) or s.has("victim")).size()
	add.call("Rounds into homes or bystanders", bad_strays, -5)
	if success and rounds_fired == 0 and arrested > 0:
		add.call("No rounds fired", 1, 15)
	if withdrawn:
		add.call("Withdrew from the scene", 1, -30)
	for l in lines:
		score += int(l.points)
	var rating := "Terrible"
	if score >= 60:
		rating = "Excellent"
	elif score >= 30:
		rating = "Good"
	elif score >= 0:
		rating = "Fair"
	elif score >= -40:
		rating = "Poor"
	var reviews: Array = []
	var worst := {}
	for e in force_log:
		var r := review_force_event(e)
		var actor := unit_by_id(int(e.actor))
		var target := unit_by_id(int(e.target))
		reviews.append({"officer": actor.name if actor else "?", "target": target.name if target else "?",
			"item": String(e.item), "outcome": r.outcome, "reason": r.reason, "severity": r.severity})
		var k := actor.key if actor else "?"
		if not worst.has(k) or int(worst[k].severity) < int(r.severity):
			worst[k] = r
	var officer_results: Array = []
	for o in officers():
		officer_results.append({"key": o.key, "name": o.name, "status": o.status_name(), "wound": o.wound_label(),
			"health": o.health, "health_max": o.health_max, "morale": o.morale, "record": o.record.duplicate(),
			"review": worst.get(o.key, {"outcome": "No force used", "severity": 0, "reason": ""})})
	return {
		"success": success, "reason": reason, "score": score, "rating": rating, "lines": lines,
		"turns": turn, "rounds_fired": rounds_fired, "stray_rounds": stray_rounds.duplicate(true),
		"reviews": reviews, "officers": officer_results, "arrested": arrested, "fled": fled,
		"suspects_dead": suspects_dead, "civilians_hurt": civ_hurt, "civilians_dead": civ_dead,
		"call": call.duplicate(true), "basis": basis,
	}


func _label(u: TacUnit) -> String:
	return u.name
