extends SceneTree
## Loads every script and scene so parse errors surface: godot --headless --path . -s res://tests/check_scripts.gd


func _init() -> void:
	_run.call_deferred()


func _walk(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd") or f.ends_with(".tscn"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		if not sub.begins_with("."):
			_walk(dir.path_join(sub), out)


func _run() -> void:
	var files: Array = []
	for root_dir in ["res://scripts", "res://scenes", "res://tests"]:
		_walk(root_dir, files)
	var bad := 0
	for f in files:
		var r = load(f)
		if r == null:
			bad += 1
			printerr("FAILED TO LOAD ", f)
	print("%d files loaded, %d failed" % [files.size(), bad])
	quit(1 if bad > 0 else 0)
