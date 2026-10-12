class_name StreetMap
extends Node2D
## Builds a district block from map data: isometric ground tiles, y-sorted props and vehicles,
## and the ground-space collision and interaction areas the officer moves through.

const TILESET := "res://art/tiles/rampart_street_tileset.tres"
const TILE_INDEX := "res://data/art/rampart_street_tiles_index.json"
const PROP_ANCHORS := "res://data/art/props_anchors.json"
const CAR_ANCHORS := "res://data/art/crown_vic_anchors.json"

@export_file("*.json") var map_path := "res://data/maps/westlake_intersection.json"

var data := {}
var size := Vector2i.ZERO
var ground: TileMapLayer
var actors: Node2D
## Ground-space circles {center, radius} and boxes (Rect2) that block movement.
var circles: Array = []
var boxes: Array[Rect2] = []
## Things the officer can use: {rect: Rect2 in ground units, event: String, label: String}.
var interactables: Array = []


func _ready() -> void:
	load_map(map_path)


func load_map(path: String) -> void:
	data = _read_json(path)
	size = Vector2i(data.size[0], data.size[1])
	_build_ground()
	actors = Node2D.new()
	actors.name = "Actors"
	actors.y_sort_enabled = true
	add_child(actors)
	_build_props()
	_build_vehicles()
	for b in data.get("blocked", []):
		boxes.append(_tile_rect(b))


func _build_ground() -> void:
	ground = TileMapLayer.new()
	ground.name = "Ground"
	ground.tile_set = load(TILESET)
	add_child(ground)
	var index: Dictionary = _read_json(TILE_INDEX)
	for gy in size.y:
		for gx in size.x:
			var tile_name: String = data.tiles[gy][gx]
			assert(index.has(tile_name), "Unknown tile %s" % tile_name)
			var atlas: Array = index[tile_name]
			ground.set_cell(Vector2i(gx, gy), 0, Vector2i(atlas[0], atlas[1]))


func _build_props() -> void:
	var anchors: Dictionary = _read_json(PROP_ANCHORS)
	for p in data.get("props", []):
		var a: Dictionary = anchors[p.name]
		var g := Iso.tile_to_ground(Vector2(p.x, p.y))
		var sprite := _sprite("res://art/props/%s.png" % p.name, Vector2(a.ground_anchor_px[0], a.ground_anchor_px[1]), g)
		sprite.name = p.name.capitalize().replace(" ", "")
		actors.add_child(sprite)
		if float(p.get("radius", 0)) > 0:
			circles.append({"center": g, "radius": float(p.radius)})


func _build_vehicles() -> void:
	var anchors: Dictionary = _read_json(CAR_ANCHORS)
	for v in data.get("vehicles", []):
		var a: Dictionary = anchors[v.facing]
		var g := Iso.tile_to_ground(Vector2(v.x, v.y))
		var sprite := _sprite("res://art/vehicles/%s" % a.file, Vector2(a.ground_center_px[0], a.ground_center_px[1]), g)
		sprite.name = "CrownVic"
		actors.add_child(sprite)
		var he := Vector2(v.half_extents[0], v.half_extents[1])
		var rect := _tile_rect([v.x - he.x, v.y - he.y, v.x + he.x, v.y + he.y])
		boxes.append(rect)
		if v.has("interact"):
			interactables.append({"rect": rect, "event": v.interact, "label": "Car check"})


func _sprite(texture_path: String, anchor_px: Vector2, ground_pos: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = load(texture_path)
	s.centered = false
	s.offset = -anchor_px.round()
	s.position = Iso.ground_to_screen(ground_pos).round()
	return s


func _tile_rect(b: Array) -> Rect2:
	var p0 := Iso.tile_to_ground(Vector2(b[0], b[1]))
	var p1 := Iso.tile_to_ground(Vector2(b[2], b[3]))
	return Rect2(p0, p1 - p0)


func spawn_ground() -> Vector2:
	var s: Dictionary = data.get("spawn", {"x": 0.5, "y": 0.5})
	return Iso.tile_to_ground(Vector2(s.x, s.y))


func ground_bounds() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(size) * Iso.TILE_UNITS)


## True when a body of this radius can stand at this ground point.
func is_free(g: Vector2, radius: float = 5.0) -> bool:
	if not ground_bounds().grow(-radius).has_point(g):
		return false
	for c in circles:
		if g.distance_to(c.center) < c.radius + radius:
			return false
	for r in boxes:
		if r.grow(radius).has_point(g):
			return false
	return true


## The closest interactable within reach of a ground point, or an empty dictionary.
func interactable_near(g: Vector2, reach: float = 20.0) -> Dictionary:
	var best := {}
	var best_d := INF
	for it in interactables:
		var r: Rect2 = it.rect
		var closest := Vector2(clampf(g.x, r.position.x, r.end.x), clampf(g.y, r.position.y, r.end.y))
		var d := g.distance_to(closest)
		if d <= reach and d < best_d:
			best = it
			best_d = d
	return best


static func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(typeof(parsed) == TYPE_DICTIONARY, "Could not parse %s" % path)
	return parsed
