class_name OfficerActor
extends Node2D
## The player officer on foot: direct control (keys or stick) or click-to-move, in ground space.

signal moved(ground_pos: Vector2)

const FRAMES := "res://art/characters/rookie_officer_frames.tres"
## The sprite's feet sit at (16, 45.5) in its 32x48 frame.
const FEET := Vector2(16, 46)
## About 1.5 m/s walking and 3.5 m/s running.
const WALK_SPEED := 1.5 * Iso.UNITS_PER_METER
const RUN_SPEED := 3.5 * Iso.UNITS_PER_METER
const BODY_RADIUS := 5.0
const ARRIVE_DISTANCE := 2.0

var map: StreetMap
var ground := Vector2.ZERO
var facing := "down"
var target = null  # Vector2 or null
var sprite: AnimatedSprite2D


func _ready() -> void:
	sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = load(FRAMES)
	sprite.centered = false
	sprite.offset = -FEET
	add_child(sprite)
	_face("down", false)


func place(g: Vector2, face: String = "down") -> void:
	ground = g
	position = Iso.ground_to_screen(ground).round()
	_face(face, false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("move_to") and map:
		var g := Iso.screen_to_ground(map.get_local_mouse_position())
		if map.ground_bounds().has_point(g):
			target = g
			get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	var screen_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var ground_dir := Vector2.ZERO
	if screen_dir != Vector2.ZERO:
		target = null
		ground_dir = Iso.screen_dir_to_ground(screen_dir).normalized()
	elif target != null:
		var to_target: Vector2 = target - ground
		if to_target.length() <= ARRIVE_DISTANCE:
			target = null
		else:
			ground_dir = to_target.normalized()
	if ground_dir == Vector2.ZERO:
		_face(facing, false)
		return
	var speed := RUN_SPEED if Input.is_action_pressed("run") else WALK_SPEED
	var step := ground_dir * speed * delta
	if target != null:
		step = step.limit_length(ground.distance_to(target))
	if not _try_move(step):
		target = null
	var screen_vel := Iso.ground_to_screen(step) - Iso.ground_to_screen(Vector2.ZERO)
	_face(_direction_name(screen_vel), true)


## Moves with sliding along blockers. Returns false when completely stuck.
func _try_move(step: Vector2) -> bool:
	for candidate in [step, Vector2(step.x, 0), Vector2(0, step.y)]:
		if candidate != Vector2.ZERO and (map == null or map.is_free(ground + candidate, BODY_RADIUS)):
			ground += candidate
			position = Iso.ground_to_screen(ground).round()
			moved.emit(ground)
			return true
	return false


static func _direction_name(v: Vector2) -> String:
	if absf(v.x) > absf(v.y):
		return "right" if v.x > 0 else "left"
	return "down" if v.y > 0 else "up"


func _face(dir: String, walking: bool) -> void:
	facing = dir
	var anim := ("walk_" if walking else "idle_") + dir
	if sprite and sprite.animation != anim:
		sprite.play(anim)
