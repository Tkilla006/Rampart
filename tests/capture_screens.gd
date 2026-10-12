extends SceneTree
## Renders the vertical slice and saves screenshots: the street, the car check, and the found baggie.
## Run with a display (or xvfb-run): godot --path . -s res://tests/capture_screens.gd -- <out_dir>

var out_dir := "user://screens"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)


func _run() -> void:
	var main: Node = load("res://scenes/prologue.tscn").instantiate()
	root.add_child(main)
	await _frames(40)
	await _shot("01_street")
	# Walk the officer up to the car, then open the car check.
	main.officer.place(Iso.tile_to_ground(Vector2(2.6, 11.4)), "up")
	await _frames(30)
	await _shot("02_at_car")
	main._start_event("ST-06")
	await _frames(5)
	await _shot("03_car_check")
	main.dialogue._show("found")
	await _frames(5)
	await _shot("04_found")
	quit()
