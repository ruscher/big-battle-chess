class_name TestSuite
extends RefCounted
## Minimal headless test framework. Every method named `test_*` in a suite is
## run by tests/run_tests.gd; failures are collected with readable messages.

var failures: PackedStringArray = []
var checks: int = 0
var current_test: String = ""


func check(condition: bool, message: String = "") -> bool:
	checks += 1
	if not condition:
		failures.append("%s: %s" % [current_test, message if not message.is_empty() else "check failed"])
	return condition


func check_eq(actual: Variant, expected: Variant, message: String = "") -> bool:
	checks += 1
	if typeof(actual) != typeof(expected) or actual != expected:
		failures.append("%s: %s expected <%s> got <%s>" % [current_test, message, str(expected), str(actual)])
		return false
	return true


## Optional per-test setup hook.
func before_each() -> void:
	pass
