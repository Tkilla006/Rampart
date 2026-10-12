extends Control
## Rampart Station, the base: the roster with each officer's numbers and injuries, the crew of 2A43,
## the backup units, kit room loadouts, range time, and the field manual.

var _roster: ItemList
var _detail: Label
var _loadout: OptionButton
var _manual: Label
var _keys: Array = []


func _ready() -> void:
	name = "Station"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	UiKit.backdrop(self)
	var head := HBoxContainer.new()
	head.position = Vector2(8, 6)
	add_child(head)
	UiKit.label(head, "RAMPART STATION, 1401 W 6TH ST", UiKit.ACCENT, 11)
	var tabs := TabContainer.new()
	tabs.position = Vector2(8, 24)
	tabs.size = Vector2(624, 300)
	add_child(tabs)
	_roster_tab(tabs)
	_manual_tab(tabs)
	var foot := HBoxContainer.new()
	foot.position = Vector2(8, 330)
	add_child(foot)
	UiKit.button(foot, "Back to the map", func(): Flow.cityscape())
	UiKit.button(foot, "Range time ($60, 8 hours)", func(): _detail.text = Campaign.range_time())


func _roster_tab(tabs: TabContainer) -> void:
	var row := HBoxContainer.new()
	row.name = "Roster and kit room"
	tabs.add_child(row)
	_roster = ItemList.new()
	_roster.custom_minimum_size = Vector2(230, 270)
	_roster.item_selected.connect(_show)
	row.add_child(_roster)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(380, 0)
	row.add_child(col)
	_detail = UiKit.para(col, "Select an officer.", 370)
	var lrow := HBoxContainer.new()
	col.add_child(lrow)
	UiKit.label(lrow, "Kit room loadout:", UiKit.MUTED)
	_loadout = OptionButton.new()
	for l in ItemDB.loadout_ids():
		_loadout.add_item(l)
	_loadout.item_selected.connect(_set_loadout)
	lrow.add_child(_loadout)
	var arow := HBoxContainer.new()
	col.add_child(arow)
	UiKit.button(arow, "Ride in 2A43", _assign_crew)
	UiKit.button(arow, "Backup unit", _assign_backup)
	UiKit.button(arow, "Off the car", _unassign)
	_fill_roster()


func _fill_roster() -> void:
	_roster.clear()
	_keys.clear()
	for k in Campaign.roster:
		var r: Dictionary = Campaign.roster[k]
		var tag := ""
		if k in Campaign.crew:
			tag = " [2A43]"
		elif k in Campaign.backup_crew:
			tag = " [backup]"
		if int(r.get("injured_days", 0)) > 0:
			tag += " (injured %dd)" % int(r.injured_days)
		elif int(r.get("off_days", 0)) > 0:
			tag += " (day off)"
		tag += "  " + Campaign.energy_label(k)
		var display: String = GameState.officer.display_name if k == "player" else r.name
		_roster.add_item("%s%s" % [display, tag])
		_keys.append(k)


func _show(i: int) -> void:
	var k: String = _keys[i]
	var r: Dictionary = Campaign.roster[k]
	var u := Campaign.tac_unit_for(k)
	var o := u.officer
	var skills: Array = o.skills.keys().filter(func(s): return int(o.skills[s]) >= 2)
	skills.sort()
	var lines := ["%s, %s" % [u.name, r.get("rank", "")],
		"Time units %d   Health %d   Reactions %d   Firing accuracy %d   Bravery %d" % [u.tu_max, u.health_max, u.reactions, u.accuracy, u.bravery],
		" ".join(Officer.ATTRIBUTES.map(func(a): return "%s %d" % [a.substr(0, 3).capitalize(), o.attributes[a]])),
		"Skills: " + ", ".join(skills.map(func(s): return "%s %d" % [s.replace("_", " "), o.skills[s]])),
		"Habits: " + (", ".join(o.habits.map(func(h): return "%s %d" % [h.title(), h.strength])) if not o.habits.is_empty() else "none"),
	]
	if r.has("partner"):
		var p: Dictionary = r.partner
		lines.append("As a partner: aggression %d, discipline %d, talk %d, loyalty %d, skill %d" % [p.aggression, p.discipline, p.talk, p.loyalty, p.skill])
	var appr: int = int(GameState.relationship(k).get("approval", 0)) if k != "player" else 0
	if k != "player":
		lines.append("Approval of you: %d" % appr)
	if int(r.get("injured_days", 0)) > 0:
		lines.append("Light duty for %d more days." % int(r.injured_days))
	var mood := "happy" if int(r.get("happiness", 7)) >= int(r.get("happiness_threshold", 4)) + 2 else ("unhappy" if int(r.get("happiness", 7)) < int(r.get("happiness_threshold", 4)) else "getting by")
	lines.append("Energy: %s (%d/6). Mood: %s.%s%s" % [Campaign.energy_label(k), int(r.get("energy", 6)), mood,
		" Drinks after shifts." if r.get("drinker", false) else "", " Often late." if int(r.get("laziness", 0)) >= 2 else ""])
	_detail.text = "\n".join(lines)
	_loadout.select(ItemDB.loadout_ids().find(r.get("loadout", "patrol")))


func _current() -> String:
	var sel := _roster.get_selected_items()
	return _keys[sel[0]] if not sel.is_empty() else ""


func _set_loadout(i: int) -> void:
	var k := _current()
	if k != "":
		Campaign.set_loadout(k, ItemDB.loadout_ids()[i])


## Field training: you ride with your FTO. Up to three officers in the car, two backup units.
func _assign_crew() -> void:
	var k := _current()
	if k == "" or k in Campaign.crew or Campaign.crew.size() >= 3:
		return
	Campaign.backup_crew.erase(k)
	Campaign.crew.append(k)
	_fill_roster()


func _assign_backup() -> void:
	var k := _current()
	if k == "" or k == "player" or k in Campaign.backup_crew or Campaign.backup_crew.size() >= 2:
		return
	Campaign.crew.erase(k)
	Campaign.backup_crew.append(k)
	_fill_roster()


func _unassign() -> void:
	var k := _current()
	if k == "" or k == "player":
		return
	Campaign.crew.erase(k)
	Campaign.backup_crew.erase(k)
	_fill_roster()


## The field manual, X-COM's UFOpaedia: equipment and procedure from design section 6.
func _manual_tab(tabs: TabContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Field manual"
	tabs.add_child(scroll)
	var col := VBoxContainer.new()
	scroll.add_child(col)
	var lines: Array[String] = []
	for id in ItemDB.all_ids():
		var d := ItemDB.get_item(id)
		if id.begins_with("suspect_") or d.kind in ["harmless", "contraband"]:
			continue
		var t := "%s (%s)" % [d.name, d.kind.replace("_", "-")]
		if d.has("modes"):
			t += ": " + ", ".join(d.modes.keys().map(func(m): return "%s %d%% TU" % [d.modes[m].label.to_lower(), d.modes[m].tu]))
		if d.has("damage") and int(d.damage) > 1:
			t += "; damage %d" % int(d.damage)
		if d.has("force"):
			t += "; force step %d" % int(d.force)
		lines.append(t)
	lines.append("")
	lines.append("Cover: full cover -40 to hit and stops handgun rounds; half cover -20; concealment -10 and stops nothing.")
	lines.append("Time units: 4 a straight step, 6 diagonal, +4 to open a door, more over rubble and fences. Kneel 4, stand 8.")
	lines.append("Reaction fire: an officer with time units left fires on a visible deadly threat if quicker than the mover.")
	lines.append("Legal basis: consensual, reasonable suspicion, probable cause, exigency, warrant. The game records what you had.")
	lines.append("Force ladder: presence, commands, hands-on, OC/Taser/beanbag, baton, firearm. Every step is reviewed.")
	UiKit.para(col, "\n".join(lines), 600)
