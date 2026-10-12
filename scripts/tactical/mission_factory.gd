class_name MissionFactory
extends RefCounted
## Builds a battlescape from a call for service: a map template (street, apartment courtyard, store,
## alley, cape debris), the officers who responded, and whoever is really on scene.

const LOOK_NAMES := {
	"suspect_hoodie": "Man in a gray hoodie", "suspect_white_tee": "Man in a white T-shirt",
	"suspect_flannel": "Man in a red flannel", "suspect_tracksuit": "Man in a black tracksuit",
	"civilian_vendor": "Vendor", "civilian_nurse": "Woman in scrubs", "civilian_elder": "Older resident",
	"civilian_clerk": "Clerk",
}
const CIVILIAN_LOOKS := ["civilian_vendor", "civilian_nurse", "civilian_elder", "civilian_clerk"]
const DISPOSITIONS := {"compliant": 0, "passive": 1, "active": 2, "assaultive": 3, "deadly": 4}
const SEDANS := ["maroon", "silver", "blue", "white", "green", "tan"]


## call: {type, label, truth (one entry of the call type's truth list), district, watch, basis}
## squad: Array of TacUnit officers. Returns a ready TacMission.
static func build(call: Dictionary, squad: Array, seed_value: int = 0, backup: Array = []) -> TacMission:
	var m := TacMission.new(seed_value)
	var rng := m.rng
	m.call = call
	m.basis = call.get("basis", "consensual")
	var template: String = call.get("map", "street")
	var zones := {}
	match template:
		"courtyard":
			m.map = courtyard(rng, zones)
		"store":
			m.map = store(rng, zones)
		"alley":
			m.map = alley(rng, zones)
		"debris":
			m.map = street(rng, zones, true)
		_:
			m.map = street(rng, zones, false)
	m.map.night = call.get("watch", "pm") == "morning"
	m.map.name = template
	for i in squad.size():
		var o: TacUnit = squad[i]
		var at: Vector2i = m.map.officer_start[i % m.map.officer_start.size()]
		while m.unit_at(at) != null:
			at = _free_near(m, at)
		m.add_unit(o, at)
		o.facing = 2
	for b in backup:
		m.backup_pending.append(b)
	var truth: Dictionary = call.get("truth", {})
	var n := 0
	for spec in truth.get("suspects", []):
		n += 1
		var u := TacUnit.make_npc(TacUnit.Side.SUSPECT, LOOK_NAMES.get(spec.look, "Suspect %d" % n), spec.look, rng)
		u.disposition = DISPOSITIONS.get(spec.get("disposition", "passive"), 1)
		u.state = spec.get("state", "")
		u.looter = spec.get("looter", false)
		if u.state == "boosted":
			u.boosted = true
			u.health_max += 18
			u.health = u.health_max
			u.tu_max += 8
			u.morale = 95
		if u.state == "intoxicated" or u.state == "high":
			u.accuracy -= 10
			u.reactions -= 10
		if spec.get("weapon") != null:
			u.give_weapon(spec.weapon, true)
		if spec.get("hidden") != null:
			u.give_weapon(spec.hidden, false)
		m.add_unit(u, _take(m, zones.get("suspect", []), rng))
		u.face(m.map.officer_start[0])
	for i in int(truth.get("civilians", 0)):
		var look: String = CIVILIAN_LOOKS[rng.randi_range(0, CIVILIAN_LOOKS.size() - 1)]
		var c := TacUnit.make_npc(TacUnit.Side.CIVILIAN, LOOK_NAMES[look], look, rng)
		m.add_unit(c, _take(m, zones.get("civilian", []), rng))
		c.facing = rng.randi_range(0, 7)
	for i in int(truth.get("wounded", 0)):
		var look: String = CIVILIAN_LOOKS[rng.randi_range(0, CIVILIAN_LOOKS.size() - 1)]
		var v := TacUnit.make_npc(TacUnit.Side.CIVILIAN, "Victim (%s)" % LOOK_NAMES[look].to_lower(), look, rng)
		v.health = rng.randi_range(9, 14)
		v.fatal_wounds = rng.randi_range(1, 2)
		v.status = TacUnit.Status.UNCONSCIOUS
		m.add_unit(v, _take(m, zones.get("victim", zones.get("civilian", [])), rng))
	m.objectives = objectives_for(call, truth)
	return m


static func objectives_for(call: Dictionary, truth: Dictionary) -> Array:
	var obj: Array = [{"kind": "primary", "text": "Take every suspect into custody or end the threat"}]
	if int(truth.get("wounded", 0)) > 0:
		obj.append({"kind": "primary", "text": "Give first aid to the wounded"})
	obj.append({"kind": "secondary", "text": "No civilian injuries"})
	obj.append({"kind": "secondary", "text": "No rounds fired"})
	if call.get("type", "") == "5150":
		obj.append({"kind": "secondary", "text": "Get the subject to evaluation without lethal force"})
	return obj


static func _take(m: TacMission, cells: Array, rng: RandomNumberGenerator) -> Vector2i:
	var pool := cells.duplicate()
	pool.shuffle()
	for c in pool:
		if m.unit_at(c) == null and not m.map.object_blocks_move(c):
			return c
	# Fall back to any free interior cell of the map.
	for i in 400:
		var c := Vector2i(rng.randi_range(2, m.map.width - 3), rng.randi_range(2, m.map.height - 3))
		if m.unit_at(c) == null and not m.map.object_blocks_move(c):
			return c
	return Vector2i(1, 1)


static func _free_near(m: TacMission, c: Vector2i) -> Vector2i:
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var n := c + Vector2i(dx, dy)
				if m.map.in_bounds(n) and m.unit_at(n) == null and not m.map.object_blocks_move(n):
					return n
	return c


# ---------------------------------------------------------------- building blocks

static func _fill(map: TacMap, r: Rect2i, tile: String, interior: bool = false) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if map.in_bounds(Vector2i(x, y)):
				map.set_floor(Vector2i(x, y), tile, interior)


## A road running along x over rows y0..y1 (inclusive), with curbs on the sidewalk rows either side.
static func _road_x(map: TacMap, y0: int, y1: int) -> void:
	var mid := (y0 + y1) / 2
	for x in map.width:
		for y in range(y0, y1 + 1):
			var t := "asphalt"
			if y == mid:
				t = "double_yellow_x"
			elif (y == mid - 1 or y == mid + 1) and x % 3 == 0:
				t = "lane_dash_x"
			map.set_floor(Vector2i(x, y), t)
		if map.in_bounds(Vector2i(x, y0 - 1)):
			map.set_floor(Vector2i(x, y0 - 1), "curb_SW")
		if map.in_bounds(Vector2i(x, y1 + 1)):
			map.set_floor(Vector2i(x, y1 + 1), "curb_NE")


## Exterior walls around a rectangle of interior floor, with windows every few cells.
## doors: Array of [Vector2i cell, side ("n" | "s" | "w" | "e")] on the rectangle's edge.
static func _building(map: TacMap, r: Rect2i, material: String, floor: String, doors: Array, windows: bool = true,
		front: String = "", front_material: String = "") -> void:
	_fill(map, r, floor, true)
	var x0 := r.position.x
	var y0 := r.position.y
	var x1 := r.end.x
	var y1 := r.end.y
	for x in range(x0, x1):
		var wn := "window" if windows and (x - x0) % 3 == 1 else "plain"
		var ws := wn
		map.set_wall(Vector2i(x, y0), "n", front_material if front == "n" else material, "storefront" if front == "n" else wn)
		map.set_wall(Vector2i(x, y1), "n", front_material if front == "s" else material, "storefront" if front == "s" else ws)
	for y in range(y0, y1):
		var ww := "window" if windows and (y - y0) % 3 == 1 else "plain"
		map.set_wall(Vector2i(x0, y), "w", front_material if front == "w" else material, "storefront" if front == "w" else ww)
		map.set_wall(Vector2i(x1, y), "w", front_material if front == "e" else material, "storefront" if front == "e" else ww)
	for d in doors:
		var c: Vector2i = d[0]
		match String(d[1]):
			"n":
				map.wall_n[Vector2i(c.x, y0)].kind = "door"
			"s":
				map.wall_n[Vector2i(c.x, y1)].kind = "door"
			"w":
				map.wall_w[Vector2i(x0, c.y)].kind = "door"
			"e":
				map.wall_w[Vector2i(x1, c.y)].kind = "door"


## An interior partition: a drywall line along x at row y (north edges) or along y at column x.
static func _partition(map: TacMap, from: Vector2i, length: int, along_x: bool, door_at: int = -1) -> void:
	for i in length:
		var c := from + (Vector2i(i, 0) if along_x else Vector2i(0, i))
		map.set_wall(c, "n" if along_x else "w", "drywall", "door" if i == door_at else "plain")


static func _prop(map: TacMap, prop: String, c: Vector2i, visual: String = "") -> void:
	map.place_object(prop, [c])
	map.add_visual("prop", visual if visual != "" else prop, Vector2(c) + Vector2(0.5, 0.5))
	if prop == "streetlight":
		map.lights.append(c)


static func _wide_prop(map: TacMap, prop: String, cells: Array, visual: String) -> void:
	map.place_object(prop, cells)
	var center := Vector2.ZERO
	for c in cells:
		center += Vector2(c) + Vector2(0.5, 0.5)
	map.add_visual("prop", visual, center / cells.size())


static func _sedan(map: TacMap, rng: RandomNumberGenerator, origin: Vector2i, facing: String) -> void:
	map.place_car(origin, facing, "sedan_%s" % SEDANS[rng.randi_range(0, SEDANS.size() - 1)])


static func _patrol_car(map: TacMap, origin: Vector2i, start_column: int, rows: Array) -> void:
	map.place_car(origin, "SE", "crown_vic")
	for y in rows:
		map.officer_start.append(Vector2i(start_column, y))
	for x in range(origin.x, origin.x + 5):
		for y in [origin.y - 1, origin.y + 2]:
			if map.in_bounds(Vector2i(x, y)):
				map.exit_zone.append(Vector2i(x, y))


static func _cells(r: Rect2i) -> Array:
	var out: Array = []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			out.append(Vector2i(x, y))
	return out


# ---------------------------------------------------------------- templates

## A block of Rampart street: road, sidewalks, storefronts and apartments, parked cars.
static func street(rng: RandomNumberGenerator, zones: Dictionary, debris: bool) -> TacMap:
	var map := TacMap.new(26, 24, "sidewalk")
	_road_x(map, 10, 14)
	_fill(map, Rect2i(0, 0, 26, 1), "parkway_grass")
	_fill(map, Rect2i(0, 22, 26, 2), "parkway_grass")
	_building(map, Rect2i(1, 1, 9, 7), "stucco", "wood_floor", [[Vector2i(5, 7), "s"]])
	_building(map, Rect2i(12, 2, 11, 6), "brick", "linoleum", [[Vector2i(16, 7), "s"]], true, "s", "storefront")
	_partition(map, Vector2i(18, 2), 6, false, 2)
	_building(map, Rect2i(2, 18, 8, 4), "brick", "carpet", [[Vector2i(5, 18), "n"]])
	_building(map, Rect2i(14, 18, 9, 4), "stucco", "wood_floor", [[Vector2i(17, 18), "n"]])
	_partition(map, Vector2i(14, 20), 9, true, 4)
	for c in [Vector2i(3, 8), Vector2i(11, 8), Vector2i(24, 8), Vector2i(7, 16), Vector2i(21, 16)]:
		_prop(map, "palm_tree", c)
	_prop(map, "streetlight", Vector2i(9, 8), "streetlight_r1")
	_prop(map, "streetlight", Vector2i(13, 16), "streetlight_r3")
	_prop(map, "fire_hydrant", Vector2i(14, 9))
	_wide_prop(map, "bus_bench", [Vector2i(18, 16), Vector2i(19, 16)], "bus_bench_r2")
	_prop(map, "trash_can", Vector2i(23, 9))
	_wide_prop(map, "dumpster", [Vector2i(11, 20), Vector2i(12, 20)], "dumpster_r1")
	_sedan(map, rng, Vector2i(15, 10), "NW")
	_sedan(map, rng, Vector2i(8, 13), "SE")
	_patrol_car(map, Vector2i(0, 12), 5, [12, 13, 11, 14, 10])
	if debris:
		for i in 26:
			var c := Vector2i(rng.randi_range(8, 24), rng.randi_range(9, 16))
			if not map.object_at(c).is_empty():
				continue
			map.set_floor(c, "rubble_heavy" if rng.randf() < 0.4 else "rubble")
		for c in [Vector2i(13, 9), Vector2i(20, 12), Vector2i(17, 15)]:
			if map.object_at(c).is_empty():
				map.place_object("rubble_pile", [c])
				map.set_floor(c, "rubble_heavy")
		for x in range(12, 18):
			map.wall_n[Vector2i(x, 8)].kind = "broken"
	zones["suspect"] = _cells(Rect2i(14, 9, 10, 7)) + _cells(Rect2i(13, 3, 4, 4))
	zones["civilian"] = _cells(Rect2i(9, 15, 15, 2)) + _cells(Rect2i(2, 2, 7, 5)) + _cells(Rect2i(15, 19, 7, 2))
	zones["victim"] = _cells(Rect2i(12, 11, 10, 4))
	return map


## Pico-Union apartments around a courtyard, open to the street on the south.
static func courtyard(rng: RandomNumberGenerator, zones: Dictionary) -> TacMap:
	var map := TacMap.new(26, 26, "sidewalk")
	_road_x(map, 21, 24)
	_fill(map, Rect2i(0, 0, 26, 2), "dirt_weeds")
	# Wings: west and east apartments, north apartments; the courtyard is open to the street.
	_building(map, Rect2i(3, 2, 6, 16), "brick", "carpet", [[Vector2i(8, 4), "e"], [Vector2i(8, 9), "e"], [Vector2i(8, 14), "e"]])
	_building(map, Rect2i(17, 2, 6, 16), "brick", "wood_floor", [[Vector2i(17, 4), "w"], [Vector2i(17, 9), "w"], [Vector2i(17, 14), "w"]])
	_building(map, Rect2i(9, 2, 8, 5), "brick", "linoleum", [[Vector2i(11, 6), "s"], [Vector2i(14, 6), "s"]], false)
	_partition(map, Vector2i(3, 7), 6, true)
	_partition(map, Vector2i(3, 12), 6, true)
	_partition(map, Vector2i(17, 7), 6, true)
	_partition(map, Vector2i(17, 12), 6, true)
	_partition(map, Vector2i(13, 2), 5, false)
	_fill(map, Rect2i(9, 7, 8, 12), "courtyard_tile")
	_prop(map, "planter", Vector2i(12, 11))
	_prop(map, "planter", Vector2i(14, 15), "planter")
	map.place_object("mattress", [Vector2i(10, 16)])
	map.add_visual("object", "mattress_r0", Vector2(10.5, 16.5))
	_prop(map, "trash_can", Vector2i(16, 8))
	_prop(map, "streetlight", Vector2i(8, 19), "streetlight_r1")
	_prop(map, "palm_tree", Vector2i(2, 19))
	_prop(map, "palm_tree", Vector2i(23, 19))
	_sedan(map, rng, Vector2i(14, 21), "NW")
	_patrol_car(map, Vector2i(1, 23), 5, [23, 24, 22, 21, 20])
	zones["suspect"] = _cells(Rect2i(9, 7, 8, 9)) + _cells(Rect2i(4, 3, 4, 3)) + _cells(Rect2i(18, 8, 4, 3))
	zones["civilian"] = _cells(Rect2i(4, 13, 4, 4)) + _cells(Rect2i(18, 13, 4, 4)) + _cells(Rect2i(10, 3, 6, 3)) + _cells(Rect2i(10, 12, 6, 6))
	zones["victim"] = _cells(Rect2i(10, 9, 6, 6))
	return map


## A corner market on a commercial strip, with a back room and a rear door to the alley.
static func store(rng: RandomNumberGenerator, zones: Dictionary) -> TacMap:
	var map := TacMap.new(26, 24, "sidewalk")
	_road_x(map, 18, 21)
	_fill(map, Rect2i(0, 0, 26, 4), "alley")
	_building(map, Rect2i(5, 4, 14, 12), "stucco", "linoleum", [[Vector2i(11, 15), "s"], [Vector2i(15, 4), "n"]], false, "s", "storefront")
	_partition(map, Vector2i(5, 8), 14, true, 3)
	_fill(map, Rect2i(5, 4, 14, 4), "concrete_floor", true)
	_building(map, Rect2i(20, 4, 6, 12), "brick", "concrete_floor", [], true)
	_building(map, Rect2i(0, 4, 4, 12), "brick", "concrete_floor", [], true)
	_wide_prop(map, "store_counter", [Vector2i(13, 13), Vector2i(14, 13)], "store_counter_r0")
	for c in [Vector2i(6, 10), Vector2i(9, 10), Vector2i(6, 12), Vector2i(9, 12)]:
		_wide_prop(map, "store_shelf", [c, c + Vector2i(1, 0)], "store_shelf_r0")
	_wide_prop(map, "dumpster", [Vector2i(8, 1), Vector2i(9, 1)], "dumpster_r0")
	_prop(map, "trash_can", Vector2i(17, 2))
	_prop(map, "streetlight", Vector2i(19, 17), "streetlight_r1")
	_prop(map, "fire_hydrant", Vector2i(4, 17))
	_prop(map, "palm_tree", Vector2i(22, 17))
	_sedan(map, rng, Vector2i(14, 18), "NW")
	_patrol_car(map, Vector2i(1, 19), 5, [19, 20, 18, 21, 17])
	zones["suspect"] = _cells(Rect2i(6, 9, 12, 6))
	zones["civilian"] = _cells(Rect2i(13, 14, 3, 1)) + _cells(Rect2i(6, 9, 6, 6)) + _cells(Rect2i(6, 5, 10, 2))
	zones["victim"] = _cells(Rect2i(7, 13, 8, 2))
	return map


## A back alley between two rows of buildings, fenced lots and dumpsters.
static func alley(rng: RandomNumberGenerator, zones: Dictionary) -> TacMap:
	var map := TacMap.new(26, 24, "sidewalk")
	_fill(map, Rect2i(0, 9, 26, 6), "alley")
	_building(map, Rect2i(0, 1, 11, 8), "brick", "concrete_floor", [[Vector2i(6, 8), "s"]])
	_building(map, Rect2i(13, 1, 13, 8), "stucco", "wood_floor", [[Vector2i(18, 8), "s"]])
	_partition(map, Vector2i(19, 1), 8, false, 3)
	_building(map, Rect2i(2, 16, 9, 7), "stucco", "carpet", [[Vector2i(6, 16), "n"]])
	_building(map, Rect2i(14, 16, 12, 7), "brick", "linoleum", [[Vector2i(19, 16), "n"]])
	_fill(map, Rect2i(11, 15, 3, 9), "dirt_weeds")
	for x in [11, 12, 13]:
		map.place_object("chainlink_fence", [Vector2i(x, 15)])
		map.add_visual("prop", "chainlink_fence_r0", Vector2(x + 0.5, 15.5))
	_wide_prop(map, "dumpster", [Vector2i(3, 9), Vector2i(4, 9)], "dumpster_r0")
	_wide_prop(map, "dumpster", [Vector2i(21, 14), Vector2i(22, 14)], "dumpster_r0")
	_prop(map, "trash_can", Vector2i(9, 9))
	_prop(map, "trash_can", Vector2i(15, 14))
	map.place_object("mattress", [Vector2i(16, 12)])
	map.add_visual("object", "mattress_r0", Vector2(16.5, 12.5))
	_prop(map, "traffic_cone", Vector2i(12, 10))
	_prop(map, "streetlight", Vector2i(10, 14), "streetlight_r3")
	_sedan(map, rng, Vector2i(14, 10), "NW")
	_patrol_car(map, Vector2i(0, 11), 5, [11, 12, 10, 13, 9])
	zones["suspect"] = _cells(Rect2i(17, 9, 8, 6)) + _cells(Rect2i(14, 2, 5, 5)) + _cells(Rect2i(15, 17, 9, 4))
	zones["civilian"] = _cells(Rect2i(3, 17, 7, 4)) + _cells(Rect2i(20, 2, 5, 5))
	zones["victim"] = _cells(Rect2i(8, 10, 8, 4))
	return map
