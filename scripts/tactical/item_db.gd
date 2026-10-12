class_name ItemDB
extends RefCounted
## Equipment definitions from data/tactical/items.json (design 6.4).

const PATH := "res://data/tactical/items.json"

static var _items := {}
static var _loadouts := {}


static func _ensure() -> void:
	if not _items.is_empty():
		return
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	assert(typeof(doc) == TYPE_DICTIONARY, "Could not parse %s" % PATH)
	_items = doc["items"]
	_loadouts = doc["officer_loadouts"]


static func has(id: String) -> bool:
	_ensure()
	return _items.has(id)


static func get_item(id: String) -> Dictionary:
	_ensure()
	assert(_items.has(id), "Unknown item %s" % id)
	return _items[id]


static func all_ids() -> Array:
	_ensure()
	return _items.keys()


static func loadout(id: String) -> Dictionary:
	_ensure()
	return _loadouts.get(id, _loadouts["patrol"])


static func loadout_ids() -> Array:
	_ensure()
	return _loadouts.keys()


static func is_weapon(id: String) -> bool:
	if id == "" or not has(id):
		return false
	return get_item(id).has("modes")


static func is_lethal(id: String) -> bool:
	return is_weapon(id) and int(get_item(id).get("force", 0)) >= 6


## A dangerous object a suspect could use: guns, knives, bats.
static func is_threat(id: String) -> bool:
	if id == "" or not has(id):
		return false
	var k: String = get_item(id)["kind"]
	return k == "firearm" or k == "melee"


static func range_modifier(id: String, distance: float) -> int:
	var item := get_item(id)
	for band in item.get("ranges", []):
		if distance <= float(band[0]):
			return int(band[1])
	return -100


static func max_range(id: String) -> float:
	var item := get_item(id)
	if item.has("max_range"):
		return float(item["max_range"])
	if item["kind"] == "melee":
		return 1.5
	return 30.0
