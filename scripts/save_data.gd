class_name SaveData
extends RefCounted
## Player progression persistence for Mouse-Hunter, stored as JSON at
## user://savegame.json. Holds the unified level progression
## (highest_unlocked_level / current_level / completed_levels), the
## user_level_v1 adaptive-skill state (skill tier, clean-clear streak,
## rolling result window, transition log) and the per-level assigned wall
## variants. Writes are atomic (temp file + rename) so a crash mid-write
## cannot corrupt the existing save; loads tolerate missing or extra fields
## so older saves keep working.

const SAVE_PATH := "user://savegame.json"

## File location; tests override this right after construction.
var path := SAVE_PATH

## Adaptive player skill tier: "lv1" .. "lv5" (new players start at lv2).
var user_level_v1 := "lv2"
## Next level the Play button continues at (1-based). Winning N sets N+1.
var highest_unlocked_level := 1
## Numbered level currently loaded (1-based); informational only.
var current_level := 1
## Consecutive clean clears at the current skill tier.
var clean_clear_streak := 0
## Rolling per-attempt results since the last skill change; each entry is
## 1 (problematic: restarted/prop/failure/quit) or 0 (clean), trimmed to
## the current tier's evaluation window by the SkillTracker.
var results_since_skill_change: Array = []
## Wall variant pinned per numbered level, e.g. {"5": "easy"}. Once a level
## is assigned a variant it never changes.
var assigned_variants := {}
## 1-based numbers of levels completed at least once; a replay of an
## already completed level never counts as new progression.
var completed_levels: Array = []
## Skill transitions, newest last: {"level", "from", "to", "reason"}.
## Kept for the debug panel; session logs persist across restarts.
var change_log: Array = []


func save_game() -> void:
	## Serialize and write atomically: temp file first, then rename over the
	## real save so an interruption can only ever lose the newest write.
	var json := JSON.stringify(to_dict(), "\t")
	var tmp_path := path + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_error("SaveData: cannot write %s" % tmp_path)
		return
	f.store_string(json)
	f.close()
	var err := DirAccess.rename_absolute(
			ProjectSettings.globalize_path(tmp_path),
			ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("SaveData: rename failed (%d)" % err)


func load_save() -> bool:
	## Load the save file into this instance; false (and defaults kept) when
	## no valid save exists yet. Unknown fields are ignored, missing fields
	## keep their defaults.
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SaveData: corrupt save at %s, starting fresh" % path)
		return false
	from_dict(parsed)
	return true


func to_dict() -> Dictionary:
	return {
		"user_level_v1": user_level_v1,
		"highest_unlocked_level": highest_unlocked_level,
		"current_level": current_level,
		"clean_clear_streak": clean_clear_streak,
		"results_since_skill_change": results_since_skill_change.duplicate(),
		"assigned_variants": assigned_variants.duplicate(),
		"completed_levels": completed_levels.duplicate(),
		"change_log": change_log.duplicate(),
	}


func from_dict(d: Dictionary) -> void:
	user_level_v1 = str(d.get("user_level_v1", user_level_v1))
	highest_unlocked_level = int(d.get("highest_unlocked_level",
			highest_unlocked_level))
	current_level = int(d.get("current_level", current_level))
	clean_clear_streak = int(d.get("clean_clear_streak", clean_clear_streak))
	# JSON parses every number as float; gameplay code compares these
	# arrays with int values (Array.has/== are type-strict), so coerce.
	results_since_skill_change.clear()
	for r in d.get("results_since_skill_change", []):
		results_since_skill_change.append(int(r))
	assigned_variants = d.get("assigned_variants", assigned_variants).duplicate()
	completed_levels.clear()
	for n in d.get("completed_levels", []):
		completed_levels.append(int(n))
	change_log = d.get("change_log", change_log).duplicate()


static func delete_file(save_path: String) -> void:
	## Remove a save file (used by tests and the debug reset control).
	for p in [save_path, save_path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
