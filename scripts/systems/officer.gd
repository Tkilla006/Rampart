class_name Officer
extends RefCounted
## The player character's numbers: attributes, skills, Composure and Habits (design sections 4 and 5).

enum ComposureBand { FULL, ABOVE_HALF, BELOW_HALF, BELOW_QUARTER, ZERO }

const ATTRIBUTES := ["fitness", "nerve", "perception", "intellect", "presence", "empathy"]

## Skill -> governing attribute, from the skills table in section 4. Languages have no attribute.
const SKILL_ATTRIBUTE := {
	"firearms": "perception",
	"less_lethal": "perception",
	"defensive_tactics": "fitness",
	"athletics": "fitness",
	"driving": "perception",
	"first_aid": "intellect",
	"law_and_policy": "intellect",
	"report_writing": "intellect",
	"evidence": "perception",
	"search": "perception",
	"radio_and_dispatch": "intellect",
	"interview": "empathy",
	"interrogation": "presence",
	"de_escalation": "empathy",
	"command_presence": "presence",
	"deception": "presence",
	"streetwise": "perception",
	"ledger_knowledge": "intellect",
	"super_incident_response": "nerve",
	"power_assessment": "perception",
}

## Creation rules: every attribute starts at 3; spend 15 points; cap 7 before background bonuses; 8 after.
const CREATION_BASE := 3
const CREATION_POINTS := 15
const CREATION_CAP := 7
const CREATION_CAP_WITH_BONUS := 8

var display_name := "Officer"
var attributes := {}
var skills := {}
var languages := {}
var composure := 0
var habits: Array[Habit] = []


func _init() -> void:
	for a in ATTRIBUTES:
		attributes[a] = CREATION_BASE
	composure = max_composure()


func max_composure() -> int:
	return attributes["nerve"] * 3


func attribute(name: String) -> int:
	return attributes.get(name, 0)


func skill(name: String) -> int:
	return skills.get(name, 0)


func composure_band() -> ComposureBand:
	var m := max_composure()
	if composure <= 0:
		return ComposureBand.ZERO
	if composure >= m:
		return ComposureBand.FULL
	if composure * 4 < m:
		return ComposureBand.BELOW_QUARTER
	if composure * 2 < m:
		return ComposureBand.BELOW_HALF
	return ComposureBand.ABOVE_HALF


## Stress penalty for a skill from the Composure table: fine motor skills and complex thinking go first.
func stress_penalty(skill_name: String) -> int:
	var governed_by: String = SKILL_ATTRIBUTE.get(skill_name, "")
	var thinking := governed_by == "intellect" or governed_by == "empathy"
	match composure_band():
		ComposureBand.BELOW_HALF:
			return 10 if thinking else 0
		ComposureBand.BELOW_QUARTER, ComposureBand.ZERO:
			if thinking:
				return 20
			return 10 if skill_name == "firearms" else 0
	return 0


## Chance for a skill check including its attribute and the current stress penalty.
func skill_chance(skill_name: String, modifiers: int = 0) -> int:
	var attr: String = SKILL_ATTRIBUTE.get(skill_name, "")
	return Check.chance_for(attribute(attr), skill(skill_name), modifiers - stress_penalty(skill_name))


func check_skill(skill_name: String, modifiers: int = 0, rng: RandomNumberGenerator = null) -> Check:
	return Check.make(skill_chance(skill_name, modifiers), rng)


func change_composure(delta: int) -> void:
	composure = clampi(composure + delta, 0, max_composure())


func habit_named(habit_name: String) -> Habit:
	for h in habits:
		if h.name == habit_name:
			return h
	return null


## Validates attribute spending at character creation. Returns a list of problems; empty means valid.
## `bonuses` maps attribute -> +1 or +2 from origin and background.
static func validate_creation(spent: Dictionary, bonuses: Dictionary = {}) -> Array[String]:
	var problems: Array[String] = []
	var total := 0
	for a in spent:
		if not a in ATTRIBUTES:
			problems.append("unknown attribute %s" % a)
			continue
		var points: int = spent[a]
		if points < 0:
			problems.append("%s: negative points" % a)
		total += points
		if CREATION_BASE + points > CREATION_CAP:
			problems.append("%s: above %d before bonuses" % [a, CREATION_CAP])
		var bonus: int = bonuses.get(a, 0)
		if bonus < 0 or bonus > 2:
			problems.append("%s: bonus must be +1 or +2" % a)
		if CREATION_BASE + points + bonus > CREATION_CAP_WITH_BONUS:
			problems.append("%s: above %d at creation" % [a, CREATION_CAP_WITH_BONUS])
	if total != CREATION_POINTS:
		problems.append("spent %d of %d points" % [total, CREATION_POINTS])
	return problems


func to_dict() -> Dictionary:
	var hs := []
	for h in habits:
		hs.append(h.to_dict())
	return {
		"display_name": display_name,
		"attributes": attributes.duplicate(),
		"skills": skills.duplicate(),
		"languages": languages.duplicate(),
		"composure": composure,
		"habits": hs,
	}


static func from_dict(d: Dictionary) -> Officer:
	var o := Officer.new()
	o.display_name = d.get("display_name", "Officer")
	for a in d.get("attributes", {}):
		o.attributes[a] = int(d["attributes"][a])
	for s in d.get("skills", {}):
		o.skills[s] = int(d["skills"][s])
	for l in d.get("languages", {}):
		o.languages[l] = int(d["languages"][l])
	for h in d.get("habits", []):
		o.habits.append(Habit.from_dict(h))
	o.composure = clampi(int(d.get("composure", o.max_composure())), 0, o.max_composure())
	return o


## The sample build from section 4: combat veteran, Boyle Heights native.
static func sample_combat_veteran() -> Officer:
	var o := Officer.new()
	o.display_name = "Boyle Heights veteran"
	o.attributes = {"fitness": 7, "nerve": 7, "perception": 6, "intellect": 4, "presence": 6, "empathy": 3}
	o.skills = {
		"firearms": 3, "defensive_tactics": 2, "athletics": 2, "first_aid": 2, "command_presence": 2,
		"streetwise": 2, "de_escalation": 1, "report_writing": 1, "law_and_policy": 1,
	}
	o.languages = {"spanish": 5}
	o.habits.append(Habit.make("engage_the_threat"))
	o.habits.append(Habit.make("dominate"))
	o.habits.append(Habit.make("military_language"))
	o.composure = o.max_composure()
	return o
