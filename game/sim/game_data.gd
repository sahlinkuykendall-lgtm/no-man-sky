class_name GameData
extends RefCounted
## Loads static game content from the JSON files in res://game/data/.
## Files are cached after the first read. Pure logic: safe to use on a headless server.

const DATA_DIR := "res://game/data/"

static var _cache: Dictionary = {}
static var _indexes: Dictionary = {} ## list name -> {id: entry}, for fast lookups by id.
static var _item_kinds: Dictionary = {} ## item id -> kind ("hull", "engine", ...).


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


static func shields() -> Array:
	return load_json("equipment.json").get("shields", [])


static func radars() -> Array:
	return load_json("equipment.json").get("radars", [])


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


## Like find_by_id for the list `key` in a data file, but remembers an index of the list
## (these lookups happen very often).
static func _indexed(file_name: String, key: String, id: String) -> Dictionary:
	var index: Dictionary = _indexes.get(key, {})
	if index.is_empty():
		for entry: Dictionary in load_json(file_name).get(key, []):
			index[entry.get("id")] = entry
		_indexes[key] = index
	return index.get(id, {})


static func race(id: String) -> Dictionary:
	return _indexed("races.json", "races", id)


static func star_type(id: String) -> Dictionary:
	return _indexed("star_types.json", "star_types", id)


static func planet_type(id: String) -> Dictionary:
	return _indexed("planet_types.json", "planet_types", id)


static func economy(id: String) -> Dictionary:
	return _indexed("world.json", "economies", id)


static func government(id: String) -> Dictionary:
	return _indexed("world.json", "governments", id)


static func good(id: String) -> Dictionary:
	return _indexed("goods.json", "goods", id)


static func market_event(id: String) -> Dictionary:
	return _indexed("goods.json", "events", id)


## Every list of items in equipment.json, by kind.
static func items_by_kind() -> Dictionary:
	return {"hull": hulls(), "engine": engines(), "fuel_tank": fuel_tanks(), "gripper": grippers(),
		"radar": radars(), "shield": shields(), "weapon": weapons()}


## A hull or piece of equipment from equipment.json, whatever its kind.
static func item_type(id: String) -> Dictionary:
	if _item_kinds.is_empty():
		_index_items()
	return _indexes["items"].get(id, {})


## "hull", "engine", "fuel_tank", "gripper", "radar", "shield", "weapon", or "" if unknown.
static func item_kind(id: String) -> String:
	if _item_kinds.is_empty():
		_index_items()
	return _item_kinds.get(id, "")


static func _index_items() -> void:
	var index := {}
	var lists := items_by_kind()
	for kind: String in lists:
		for entry: Dictionary in lists[kind]:
			index[entry.get("id")] = entry
			_item_kinds[entry.get("id")] = kind
	_indexes["items"] = index


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
