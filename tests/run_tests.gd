extends SceneTree
## Finds every tests/**/test_*.gd file, runs its test_* methods and reports the results.
## Exit code is 0 when everything passes, 1 otherwise (used by GitHub Actions).
##
## Usage: godot --headless -s res://tests/run_tests.gd


func _initialize() -> void:
	var files: Array[String] = []
	_collect("res://tests", files)
	files.sort()
	var total := 0
	var failed: Array[String] = []

	for path in files:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			failed.append("%s: script failed to load (syntax error?)" % path)
			continue
		var instance: Object = script.new()
		if not instance is TestCase:
			continue
		var test_case: TestCase = instance
		for method in script.get_script_method_list():
			var method_name: String = method["name"]
			if not method_name.begins_with("test_"):
				continue
			total += 1
			test_case.current_test = "%s::%s" % [path.get_file(), method_name]
			var failures_before := test_case.failures.size()
			test_case.call(method_name)
			var passed := test_case.failures.size() == failures_before
			print("  %s %s" % ["PASS" if passed else "FAIL", test_case.current_test])
		failed.append_array(test_case.failures)

	print("")
	if failed.is_empty():
		print("All %d tests passed." % total)
		quit(0)
	else:
		for failure in failed:
			printerr("FAILED: " + failure)
		printerr("%d failure(s) in %d tests." % [failed.size(), total])
		quit(1)


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_collect(dir_path.path_join(sub), out)
	for file in dir.get_files():
		if file.begins_with("test_") and file.ends_with(".gd") and file != "test_case.gd":
			out.append(dir_path.path_join(file))
