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
