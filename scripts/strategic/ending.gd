extends Control
## The end of a probation: Police Officer II, washed out, or End of Watch (design 15, 16).


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	UiKit.backdrop(self)
	var e: Dictionary = Campaign.ending
	var col := VBoxContainer.new()
	col.position = Vector2(60, 60)
	add_child(col)
	UiKit.label(col, String(e.get("title", "The end")), UiKit.ACCENT, 20)
	UiKit.para(col, String(e.get("text", "")), 500)
	var lines: Array = []
	for h in Campaign.history.slice(maxi(0, Campaign.history.size() - 10)):
		lines.append("%s  %s  %s" % [h.date, h.label, h.rating])
	UiKit.para(col, "\n".join(lines), 500, UiKit.MUTED)
	UiKit.button(col, "Main menu", func(): Flow.main_menu())
