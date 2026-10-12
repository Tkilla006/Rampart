class_name UnitView
extends Node2D
## One person on the battlescape: animated sprite in four facings, kneel and down poses,
## a selection marker, and a small status tag.

const FEET := Vector2(16, 46)
const SIDE_COLORS := {0: Color(0.45, 0.7, 1.0), 1: Color(1.0, 0.35, 0.3), 2: Color(0.95, 0.85, 0.4)}

var unit: TacUnit
var cell := Vector2i.ZERO
var selected := false
var sprite: AnimatedSprite2D
var tag: Label
var _walking := false


func setup(u: TacUnit) -> void:
	unit = u
	name = "Unit%d" % u.id
	sprite = AnimatedSprite2D.new()
	var path := "res://art/characters/people/%s_tac_frames.tres" % u.look
	if not ResourceLoader.exists(path):
		path = "res://art/characters/people/officer_tac_frames.tres"
	sprite.sprite_frames = load(path)
	sprite.centered = false
	sprite.offset = -FEET
	add_child(sprite)
	tag = Label.new()
	tag.add_theme_font_size_override("font_size", 8)
	tag.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	tag.add_theme_constant_override("shadow_offset_x", 1)
	tag.add_theme_constant_override("shadow_offset_y", 1)
	tag.position = Vector2(-30, -62)
	tag.size = Vector2(60, 10)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(tag)
	snap_to(u.pos)
	refresh()


static func cell_to_screen(c: Vector2i) -> Vector2:
	return Iso.ground_to_screen(Iso.tile_to_ground(Vector2(c) + Vector2(0.5, 0.5)))


func snap_to(c: Vector2i) -> void:
	cell = c
	position = cell_to_screen(c).round()


## The 8-way grid facing shown with the nearest of the sprite's four screen facings.
static func facing_name(dir_index: int) -> String:
	var d := Vector2(TacUnit.DIRS[dir_index])
	var s := Iso.ground_to_screen(d) - Iso.ground_to_screen(Vector2.ZERO)
	if absf(s.x) > absf(s.y):
		return "right" if s.x > 0 else "left"
	return "down" if s.y > 0 else "up"


func refresh() -> void:
	var down := unit.status in [TacUnit.Status.DEAD, TacUnit.Status.DYING, TacUnit.Status.UNCONSCIOUS] \
		or (unit.status == TacUnit.Status.INCAPACITATED)
	var anim := "down"
	if not down:
		var face := facing_name(unit.facing)
		if _walking:
			anim = "walk_" + face
		elif unit.stance == TacUnit.Stance.KNEELING or unit.status in [TacUnit.Status.SURRENDERED, TacUnit.Status.CUFFED]:
			anim = "kneel_" + face
		else:
			anim = "idle_" + face
	if sprite.animation != anim:
		sprite.play(anim)
	var t := ""
	match unit.status:
		TacUnit.Status.SURRENDERED:
			t = "Surrendered"
		TacUnit.Status.CUFFED:
			t = "In custody"
		TacUnit.Status.INCAPACITATED:
			t = "Tased"
		TacUnit.Status.UNCONSCIOUS:
			t = "Unconscious" if unit.fatal_wounds == 0 else "Bleeding"
		TacUnit.Status.DYING:
			t = "Dying (%d)" % unit.dying_turns
		TacUnit.Status.DEAD:
			t = "Dead"
		_:
			if unit.blinded_turns > 0:
				t = "Blinded"
			elif unit.fatal_wounds > 0:
				t = "Bleeding"
			elif unit.side == TacUnit.Side.SUSPECT and unit.is_armed():
				t = ItemDB.get_item(unit.right_hand).name.split(" (")[0]
	tag.text = t
	tag.add_theme_color_override("font_color", SIDE_COLORS[unit.side])
	sprite.modulate = Color(1, 1, 1) if unit.status != TacUnit.Status.DEAD else Color(0.6, 0.55, 0.55)
	queue_redraw()


func set_walking(v: bool) -> void:
	_walking = v
	refresh()


func _draw() -> void:
	if not selected and unit.side == TacUnit.Side.OFFICER:
		return
	var col: Color = SIDE_COLORS[unit.side]
	if not selected:
		col.a = 0.35
	var pts := PackedVector2Array([Vector2(0, -8), Vector2(16, 0), Vector2(0, 8), Vector2(-16, 0), Vector2(0, -8)])
	draw_polyline(pts, col, 1.0 if not selected else 1.5)
	if selected:
		draw_polygon(PackedVector2Array([Vector2(-4, -60), Vector2(4, -60), Vector2(0, -54)]), PackedColorArray([col]))
