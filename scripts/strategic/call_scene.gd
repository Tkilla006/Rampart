class_name CallScene
extends RefCounted
## On-scene choices for calls for service (design 6.1 Contact, played as a short text scene).
## Each node offers up to a few options. An option can need a skill check, made by whichever officer
## on scene is best at it, and can need an item from the kit room. Success and failure each lead to
## another node or to a result. A result can hand the scene to the battlescape ("tactical").
##
## Scene files: data/scenes/calls/<call type>.json
##   {"call_type": "415", "variants": [{"when": {...}, "start": "id"}], "nodes": {id: node}}
##   when: {"truth": [indexes]} | {"false_alarm": true} | {} (fallback)
##   node: {"text": "...", "options": [option]}
##   option: {"text", "skill"?, "modifier"?, "item"?, "success": outcome, "failure"?: outcome}
##   outcome: {"next": "id"} or {"result": code, "injury"?: 0-3, "note"?: "..."}

const DIR := "res://data/scenes/calls/"
const RESULTS := ["arrest", "cite", "warn", "report", "hold_5150", "cleared", "escaped", "false_alarm", "tactical"]

## Points and reputation per result, in the spirit of the battlescape debrief.
const RESULT_EFFECTS := {
	"arrest": {"score": 30, "squad": 1, "community": 0, "minutes": 90},
	"cite": {"score": 15, "squad": 0, "community": 0, "minutes": 20},
	"warn": {"score": 8, "squad": 0, "community": 1, "minutes": 10},
	"report": {"score": 5, "squad": 0, "community": 0, "minutes": 35},
	"hold_5150": {"score": 20, "squad": 0, "community": 1, "minutes": 120},
	"cleared": {"score": 10, "squad": 0, "community": 1, "minutes": 10},
	"escaped": {"score": -20, "squad": -1, "community": -1, "minutes": 20},
	"false_alarm": {"score": 0, "squad": 0, "community": 0, "minutes": 10},
	"tactical": {"score": 0, "squad": 0, "community": 0, "minutes": 0},
}
const INJURY_DAYS := [0, 1, 3, 10]
const INJURY_NAMES := ["", "bruised", "hurt", "wounded"]

static var _cache := {}

var data := {}
var call := {}
var crew: Array = []   # [{key, name, officer: Officer, items: Array}]
var current := ""
var log: Array[String] = []
var result := {}
var rng := RandomNumberGenerator.new()


static func load_for(call_type: String) -> Dictionary:
	if _cache.has(call_type):
		return _cache[call_type]
	var path := DIR + "%s.json" % call_type
	var d := {}
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			d = parsed
	_cache[call_type] = d
	return d


static func has_scene(call_type: String) -> bool:
	return not load_for(call_type).is_empty()


func _init(scene_data: Dictionary = {}, the_call: Dictionary = {}, the_crew: Array = [], seed_value: int = 0) -> void:
	data = scene_data
	call = the_call
	crew = the_crew
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value


func start() -> String:
	for v in data.get("variants", []):
		if _matches(v.get("when", {})):
			current = v.start
			return current
	current = ""
	return current


func _matches(when: Dictionary) -> bool:
	if when.has("false_alarm"):
		return bool(call.get("false_alarm", false)) == bool(when.false_alarm)
	if when.has("truth"):
		return not call.get("false_alarm", false) and int(call.get("truth_index", 0)) in Array(when.truth).map(func(i): return int(i))
	return true


func node() -> Dictionary:
	return data.nodes.get(current, {})


## The officer on scene best placed to attempt an option, with their odds (visible, design 4).
func attempt_for(option: Dictionary) -> Dictionary:
	if not option.has("skill"):
		return {"name": "", "chance": 100, "key": ""}
	var best := {}
	for m in crew:
		var o: Officer = m.officer
		var c := o.skill_chance(option.skill, int(option.get("modifier", 0)))
		if best.is_empty() or c > int(best.chance):
			best = {"name": m.name, "chance": c, "key": m.key}
	if best.is_empty():
		return {"name": "", "chance": 0, "key": ""}
	best.chance = Check.display_odds(int(best.chance))
	return best


func option_available(option: Dictionary) -> bool:
	if not option.has("item"):
		return true
	for m in crew:
		if option.item in m.get("items", []):
			return true
	return false


func option_label(option: Dictionary) -> String:
	var t: String = option.text
	if option.has("skill"):
		var a := attempt_for(option)
		t += "  [%s %d%%: %s]" % [String(option.skill).replace("_", " ").capitalize(), a.chance, a.name]
	if option.has("item"):
		t += "  (needs %s)" % ItemDB.get_item(option.item).name.split(" (")[0]
	return t


## Picks an option. Returns true when the scene has ended; the result is then in `result`.
func choose(index: int) -> bool:
	var options: Array = node().get("options", [])
	if index < 0 or index >= options.size():
		return false
	var option: Dictionary = options[index]
	if not option_available(option):
		return false
	var outcome: Dictionary = option.success
	var who := attempt_for(option)
	if option.has("skill"):
		var res := Check.make(int(who.chance), rng)
		log.append("%s: %s (%s)" % [who.name, res.describe(), String(option.skill).replace("_", " ")])
		if not res.success:
			outcome = option.get("failure", option.success)
	if outcome.has("next"):
		current = outcome.next
		return false
	result = {"result": outcome.result, "injury": int(outcome.get("injury", 0)), "note": outcome.get("note", ""),
		"officer": who.get("key", ""), "officer_name": who.get("name", "")}
	if result.officer == "" and not crew.is_empty():
		result.officer = crew[0].key
		result.officer_name = crew[0].name
	return true


## Checks a scene file: variants point at nodes, every option resolves, no dead ends, results are known.
static func validate(d: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	var nodes: Dictionary = d.get("nodes", {})
	if d.get("variants", []).is_empty():
		problems.append("no variants")
	var reachable := {}
	var stack: Array = []
	for v in d.get("variants", []):
		if not nodes.has(v.start):
			problems.append("variant starts at missing node %s" % v.start)
		else:
			stack.append(v.start)
	while not stack.is_empty():
		var id: String = stack.pop_back()
		if reachable.has(id):
			continue
		reachable[id] = true
		var opts: Array = nodes[id].get("options", [])
		if opts.is_empty():
			problems.append("%s has no options" % id)
		for o in opts:
			if o.has("skill") and not Officer.SKILL_ATTRIBUTE.has(o.skill):
				problems.append("%s: unknown skill %s" % [id, o.skill])
			if o.has("item") and not ItemDB.has(o.item):
				problems.append("%s: unknown item %s" % [id, o.item])
			for key in ["success", "failure"]:
				if not o.has(key):
					continue
				var out: Dictionary = o[key]
				if out.has("next"):
					if nodes.has(out.next):
						stack.append(out.next)
					else:
						problems.append("%s links to missing %s" % [id, out.next])
				elif not out.get("result", "") in RESULTS:
					problems.append("%s: unknown result %s" % [id, out.get("result", "")])
			if o.has("skill") and not o.has("failure"):
				problems.append("%s: a skill check needs a failure outcome" % id)
	for id in nodes:
		if not reachable.has(id):
			problems.append("%s unreachable" % id)
	return problems
