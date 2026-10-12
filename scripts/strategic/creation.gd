extends Control
## Character creation (design section 3), on one screen: identity, origin, background, the Cascade,
## why you joined, academy record, attributes, traits and flaw, personal start, difficulty.
## Academy record and background decide your training officer.

const CASCADE := ["Saved by a hero", "Lost someone to a fight", "A sibling manifested", "Grew up on Ledger culture", "Anti-cape household"]
const JOINED := ["Serve the community", "Family legacy", "Steady paycheck and pension", "Get out of the neighborhood", "Get close to the capes"]
const HOUSING := ["Koreatown apartment with a roommate", "Valley studio", "Parents' place"]
const RELATIONSHIP := ["Single", "Dating", "Engaged", "Married"]

var data: Dictionary
var _name: LineEdit
var _pick := {}
var _spin := {}
var _summary: Label
var _points: Label
var _begin: Button
var _ironman: CheckBox


func _ready() -> void:
	data = Campaign.creation
	set_anchors_preset(Control.PRESET_FULL_RECT)
	UiKit.backdrop(self)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(8, 8)
	scroll.size = Vector2(380, 344)
	add_child(scroll)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(360, 0)
	col.add_theme_constant_override("separation", 3)
	scroll.add_child(col)
	UiKit.label(col, "NEW PROBATION: POLICE OFFICER I", UiKit.ACCENT, 12)
	_name = LineEdit.new()
	_name.placeholder_text = "Your name"
	_name.text = "Officer Reyes"
	_name.text_changed.connect(func(_t): _update())
	_row(col, "Name", _name)
	_option(col, "origin", "Origin", _labels(data.origins))
	_option(col, "background", "Background", _labels(data.backgrounds))
	_option(col, "cascade", "During the Cascade", _plain(CASCADE))
	_option(col, "joined", "Why you joined", _plain(JOINED))
	_option(col, "standing", "Class standing", _labels(data.academy_standing))
	_option(col, "strength", "Academy strength", _labels(data.academy_strength))
	UiKit.label(col, "Attributes: start at 3, spend 15 points, cap 7 (8 with bonuses)", UiKit.MUTED)
	for a in Officer.ATTRIBUTES:
		var s := SpinBox.new()
		s.min_value = 0
		s.max_value = 4
		s.value = 3 if a in ["fitness", "nerve", "perception"] else 2
		s.value_changed.connect(func(_v): _update())
		_spin[a] = s
		_row(col, a.capitalize(), s)
	_points = UiKit.label(col, "", UiKit.ACCENT)
	_option(col, "trait1", "Trait", _labels_text(data.traits))
	_option(col, "trait2", "Second trait", _labels_text(data.traits), 1)
	_option(col, "flaw", "Flaw", _labels_text(data.flaws))
	_option(col, "housing", "Housing", _plain(HOUSING))
	_option(col, "relationship", "Relationship", _plain(RELATIONSHIP))
	_ironman = CheckBox.new()
	_ironman.text = "Ironman (End of Watch): one save, death is permanent"
	col.add_child(_ironman)
	var side := VBoxContainer.new()
	side.position = Vector2(398, 8)
	side.custom_minimum_size = Vector2(234, 340)
	add_child(side)
	_summary = UiKit.para(side, "", 230)
	var buttons := HBoxContainer.new()
	side.add_child(buttons)
	UiKit.button(buttons, "Back", func(): Flow.main_menu())
	_begin = UiKit.button(buttons, "Begin probation", _start)
	_update()


func _labels(d: Dictionary) -> Array:
	var out: Array = []
	for k in d:
		out.append([k, d[k].label])
	return out


func _labels_text(d: Dictionary) -> Array:
	var out: Array = []
	for k in d:
		out.append([k, String(d[k]).split(":")[0]])
	return out


func _plain(items: Array) -> Array:
	return items.map(func(i): return [i, i])


func _row(parent: Node, text: String, control: Control) -> void:
	var h := HBoxContainer.new()
	parent.add_child(h)
	var l := UiKit.label(h, text, UiKit.MUTED)
	l.custom_minimum_size = Vector2(110, 0)
	control.custom_minimum_size.x = 230
	h.add_child(control)


func _option(parent: Node, key: String, text: String, items: Array, selected: int = 0) -> void:
	var o := OptionButton.new()
	for i in items:
		o.add_item(i[1])
		o.set_item_metadata(o.item_count - 1, i[0])
	o.select(selected)
	o.item_selected.connect(func(_i): _update())
	_pick[key] = o
	_row(parent, text, o)


func _val(key: String) -> String:
	return String(_pick[key].get_selected_metadata())


func _bonuses() -> Dictionary:
	var b := {}
	for src in [data.origins[_val("origin")].bonus, data.backgrounds[_val("background")].bonus]:
		for a in src:
			b[a] = mini(2, int(b.get(a, 0)) + int(src[a]))
	return b


func _spent() -> Dictionary:
	var s := {}
	for a in _spin:
		s[a] = int(_spin[a].value)
	return s


## Academy record and background pick the training officer (design 3 and 11).
static func assign_fto(background: Dictionary, standing: String) -> String:
	if standing == "barely":
		return "arakawa"
	if background.get("military", false) or background.get("physical", false):
		return "whitfield"
	return "ortega"


func build_officer() -> Officer:
	var o := Officer.new()
	o.display_name = _name.text.strip_edges() if _name.text.strip_edges() != "" else "Officer"
	var b := _bonuses()
	var s := _spent()
	for a in Officer.ATTRIBUTES:
		o.attributes[a] = Officer.CREATION_BASE + int(s[a]) + int(b.get(a, 0))
	var skills: Dictionary = data.academy_baseline.duplicate()
	var bg: Dictionary = data.backgrounds[_val("background")]
	var origin: Dictionary = data.origins[_val("origin")]
	var strength: Dictionary = data.academy_strength[_val("strength")]
	for src in [bg.skills, origin.skills, strength.get("skills", {})]:
		for k in src:
			skills[k] = mini(5, int(skills.get(k, 0)) + int(src[k]))
	o.skills = skills
	for src in [origin.languages, strength.get("languages", {})]:
		for k in src:
			o.languages[k] = maxi(int(o.languages.get(k, 0)), int(src[k]))
	if "bilingual_bonus" in [_val("trait1"), _val("trait2")]:
		o.languages["spanish"] = maxi(int(o.languages.get("spanish", 0)), 3)
	for h in bg.habits:
		o.habits.append(Habit.make(h[0], int(h[1])))
	o.composure = o.max_composure()
	if _val("flaw") == "bottle_problem":
		o.composure = maxi(1, o.composure - 3)
	return o


func _update() -> void:
	var problems := Officer.validate_creation(_spent(), _bonuses())
	if _val("trait1") == _val("trait2"):
		problems.append("pick two different traits")
	var spent := 0
	for a in _spin:
		spent += int(_spin[a].value)
	_points.text = "Points spent: %d of %d" % [spent, Officer.CREATION_POINTS]
	var o := build_officer()
	var bg: Dictionary = data.backgrounds[_val("background")]
	var fto := assign_fto(bg, _val("standing"))
	var lines: Array[String] = []
	lines.append(o.display_name)
	lines.append("")
	for a in Officer.ATTRIBUTES:
		lines.append("%s %d" % [a.capitalize(), o.attributes[a]])
	lines.append("")
	var sk: Array = o.skills.keys()
	sk.sort()
	lines.append("Skills: " + ", ".join(sk.filter(func(k): return int(o.skills[k]) > 1).map(func(k): return "%s %d" % [k.replace("_", " ").capitalize(), o.skills[k]])))
	lines.append("Languages: " + (", ".join(o.languages.keys().map(func(k): return "%s %d" % [k.capitalize(), o.languages[k]])) if not o.languages.is_empty() else "English"))
	lines.append("Habits: " + (", ".join(o.habits.map(func(h): return h.title())) if not o.habits.is_empty() else "none"))
	lines.append("Firearms %d%%, Command Presence %d%%, De-escalation %d%%" % [o.skill_chance("firearms"), o.skill_chance("command_presence"), o.skill_chance("de_escalation")])
	var t := TacUnit.from_officer(o, "player", o.display_name, {"traits": [_val("trait1"), _val("trait2"), _val("flaw")]})
	lines.append("Time units %d, health %d, reactions %d" % [t.tu_max, t.health_max, t.reactions])
	lines.append("")
	lines.append("Training officer: %s" % Campaign.people[fto].name)
	if not problems.is_empty():
		lines.append("")
		lines.append("To fix: " + "; ".join(problems))
	_summary.text = "\n".join(lines)
	_begin.disabled = not problems.is_empty()


func _start() -> void:
	if _begin.disabled:
		return
	var o := build_officer()
	var bg_key := _val("background")
	var bg: Dictionary = data.backgrounds[bg_key]
	var fto := assign_fto(bg, _val("standing"))
	GameState.new_game(o)
	for d in data.origins[_val("origin")].get("community", {}):
		GameState.change_reputation("community:%s" % d, int(data.origins[_val("origin")].community[d]))
	var profile := {
		"name": o.display_name, "rank": "Police Officer I", "role": "player", "look": "officer",
		"background": bg_key, "origin": _val("origin"), "traits": [_val("trait1"), _val("trait2"), _val("flaw")],
		"loadout": "taser", "cascade": _val("cascade"), "joined": _val("joined"), "standing": _val("standing"),
		"housing": _val("housing"), "relationship": _val("relationship"),
	}
	Campaign.new_campaign(profile, fto)
	Campaign.difficulty["ironman"] = _ironman.button_pressed
	GameState.set_flag("background", bg_key)
	GameState.set_flag("academy_standing", _val("standing"))
	Flow.go(Flow.PROLOGUE)
