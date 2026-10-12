extends Node
## Scene wrapper: runs the battlescape for the pending mission and reports the result to Flow.


func _ready() -> void:
	var b := Battlescape.new()
	b.name = "Battlescape"
	b.finished.connect(Flow.mission_finished)
	add_child(b)
