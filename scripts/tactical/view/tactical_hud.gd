class_name TacticalHud
extends CanvasLayer
## The battlescape control panel, X-COM style: the selected officer's portrait, rank, time units,
## health and Composure, the weapon in hand with its fire modes, belt items, stance, reserve,
## next officer, backup, end turn and withdraw; the message log, objectives, spotted suspects,
## and the debrief at the end.

const FONT := 9
const PANEL_H := 70

var battlescape: Battlescape
var _name: Label
var _bars: Control
var _weapon_btn: Button
var _belt_box: HBoxContainer
var _info: Label
var _log: Label
var _objectives: Label
var _banner: Label
var _spotted: HBoxContainer
var _reserve_btn: Button
var _portrait: TextureRect
var _hover: Label
var _modes: PopupMenu
var _debrief: PanelContainer
var _lines: Array[String] = []


func _ready() -> void:
	layer = 10
	var panel := PanelContainer.new()
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.anchor_right = 1.0
	panel.offset_top = -PANEL_H
	panel.add_theme_stylebox_override("panel", _box(Color(0.07, 0.08, 0.11, 0.96), Color(0.3, 0.34, 0.45)))
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(56, 56)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture = load("res://art/characters/portraits/rookie_portrait_neutral.png")
	row.add_child(_portrait)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(150, 0)
	col.add_theme_constant_override("separation", 1)
	row.add_child(col)
	_name = _label(col, "")
	_bars = Control.new()
	_bars.custom_minimum_size = Vector2(150, 30)
	_bars.draw.connect(_draw_bars)
	col.add_child(_bars)
	_info = _label(col, "")
	_info.add_theme_color_override("font_color", Color(0.7, 0.72, 0.78))
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 2)
	row.add_child(mid)
	_weapon_btn = _button(mid, "Weapon", _on_weapon)
	_weapon_btn.custom_minimum_size = Vector2(120, 0)
	_belt_box = HBoxContainer.new()
	mid.add_child(_belt_box)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	row.add_child(grid)
	_button(grid, "Kneel", func(): battlescape.act(func(): return battlescape.mission.toggle_stance(battlescape.selected))).tooltip_text = "Kneel or stand [K]"
	_button(grid, "Next", func(): battlescape.select_next()).tooltip_text = "Next officer [N]"
	_button(grid, "Center", func(): battlescape.center_on_selected()).tooltip_text = "Center on officer [C]"
	_reserve_btn = _button(grid, "Rsv: -", _cycle_reserve)
	_reserve_btn.tooltip_text = "Reserve time units for reaction fire"
	_button(grid, "Reload", func(): battlescape.act(func(): return battlescape.mission.reload(battlescape.selected))).tooltip_text = "Reload [R]"
	_button(grid, "Bag item", func(): battlescape.act(func(): return battlescape.mission.pick_up(battlescape.selected))).tooltip_text = "Make safe and bag evidence underfoot [P]"
	_button(grid, "Backup", func(): battlescape.act(func(): return battlescape.mission.request_backup(battlescape.selected))).tooltip_text = "Radio for backup"
	_button(grid, "Help!", func(): battlescape.act(func(): return battlescape.mission.request_backup(battlescape.selected, true))).tooltip_text = "Officer needs help: everyone comes, fast"
	var end_btn := _button(grid, "End turn", func(): battlescape.end_turn())
	end_btn.tooltip_text = "End turn [Enter]"
	end_btn.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	_button(grid, "Withdraw", _on_withdraw).tooltip_text = "Pull back and wait for SWAT (the scene is lost)"
	_weapon_btn.get_parent().move_child(_belt_box, 1)
	_button(_belt_box, "Gear [I]", toggle_inventory).tooltip_text = "Inventory: everything this officer carries"

	_log = _label(self, "")
	_log.position = Vector2(6, 4)
	_log.size = Vector2(380, 60)
	_log.custom_minimum_size = Vector2(380, 0)
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objectives = _label(self, "")
	_objectives.position = Vector2(400, 4)
	_objectives.size = Vector2(236, 60)
	_objectives.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objectives.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_objectives.add_theme_color_override("font_color", Color(0.8, 0.82, 0.7))
	_spotted = HBoxContainer.new()
	_spotted.anchor_left = 1.0
	_spotted.anchor_right = 1.0
	_spotted.anchor_top = 1.0
	_spotted.anchor_bottom = 1.0
	_spotted.offset_left = -200
	_spotted.offset_top = -PANEL_H - 18
	_spotted.alignment = BoxContainer.ALIGNMENT_END
	_spotted.size = Vector2(196, 16)
	add_child(_spotted)
	_hover = _label(self, "")
	_hover.anchor_top = 1.0
	_hover.anchor_bottom = 1.0
	_hover.offset_top = -PANEL_H - 16
	_hover.position.x = 6
	_hover.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	_banner = _label(self, "")
	_banner.anchor_right = 1.0
	_banner.anchor_top = 0.35
	_banner.offset_right = 0
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 14)
	_banner.add_theme_color_override("font_color", Color(1, 0.85, 0.5))
	_banner.visible = false
	_modes = PopupMenu.new()
	_modes.add_theme_font_size_override("font_size", FONT)
	_modes.id_pressed.connect(_on_mode)
	add_child(_modes)
	refresh()


func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_content_margin_all(4)
	return s


func _label(parent: Node, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", FONT)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	parent.add_child(l)
	return l


var _compact := {}


## Compact buttons: the shared theme's padding is too wide for an X-COM control panel.
func _button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 8)
	if _compact.is_empty():
		var t := UiKit.theme()
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			var sb: StyleBoxFlat = t.get_stylebox(state, "Button").duplicate()
			sb.content_margin_left = 2
			sb.content_margin_right = 2
			sb.content_margin_top = 1
			sb.content_margin_bottom = 1
			_compact[state] = sb
	for state in _compact:
		b.add_theme_stylebox_override(state, _compact[state])
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func refresh() -> void:
	if battlescape == null or _name == null:
		return
	var m := battlescape.mission
	var u := battlescape.selected
	_objectives.text = "Turn %d  %s\n%s" % [m.turn, "(night)" if m.map.night else "",
		"\n".join(m.objectives.map(func(o): return ("* " if o.kind == "primary" else "- ") + o.text))]
	for c in _spotted.get_children():
		c.queue_free()
	var n := 0
	for s in m.suspects():
		if s.is_threat() and m.visible_to_officers(s):
			n += 1
			var su := s
			var b := _button(_spotted, str(n), func(): battlescape.camera.position = UnitView.cell_to_screen(su.pos))
			b.add_theme_color_override("font_color", Color(1, 0.4, 0.35))
			b.tooltip_text = s.name
	if u == null:
		_name.text = "No officer able to act"
		_info.text = ""
		_weapon_btn.text = "-"
		_bars.queue_redraw()
		return
	_name.text = "%s  %s" % [u.name, u.rank]
	var stance := "Kneeling" if u.stance == TacUnit.Stance.KNEELING else "Standing"
	_info.text = "%s  %s  %s  Basis: %s" % [stance, u.wound_label(), "Bleeding" if u.fatal_wounds > 0 else "", m.basis.replace("_", " ")]
	var w := u.weapon()
	if w == "":
		_weapon_btn.text = "Empty hands"
	else:
		var item := ItemDB.get_item(w)
		var ammo := ""
		if item.has("capacity"):
			ammo = "  %d/%d (+%d)" % [int(u.ammo.get(w, 0)), int(item.capacity), int(u.uses.get("%s_spare" % w, 0))]
		_weapon_btn.text = "%s%s%s" % [item.name, ammo, "  [targeting]" if battlescape.mode == Battlescape.Mode.TARGET else ""]
	for c in _belt_box.get_children():
		if c.text != "Gear [I]":
			c.queue_free()
	for b in u.belt:
		if ItemDB.is_weapon(b):
			var bb: String = b
			var btn := _button(_belt_box, ItemDB.get_item(b).name.split(" (")[0], func(): battlescape.act(func(): return battlescape.mission.equip(battlescape.selected, bb)))
			btn.tooltip_text = "Draw (%d TU)" % TacMission.DRAW_TU
	_reserve_btn.text = "Rsv: %s" % ["-", "snap", "aim"][u.reserve]
	var expression := "neutral"
	if u.morale < 25:
		expression = "shaken"
	elif u.morale < 50:
		expression = "tired"
	elif u.fatal_wounds > 0 or u.health < u.health_max / 2:
		expression = "sad"
	_portrait.texture = load("res://art/characters/portraits/rookie_portrait_%s.png" % expression)
	_bars.queue_redraw()


## TU and health are numbered; Composure is shown, never numbered (design 5).
func _draw_bars() -> void:
	var u := battlescape.selected if battlescape else null
	if u == null:
		return
	var rows := [["TU %d/%d" % [u.tu, u.tu_max], float(u.tu) / u.tu_max, Color(0.35, 0.8, 0.45), float(u.reserved_tu()) / u.tu_max],
		["HP %d/%d" % [maxi(u.health, 0), u.health_max], float(maxi(u.health, 0)) / u.health_max, Color(0.85, 0.3, 0.28), 0.0],
		["Composure", float(u.morale) / 100.0, Color(0.4, 0.55, 0.95), 0.0]]
	var font := ThemeDB.fallback_font
	for i in rows.size():
		var y := i * 10.0
		_bars.draw_rect(Rect2(52, y + 2, 96, 6), Color(0.15, 0.16, 0.2))
		_bars.draw_rect(Rect2(52, y + 2, 96 * clampf(rows[i][1], 0, 1), 6), rows[i][2])
		if rows[i][3] > 0:
			_bars.draw_rect(Rect2(52 + 96 * clampf(rows[i][1] - rows[i][3], 0, 1), y + 2, 96 * rows[i][3], 6), Color(1, 1, 1, 0.3))
		_bars.draw_string(font, Vector2(0, y + 8), rows[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.85, 0.86, 0.9))


func update_hover() -> void:
	var b := battlescape
	if b == null or b.selected == null or not b.mission.map.in_bounds(b.hover):
		_hover.text = ""
		return
	var m := b.mission
	var t := m.unit_at(b.hover)
	if t and t != b.selected and m.visible_to_officers(t):
		var extra := ""
		if b.mode == Battlescape.Mode.TARGET and b.selected.weapon() != "":
			extra = "  %s: %d%% for %d TU" % [b.target_mode, m.hit_chance(b.selected, b.selected.weapon(), b.target_mode, t), m.mode_tu(b.selected, b.selected.weapon(), b.target_mode)]
		var cover: String = TacMap.COVER_NAMES[m.map.cover_against(t.pos, b.selected.pos)]
		var read := ""
		if t.side != TacUnit.Side.OFFICER and (b.selected.background.get("read_the_situation", false) or t.pos.distance_to(b.selected.pos) < 5):
			read = ", " + t.disposition_name()
		_hover.text = "%s (%s%s, %s)%s" % [t.name, t.status_name(), read, cover, extra]
		return
	if b._reach.has("cost") and b._reach.cost.has(b.hover):
		var cost: int = b._reach.cost[b.hover]
		_hover.text = "Move: %d TU (%d left)" % [cost, b.selected.tu - cost]
	else:
		_hover.text = ""


func log_line(text: String) -> void:
	_lines.append(text)
	while _lines.size() > 5:
		_lines.pop_front()
	_log.text = "\n".join(_lines)


func flash_spotted() -> void:
	refresh()


func show_banner(text: String) -> void:
	_banner.text = text
	_banner.visible = true


func hide_banner() -> void:
	_banner.visible = false


func _on_weapon() -> void:
	var u := battlescape.selected
	if u == null or u.weapon() == "":
		return
	var item := ItemDB.get_item(u.weapon())
	_modes.clear()
	var i := 0
	for mname in item.modes:
		_modes.add_item("%s  (%d TU)" % [item.modes[mname].label, battlescape.mission.mode_tu(u, u.weapon(), mname)], i)
		_modes.set_item_metadata(i, mname)
		i += 1
	_modes.position = Vector2i(_weapon_btn.global_position + Vector2(0, -12 * (i + 1)))
	_modes.reset_size()
	_modes.popup()


func _on_mode(id: int) -> void:
	battlescape.set_target_mode(String(_modes.get_item_metadata(id)))


func _cycle_reserve() -> void:
	var u := battlescape.selected
	if u == null:
		return
	u.reserve = ((u.reserve + 1) % 3) as TacUnit.Reserve
	battlescape._recompute_reach()
	refresh()


func _on_withdraw() -> void:
	if battlescape.busy or battlescape.mission.phase == TacMission.Phase.OVER:
		return
	battlescape.mission.withdraw()
	battlescape._play(battlescape.mission.take_events())


## The debrief: X-COM's mission score, then Rampart's use-of-force review (design 6.5).
func show_debrief(result: Dictionary) -> void:
	hide_banner()
	if _debrief:
		_debrief.queue_free()
	_debrief = PanelContainer.new()
	_debrief.custom_minimum_size = Vector2(460, 300)
	_debrief.position = Vector2(90, 20)
	_debrief.add_theme_stylebox_override("panel", _box(Color(0.06, 0.07, 0.1, 0.98), Color(0.5, 0.45, 0.3)))
	add_child(_debrief)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(450, 290)
	_debrief.add_child(scroll)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(420, 0)
	scroll.add_child(col)
	var title := _label(col, "%s: %s" % ["SCENE SECURED" if result.success else "SCENE LOST", result.reason])
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5) if result.success else Color(1, 0.5, 0.45))
	_label(col, "%s  |  %d turns" % [result.call.get("label", ""), result.turns])
	var lines := ""
	for l in result.lines:
		lines += "%-32s %3d %+5d\n" % [l.label, l.count, l.points]
	var table := _label(col, lines + "\nScore %+d   Rating: %s" % [result.score, result.rating])
	table.add_theme_font_override("font", _mono())
	table.add_theme_font_size_override("font_size", 8)
	_label(col, "")
	var rv := _label(col, "USE-OF-FORCE REVIEW")
	rv.add_theme_color_override("font_color", Color(0.85, 0.75, 0.45))
	if result.reviews.is_empty():
		_label(col, "No force applied.")
	for r in result.reviews:
		var l := _label(col, "%s -> %s (%s): %s. %s" % [r.officer, r.target, String(r.item).replace("_", " "), r.outcome, r.reason])
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(410, 0)
		l.add_theme_color_override("font_color", [Color(0.7, 0.9, 0.7), Color(0.9, 0.9, 0.6), Color(1, 0.7, 0.4), Color(1, 0.45, 0.4)][int(r.severity)])
	for s in result.stray_rounds:
		_label(col, "Round fired: %s." % s.outcome)
	_label(col, "")
	for o in result.officers:
		_label(col, "%s: %s, %s" % [o.name, o.status, o.wound.to_lower()])
	var btn := _button(col, "Return to the station", func(): battlescape.finished.emit(result))
	btn.add_theme_font_size_override("font_size", 10)


## The X-COM inventory screen, police edition: hand, belt, armor, ammunition, cuffs, aid kit and evidence.
var _inventory: PanelContainer


func toggle_inventory() -> void:
	if _inventory:
		_inventory.queue_free()
		_inventory = null
		return
	var u := battlescape.selected
	if u == null:
		return
	_inventory = PanelContainer.new()
	_inventory.position = Vector2(150, 40)
	_inventory.custom_minimum_size = Vector2(320, 0)
	_inventory.add_theme_stylebox_override("panel", _box(Color(0.06, 0.07, 0.1, 0.98), Color(0.4, 0.42, 0.55)))
	add_child(_inventory)
	var col := VBoxContainer.new()
	_inventory.add_child(col)
	var t := _label(col, "%s: equipment" % u.name)
	t.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	var weight := 0
	var rows: Array[String] = []
	var hand := u.right_hand
	rows.append("In hand: %s" % (ItemDB.get_item(hand).name if hand != "" else "nothing"))
	for b in u.belt:
		var d := ItemDB.get_item(b)
		weight += int(d.get("weight", 0))
		var extra := ""
		if d.has("capacity"):
			extra = " (%d loaded, %d spare)" % [int(u.ammo.get(b, 0)), int(u.uses.get("%s_spare" % b, 0))]
		elif u.uses.has(b):
			extra = " (%d left)" % int(u.uses[b])
		rows.append("Belt: %s%s" % [d.name, extra])
	if hand != "":
		weight += int(ItemDB.get_item(hand).get("weight", 0))
	if u.armor != "":
		weight += int(ItemDB.get_item(u.armor).get("weight", 0))
		rows.append("Worn: %s (stops %d ballistic)" % [ItemDB.get_item(u.armor).name, u.armor_value("ballistic")])
	if not u.ground_items.is_empty():
		rows.append("Evidence bagged: " + ", ".join(u.ground_items.map(func(i): return ItemDB.get_item(i).name.to_lower())))
	var underfoot: Array = battlescape.mission.ground_items.get(u.pos, [])
	if not underfoot.is_empty():
		rows.append("On the ground here: " + ", ".join(underfoot.map(func(i): return ItemDB.get_item(i).name.to_lower())))
	rows.append("Carried weight %d of %d" % [weight, u.strength / 2])
	rows.append("Drawing an item from the belt costs %d TU; bagging evidence %d TU." % [TacMission.DRAW_TU, TacMission.PICKUP_TU])
	for r in rows:
		_label(col, r)
	_button(col, "Close", toggle_inventory)


func _mono() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["DejaVu Sans Mono", "Liberation Mono", "Courier New", "monospace"])
	return f
