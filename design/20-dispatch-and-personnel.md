# 20. Dispatch, on-scene choices and personnel

The day-to-day layer borrows its structure from *This Is the Police 2*: a shift of incoming calls, a small crew to spread across them, short text scenes on arrival, and officers who are tired, late, hungover or asking for the day off. The study of that game covered its structure and tuning only. Rampart's code, data, numbers and writing are its own.

## What was learned from the reference

| Reference system | Its structure | Rampart's version |
|---|---|---|
| Crime schedule | Mostly hand-placed crimes per day, plus a weekly pool drawn to a daily quota of real versus false calls. About a quarter are false alarms | Procedural calls weighted by type, district and watch (section 8), plus weekday, payday and month multipliers. A false-alarm rate per call type, averaging about 20% |
| Difficulty ramp | The strength each crime needs climbs steadily across the campaign | The worse truths behind a call (armed, assaultive, deadly) grow more likely each probation month |
| Warning and critical timers | A call shows warning, then critical, before it is lost | The pending queue (section 8): escalation and expiry per call type. On the map, a call's ring fills and its blink speeds up as time runs out |
| Text quests | Up to three options per node. Each option can be gated by one stat or an item. Success chance comes from stat level, a near-certain table from 0 to 3. Outcomes lead to another node or a result code, with injury severity. Chains are usually 2 or 3 nodes, at most 7 | The same shape, with Rampart's visible percentile checks (section 4) instead of a fixed table: the best officer on scene for the skill makes the roll. Results come from design 8's resolution table, plus "tactical", which hands the scene to the battlescape |
| Officer card | Six stats rated 0 to 3, energy 0 to 6, laziness, an alcoholism flag, happiness against a threshold | Rampart's attributes and skills (section 4), plus energy 0 to 6, laziness 0 to 2, drinker, happiness against a threshold |
| Accidents | Higher chance when exhausted, tired or drunk | A collision chance on Code 3 runs with an exhausted (10%), tired (3%) or hungover (6%) crew |
| Alcoholism triggers | Low energy and traumatic outcomes | Trauma (deaths on scene, serious wounds) can turn an officer into a drinker, and drinkers come in hungover when unhappy or worn out |
| Day-off reasons | A list with severities | Ten original reasons, serious or not. Refusing a serious request costs more |
| Story scenes on set days | Scripted scenes keyed to campaign days | `data/strategic/story_schedule.json`: fixed beats from section 17 placed on campaign days, gated by FTO and flags |

## Calls

- **Volume:** a base rate times the weekday multiplier (Friday and Saturday busiest), times paydays (the 1st and 15th), times 3% more per probation month.
- **False alarms:** each call type has its own rate (`false_alarm` in `call_types.json`). False alarms resolve quickly on scene.
- **Misleading dispatch:** half of false alarms come in flagged "possible prank", and so do about one in eight real calls.
- **Reading the scene on approach:** a Streetwise roll by the crew can show that a call is quiet (probably nothing), that it isn't what dispatch said, or that people are running away from it.

## On-scene choices

- **Files:** one scene file per call type, `data/scenes/calls/<type>.json`, with a variant for each hidden truth and one for the false alarm.
- **Options:** each can name a skill, a modifier and a required item.
- **Odds:** the option shows the best officer's chance before you pick.
- **Results:** arrest, cite, warn, report, 5150 hold, cleared, escaped, false alarm or tactical. Each has a score, reputation effects and a time cost.
- **Injuries:** an injury of 1 to 3 puts the officer who acted on 1, 3 or 10 days of light duty.
- **Escalation:** "tactical" sends the call to the battlescape with the same hidden truth.

## Personnel

- **Energy:** each watch worked costs 1 energy, and a long call costs another. A day off restores 3.
- **Low energy:** at energy 3 or less, officers lose 3 time units on the battlescape for each point below 4. Below 2, they start with less Composure.
- **Roll call, at the start of each watch:**
  - Unhappy or exhausted drinkers may arrive hungover: fewer time units and slower reactions, and worse odds in scenes.
  - Lazy officers may be late, keeping the car out of service for half an hour.
  - Someone may ask for the next day off.
- **Happiness:** rises with good outcomes and falls with injuries and refused requests. Below their threshold, officers drink and are late more often.

## Story beats on the calendar

The fixed beats of section 17 (first day, first shift, first body, the 6th Street fight and so on) surface as story cards on their scheduled day. The card's choices come straight from the event's Branches text. `story_schedule.json` maps chosen branches to the flags later events read, for example asking Peg about Temple Street sets `asked_temple_st`, which later opens MS-17. Beats tied to one training officer only appear with that officer. The day for each beat is read off its trigger and is a placeholder until the calendar is designed.
