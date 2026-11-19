extends SceneTree
## Unit tests for the adaptive-difficulty rules (SkillTracker) and the
## progression persistence (SaveData). Pure logic, no scene involved:
## run headless with `--headless -s tests/skill_test.gd`.

var failures := 0


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		printerr("FAIL: %s" % label)


func _initialize() -> void:
	_run_tracker_tests()
	_run_save_tests()
	print("== %d failure(s) ==" % failures)
	quit(1 if failures > 0 else 0)


## Feed the tracker results at consecutive level numbers starting from
## `from_level` (use >= 5 so evaluation is active); returns the next level.
func _feed(tracker: SkillTracker, from_level: int, results: Array) -> int:
	var n := from_level
	for clean in results:
		tracker.record_result(n, bool(clean))
		n += 1
	return n


func _run_tracker_tests() -> void:
	# --- Defaults ---------------------------------------------------------
	var t := SkillTracker.new()
	_check(t.skill == "lv2" and t.clean_clear_streak == 0
			and t.results_since_skill_change.is_empty(),
			"new player starts at lv2 with empty streak and window")

	# --- Evaluation gate: results before level 5 are recorded only --------
	var gate := SkillTracker.new()
	for i in range(4):
		gate.record_result(i + 1, true)
	_check(gate.skill == "lv2" and gate.clean_clear_streak == 4,
			"levels 1-4 build the streak but never change the tier")
	gate.record_result(5, true)
	_check(gate.skill == "lv3" and gate.clean_clear_streak == 0,
			"evaluation starts at level 5: streak 5 upgrades lv2")

	# --- Upgrade thresholds per tier --------------------------------------
	var up := SkillTracker.new()
	up.skill = "lv1"
	var n := _feed(up, 5, [true])
	_check(up.skill == "lv1", "lv1: one clean clear is not enough")
	_feed(up, n, [true])
	_check(up.skill == "lv2", "lv1 upgrades to lv2 after 2 clean clears")

	up = SkillTracker.new()  # lv2
	n = _feed(up, 5, [true, true])
	_check(up.skill == "lv3", "lv2 upgrades to lv3 after 2 clean clears")

	up = SkillTracker.new()
	up.skill = "lv3"
	n = _feed(up, 5, [true, true])
	_check(up.skill == "lv3", "lv3: two clean clears are not enough")
	_feed(up, n, [true])
	_check(up.skill == "lv4", "lv3 upgrades to lv4 after 3 clean clears")

	up = SkillTracker.new()
	up.skill = "lv4"
	n = _feed(up, 5, [true, true, true, true])
	_check(up.skill == "lv4", "lv4: four clean clears are not enough")
	_feed(up, n, [true])
	_check(up.skill == "lv5", "lv4 upgrades to lv5 after 5 clean clears")

	up = SkillTracker.new()
	up.skill = "lv5"
	_feed(up, 5, [true, true, true, true, true, true, true])
	_check(up.skill == "lv5", "lv5 is the maximum tier")

	# --- Downgrade windows (spec examples) --------------------------------
	var down := SkillTracker.new()
	down.skill = "lv2"
	_feed(down, 5, [false, true])
	_check(down.skill == "lv2", "1 problematic of 2: no downgrade")
	down = SkillTracker.new()
	down.skill = "lv2"
	_feed(down, 5, [false, false])
	_check(down.skill == "lv1", "2 problematic of 2: downgrade lv2 to lv1")
	down = SkillTracker.new()
	down.skill = "lv3"
	_feed(down, 5, [false, false, true])
	_check(down.skill == "lv2", "2 problematic of 3: downgrade lv3 to lv2")
	down = SkillTracker.new()
	down.skill = "lv4"
	_feed(down, 5, [false, false, true, true, true])
	_check(down.skill == "lv4", "2 problematic of 5: no downgrade")
	down = SkillTracker.new()
	down.skill = "lv4"
	_feed(down, 5, [false, false, false, true, true])
	_check(down.skill == "lv3", "3 problematic of 5: downgrade lv4 to lv3")
	down = SkillTracker.new()
	down.skill = "lv1"
	_feed(down, 5, [false, false, false])
	_check(down.skill == "lv1", "lv1 is the minimum tier")

	# --- Streak reset and single change per evaluation --------------------
	var mixed := SkillTracker.new()
	mixed.skill = "lv3"
	n = _feed(mixed, 5, [true, true])
	_feed(mixed, n, [false])
	_check(mixed.clean_clear_streak == 0 and mixed.skill == "lv3",
			"a non-clean result resets the streak without downgrading")
	mixed = SkillTracker.new()
	mixed.skill = "lv1"
	# A long clean run climbs at most one tier per completed level and the
	# streak restarts on every change: 4 clears at lv1 (threshold 2) land
	# exactly at lv3 with a fresh streak, never higher.
	_feed(mixed, 5, [true, true, true, true])
	_check(mixed.skill == "lv3" and mixed.clean_clear_streak == 0,
			"one upgrade per evaluation; each change resets the streak")

	# --- Window resets after a change: old results never re-trigger -------
	var rolling := SkillTracker.new()
	rolling.skill = "lv3"
	n = _feed(rolling, 5, [false, false])
	_check(rolling.skill == "lv2", "downgrade consumes the window")
	_check(rolling.results_since_skill_change.is_empty(),
			"window starts fresh after a tier change")
	# A single new problematic result at lv2 (window 2) is only 1/2.
	n = _feed(rolling, n, [true])
	_feed(rolling, n, [false])
	_check(rolling.skill == "lv2",
			"old problematic results cannot cause a repeated downgrade")

	# --- Rolling window trims to the tier's size ---------------------------
	var trim := SkillTracker.new()
	trim.skill = "lv2"  # window 2
	n = _feed(trim, 5, [true, true])  # upgrades to lv3, window resets
	n = _feed(trim, n, [true, true, true, true])
	_check(trim.results_since_skill_change.size() <= 3,
			"window never exceeds the current tier's size")

	# --- Skill -> variant mapping -----------------------------------------
	var map := SkillTracker.new()
	var seen := {}
	for tier in SkillTracker.TIERS:
		map.skill = tier
		seen[tier] = map.variant_for_current_skill()
	_check(seen["lv1"] == "easy" and seen["lv2"] == "easy"
			and seen["lv3"] == "medium"
			and seen["lv4"] == "hard" and seen["lv5"] == "hard",
			"default skill->variant mapping: lv1/2 easy, lv3 medium, lv4/5 hard")

	# --- Change log ---------------------------------------------------------
	var log_t := SkillTracker.new()
	_feed(log_t, 5, [true, true])
	_check(log_t.change_log.size() == 1
			and log_t.change_log[0]["from"] == "lv2"
			and log_t.change_log[0]["to"] == "lv3"
			and log_t.change_log[0]["level"] == 6,
			"skill changes are logged with level and reason")


func _run_save_tests() -> void:
	var path := "user://skill_test_save.json"
	SaveData.delete_file(path)

	# Missing file -> defaults, load reports false.
	var fresh := SaveData.new()
	fresh.path = path
	_check(not fresh.load_save() and fresh.user_level_v1 == "lv2"
			and fresh.highest_unlocked_level == 1
			and fresh.completed_levels.is_empty(),
			"missing save loads defaults and reports false")

	# Roundtrip: write one instance, read it back with another.
	var out := SaveData.new()
	out.path = path
	out.user_level_v1 = "lv3"
	out.highest_unlocked_level = 8
	out.current_level = 8
	out.clean_clear_streak = 1
	out.results_since_skill_change = [0, 1]
	out.assigned_variants = {"5": "easy", "8": "medium"}
	out.completed_levels = [1, 2, 3, 5, 7]
	out.change_log = [{"level": 7, "from": "lv2", "to": "lv3", "reason": "x"}]
	out.save_game()
	var back := SaveData.new()
	back.path = path
	_check(back.load_save()
			and back.user_level_v1 == "lv3"
			and back.highest_unlocked_level == 8
			and back.current_level == 8
			and back.clean_clear_streak == 1
			and back.results_since_skill_change == [0, 1]
			and back.assigned_variants == {"5": "easy", "8": "medium"}
			and back.completed_levels == [1, 2, 3, 5, 7]
			and back.change_log.size() == 1,
			"save roundtrip preserves every field")

	# Corrupt file -> defaults, no crash.
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{ not json !")
	f.close()
	var corrupt := SaveData.new()
	corrupt.path = path
	_check(not corrupt.load_save() and corrupt.user_level_v1 == "lv2",
			"corrupt save falls back to defaults")

	# Older save missing newer fields -> defaults for the gaps.
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"user_level_v1": "lv4"}))
	f.close()
	var legacy := SaveData.new()
	legacy.path = path
	_check(legacy.load_save() and legacy.user_level_v1 == "lv4"
			and legacy.highest_unlocked_level == 1
			and legacy.assigned_variants.is_empty(),
			"partial legacy save keeps defaults for missing fields")

	SaveData.delete_file(path)