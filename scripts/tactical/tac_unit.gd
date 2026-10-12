class_name TacUnit
extends RefCounted
## Anyone on the battlescape: officers, suspects, civilians. X-COM style time units, health, stun,
## morale and fatal (bleeding) wounds, with Rampart's dispositions and states (design 6.5).

enum Side { OFFICER, SUSPECT, CIVILIAN }
enum Status { ACTIVE, SURRENDERED, INCAPACITATED, UNCONSCIOUS, DYING, DEAD, CUFFED, FLED }
enum Disposition { COMPLIANT, PASSIVE, ACTIVE, ASSAULTIVE, DEADLY }
enum Stance { STANDING, KNEELING }
enum Reserve { NONE, SNAP, AIMED }

const DIRS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
]
const DISPOSITION_NAMES := ["compliant", "passive resistance", "active resistance", "assaultive", "deadly"]
const STATUS_NAMES := ["active", "surrendered", "incapacitated", "unconscious", "dying", "dead", "in custody", "fled"]
const KNEEL_TU := 4
const STAND_TU := 8
const TURN_TU := 1
const BLEED_OUT_TURNS := 3

var id := 0
var key := ""
var name := ""
var side := Side.OFFICER
var look := "officer"
var rank := ""
var pos := Vector2i.ZERO
var facing := 4
var stance := Stance.STANDING
var reserve := Reserve.NONE

var tu_max := 60
var health_max := 30
var reactions := 50
var accuracy := 50
var bravery := 50
var strength := 30

var tu := 60
var health := 30
var stun := 0
var morale := 100
var fatal_wounds := 0
var dying_turns := 0
var status := Status.ACTIVE

var disposition := Disposition.COMPLIANT
var state := ""
var boosted := false
var looter := false
var blinded_turns := 0
var incapacitated_turns := 0
var knocked_down := false
var free_command_used := false
var spotted := false

var right_hand := ""
var belt: Array[String] = []
var armor := ""
var hidden_item := ""
var ammo := {}
var uses := {}
var ground_items: Array[String] = []

## Officers only: the Rampart character sheet behind this unit.
var officer: Officer = null
var traits: Array = []
var background := {}

## Per-mission record, used for the debrief and X-COM style stat gains.
var record := {"shots": 0, "hits": 0, "reaction_shots": 0, "arrests": 0, "aid": 0, "commands": 0, "force": 0,
	"damage_taken": 0, "panicked": 0}


# ---------------------------------------------------------------- construction

static func from_officer(o: Officer, unit_key: String, unit_name: String, extra := {}) -> TacUnit:
	var u := TacUnit.new()
	u.key = unit_key
	u.name = unit_name
	u.side = Side.OFFICER
	u.officer = o
	u.look = extra.get("look", "officer")
	u.rank = extra.get("rank", "Police Officer I")
	u.traits = extra.get("traits", [])
	u.background = extra.get("background", {})
	var f := o.attribute("fitness")
	var n := o.attribute("nerve")
	u.tu_max = 40 + f * 3 + n * 2
	if "gym_rat" in u.traits:
		u.tu_max += 6
	if "bad_knee" in u.traits:
		u.tu_max -= 6
	if extra.get("hungover", false):
		u.tu_max -= 4
		u.reactions -= 10
	# Fatigue (design 5): a tired officer is slower and starts shakier.
	var energy: int = int(extra.get("energy", 6))
	if energy < 4:
		u.tu_max -= (4 - energy) * 3
	u.health_max = 20 + f * 3
	u.reactions = (o.attribute("perception") + n) * 5
	u.accuracy = o.attribute("perception") * 5 + o.skill("firearms") * 10
	u.bravery = n * 10
	u.strength = 10 + f * 5
	u.boosted = extra.get("boosted", false)
	u.tu = u.tu_max
	u.health = u.health_max
	u.morale = int(round(100.0 * o.composure / maxf(1.0, o.max_composure())))
	if energy < 2:
		u.morale = maxi(10, u.morale - 15)
	u.apply_loadout(extra.get("loadout", "patrol"))
	return u


static func make_npc(npc_side: int, npc_name: String, npc_look: String, rng: RandomNumberGenerator) -> TacUnit:
	var u := TacUnit.new()
	u.side = npc_side
	u.name = npc_name
	u.look = npc_look
	u.tu_max = rng.randi_range(50, 66)
	u.health_max = rng.randi_range(26, 38)
	u.reactions = rng.randi_range(30, 60)
	u.accuracy = rng.randi_range(30, 55)
	u.bravery = rng.randi_range(20, 60)
	u.strength = rng.randi_range(25, 45)
	u.tu = u.tu_max
	u.health = u.health_max
	u.morale = rng.randi_range(55, 85) if npc_side == Side.SUSPECT else rng.randi_range(40, 70)
	return u


func apply_loadout(loadout_id: String) -> void:
	var l := ItemDB.loadout(loadout_id)
	right_hand = l.get("right_hand", "")
	belt.clear()
	for b in l.get("belt", []):
		belt.append(b)
	armor = l.get("armor", "")
	for item in [right_hand] + Array(belt):
		_stock(item)


func _stock(item: String) -> void:
	if item == "" or not ItemDB.has(item):
		return
	var d := ItemDB.get_item(item)
	if d.has("capacity"):
		ammo[item] = int(d.capacity)
		uses["%s_spare" % item] = int(d.get("spare_mags", 0))
	if d.has("uses"):
		uses[item] = int(d.uses)


func give_weapon(item: String, in_hand: bool = true) -> void:
	if item == "":
		return
	if in_hand:
		right_hand = item
	else:
		hidden_item = item
	_stock(item)


# ---------------------------------------------------------------- state

func is_officer() -> bool:
	return side == Side.OFFICER


func is_active() -> bool:
	return status == Status.ACTIVE


## On the map and able to act this turn.
func can_act() -> bool:
	return status == Status.ACTIVE and incapacitated_turns <= 0


func is_down() -> bool:
	return status in [Status.UNCONSCIOUS, Status.DYING, Status.DEAD, Status.INCAPACITATED]


func is_gone() -> bool:
	return status == Status.FLED


## Still a problem for the officers: not in custody, down, gone or surrendered.
func is_threat() -> bool:
	return side == Side.SUSPECT and status == Status.ACTIVE


## Holds or has drawn a dangerous weapon (guns, knives, bats). Hidden items do not count.
func is_armed() -> bool:
	return ItemDB.is_threat(right_hand)


## Holds something that can look like a gun at a glance (design 6.3: a phone raised fast).
func holds_lookalike() -> bool:
	if right_hand == "" or not ItemDB.has(right_hand):
		return false
	return bool(ItemDB.get_item(right_hand).get("looks_like_weapon", false))


func weapon() -> String:
	return right_hand if ItemDB.is_weapon(right_hand) else ""


func has_item(item: String) -> bool:
	return right_hand == item or item in belt


func armor_value(damage_type: String) -> int:
	if armor == "" or not ItemDB.has(armor):
		return 0
	return int(ItemDB.get_item(armor).get("armor", {}).get(damage_type, 0))


## Wound levels from design section 4, from remaining health.
func wound_label() -> String:
	if status == Status.DEAD:
		return "Dead"
	if status == Status.DYING:
		return "Dying"
	var f := float(health) / float(maxi(health_max, 1))
	if f >= 0.95:
		return "Unhurt"
	if f >= 0.8:
		return "Bruised"
	if f >= 0.6:
		return "Hurt"
	if f >= 0.35:
		return "Wounded"
	return "Critical"


func status_name() -> String:
	return STATUS_NAMES[status]


func disposition_name() -> String:
	return DISPOSITION_NAMES[disposition]


# ---------------------------------------------------------------- facing and stance

static func dir_index(v: Vector2i) -> int:
	var best := 0
	var best_dot := -INF
	var vn := Vector2(v).normalized()
	for i in DIRS.size():
		var dd := Vector2(DIRS[i]).normalized().dot(vn)
		if dd > best_dot:
			best_dot = dd
			best = i
	return best


static func turn_steps(from_dir: int, to_dir: int) -> int:
	var d := absi(from_dir - to_dir) % 8
	return mini(d, 8 - d)


func turn_cost(to_cell: Vector2i) -> int:
	if to_cell == pos:
		return 0
	return turn_steps(facing, dir_index(to_cell - pos)) * TURN_TU


func face(to_cell: Vector2i) -> void:
	if to_cell != pos:
		facing = dir_index(to_cell - pos)


func stance_cost() -> int:
	return STAND_TU if stance == Stance.KNEELING else KNEEL_TU


## TU kept back for reaction fire (X-COM's reserve time units).
func reserved_tu() -> int:
	var w := weapon()
	if w == "" or reserve == Reserve.NONE:
		return 0
	var modes: Dictionary = ItemDB.get_item(w)["modes"]
	var mode := "aimed" if reserve == Reserve.AIMED and modes.has("aimed") else "snap"
	if not modes.has(mode):
		mode = modes.keys()[0]
	return action_tu(int(modes[mode]["tu"]))


## Converts a percentage-of-maximum TU cost (X-COM weapons) into time units.
func action_tu(percent: int) -> int:
	return int(ceil(tu_max * percent / 100.0))


func spend(amount: int) -> bool:
	if amount > tu:
		return false
	tu -= amount
	return true


func start_turn() -> void:
	tu = tu_max
	free_command_used = false
	if knocked_down:
		tu = tu_max / 2
		knocked_down = false
	if blinded_turns > 0:
		tu = int(tu * 0.6)


func morale_label() -> String:
	if morale >= 70:
		return "Steady"
	if morale >= 50:
		return "Shaken"
	if morale >= 25:
		return "Rattled"
	return "Breaking"
