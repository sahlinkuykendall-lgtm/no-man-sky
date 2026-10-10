class_name NameGenerator
extends RefCounted
## Builds pronounceable, unique names (for star systems and planets) from syllables.

var _rng: RandomNumberGenerator
var _used: Dictionary = {}


func _init(rng: RandomNumberGenerator) -> void:
	_rng = rng


## Returns a name that this generator has not returned before.
func unique_name() -> String:
	for attempt in 200:
		var candidate := _make_name()
		if not _used.has(candidate):
			_used[candidate] = true
			return candidate
	# Extremely unlikely fallback: add a number to guarantee uniqueness.
	var fallback := "%s %d" % [_make_name(), _used.size()]
	_used[fallback] = true
	return fallback


func _make_name() -> String:
	var syllables := GameData.name_syllables()
	var starts: Array = syllables.get("starts", ["x"])
	var middles: Array = syllables.get("middles", ["a"])
	var ends: Array = syllables.get("ends", ["on"])
	var result: String = starts[_rng.randi_range(0, starts.size() - 1)]
	if _rng.randf() < 0.45:
		result += middles[_rng.randi_range(0, middles.size() - 1)]
	result += ends[_rng.randi_range(0, ends.size() - 1)]
	return result.capitalize()
