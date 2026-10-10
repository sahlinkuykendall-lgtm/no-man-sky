class_name TestCase
extends RefCounted
## Base class for tests. Make a file tests/**/test_*.gd that extends TestCase, and add
## methods whose names start with "test_". Run all tests with:
##   godot --headless -s res://tests/run_tests.gd

var failures: Array[String] = []
var current_test: String = ""


func assert_true(condition: bool, message: String = "expected true") -> void:
	if not condition:
		_fail(message)


func assert_false(condition: bool, message: String = "expected false") -> void:
	if condition:
		_fail(message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if actual != expected:
		_fail("%s (expected %s, got %s)" % [message, _short(expected), _short(actual)])


func assert_ne(actual: Variant, unexpected: Variant, message: String = "") -> void:
	if actual == unexpected:
		_fail("%s (did not expect %s)" % [message, _short(unexpected)])


func assert_almost_eq(actual: float, expected: float, tolerance: float = 0.001, message: String = "") -> void:
	if absf(actual - expected) > tolerance:
		_fail("%s (expected %f ± %f, got %f)" % [message, expected, tolerance, actual])


## Compares nested dictionaries/arrays, allowing tiny float differences.
func assert_data_almost_eq(actual: Variant, expected: Variant, tolerance: float = 0.0001, message: String = "") -> void:
	var difference := _find_difference(actual, expected, tolerance, "")
	if difference != "":
		_fail("%s (first difference at %s)" % [message, difference])


func _find_difference(a: Variant, b: Variant, tolerance: float, path: String) -> String:
	var a_is_number := typeof(a) == TYPE_FLOAT or typeof(a) == TYPE_INT
	var b_is_number := typeof(b) == TYPE_FLOAT or typeof(b) == TYPE_INT
	if a_is_number and b_is_number:
		return "" if absf(float(a) - float(b)) <= tolerance else "%s: %s vs %s" % [path, a, b]
	if typeof(a) != typeof(b):
		return "%s: type %s vs %s" % [path, type_string(typeof(a)), type_string(typeof(b))]
	if a is Dictionary:
		if a.size() != b.size():
			return "%s: %d keys vs %d keys" % [path, a.size(), b.size()]
		for key in a:
			if not b.has(key):
				return "%s.%s: missing" % [path, key]
			var found := _find_difference(a[key], b[key], tolerance, "%s.%s" % [path, key])
			if found != "":
				return found
		return ""
	if a is Array:
		if a.size() != b.size():
			return "%s: %d items vs %d items" % [path, a.size(), b.size()]
		for i in a.size():
			var found := _find_difference(a[i], b[i], tolerance, "%s[%d]" % [path, i])
			if found != "":
				return found
		return ""
	return "" if a == b else "%s: %s vs %s" % [path, a, b]


func _fail(message: String) -> void:
	failures.append("%s: %s" % [current_test, message])


## Keeps failure messages readable when comparing big values.
func _short(value: Variant) -> String:
	var text := str(value)
	return text if text.length() <= 200 else text.left(200) + "..."
