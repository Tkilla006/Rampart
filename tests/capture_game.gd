extends SceneTree
## Screenshots of every screen: menu, creation, city map, station, battlescape, debrief.
## godot --path . -s res://tests/capture_game.gd -- <out_dir>

var out_dir := "user://shots"


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
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)


func _goto(path: String) -> Node:
	change_scene_to_file(path)
	await _frames(12)
	return current_scene


func _run() -> void:
	await _goto("res://scenes/main_menu.tscn")
	await _shot("10_main_menu")
	var creation = await _goto("res://scenes/creation.tscn")
	await _shot("11_creation")
	# Start a probation the way the creation screen does, then jump to the map.
	creation._start()
	await _frames(5)
	var campaign = root.get_node("/root/Campaign")
	campaign.spawn_call("211", "lafayette_park")
	campaign.spawn_call("415", "pico_union")
	campaign.spawn_call("5150", "macarthur_park")
	await _goto("res://scenes/cityscape.tscn")
	await _frames(5)
	if current_scene._modal:
		current_scene._modal.queue_free()
	current_scene._select(int(campaign.calls[0].id))
	await _frames(5)
	await _shot("12_cityscape")
	await _goto("res://scenes/station.tscn")
	current_scene._roster.select(0)
	current_scene._show(0)
	await _frames(3)
	await _shot("13_station")
	campaign.begin_mission(int(campaign.calls[0].id))
	var scene = await _goto("res://scenes/battlescape.tscn")
	await _frames(20)
	var b = scene.get_node("Battlescape")
	await _shot("14_battlescape")
	# Walk the selected officer forward and open the police action menu on the nearest suspect.
	var s = null
	for u in b.mission.suspects():
		s = u
	b.camera.position = UnitView.cell_to_screen(s.pos)
	await _frames(10)
	await _shot("15_battlescape_suspect")
	b._open_menu(s)
	await _frames(5)
	await _shot("16_action_menu")
	b.menu.hide()
	# Move the selected officer toward the suspect, then end the turn and let the others act.
	var o = b.selected
	var path = Pathfinder.find_path(b.mission.map, o.pos, s.pos, b.mission.occupied(o))
	path.resize(mini(path.size() - 1, 5))
	b.act(func(): return b.mission.move_unit(o, path) > 0)
	await _frames(40)
	b.center_on_selected()
	b.set_target_mode("aimed")
	b.hover = s.pos
	b.overlay.queue_redraw()
	b.hud.update_hover()
	await _frames(10)
	await _shot("16b_targeting")
	b.hud.toggle_inventory()
	await _frames(5)
	await _shot("16d_inventory")
	b.hud.toggle_inventory()
	b.end_turn()
	await _frames(90)
	await _shot("16c_after_enemy_turn")
	b.mission.withdraw()
	b._play(b.mission.take_events())
	await _frames(30)
	await _shot("17_debrief")
	quit()
