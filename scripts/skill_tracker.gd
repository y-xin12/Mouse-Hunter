class_name SkillTracker
extends RefCounted
## Mouse-Hunter adaptive-difficulty state machine ("user_level_v1").
##
## Pure logic, no scene/file dependencies: GameManager owns one instance,
## calls record_result() exactly once per completed level (never for
## replays or abandoned attempts) and mirrors the state into SaveData.
##
## Rules (all centralized here):
## - New players start at lv2; levels 1..EVALUATION_START_LEVEL-1 are
##   recorded but never change the tier (evaluation starts at the
##   Level-EVALUATION_START_LEVEL boundary).
## - Upgrade after N consecutive clean clears (clean = completed with no
##   restart / prop / failure / quit; there are no props or failure
##   mechanics yet, so "restarted" is the only current blemish).
## - Downgrade when the share of problematic results in the tier's rolling
##   window is STRICTLY greater than 50%.
## - At most one tier change per evaluation, clamped lv1..lv5; the streak
##   and the window reset on every change so old results never re-trigger.

signal skill_changed(old_tier: String, new_tier: String, reason: String)

const TIERS: Array[String] = ["lv1", "lv2", "lv3", "lv4", "lv5"]
## Consecutive clean clears required to leave each tier (0 = max tier).
const UPGRADE_STREAKS := {"lv1": 2, "lv2": 2, "lv3": 3, "lv4": 5, "lv5": 0}
## Rolling evaluation window per tier (lv1 cannot downgrade).
const DOWNGRADE_WINDOWS := {"lv1": 2, "lv2": 2, "lv3": 3, "lv4": 5, "lv5": 5}
## Results are recorded from level 1, but tier changes are only evaluated
## once this numbered level is completed.
const EVALUATION_START_LEVEL := 5

## Skill tier -> wall variant selection. Deliberately a plain (editable)
## Dictionary: the mapping is meant to be tunable without touching logic.
var skill_to_variant := {
	"lv1": "easy", "lv2": "easy", "lv3": "medium", "lv4": "hard", "lv5": "hard"}

var skill := "lv2"
var clean_clear_streak := 0
## Rolling result window: 1 = problematic attempt, 0 = clean clear,
## trimmed to the current tier's DOWNGRADE_WINDOWS size.
var results_since_skill_change: Array = []
## Transition log for the debug panel: {"level", "from", "to", "reason"}.
var change_log: Array = []


func record_result(level_number: int, clean: bool) -> void:
	## Record one completed level attempt. The result feeds the streak and
	## the rolling window; tier changes are evaluated only from the
	## EVALUATION_START_LEVEL boundary on.
	_push_result(0 if clean else 1)
	if clean:
		clean_clear_streak += 1
	else:
		clean_clear_streak = 0
	if level_number < EVALUATION_START_LEVEL:
		return
	# At most one change per evaluation: a clean result can only upgrade,
	# a problematic one can only downgrade (never both at once).
	if clean:
		var needed: int = UPGRADE_STREAKS[skill]
		if needed > 0 and clean_clear_streak >= needed:
			_change_tier(1, level_number,
					"%d consecutive clean clears" % clean_clear_streak)
	else:
		if _can_downgrade():
			var window: int = DOWNGRADE_WINDOWS[skill]
			var bad := _problematic_count()
			if float(bad) / float(window) > 0.5:
				_change_tier(-1, level_number,
						"%d/%d problematic results" % [bad, window])


func variant_for_current_skill() -> String:
	## Wall variant the next level should use for the current skill tier.
	return skill_to_variant.get(skill, "medium")


func upgrade_requirement() -> int:
	## Clean clears needed for the next tier (0 = already at the top).
	return UPGRADE_STREAKS[skill]


func downgrade_window() -> int:
	return DOWNGRADE_WINDOWS[skill]


func _push_result(result: int) -> void:
	results_since_skill_change.append(result)
	var window: int = DOWNGRADE_WINDOWS[skill]
	while results_since_skill_change.size() > window:
		results_since_skill_change.pop_front()


func _problematic_count() -> int:
	var count := 0
	for r in results_since_skill_change:
		count += int(r)
	return count


func _can_downgrade() -> bool:
	return TIERS.find(skill) > 0


func _change_tier(direction: int, level_number: int, reason: String) -> void:
	var old := skill
	var new_index: int = clampi(TIERS.find(skill) + direction, 0, TIERS.size() - 1)
	skill = TIERS[new_index]
	# Fresh window and streak after every change: no repeated downgrades
	# from already-consumed history, no instant chained upgrades.
	results_since_skill_change.clear()
	clean_clear_streak = 0
	change_log.append({
		"level": level_number, "from": old, "to": skill, "reason": reason})
	skill_changed.emit(old, skill, reason)
