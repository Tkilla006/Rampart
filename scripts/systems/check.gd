class_name Check
extends RefCounted
## Percentile checks (design section 4).
##
## chance = (Attribute x 5) + (Skill x 10) + modifiers, rolled on d100 equal or under.
## A roll at or under 10% of the chance is a clean success; 95 to 100 always fails.

const AUTO_FAIL_FROM := 95

var chance: int
var roll: int
var success: bool
var clean: bool


static func chance_for(attribute: int, skill: int, modifiers: int = 0) -> int:
	return attribute * 5 + skill * 10 + modifiers


## Override check for a Habit (design section 5):
## (Nerve x 5) + (relevant skill x 10) - (Habit strength x 10) - stress penalties.
static func override_chance(nerve: int, skill: int, habit_strength: int, stress_penalty: int = 0) -> int:
	return nerve * 5 + skill * 10 - habit_strength * 10 - stress_penalty


## Firearms hit chance (design section 6.3):
## (Perception x 5) + (Firearms x 10) + aim + range - cover - stress - movement - light.
## Range is a signed modifier for the range band; the other penalties are passed as positive numbers.
static func hit_chance(perception: int, firearms: int, aim: int = 0, range_mod: int = 0, cover: int = 0,
		stress: int = 0, movement: int = 0, light: int = 0) -> int:
	return perception * 5 + firearms * 10 + aim + range_mod - cover - stress - movement - light


## Resolves a check against a given d100 roll (1-100). Kept separate from randomness so it can be tested.
static func resolve(chance_value: int, d100: int) -> Check:
	var c := Check.new()
	c.chance = chance_value
	c.roll = d100
	c.success = d100 < AUTO_FAIL_FROM and d100 <= chance_value
	c.clean = c.success and d100 <= int(floor(chance_value * 0.1))
	return c


static func roll_d100(rng: RandomNumberGenerator = null) -> int:
	if rng == null:
		return randi_range(1, 100)
	return rng.randi_range(1, 100)


static func make(chance_value: int, rng: RandomNumberGenerator = null) -> Check:
	return resolve(chance_value, roll_d100(rng))


## The visible odds shown on every check: the chance clamped to what can actually happen.
static func display_odds(chance_value: int) -> int:
	return clampi(chance_value, 0, AUTO_FAIL_FROM - 1)


func describe() -> String:
	if clean:
		return "Clean success (%d vs %d%%)" % [roll, chance]
	if success:
		return "Success (%d vs %d%%)" % [roll, chance]
	return "Failure (%d vs %d%%)" % [roll, chance]
