# 6. Encounters: interactions and tactical combat

Rampart plays like Baldur's Gate until something goes wrong, then like XCOM: real-time-with-pause exploration and dialogue, a full police interaction menu for every contact, and turn-based grid tactics (Critical Time) when a situation turns dangerous. Most contacts end in the interaction menu; few ever reach a gunfight, and when one does it lasts three or four turns.

## Three modes

| Mode | Inspired by | Time | Used for |
|---|---|---|---|
| Exploration | Baldur's Gate | Real time with pause; party follows in formation | Patrol on foot or by car, entering scenes, searching rooms, talking to the neighborhood, station and off-duty life |
| Contact | Baldur's Gate dialogue + police procedure | Paused, turn-free; each action costs scene time | Talking, identifying, frisking, searching, detaining, arresting, citing, aiding, collecting evidence |
| Critical Time | XCOM | Turn-based; one turn ≈ 1.5 seconds; 2 AP per officer | Any moment where a weapon, flight, assault or cape debris makes seconds matter |

**Switching modes.** Exploration drops into Contact when you initiate or are approached; Contact escalates into Critical Time when a suspect or the scene crosses a threat threshold (a weapon seen, sudden flight, an attack, a vehicle accelerating, a building starting to fall). Critical Time ends when every threat is controlled, fled, or down, and the scene returns to Contact for arrests, aid and evidence. Pause is always available in Exploration and Contact; Critical Time is already turn-based.

**Two clocks.** Critical Time counts turns. Contact and Exploration spend scene minutes: every action has a time cost that keeps the pending queue growing, delays backup, pushes overtime, and decides whether you make it to your kid's school play.

**The party.** Like Baldur's Gate, you control the player character directly and issue requests to your partner (and later to backup units). Partners act on their own AI between requests, and approval decides whether they follow you (section 7).

A contact only enters Critical Time when it crosses a threat threshold, and always returns to Contact for cuffs, aid and evidence before it can end.

## 6.1 The interaction menu

Right-clicking a person, vehicle, object or door opens a radial menu of police actions, grouped into ten rings; every action costs scene minutes (or AP in Critical Time), may call for a check, and carries a legal basis the game records for later review.

**How the menu reads.** Each option shows its cost, its check chance, and a basis tag (Consensual, Reasonable suspicion, Probable cause, Warrant, Exigent). With Law and Policy 2 or higher, options you lack the basis for are marked in amber with the reason ("no reasonable suspicion of a weapon"). Below that rank, nothing warns you: you find out in court. Nothing is ever greyed out; the game lets you break the law and remembers.

### Approach and presence

| Action | Cost | Check | Notes |
|---|---|---|---|
| Approach | Movement | Perception (spot threats on the way) | Pick distance and angle; too close removes your reaction time |
| Take position | 1 min | none | Assign contact and cover roles with your partner |
| Light up | Instant | none | Flashlight or spotlight: +Perception on the target, reveals your position |
| Announce | Instant | Command Presence | "Police!" Starts the contact; can trigger flight |
| Observe | 1 min | Perception | Read hands, waistband bulges, intoxication, fear, gang signs, injuries |
| Radio in | 1 min | Radio and Dispatch | Code 6 location, request backup, airship, supervisor, RA (ambulance) |
| Wait for backup | Variable | none | Safer; the situation may change while you wait |
| Keep distance | Instant | none | Maintain the gap that lets you react; the menu shows it as a ring |

### Talk

| Action | Cost | Check | Notes |
|---|---|---|---|
| Ask what happened | 2–5 min | Interview | Opens the statement; witnesses remember differently |
| Calm down | 1–3 min | De-escalation | Lowers disposition one step; repeated success can end a crisis |
| Command | Instant | Command Presence | "Show me your hands", "sit on the curb", "step away"; compliance depends on disposition |
| Reassure | 2 min | Empathy | Victims and witnesses; raises trust and statement quality |
| Separate parties | 2 min | none | Domestics and fights; prevents stories being aligned |
| Ask for consent | 1 min | Presence | Consent to search a person, bag, car or home; refusal is legal and recorded |
| Persuade | 2 min | Presence | Talk someone into leaving, surrendering, or going to the hospital |
| Bluff | 1 min | Deception | Lawful trickery ("your friend already talked"); a lie in a report is not |
| Threaten | 1 min | Command Presence | Works sometimes; complaint and misconduct risk |
| Speak their language | Varies | Language rank 3+ | Unlocks witnesses and informants; without it, request an interpreter (+15 min) |
| Good cop, bad cop | 3 min | Partner pairing | Needs a partner willing to play the other role |

### Identify

| Action | Cost | Check | Notes |
|---|---|---|---|
| Ask for ID | 1 min | none | Refusal handling depends on the stop's basis |
| Run name and date of birth | 2 min | Radio and Dispatch | Warrants, probation or parole status, priors, gang file, alerts |
| Run plate | 1 min | none | Stolen, registered owner, wants; can be done before the stop |
| Check Ledger registry | 3 min | Ledger Knowledge | Licensed superhumans, revoked licenses, Accords flags |
| Field interview card | 3 min | Report Writing | Records the contact; feeds intelligence and profiling data |
| Photograph tattoos | 2 min | Streetwise | Gang identification; consent or arrest needed |

### Control and detain

| Action | Cost | Check | Notes |
|---|---|---|---|
| Order to stay | Instant | Command Presence | Converts a consensual contact into a detention; needs reasonable suspicion |
| Position the subject | Instant | Command Presence | Hands on the car, sit, kneel, face away |
| Handcuff for detention | 1 min | Defensive Tactics | Officer safety; must be explained ("you're not under arrest") |
| Seat in the car | 1 min | none | Locks the subject in the back seat |
| Release | Instant | none | "You're free to go"; ends the detention |

### Search

| Action | Cost | Check | Basis |
|---|---|---|---|
| Pat-down (frisk) | 1 min | Search | Reasonable suspicion the person is armed; outer clothing only |
| Consent search | 3–10 min | Search | Consent; can be limited or withdrawn mid-search |
| Search incident to arrest | 3 min | Search | Lawful arrest; person and immediate reach |
| Probation or parole search | 5–15 min | Search | Search conditions on file (California); check status first |
| Vehicle search | 5–20 min | Search | Consent, probable cause, or inventory before impound |
| Plain view | Instant | Perception | Seize what is visible from where you lawfully stand |
| Clear a room or building | 2–10 min | Search + tactics | Exigency or warrant; can drop into Critical Time |
| Request K9 | 20–40 min | none | Drugs, hidden suspects; detention cannot be stretched unreasonably |
| Request warrant | Hours | Report Writing | Through detectives and a judge; the right way, and the slow one |

Searches reveal items by depth: pockets, waistband, ankles and shoes, bag lining; for vehicles, cabin, console, under seats, trunk, hidden compartments. Each depth is a separate Search roll, and a missed weapon stays on the subject.

### Arrest and custody

| Action | Cost | Check | Notes |
|---|---|---|---|
| Announce arrest | Instant | Command Presence | Needs probable cause; may trigger resistance |
| Handcuff | 1–3 steps | Defensive Tactics | Cooperative or resisting sequence (6.2); double-lock or risk injury claims |
| Search incident to arrest | 3 min | Search | See Search |
| Miranda warning | 1 min | Law and Policy | Required before custodial questioning, not at the moment of arrest |
| Question in custody | 5–20 min | Interrogation | Only after a valid waiver; otherwise statements are suppressed |
| Place in car and transport | 15–45 min | Driving | Head guard, seat belt, transport log; injuries in transport become complaints |
| Book at the station | 30–90 min | Report Writing | Property, prints, photos, holding; the arrest report follows |
| Cite and release | 10 min | Report Writing | Misdemeanors; signed promise to appear |
| Warn | 1 min | Presence | No paperwork; trust gain or regret later |
| 5150 hold | 60–180 min | Law and Policy | Danger to self, to others, or gravely disabled; hospital wait |
| Refer | 5 min | none | Shelters, gang intervention, services; rarely sticks |

### Aid and scene

| Action | Cost | Check | Notes |
|---|---|---|---|
| First aid | 1–5 min | First Aid | Pressure, tourniquet, CPR, recovery position; applies to suspects too |
| Request RA | 1 min | Radio | Fire department rescue ambulance; arrival time varies |
| Evacuate | Varies | Command Presence | Clear a building or block; cape incidents |
| Set perimeter | 3 min | none | Tape and positions; keeps media and onlookers out |
| Crowd control | Ongoing | Command Presence | Hostile or curious crowds; flash point for complaints |
| Traffic control | Ongoing | none | Flares, car placement, direct traffic around a scene |
| Comfort | 2 min | Empathy | Victims, families; the call the game never scores |

### Evidence

| Action | Cost | Check | Notes |
|---|---|---|---|
| Make weapon safe | 1 min | Firearms | Unload and secure; mishandling ruins prints |
| Bag and tag | 2 min | Evidence | Chain of custody starts here |
| Photograph | 2 min | Evidence | Scene, injuries, damage |
| Canvass | 10–30 min | Interview | Knock on doors; witnesses and footage |
| Request footage | 5 min | Presence | Store cameras and civilian phones; owners may refuse |
| Call detectives or crime lab | 1 min | none | Homicides and major crimes; the scene becomes theirs |
| Log custody | 2 min | Report Writing | Gaps become defense arguments |

### Vehicle stops

| Action | Cost | Check | Notes |
|---|---|---|---|
| Initiate stop | 1 min | Driving | Lights, siren burst, choose where they pull over |
| Approach driver or passenger side | Movement | Perception | Passenger side is safer from traffic and from the driver's gun hand |
| High-risk stop | 5–10 min | Command Presence | Wanted or armed occupants: commands from cover, occupants out one by one |
| Field sobriety tests | 5 min | Law and Policy | Standardized tests; observations feed the DUI report |
| Preliminary breath test | 2 min | none | Roadside screening device |
| Impound | 20–40 min | Report Writing | Inventory search of the car; tow wait |

### Superhuman contacts

| Action | Cost | Check | Notes |
|---|---|---|---|
| Ask for license | 1 min | Ledger Knowledge | Licensed heroes must carry it |
| Assess powers | 1 min | Power Assessment | Estimates tier; wrong guesses kill |
| Request suppression unit | 1 min | Radio | Federal or Metro; long wait, takes the scene |
| Notify handler agency | 1 min | none | Mandatory for some flags; they arrive faster than they should |
| File Ledger statement | 20 min | Report Writing | Feeds review boards (section 9) |

### Off the books

Always available, never marked, always tracked: search without basis, plant evidence, pocket cash, use force on a compliant subject, threaten a witness, let someone go for a favor, write a false report. Each raises a hidden exposure value that witnesses, footage, partners and your own reports can expose (sections 9 and 10).

## 6.2 Legal standards and procedures

Every contact climbs a ladder of legal basis, and each rung unlocks more of the interaction menu; the game tracks the basis you actually had, not the one you claim, and a judge, the DA or IA compares the two later.

### The ladder of basis (2010 US and California law, simplified)

| Basis | How you get it | What it allows |
|---|---|---|
| Consensual encounter | Anyone, any time | Talk, ask for ID or consent; the person may walk away |
| Reasonable suspicion | Specific facts that a crime is happening or about to (Terry v. Ohio) | Brief detention, questions, pat-down if you also reasonably suspect a weapon |
| Probable cause | Facts a reasonable officer would believe show a crime and this suspect | Arrest; vehicle search under the automobile exception |
| Exigency | Emergency: screams, gunshots, a fleeing felon, evidence about to be destroyed | Warrantless entry and search, limited to the emergency |
| Warrant | A judge signs it | Search or arrest as written, nothing beyond it |

**Gaining basis.** Basis comes from what you observe and learn: Perception reads (a bulge, a hand-to-hand exchange), dispatch information, records checks (a warrant hit is instant probable cause to arrest), statements, admissions, and plain-view items. The game shows the facts you have collected as cards, and you build the justification from them, just as you will in the report.

**Losing basis.** Basis decays: a detention that runs too long without new facts becomes unlawful; a frisk that finds no weapon cannot become a full search; consent ends when it is withdrawn.

### Warrant exceptions the game models

- **Consent:** voluntary, can be limited ("just the trunk"), can be withdrawn.
- **Search incident to arrest:** the person and the area within immediate reach. Vehicle searches incident to arrest follow the 2009 Arizona v. Gant limits: only if the arrestee could reach the car or there is reason to believe evidence of that crime is inside.
- **Automobile exception:** probable cause that the car holds evidence or contraband.
- **Plain view:** lawfully present, incriminating nature immediately apparent.
- **Inventory:** before an impound, following department policy, not as a pretext.
- **Probation and parole searches:** California search conditions allow searches of people on supervision; the records check must show it first.
- **Exigency:** hot pursuit, imminent danger, imminent destruction of evidence.

**The exclusionary rule.** Evidence found through an unlawful stop, search or interrogation can be suppressed in court (section 10). A gun you found illegally may walk out of court with the person who carried it.

### Miranda

Miranda warnings are required before custodial interrogation, not at the moment of arrest. Spontaneous statements are usable; questions in custody without a valid warning and waiver are not. The game lets you skip it and suppresses what follows.

### The arrest sequence

1. Probable cause established (facts on cards).
2. Position the subject with a command (hands behind the back, face away, kneel or against a car).
3. Handcuff:
   - Cooperative: three Defensive Tactics steps (control a wrist, cuff, cuff the second wrist), each with a small resistance roll.
   - Resisting: a control or takedown action first; each failed step can drop the scene into Critical Time.
   - Double-lock and check tightness (1 action). Skipped: injury claims and complaints.
4. Search incident to arrest. Missed items stay hidden until booking, or until they hurt someone in the back seat.
5. Miranda, if you will question in custody.
6. Transport: head guard, seat belt, start and end mileage on the radio for some arrests; medical check if injured.
7. Booking: property inventory, prints and photographs, holding cell; the clock keeps running toward end of watch and overtime.
8. Reports (section 9), then the DA filing decision days later.

### Detentions that turn into something else

- A detention that turns up nothing ends with release, and the person's trust in police moves with how you treated them.
- Probable cause for a misdemeanor often ends in cite and release instead of booking.
- A person in crisis who is a danger to self or others, or gravely disabled, can be placed on a 5150 hold and taken for evaluation.
- Juvenile and federal custody follow separate procedures that the game handles through the watch commander.

### Profiling and the consent decree

Every stop, frisk and search fills in a stop data record (reason, basis, outcome, demographics as the officer perceived them). Supervisors review the data. A pattern of low-basis stops in some neighborhoods surfaces as a sergeant's conversation, then an IA audit, then a complaint pattern used against you in court.

## 6.3 Tactical combat (Critical Time)

Critical Time is XCOM's grammar on a police scale: a square grid, two actions a round, half and full cover, visible hit chances and a hold-aim stance like overwatch, but each round is 1.5 seconds, the goal is control rather than kills, and cover that looks solid often isn't.

### Entering

- **Trigger:** a threat threshold in Contact or Exploration (weapon seen, flight, assault, vehicle used as a weapon, structural collapse, gunfire nearby).
- **Surprise:** whoever did not see it coming loses their first round. Combat veterans never do (section 7).
- **No setup phase.** Everyone starts exactly where they stood. Where you parked, where you stood during the talk and who held the cover role decide the fight before it starts.

### The grid and the round

- **Grid:** one square per ground tile (about 1.5 m), shown only in Critical Time.
- **Round:** 1.5 seconds. Everyone acts in Reaction order (Perception + Nerve, with surprise and stress modifiers), one actor at a time, like Baldur's Gate 3, rather than XCOM's whole-side turns. A suspect quicker than you acts before you.
- **Action points:** 2 per round, plus one free short command.
- **Movement:** 1 AP walks up to 3 squares, 2 AP sprints up to 6 (Fitness and wounds modify). Vaulting a low wall, climbing a fence, opening or kicking a door, and getting out of a car all have costs.

### Cover and concealment

| Type | Examples | Defense | Stops handgun rounds? |
|---|---|---|---|
| Full cover | Engine block, wheel and axle, concrete or brick wall, utility pole, cinder block planter | −40 to hit | Yes |
| Half cover | Car hood and trunk, low concrete wall, curb when prone, mailbox | −20 to hit | Mostly |
| Concealment | Drywall, interior doors, car doors and body panels, wooden fences, hedges, dumpster lids, darkness | −10 to hit (harder to see) | No |
| None | Open sidewalk, middle of the street | 0 | n/a |

The UI shows a solid shield for cover and an open eye for concealment. A player who learns the difference survives; one who trusts a car door does not. Flanking a target removes its cover bonus and raises crit chance.

### Actions

| Action | AP | Notes |
|---|---|---|
| Move / sprint | 1 / 2 | Squares as above; moving shooters take −20 |
| Take cover / go prone | 1 | Prone: harder to hit at range, slow to get up |
| Draw | 1 | Free if already drawn; drawing is reviewed afterward |
| Aim | 1 | +20 to the next shot |
| Fire (single) / controlled pair | 1 / 2 | Second shot of a pair −10; veterans pair for 1 AP |
| Hold aim (cover stance) | 2 | Overwatch for police: set triggers (below) |
| Command (longer) | 1 | First short command each round is free |
| Less-lethal | 1 | Taser, beanbag, OC, baton (6.4) |
| Hands-on | 1–2 | Grab, takedown, control, strike, cuff step, weapon retention |
| Reload / clear malfunction | 1–2 | Fumbles under stress cost more |
| Radio | 1 | Backup, "officer needs help", airship, RA |
| Scan | 1 | Reveals squares hidden by tunnel vision |
| First aid | 2 | Tourniquet stops bleeding; pressure slows it |
| Request partner action | Free | Flank, cover, hold, talk, cuff; approval decides |
| Use the car | 1–2 | Get in, reverse out, ram (always reviewed) |

### Hold aim (overwatch)

Hold aim spends both AP and sets a trigger: fire if a weapon is raised, if the subject moves toward a person, if they reach toward the waistband, or Taser if they run. Reaction shots take −10 unless you aimed last round. Triggers can misfire on a misread: a phone raised fast looks like a gun, and Composure decides how often (section 5).

### Hit chance

```
Hit = (Perception × 5) + (Firearms × 10) + aim + range − cover − stress − movement − light
```

The targeting line shows the hit chance and the path past the target, highlighting anyone and anything behind it: a wall it will go through, a window, a child. Misses travel and penetrate according to the cover table. Every round fired becomes a memory card and a line in the use-of-force review.

### Wounds, not hit points

Hits inflict wound levels (Bruised, Hurt, Wounded, Critical, Dying) with lasting penalties. A Dying character bleeds out in three rounds unless stabilized, like XCOM's bleed-out, then needs the RA. Vests turn many handgun hits into Bruised and a lost round. Suspects on Spark or boosters keep acting through wounds that would stop anyone else.

### Vision, light and sound

- **Fog of war:** you see what your character sees; partners share what they report on the radio, with a delay.
- **Tunnel vision:** low Composure narrows the visible cone; Scan widens it for a round.
- **Light:** night scenes need flashlights and spotlights; lit units are easier to see and easier to shoot.
- **Sound:** gunfire alerts the block; civilians panic, film, flee or step outside at the worst time.

### Control of your partner

By default you control your own officer and give your partner requests, as in Baldur's Gate with an independent companion. A difficulty option allows full XCOM-style control of every officer on scene.

### Ending

Critical Time ends when every threat is controlled, fled or down, and the scene returns to Contact: cuffs, aid, perimeter, evidence and the long aftermath (6.5).

## 6.4 Weapons, gear and less-lethal options

A rookie carries 2010 LAPD patrol gear and nothing better; every tool has a range, a failure mode and a review cost, and the less-lethal options are the ones that most often decide whether a contact ends in an arrest or a funeral.

### Duty gear

| Item | Source | Range | Effect | Failure mode | Review weight |
|---|---|---|---|---|---|
| Glock 22 (.40), 15+1, two spare magazines | Issued | Close to medium | Lethal; wound levels per hit | Malfunction chance, higher with poor maintenance | Highest |
| Remington 870 shotgun | Kit room | Close to long (slugs) | Lethal; buckshot spreads | Condition depends on the kit room officer | High |
| Beanbag shotgun | Kit room | 2–20 squares | Pain and knockdown; Hurt or Wounded | Can kill at very close range or with a head hit; loading the wrong shotgun is a disaster | Medium |
| Taser X26, one cartridge | Kit room | 1–5 squares | Incapacitates for one round on a two-probe hit | Thick clothing, one probe, boosted suspects; then drive-stun only | Medium |
| OC spray | Belt | 1–2 squares | Blinds and chokes; penalties for several rounds | Contaminates partners and small rooms | Low to medium |
| Baton | Belt | Contact | Strikes, control holds | Head strikes are out of policy | Medium |
| Handcuffs, two pairs | Belt | Contact | Restraint; needs steps (6.2) | Single-locked cuffs tighten and injure | Low |
| Flashlight | Belt | Line of sight | Lights a cone; blinds briefly | Shows your position | None |
| Radio | Belt and shoulder mic | Division | Backup, RA, airship, supervisor | Dead battery from a bad kit room checkout | None |
| Body armor | Issued vest | n/a | Stops most handgun rounds | Not rifles; you still feel it | n/a |
| First aid kit, tourniquet | Car | Contact | Stops bleeding | Time cost | None |
| Patrol rifle | Not issued to probationers | n/a | Your training officer may carry one | n/a | n/a |

### The patrol car

The car is equipment too: full cover at the engine block, half cover at the hood, concealment at the doors; a spotlight; a locked back seat; the in-car computer for records checks; flares and tape in the trunk. Using it as a weapon (pinning, ramming) is always reviewed.

### Choosing force

The menu orders options from least to most force, and the use-of-force review compares the option you chose with the threat at that moment:

1. Presence and positioning
2. Commands
3. Hands-on control (holds, takedowns)
4. OC spray, Taser, beanbag
5. Baton strikes
6. Firearm

Nothing forces you up the ladder one step at a time, and nothing forbids jumping straight to the top when the threat calls for it. The review asks whether the choice was reasonable given what you knew, which the game knows, and given what you write, which it compares.

## 6.5 Suspects, civilians, objectives and the aftermath

Unlike XCOM's enemies, the people in a Rampart encounter are not waiting to be killed: suspects panic, surrender, run and lie; civilians film and get in the way; and every encounter has goals that a body count cannot satisfy.

### Suspect AI

Each suspect has a disposition that can change every round and a state that shapes how it changes.

| Disposition | Behavior |
|---|---|
| Compliant | Follows commands |
| Passive resistance | Goes limp, refuses, argues |
| Active resistance | Pulls away, runs, braces against cuffs |
| Assaultive | Strikes, grabs, tackles |
| Deadly | Weapon use, vehicle as a weapon |

| State | Effect |
|---|---|
| Panicked | Erratic; responds to calm talk, explodes at shouting |
| Intoxicated or high | Slow to comply, ignores pain; Spark and boosters add strength |
| Mental health crisis | Commands fail; De-escalation and time succeed |
| Gang-loyal | Watches the crowd; will not look weak in front of it |
| Afraid of deportation or prison | Runs early; surrenders if given a way out |
| Combat-trained | Uses cover, flanks, fires controlled pairs |
| Superhuman | Tier and power decide everything (below) |

Every suspect also has **resolve**. Wounds, being flanked, a partner going down, a calm voice or a clear way out lower it; when it breaks, they surrender or flee. Offering surrender ("put it down and this ends now") is a free command every round.

### Civilians

Bystanders have their own routines: freeze, flee, film, intervene, hide behind your car. Civilians in the line of fire raise the stress of every shot. A crowd that turns hostile adds a tension clock to the scene, and an intervening relative can become a second subject.

### Encounter objectives

Every Critical Time encounter shows its objectives at the top of the screen, like an XCOM mission, and none of them is "kill all".

| Objective | Examples |
|---|---|
| Primary | Take the suspect into custody; end the threat; rescue the hostage; survive until backup |
| Secondary | No civilian injuries; no rounds fired; preserve the evidence; keep your partner unhurt |
| Hidden | Discovered later: the footage someone took, the witness who saw it differently |

Objectives grade the encounter for your FTO evaluation and squad reputation; the use-of-force review grades it separately and later.

### Backup and escalation

- Backup arrives after a number of rounds set by distance and division workload; the radio shows an estimate.
- "Officer needs help" brings everyone, fast and chaotic: arriving units can escalate, crossfire risk rises, and a supervisor takes command.
- The airship lights the scene and tracks runners at night.
- Pursuits on foot or by car (section 14) can start from any round in which a suspect breaks contact.

### Cape incidents in Critical Time

- **Tier 3 and above:** survival scenarios. Objectives are evacuate, triage, set a perimeter, stay alive. The map changes every round as debris falls; shooting at the superhuman draws its attention.
- **Tier 1–2:** conventional tools sometimes work: a Street-level brute may shrug off a Taser and fall to a shotgun slug.
- **Federal takeover:** handler agency teams with suppression gear arrive, end the encounter on their terms, and take the scene.

### After the shooting stops

1. **Secure:** cuffs, weapons made safe, wounded treated (suspects included), RA requested.
2. **Scene:** perimeter, witnesses separated, footage requested.
3. **Officer-involved shooting procedure:** you are separated from your partner, your weapon is taken as evidence, the department psychologist sees you, and a long investigation begins while you work a desk.
4. Memory cards form from the encounter, some of them wrong (section 9).
5. **Use-of-force review:** the threat as it was and as you perceived it, proportionality, warnings and de-escalation attempts, the tactics that led there, and your report and testimony. Outcomes: in policy; in policy with a tactical debrief; administrative disapproval; out of policy. A shooting can be legal and still out of policy, or in policy and still the wrong call.

### Example: a stop on Alvarado, PM watch

1. **Exploration.** Your FTO points at a car rolling a stop sign. You run the plate (registered owner on parole) and initiate the stop.
2. **Contact.** You approach the passenger side. Observe shows a nervous driver and a passenger with his hand under his thigh. Run name confirms parole with search conditions. You order both out; the passenger hesitates.
3. **Escalation.** The passenger's hand comes up fast. Critical Time. The driver is surprised and loses his round; the passenger acts first.
4. **Critical Time, round 1.** He has a phone, and your hold-aim trigger was "weapon raised". A Composure check at 60% decides whether you see the phone. You pass and use the free command: "Drop it, on the ground!" Your FTO covers from the engine block.
5. **Round 2.** His resolve breaks; he drops to the curb. Back to Contact.
6. **Contact.** Parole search of the car: under the seat, a pistol. Probable cause to arrest the passenger; cuff (cooperative sequence), search incident to arrest, Miranda before you ask about the gun.
7. **Aftermath.** Transport, booking, a report that must explain why your weapon was drawn and why the parole search was lawful. Two hours of overtime, and your partner at home asks why you are late again.
