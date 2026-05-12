extends GutTest
##
## Placeholder smoke test to validate the GUT framework is wired up.
##
## When `addons/gut/` is installed and the GitHub Actions workflow runs the
## headless runner command from ADR-0014, this test must pass.
##
## File naming: `test_[system]_[feature].gd` (this is a special placeholder).
## Function naming: `test_[scenario]_[expected]()`.
##


func test_framework_smoke_runs_at_all() -> void:
	assert_true(true, "GUT framework is reachable and assert_true works")


func test_framework_smoke_assert_eq() -> void:
	assert_eq(2 + 2, 4, "Basic arithmetic still works")


func test_framework_smoke_string_compare() -> void:
	assert_eq("situation_room", "situation_room", "String equality assertions work")
