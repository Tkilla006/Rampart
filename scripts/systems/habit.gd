class_name Habit
extends RefCounted
## A trained reflex that fires under stress unless the player fights it (design section 5).

enum Mode {
	INSTINCT,        ## Shown as a highlighted option; every choice is free.
	OVERRIDE_OTHERS, ## The instinct is free; any other option needs an Override check.
	FIRES,           ## Fires automatically unless an Override check passes at a penalty.
}

const MIN_STRENGTH := 1
const MAX_STRENGTH := 3
## Extra penalty on the Override check when the Habit would fire automatically.
const FIRES_OVERRIDE_PENALTY := 10

## Habit catalog from the section 5 table: trigger, default action, backgrounds.
const CATALOG := {
	"engage_the_threat": {"title": "Engage the Threat", "trigger": "weapon_seen", "action": "Draw and fire a controlled pair", "skill": "firearms"},
	"dominate": {"title": "Dominate", "trigger": "non_compliance", "action": "Escalate to hands-on or force", "skill": "command_presence"},
	"cover_first": {"title": "Cover First", "trigger": "gunfire_or_ambush", "action": "Move to hard cover", "skill": "super_incident_response"},
	"run_to_the_wounded": {"title": "Run to the Wounded", "trigger": "casualty_visible", "action": "Move to them, even across open ground", "skill": "first_aid"},
	"book_answer": {"title": "Book Answer", "trigger": "situation_not_in_training", "action": "Hesitate a turn, look for procedure", "skill": "law_and_policy"},
	"control_the_cell": {"title": "Control the Cell", "trigger": "suspect_in_custody", "action": "Restraint over medical care", "skill": "first_aid"},
	"hands_on": {"title": "Hands On", "trigger": "contact_range", "action": "Close distance too fast", "skill": "de_escalation"},
	"find_the_camera": {"title": "Find the Camera", "trigger": "cape_incident", "action": "Assess the media angle before the threat", "skill": "super_incident_response"},
	"military_language": {"title": "Military Language", "trigger": "writing_report", "action": "Combat wording offered by default", "skill": "report_writing"},
}

var name: String
var strength := MIN_STRENGTH


static func make(habit_name: String, habit_strength: int = MIN_STRENGTH) -> Habit:
	assert(CATALOG.has(habit_name), "Unknown habit %s" % habit_name)
	var h := Habit.new()
	h.name = habit_name
	h.strength = clampi(habit_strength, MIN_STRENGTH, MAX_STRENGTH)
	return h


func title() -> String:
	return CATALOG[name]["title"]


func trigger() -> String:
	return CATALOG[name]["trigger"]


func default_action() -> String:
	return CATALOG[name]["action"]


func override_skill() -> String:
	return CATALOG[name]["skill"]


## How the Habit behaves at a Composure band; surprise always makes it fire on the first action.
static func mode_for(band: Officer.ComposureBand, surprised: bool = false) -> Mode:
	if surprised:
		return Mode.FIRES
	match band:
		Officer.ComposureBand.FULL, Officer.ComposureBand.ABOVE_HALF:
			return Mode.INSTINCT
		Officer.ComposureBand.BELOW_HALF:
			return Mode.OVERRIDE_OTHERS
	return Mode.FIRES


func override_chance(officer: Officer, surprised: bool = false) -> int:
	var skill_name := override_skill()
	var penalty := officer.stress_penalty(skill_name)
	if mode_for(officer.composure_band(), surprised) == Mode.FIRES:
		penalty += FIRES_OVERRIDE_PENALTY
	return Check.override_chance(officer.attribute("nerve"), officer.skill(skill_name), strength, penalty)


## Acting on a Habit strengthens it; overriding it or retraining with the FTO weakens it.
func reinforce() -> void:
	strength = mini(strength + 1, MAX_STRENGTH)


func weaken() -> void:
	strength = maxi(strength - 1, MIN_STRENGTH)


func to_dict() -> Dictionary:
	return {"name": name, "strength": strength}


static func from_dict(d: Dictionary) -> Habit:
	return make(d["name"], int(d.get("strength", MIN_STRENGTH)))
