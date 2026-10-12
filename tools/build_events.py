"""Builds data/events/events.json from design/17-scripted-events.md.

The design document stays the source of truth: every scripted event is one bullet of the form
**ID · Title.** **Trigger:** ... **What happens:** ... **Branches:** ... **Consequences:** ...
This script parses those bullets into data the game loads, and pulls out the flags each event
reads (named in its trigger) and sets (named in its consequences).
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "design" / "17-scripted-events.md"
OUT = ROOT / "data" / "events" / "events.json"

CATEGORIES = {
    "ST": "Prologue, station and training",
    "MS": "Main story",
    "DC": "Department cast",
    "PL": "Personal life",
    "CW": "Calendar and world",
    "SC": "Signature calls",
    "SW": "Side casework",
}
EXPECTED = {"ST": 17, "MS": 32, "DC": 32, "PL": 26, "CW": 15, "SC": 21, "SW": 12}

EVENT = re.compile(
    r"^- \*\*(?P<id>[A-Z]{2}-\d{2}) · (?P<title>.+?)\*\* "
    r"\*\*Trigger:\*\* (?P<trigger>.+?) "
    r"\*\*What happens:\*\* (?P<what>.+?) "
    r"\*\*Branches:\*\* (?P<branches>.+?) "
    r"\*\*Consequences:\*\* (?P<consequences>.+)$"
)
# A flag is a lower-case identifier with at least one underscore, like calloway_noticed_you.
FLAG = re.compile(r"\b[a-z][a-z0-9]*(?:_[a-z0-9]+)+\b")
EVENT_REF = re.compile(r"\b(?:ST|MS|DC|PL|CW|SC|SW)-\d{2}\b")
CONTENT_WARNING = re.compile(r"\s*\(CW: (?P<cw>[^)]+)\)\s*$")
ACT = re.compile(r"\bAct (\d)(?: (?:or|to) (\d))?")


def timing(trigger: str) -> str:
    t = trigger.lower()
    if "optional" in t or "random" in t:
        return "missable"
    if "fixed" in t or re.search(r"\b(?:january|february|march|april|may|june|july|august|september|october|november|december)\b", t):
        return "fixed"
    return "conditional"


def acts(trigger: str, act_heading: int | None) -> list[int]:
    found = set()
    for a, b in ACT.findall(trigger):
        lo, hi = int(a), int(b or a)
        found.update(range(lo, hi + 1))
    if not found and act_heading:
        found.add(act_heading)
    return sorted(found)


def parse(text: str) -> list[dict]:
    events, act_heading = [], None
    for line in text.splitlines():
        m = re.match(r"^### Act (\d)", line)
        if m:
            act_heading = int(m.group(1))
            continue
        if line.startswith("## "):
            act_heading = None
        if not re.match(r"^- \*\*[A-Z]{2}-\d{2} ", line):
            continue
        m = EVENT.match(line)
        if not m:
            raise ValueError(f"Malformed event line: {line[:80]}")
        d = m.groupdict()
        title = d["title"].rstrip(".")
        cw = None
        c = CONTENT_WARNING.search(title)
        if c:
            cw = c.group("cw")
            title = title[: c.start()].rstrip(".")
        code = d["id"][:2]
        reads = sorted(set(FLAG.findall(d["trigger"])))
        sets = sorted(set(FLAG.findall(d["consequences"])) - set(reads))
        events.append({
            "id": d["id"],
            "category": code,
            "title": title,
            "timing": timing(d["trigger"]),
            "acts": acts(d["trigger"], act_heading),
            "content_warning": cw,
            "trigger": d["trigger"],
            "what_happens": d["what"],
            "branches": d["branches"],
            "consequences": d["consequences"],
            "reads_flags": reads,
            "sets_flags": sets,
            "references": sorted(set(EVENT_REF.findall(" ".join(d.values()))) - {d["id"]}),
        })
    return events


def main() -> int:
    events = parse(SRC.read_text(encoding="utf-8"))
    counts = {k: 0 for k in CATEGORIES}
    for e in events:
        counts[e["category"]] += 1
    ids = [e["id"] for e in events]
    problems = []
    if counts != EXPECTED:
        problems.append(f"category counts {counts} != {EXPECTED}")
    if len(set(ids)) != len(ids):
        problems.append("duplicate event ids")
    known = set(ids)
    for e in events:
        for ref in e["references"]:
            if ref not in known:
                problems.append(f"{e['id']} references unknown event {ref}")
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    OUT.parent.mkdir(parents=True, exist_ok=True)
    doc = {"source": "design/17-scripted-events.md", "categories": CATEGORIES, "count": len(events), "events": events}
    OUT.write_text(json.dumps(doc, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Wrote {len(events)} events to {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
