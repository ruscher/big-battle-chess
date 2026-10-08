extends SceneTree
## Headless test runner.
##
##   godot --headless --path . --script res://tests/run_tests.gd
##   godot --headless --path . --script res://tests/run_tests.gd -- --suite=perft --deep
##
## Exits with code 1 when any check fails, so CI can gate on it.

const SUITE_DIR := "res://tests/suites"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var only := ""
	for a in args:
		if a.begins_with("--suite="):
			only = a.trim_prefix("--suite=")
	var total_checks := 0
	var all_failures: PackedStringArray = []
	var started := Time.get_ticks_msec()
	var files := DirAccess.get_files_at(SUITE_DIR)
	files.sort()
	for file in files:
		if not file.begins_with("test_") or not file.ends_with(".gd"):
			continue
		if not only.is_empty() and not file.contains(only):
			continue
		var script := load(SUITE_DIR.path_join(file)) as GDScript
		if script == null or not script.can_instantiate():
			all_failures.append("%s: script failed to load (parse error)" % file)
			continue
		var suite: TestSuite = script.new()
		if suite.has_method("configure"):
			suite.call("configure", args, self)
		var suite_start := Time.get_ticks_msec()
		var count := 0
		for method in script.get_script_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			suite.current_test = "%s::%s" % [file.get_basename(), name]
			if "--verbose" in args:
				print("    > " + suite.current_test)
			suite.before_each()
			suite.call(name)
			count += 1
		if suite.checks == 0:
			suite.failures.append("%s: no checks ran (script error?)" % file)
		total_checks += suite.checks
		all_failures.append_array(suite.failures)
		print("  %-28s %3d tests  %5d checks  %6d ms  %s" % [
			file.get_basename(), count, suite.checks, Time.get_ticks_msec() - suite_start,
			"OK" if suite.failures.is_empty() else "FAILED (%d)" % suite.failures.size()])
	print("")
	for f in all_failures:
		printerr("FAIL  " + f)
	print("%d checks, %d failures, %.1f s" % [total_checks, all_failures.size(),
		(Time.get_ticks_msec() - started) / 1000.0])
	quit(1 if not all_failures.is_empty() else 0)
