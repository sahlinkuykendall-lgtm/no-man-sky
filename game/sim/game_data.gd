class_name GameData
extends RefCounted
## Loads static game content from the JSON files in res://game/data/.
## Files are cached after the first read. Pure logic: safe to use on a headless server.

const DATA_DIR := "res://game/data/"

static var _cache: Dictionary = {}


static func load_json(file_name: String) -> Dictionary:
	if _cache.has(file_name):
		return _cache[file_name]
	var path := DATA_DIR + file_name
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("GameData: could not read or parse %s" % path)
		parsed = {}
	_cache[file_name] = parsed
	return parsed


static func races() -> Array:
	return load_json("races.json").get("races", [])


static func star_types() -> Array:
	return load_json("star_types.json").get("star_types", [])


static func planet_types() -> Array:
	return load_json("planet_types.json").get("planet_types", [])


static func economies() -> Array:
	return load_json("world.json").get("economies", [])


static func governments() -> Array:
	return load_json("world.json").get("governments", [])


static func goods() -> Array:
	return load_json("goods.json").get("goods", [])


static func market_events() -> Array:
	return load_json("goods.json").get("events", [])


static func hulls() -> Array:
	return load_json("equipment.json").get("hulls", [])


static func engines() -> Array:
	return load_json("equipment.json").get("engines", [])


static func fuel_tanks() -> Array:
	return load_json("equipment.json").get("fuel_tanks", [])


static func grippers() -> Array:
	return load_json("equipment.json").get("grippers", [])


static func weapons() -> Array:
	return load_json("equipment.json").get("weapons", [])


## NPC settings and loadouts (npcs.json).
static func npcs() -> Dictionary:
	return load_json("npcs.json")


static func name_syllables() -> Dictionary:
	return load_json("names.json")


## Finds the entry with the given "id" in a list of data entries. Returns {} if missing.
static func find_by_id(entries: Array, id: String) -> Dictionary:
	for entry: Dictionary in entries:
		if entry.get("id") == id:
			return entry
	return {}


static func race(id: String) -> Dictionary:
	return find_by_id(races(), id)


static func star_type(id: String) -> Dictionary:
	return find_by_id(star_types(), id)


static func planet_type(id: String) -> Dictionary:
	return find_by_id(planet_types(), id)


static func economy(id: String) -> Dictionary:
	return find_by_id(economies(), id)


static func government(id: String) -> Dictionary:
	return find_by_id(governments(), id)


static func good(id: String) -> Dictionary:
	return find_by_id(goods(), id)


static func market_event(id: String) -> Dictionary:
	return find_by_id(market_events(), id)


## Every list of items in equipment.json, by kind.
static func items_by_kind() -> Dictionary:
	return {"hull": hulls(), "engine": engines(), "fuel_tank": fuel_tanks(), "gripper": grippers(), "weapon": weapons()}


## A hull or piece of equipment from equipment.json, whatever its kind.
static func item_type(id: String) -> Dictionary:
	var lists := items_by_kind()
	for kind: String in lists:
		var entry := find_by_id(lists[kind], id)
		if not entry.is_empty():
			return entry
	return {}


## "hull", "engine", "fuel_tank", "gripper", "weapon", or "" if the id is unknown.
static func item_kind(id: String) -> String:
	var lists := items_by_kind()
	for kind: String in lists:
		if not find_by_id(lists[kind], id).is_empty():
			return kind
	return ""


## Picks a random entry, using each entry's "weight" field (default 1).
static func pick_weighted(rng: RandomNumberGenerator, entries: Array) -> Dictionary:
	var total := 0.0
	for entry: Dictionary in entries:
		total += float(entry.get("weight", 1))
	var roll := rng.randf() * total
	for entry: Dictionary in entries:
		roll -= float(entry.get("weight", 1))
		if roll <= 0.0:
			return entry
	return entries.back() if not entries.is_empty() else {}
