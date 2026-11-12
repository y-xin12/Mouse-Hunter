class_name LevelLoader
extends RefCounted
## Loads LevelDefinition resources from res://data/levels.
## Levels are named level_001.tres, level_002.tres, ... and are discovered
## by directory scan so new levels can be added without code changes.

const LEVEL_DIR := "res://data/levels"


static func level_count() -> int:
	var count := 0
	var dir := DirAccess.open(LEVEL_DIR)
	if dir == null:
		push_error("LevelLoader: missing level directory '%s'" % LEVEL_DIR)
		return 0
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			count += 1
		file_name = dir.get_next()
	dir.list_dir_end()
	return count


static func load_level(index: int) -> LevelDefinition:
	var path := "%s/level_%03d.tres" % [LEVEL_DIR, index + 1]
	var res: LevelDefinition = load(path)
	if res == null:
		push_error("LevelLoader: failed to load level '%s'" % path)
	return res
