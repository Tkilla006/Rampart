class_name Iso
extends RefCounted
## Isometric projection shared by the tile map, props and actors.
##
## Ground space is measured in units: one 64x32 tile is 32 x 32 units (about 1.45 m, 22 units per meter),
## matching the street kit, the officer sprite and the Crown Vic. Screen space matches Godot's
## TileMapLayer in DIAMOND_DOWN layout, where tile (0, 0) spans x 0..64 and y 0..32.

const TILE_UNITS := 32.0
const UNITS_PER_METER := 22.0


static func ground_to_screen(g: Vector2) -> Vector2:
	return Vector2(g.x - g.y + TILE_UNITS, (g.x + g.y) * 0.5)


static func screen_to_ground(s: Vector2) -> Vector2:
	var sx := s.x - TILE_UNITS
	return Vector2(s.y + sx * 0.5, s.y - sx * 0.5)


static func tile_to_ground(t: Vector2) -> Vector2:
	return t * TILE_UNITS


## Converts a screen-space direction (from the stick or WASD) into a ground-space direction.
static func screen_dir_to_ground(d: Vector2) -> Vector2:
	return Vector2(d.y + d.x * 0.5, d.y - d.x * 0.5)


static func meters(units: float) -> float:
	return units / UNITS_PER_METER
