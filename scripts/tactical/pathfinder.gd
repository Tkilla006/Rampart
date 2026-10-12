class_name Pathfinder
extends RefCounted
## Time unit pathfinding (X-COM: 4 TU a straight step, 6 diagonal, more over rubble, fences and doors).

## Every cell reachable from `start` within `budget` TU: {cell: cost}, plus the parent links for paths.
static func reachable(map: TacMap, start: Vector2i, budget: int, occupied: Dictionary) -> Dictionary:
	var cost := {start: 0}
	var parent := {}
	var open: Array = [[0, start]]
	while not open.is_empty():
		var best_i := 0
		for i in open.size():
			if open[i][0] < open[best_i][0]:
				best_i = i
		var cur: Array = open[best_i]
		open.remove_at(best_i)
		var c: Vector2i = cur[1]
		var g: int = cur[0]
		if g > int(cost.get(c, 1 << 30)):
			continue
		for d in TacUnit.DIRS:
			var n: Vector2i = c + d
			if occupied.has(n):
				continue
			var step := map.step_cost(c, n)
			if step < 0:
				continue
			var ng := g + step
			if ng > budget:
				continue
			if ng < int(cost.get(n, 1 << 30)):
				cost[n] = ng
				parent[n] = c
				open.append([ng, n])
	return {"cost": cost, "parent": parent}


static func path_from(result: Dictionary, target: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not result.cost.has(target):
		return out
	var c := target
	while result.parent.has(c):
		out.push_front(c)
		c = result.parent[c]
	return out


## Shortest path ignoring the TU budget (A*), for AI planning toward distant goals. Empty if none.
static func find_path(map: TacMap, start: Vector2i, goal: Vector2i, occupied: Dictionary, limit: int = 4000) -> Array[Vector2i]:
	var g := {start: 0}
	var parent := {}
	var open: Array = [[_h(start, goal), start]]
	var expanded := 0
	while not open.is_empty() and expanded < limit:
		var best_i := 0
		for i in open.size():
			if open[i][0] < open[best_i][0]:
				best_i = i
		var c: Vector2i = open[best_i][1]
		open.remove_at(best_i)
		expanded += 1
		if c == goal:
			var out: Array[Vector2i] = []
			var p := c
			while parent.has(p):
				out.push_front(p)
				p = parent[p]
			return out
		for d in TacUnit.DIRS:
			var n: Vector2i = c + d
			if occupied.has(n) and n != goal:
				continue
			var step := map.step_cost(c, n)
			if step < 0:
				continue
			var ng: int = int(g[c]) + step
			if ng < int(g.get(n, 1 << 30)):
				g[n] = ng
				parent[n] = c
				open.append([ng + _h(n, goal), n])
	return []


static func _h(a: Vector2i, b: Vector2i) -> int:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return 4 * maxi(dx, dy) + 2 * mini(dx, dy)


static func path_cost(map: TacMap, start: Vector2i, path: Array[Vector2i]) -> int:
	var total := 0
	var prev := start
	for c in path:
		var s := map.step_cost(prev, c)
		if s < 0:
			return -1
		total += s
		prev = c
	return total
