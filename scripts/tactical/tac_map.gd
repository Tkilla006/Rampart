class_name TacMap
extends RefCounted
## The battlescape grid: floor tiles, walls on tile edges, objects with cover values, light.
##
## Walls sit on edges like X-COM: wall_n[cell] is the wall on the cell's north edge (between y-1 and y),
## wall_w[cell] the wall on its west edge (between x-1 and x). One tile is about 1.5 m.
## Cover values follow design 6.3: full -40, half -20, concealment -10.

enum Cover { NONE, CONCEAL, HALF, FULL }

const COVER_PENALTY := {Cover.NONE: 0, Cover.CONCEAL: 10, Cover.HALF: 20, Cover.FULL: 40}
const COVER_NAMES := {Cover.NONE: "none", Cover.CONCEAL: "concealment", Cover.HALF: "half cover", Cover.FULL: "full cover"}

## X-COM time unit costs.
const TU_ORTHOGONAL := 4
const TU_DIAGONAL := 6
const TU_DOOR := 4

## Object catalog. cover: protection for someone behind it. sight: blocks line of sight.
## move: blocks movement (otherwise extra is added to the move cost). stops: stops handgun rounds.
const OBJECTS := {
	"palm_tree": {"cover": Cover.FULL, "sight": false, "move": true, "stops": true, "hp": 200},
	"streetlight": {"cover": Cover.FULL, "sight": false, "move": true, "stops": true, "hp": 200, "light": 4},
	"fire_hydrant": {"cover": Cover.HALF, "sight": false, "move": true, "stops": true, "hp": 200},
	"bus_bench": {"cover": Cover.HALF, "sight": false, "move": true, "stops": true, "hp": 60},
	"trash_can": {"cover": Cover.HALF, "sight": false, "move": true, "stops": false, "hp": 30},
	"dumpster": {"cover": Cover.FULL, "sight": true, "move": true, "stops": true, "hp": 120},
	"traffic_cone": {"cover": Cover.NONE, "sight": false, "move": false, "stops": false, "hp": 5, "extra": 0},
	"chainlink_fence": {"cover": Cover.NONE, "sight": false, "move": false, "stops": false, "hp": 40, "extra": 8},
	"car_engine": {"cover": Cover.FULL, "sight": true, "move": true, "stops": true, "hp": 150},
	"car_body": {"cover": Cover.CONCEAL, "sight": true, "move": true, "stops": false, "hp": 80},
	"car_hood": {"cover": Cover.HALF, "sight": false, "move": true, "stops": true, "hp": 80},
	"store_counter": {"cover": Cover.HALF, "sight": false, "move": true, "stops": true, "hp": 60},
	"store_shelf": {"cover": Cover.CONCEAL, "sight": true, "move": true, "stops": false, "hp": 40},
	"planter": {"cover": Cover.FULL, "sight": false, "move": true, "stops": true, "hp": 150},
	"mattress": {"cover": Cover.NONE, "sight": false, "move": false, "stops": false, "hp": 10, "extra": 2},
	"rubble_pile": {"cover": Cover.HALF, "sight": false, "move": false, "stops": true, "hp": 999, "extra": 6},
}

## Wall behavior by kind. Materials decide whether a plain wall stops rounds (design 6.3 cover table).
const WALL_KINDS := {
	"plain": {"move": true, "sight": true, "cover": Cover.FULL},
	"window": {"move": true, "sight": false, "cover": Cover.HALF},
	"storefront": {"move": true, "sight": false, "cover": Cover.CONCEAL},
	"door": {"move": false, "sight": true, "cover": Cover.CONCEAL, "door": true},
	"door_open": {"move": false, "sight": false, "cover": Cover.NONE},
	"broken": {"move": false, "sight": false, "cover": Cover.HALF, "extra": 4},
}
const STOPPING_MATERIALS := ["brick", "stucco", "lowwall"]

const FLOOR_EXTRA := {"rubble": 2, "rubble_heavy": 4, "dirt_weeds": 0}

var width := 0
var height := 0
var floor_tiles: Array[String] = []
var interior_floors := {}
var wall_n := {}
var wall_w := {}
var objects := {}
## Visuals to draw: {kind: "prop"|"vehicle"|"object", name, ground: Vector2 (tile units), facing}
var visuals: Array = []
var night := false
var lights: Array[Vector2i] = []
var officer_start: Array[Vector2i] = []
var exit_zone: Array[Vector2i] = []
var name := ""


func _init(w: int = 0, h: int = 0, default_floor: String = "sidewalk") -> void:
	width = w
	height = h
	floor_tiles.resize(w * h)
	floor_tiles.fill(default_floor)


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


func is_edge(c: Vector2i) -> bool:
	return c.x == 0 or c.y == 0 or c.x == width - 1 or c.y == height - 1


func get_floor(c: Vector2i) -> String:
	return floor_tiles[c.y * width + c.x]


func set_floor(c: Vector2i, tile: String, interior: bool = false) -> void:
	floor_tiles[c.y * width + c.x] = tile
	if interior:
		interior_floors[c] = true
	else:
		interior_floors.erase(c)


func is_interior(c: Vector2i) -> bool:
	return interior_floors.has(c)


# ---------------------------------------------------------------- walls

func set_wall(c: Vector2i, side: String, material: String, kind: String = "plain") -> void:
	var w := {"material": material, "kind": kind, "hp": 60 if material == "drywall" else 140}
	if side == "n":
		wall_n[c] = w
	else:
		wall_w[c] = w


## The wall between two orthogonally adjacent cells, or an empty dictionary.
func edge_between(a: Vector2i, b: Vector2i) -> Dictionary:
	var d := b - a
	if d == Vector2i(1, 0):
		return wall_w.get(b, {})
	if d == Vector2i(-1, 0):
		return wall_w.get(a, {})
	if d == Vector2i(0, 1):
		return wall_n.get(b, {})
	if d == Vector2i(0, -1):
		return wall_n.get(a, {})
	return {}


func wall_blocks_move(w: Dictionary) -> bool:
	return not w.is_empty() and bool(WALL_KINDS[w.kind]["move"])


func wall_blocks_sight(w: Dictionary) -> bool:
	return not w.is_empty() and bool(WALL_KINDS[w.kind]["sight"])


func wall_stops_rounds(w: Dictionary) -> bool:
	if w.is_empty():
		return false
	if w.kind in ["window", "storefront", "door", "door_open", "broken"]:
		return false
	return w.material in STOPPING_MATERIALS


func wall_cover(w: Dictionary) -> Cover:
	if w.is_empty():
		return Cover.NONE
	if w.material == "lowwall":
		return Cover.HALF
	if w.material == "drywall" and w.kind == "plain":
		return Cover.CONCEAL
	return WALL_KINDS[w.kind]["cover"]


func open_door(a: Vector2i, b: Vector2i) -> bool:
	var w := edge_between(a, b)
	if not w.is_empty() and w.kind == "door":
		w.kind = "door_open"
		return true
	return false


# ---------------------------------------------------------------- objects

## Places an object over one or more cells. All cells share one dictionary.
func place_object(object_name: String, cells: Array, extra: Dictionary = {}) -> Dictionary:
	assert(OBJECTS.has(object_name), "Unknown object %s" % object_name)
	var o: Dictionary = OBJECTS[object_name].duplicate()
	o["name"] = object_name
	o.merge(extra, true)
	for c in cells:
		objects[c] = o
	return o


func object_at(c: Vector2i) -> Dictionary:
	return objects.get(c, {})


func object_blocks_move(c: Vector2i) -> bool:
	var o := object_at(c)
	return not o.is_empty() and bool(o.move) and int(o.hp) > 0


func object_blocks_sight(c: Vector2i) -> bool:
	var o := object_at(c)
	return not o.is_empty() and bool(o.sight) and int(o.hp) > 0


func add_visual(kind: String, visual_name: String, ground: Vector2, facing: String = "") -> void:
	visuals.append({"kind": kind, "name": visual_name, "ground": ground, "facing": facing})


## Adds a parked car: 4 x 2 tiles along x (facing NW/SE) or 2 x 4 along y (facing NE/SW).
## The front tiles are the engine block (full cover), the middle the doors (concealment), the rear the trunk.
func place_car(origin: Vector2i, facing: String, visual: String = "crown_vic") -> Array[Vector2i]:
	var along_x := facing == "NW" or facing == "SE"
	var cells: Array[Vector2i] = []
	for i in 4:
		for j in 2:
			cells.append(origin + (Vector2i(i, j) if along_x else Vector2i(j, i)))
	var front_index := 0 if (facing == "NW" or facing == "NE") else 3
	var car_id := "car_%d_%d" % [origin.x, origin.y]
	for c in cells:
		var i := (c - origin).x if along_x else (c - origin).y
		var part := "car_body"
		if i == front_index:
			part = "car_engine"
		elif i == 3 - front_index:
			part = "car_hood"
		place_object(part, [c], {"car": car_id})
	var size := Vector2(4, 2) if along_x else Vector2(2, 4)
	add_visual("vehicle", visual, Vector2(origin) + size * 0.5, facing)
	return cells


# ---------------------------------------------------------------- movement

func extra_cost(c: Vector2i) -> int:
	var cost: int = FLOOR_EXTRA.get(get_floor(c), 0)
	var o := object_at(c)
	if not o.is_empty() and not bool(o.move):
		cost += int(o.get("extra", 0))
	return cost


## TU to step from a to an adjacent cell b, or -1 if the step is impossible. Ignores units.
func step_cost(a: Vector2i, b: Vector2i) -> int:
	if not in_bounds(b) or object_blocks_move(b):
		return -1
	var d := b - a
	if absi(d.x) > 1 or absi(d.y) > 1 or d == Vector2i.ZERO:
		return -1
	if d.x != 0 and d.y != 0:
		var side_a := Vector2i(a.x + d.x, a.y)
		var side_b := Vector2i(a.x, a.y + d.y)
		for side in [side_a, side_b]:
			if not in_bounds(side) or object_blocks_move(side):
				return -1
		if wall_blocks_move(edge_between(a, side_a)) or wall_blocks_move(edge_between(side_a, b)) \
				or wall_blocks_move(edge_between(a, side_b)) or wall_blocks_move(edge_between(side_b, b)):
			return -1
		for pair in [[a, side_a], [side_a, b], [a, side_b], [side_b, b]]:
			var w := edge_between(pair[0], pair[1])
			if not w.is_empty() and w.kind == "door":
				return -1
		return TU_DIAGONAL + extra_cost(b)
	var w := edge_between(a, b)
	if wall_blocks_move(w):
		return -1
	var cost := TU_ORTHOGONAL + extra_cost(b)
	if not w.is_empty():
		if w.kind == "door":
			cost += TU_DOOR
		cost += int(WALL_KINDS[w.kind].get("extra", 0))
	return cost


# ---------------------------------------------------------------- lines

## Cells crossed by the segment from the center of a to the center of b (or beyond, to length cells).
## Each step is {cell, from, corner}: corner steps cross a grid corner diagonally.
func trace(a: Vector2i, b: Vector2i, extend_to: float = 0.0) -> Array:
	var p0 := Vector2(a) + Vector2(0.5, 0.5)
	var p1 := Vector2(b) + Vector2(0.5, 0.5)
	var dir := p1 - p0
	if dir.length() < 0.001:
		return []
	if extend_to > 0.0:
		p1 = p0 + dir.normalized() * extend_to
		dir = p1 - p0
	var cell := a
	var step := Vector2i(int(signf(dir.x)), int(signf(dir.y)))
	var t_max_x := INF
	var t_max_y := INF
	var t_dx := INF
	var t_dy := INF
	if dir.x != 0.0:
		var next_x := float(cell.x + (1 if step.x > 0 else 0))
		t_max_x = (next_x - p0.x) / dir.x
		t_dx = absf(1.0 / dir.x)
	if dir.y != 0.0:
		var next_y := float(cell.y + (1 if step.y > 0 else 0))
		t_max_y = (next_y - p0.y) / dir.y
		t_dy = absf(1.0 / dir.y)
	var out: Array = []
	var guard := 0
	while guard < 400:
		guard += 1
		var prev := cell
		var corner := false
		if absf(t_max_x - t_max_y) < 1e-6:
			if t_max_x > 1.0:
				break
			cell += step
			t_max_x += t_dx
			t_max_y += t_dy
			corner = true
		elif t_max_x < t_max_y:
			if t_max_x > 1.0:
				break
			cell.x += step.x
			t_max_x += t_dx
		else:
			if t_max_y > 1.0:
				break
			cell.y += step.y
			t_max_y += t_dy
		out.append({"cell": cell, "from": prev, "corner": corner})
		if not in_bounds(cell):
			break
	return out


## Whether the crossing from prev to cell passes a wall matching the predicate.
func _crossing_blocked(prev: Vector2i, cell: Vector2i, corner: bool, pred: Callable) -> bool:
	if not corner:
		return pred.call(edge_between(prev, cell))
	var via_x := Vector2i(cell.x, prev.y)
	var via_y := Vector2i(prev.x, cell.y)
	var path_x: bool = pred.call(edge_between(prev, via_x)) or pred.call(edge_between(via_x, cell))
	var path_y: bool = pred.call(edge_between(prev, via_y)) or pred.call(edge_between(via_y, cell))
	return path_x and path_y


func has_line_of_sight(a: Vector2i, b: Vector2i) -> bool:
	if a == b:
		return true
	for s in trace(a, b):
		var c: Vector2i = s.cell
		if not in_bounds(c):
			return false
		if _crossing_blocked(s.from, c, s.corner, wall_blocks_sight):
			return false
		if c != b and object_blocks_sight(c):
			return false
		if c == b:
			return true
	return true


## The best cover protecting a unit in cell `target` from fire coming from `from_cell` (design 6.3).
## Flanking (no cover on the attacker's side) leaves Cover.NONE.
func cover_against(target: Vector2i, from_cell: Vector2i) -> Cover:
	var d := from_cell - target
	if d == Vector2i.ZERO:
		return Cover.NONE
	var best := Cover.NONE
	var dirs: Array[Vector2i] = []
	var sx := signi(d.x)
	var sy := signi(d.y)
	# Fire mostly along one axis only gets cover from that side.
	if absi(d.x) >= absi(d.y) * 2:
		dirs.append(Vector2i(sx, 0))
	elif absi(d.y) >= absi(d.x) * 2:
		dirs.append(Vector2i(0, sy))
	else:
		dirs.append(Vector2i(sx, 0))
		dirs.append(Vector2i(0, sy))
	for dir in dirs:
		if dir == Vector2i.ZERO:
			continue
		var n := target + dir
		var w := edge_between(target, n)
		var c := wall_cover(w)
		if c > best:
			best = c
		var o := object_at(n)
		if not o.is_empty() and int(o.hp) > 0 and n != from_cell:
			var oc: Cover = o.cover
			if oc > best:
				best = oc
	return best


# ---------------------------------------------------------------- light

func light_at(c: Vector2i) -> float:
	if not night:
		return 1.0
	var best := 0.15
	for l in lights:
		var d := Vector2(l).distance_to(Vector2(c))
		if d <= 4.0:
			best = maxf(best, 1.0 - d / 6.0)
	return best


func is_lit(c: Vector2i) -> bool:
	return light_at(c) >= 0.5


# ---------------------------------------------------------------- damage

## Damage to terrain from a round or impact. Returns a description when something changes.
func damage_edge(a: Vector2i, b: Vector2i, amount: int) -> String:
	var w := edge_between(a, b)
	if w.is_empty():
		return ""
	if w.kind in ["window", "storefront"]:
		w.kind = "broken"
		return "glass breaks"
	w.hp = int(w.hp) - amount
	if int(w.hp) <= 0 and w.kind != "broken":
		w.kind = "broken"
		return "the wall gives way"
	return ""


func damage_object(c: Vector2i, amount: int) -> String:
	var o := object_at(c)
	if o.is_empty() or int(o.hp) <= 0:
		return ""
	o.hp = int(o.hp) - amount
	if int(o.hp) <= 0:
		return "%s destroyed" % String(o.name).replace("_", " ")
	return ""
