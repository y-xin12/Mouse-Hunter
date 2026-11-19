extends SceneTree
## Headless smoke test for the Mouse-Hunter MVP.
## Run:  <godot> --headless --path . --script res://tests/smoke_test.gd
## Exits with code 0 when all checks pass, 1 otherwise.
## Uses tests/solutions.json (level_solver.py for the five original levels;
## the twenty generator levels were converted from their shipped solutions)
## to replay solver-verified solutions and cross-check cell math.

const SOLUTIONS_PATH := "res://tests/solutions.json"
## Isolated save file for the smoke run (deleted before and after).
const SMOKE_SAVE_PATH := "user://smoke_test_save.json"

var failures := 0
var gm: Node2D


func _initialize() -> void:
	_run_tests()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  %s" % label)
	else:
		failures += 1
		print("  FAIL  %s" % label)


func _run_tests() -> void:
	print("== Mouse-Hunter smoke test ==")

	# --- Scene & level loading ------------------------------------------
	# Tests must never touch the real player save: redirect it before the
	# scene's first frame (Node._ready has not run yet) and start empty.
	SaveData.delete_file(SMOKE_SAVE_PATH)
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	main.save_path = SMOKE_SAVE_PATH
	root.add_child(main)
	# Node _ready runs on the first process frame, not during add_child in
	# _initialize, so let two frames pass before inspecting game state.
	await process_frame
	await process_frame
	gm = main
	_check(gm.level != null, "level 1 loaded")
	_check(gm.pieces.size() == 6, "6 pieces instanced")
	_check(LevelLoader.level_count() == 25, "25 levels discovered")
	_check(gm.level.mice.size() == 3, "level 1 has 3 mice")
	_check(gm.level_label.text == "Level 1 — Kitchen", "level label text")
	_check(gm.menu_open and gm.home_panel.visible, "home screen shown on boot")
	_check(_badge_text() == "Level 1",
			"play pill shows Level 1 on a fresh game")
	gm.play_button.pressed.emit()
	_check(not gm.home_panel.visible and not gm.menu_open,
			"play button closes the home screen")
	_check(gm.level_index == 0, "play starts at level 1")
	_check(not gm.win_panel.visible, "popup stays hidden until the level is complete")
	_check(gm.skill_tracker.skill == "lv2"
			and gm.skill_tracker.clean_clear_streak == 0,
			"new player starts at skill lv2 with an empty streak")
	_check(gm.debug_overlay != null and not gm.debug_overlay.is_open(),
			"debug overlay exists in debug builds, hidden by default")
	_check(gm.debug_overlay.toggle_button != null
			and gm.debug_overlay.toggle_button.visible,
			"floating debug toggle button is on screen")

	# Solver reference data (solutions, expected walls) for the whole run.
	var data: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string(SOLUTIONS_PATH))
	_check(not data.is_empty()
			and data["levels"].size() == LevelLoader.level_count(),
			"solutions.json parsed and covers every catalog level")

	# --- Level category classification (unified progression) -------------
	_check(LevelDefinition.get_level_category(1) == "normal"
			and LevelDefinition.get_level_category(2) == "normal",
			"levels 1 and 2 are normal (Level 2 is never super hard)")
	_check(LevelDefinition.get_level_category(7) == "hard"
			and LevelDefinition.get_level_category(17) == "hard"
			and LevelDefinition.get_level_category(27) == "hard"
			and LevelDefinition.get_level_category(37) == "hard",
			"levels ending in 7 are hard")
	_check(LevelDefinition.get_level_category(12) == "super_hard"
			and LevelDefinition.get_level_category(22) == "super_hard"
			and LevelDefinition.get_level_category(32) == "super_hard",
			"levels ending in 2 (beyond Level 2) are super hard")
	_check(LevelDefinition.get_level_category(3) == "normal"
			and LevelDefinition.get_level_category(11) == "normal"
			and LevelDefinition.get_level_category(25) == "normal",
			"all remaining levels are normal")

	# --- Wall variants (adaptive difficulty data, all 25 levels) ---------
	# easy must be a superset of the base walls, hard a subset, and no
	# variant wall may sit inside a single piece of the reference
	# solution (walls only forbid one piece covering both of their cells).
	for i in range(LevelLoader.level_count()):
		var lvl: LevelDefinition = LevelLoader.load_level(i)
		var entry: Dictionary = data["levels"][i]
		var base_set := _wall_set(lvl.walls)
		var easy := lvl.get_wall_variant("easy")
		var hard := lvl.get_wall_variant("hard")
		var easy_set := _wall_set(easy)
		var hard_set := _wall_set(hard)
		var owner := _placement_owners(entry)
		var ok: bool = easy.size() >= lvl.walls.size() \
				and hard.size() <= lvl.walls.size()
		for key in base_set:
			ok = ok and easy_set.has(key)
		for key in hard_set:
			ok = ok and base_set.has(key)
		for flat in [easy, hard]:
			for j in range(0, flat.size(), 2):
				var ka := "%d,%d" % [flat[j].x, flat[j].y]
				var kb := "%d,%d" % [flat[j + 1].x, flat[j + 1].y]
				ok = ok and owner.get(ka) != owner.get(kb)
		_check(ok, "level %d wall variants contain base and keep the solution legal"
				% [i + 1])
	# Unknown variants fall back to the base walls; "medium" IS the base.
	var lvl_res: LevelDefinition = LevelLoader.load_level(0)
	_check(lvl_res.get_wall_variant("medium") == lvl_res.walls
			and lvl_res.get_wall_variant("bogus") == lvl_res.walls,
			"medium and unknown variants fall back to the base walls")

	# --- Tray carousel ---------------------------------------------------
	# Six pieces park in one scrollable row: only the first three slots are
	# visible at rest and every piece renders at the same scale.
	var tray_visible := 0
	for p in gm.pieces:
		if p.visible:
			tray_visible += 1
	_check(tray_visible == 3, "tray shows exactly 3 pieces at rest")
	var tray_scale: float = gm.pieces[0].scale.x
	var same_scale := true
	for p in gm.pieces:
		if absf(p.scale.x - tray_scale) > 0.0001 \
				or absf(p.scale.y - tray_scale) > 0.0001:
			same_scale = false
	_check(same_scale, "all tray pieces share one scale")

	# --- Validator unit checks ------------------------------------------
	var piece: PuzzlePiece = gm.pieces[0]  # square
	var wc: Array[Vector2i] = PlacementValidator.get_world_cells(
			piece.definition, 0, Vector2i(0, 0))
	_check(PlacementValidator.is_in_bounds(wc, Vector2i(4, 6)),
			"square in bounds at (0, 0)")
	var out_wc: Array[Vector2i] = PlacementValidator.get_world_cells(
			piece.definition, 0, Vector2i(3, 5))
	_check(not PlacementValidator.is_in_bounds(out_wc, Vector2i(4, 6)),
			"square out of bounds at (3, 5)")
	var occ := {}
	for c in wc:
		occ[c] = true
	_check(not PlacementValidator.has_no_overlap(wc, occ), "overlap detected")
	var rotated: Array[Vector2i] = piece.definition.get_cells_rotated(1)
	_check(rotated.size() == 4 and rotated.has(Vector2i(0, 0))
			and rotated.has(Vector2i(1, 1)), "square rotation keeps shape")
	_check(gm._star_count(6) == 3 and gm._star_count(9) == 2
			and gm._star_count(12) == 1,
			"star thresholds follow the real move count")

	# --- Wall (edge) rules -----------------------------------------------
	var test_walls := PlacementValidator.walls_from_pairs(
			[Vector2i(0, 0), Vector2i(1, 0)])
	var span_right: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var span_down: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1)]
	_check(PlacementValidator.crosses_no_wall(span_down, test_walls),
			"cells not crossing a wall pass")
	_check(not PlacementValidator.crosses_no_wall(span_right, test_walls),
			"cells crossing a wall are rejected")
	_check(PlacementValidator.is_placement_legal(piece.definition, 0,
			Vector2i(0, 0), Vector2i(4, 6), {}),
			"square placement legal without walls")
	_check(not PlacementValidator.is_placement_legal(piece.definition, 0,
			Vector2i(0, 0), Vector2i(4, 6), {}, test_walls),
			"square cannot be placed across a walled edge")

	# --- Drag & drop via simulated input events ------------------------
	# (1, 2) is the square's spot in the level 1 reference tiling, so the
	# placement stays legal with the level's wall hints active.
	_drag_to(piece, Vector2i(1, 2))
	_check(piece.placed and piece.board_position == Vector2i(1, 2),
			"drag placed square at (1, 2)")
	_check(gm.move_count == 1, "a completed drag counts as one move")
	_check(piece.global_position == gm.board.cell_to_world(Vector2i(1, 2)),
			"piece snapped to cell position")

	var plank: PuzzlePiece = _find_piece("plank")
	_drag_to(plank, Vector2i(1, 2))
	_check(not plank.placed, "overlapping drop rejected (plank over square)")
	_check(gm.move_count == 1, "an illegal drop does not count as a move")

	var hook: PuzzlePiece = _find_piece("hook")
	# --- Scrolling the tray carousel -------------------------------------
	# Hook parks at slot index 4 (the fifth piece), beyond the 3-slot
	# window. A horizontal swipe starting on a tray piece (the plank) must
	# scroll the carousel instead of dragging the piece — far enough to
	# reveal hook at any canvas scale (the piece's visual width varies
	# with the tray height, so a marginal swipe is not enough).
	_check(not hook.visible, "hook hidden before scrolling")
	_swipe_tray(_piece_center(plank), -2.5 * gm.tray_slot_w)
	_check(gm.tray_scroll > 0.0, "swipe scrolled the tray")
	_check(not plank.placed and plank.get_parent() == gm.tray_clip,
			"swiped piece stayed parked in the tray (not picked up)")
	_check(hook.visible, "hook scrolled into view")
	var old_orientation := hook.orientation
	var old_hook_scale: Vector2 = hook.scale
	_tap(hook)
	_check(hook.orientation == posmod(old_orientation + 1, 4),
			"tap rotates tray piece")
	_check(not hook.placed, "tap-rotated piece parked in tray")
	_check(hook.visible, "tap-rotated piece still visible in the tray")
	_check(absf(hook.scale.x - old_hook_scale.x) < 0.0001
			and absf(hook.scale.y - old_hook_scale.y) < 0.0001,
			"rotating a tray piece keeps its size")
	# Swipe back the other way so later drag tests start from rest.
	_swipe_tray(gm.tray_rect.position + Vector2(
			gm.tray_rect.size.x * 0.3, gm.tray_rect.size.y * 0.95),
			2.5 * gm.tray_slot_w)
	_check(absf(gm.tray_scroll) < 0.01, "swipe back returns the tray to rest")

	# --- Tap-rotate a placed piece keeps it on the board -----------------
	# `piece` (square) is still placed at (0, 0) from the drag test above;
	# a 2x2 square keeps its footprint when rotated, so the in-place
	# rotation is legal and must not send the piece back to the tray.
	var square_orientation := piece.orientation
	_tap(piece)
	_check(piece.placed and piece.board_position == Vector2i(1, 2),
			"tap keeps placed piece on the board")
	_check(piece.orientation == posmod(square_orientation + 1, 4),
			"tap rotates placed piece in place")
	_check(piece.global_position == gm.board.cell_to_world(Vector2i(1, 2)),
			"tapped placed piece stays snapped to its cell")

	# --- Walls block placement across them --------------------------------
	# Walls are edges between cells; no piece may be placed across one.
	# Find a level-1 wall whose lower cell still fits the 2x2 square.
	var wall_a := Vector2i(-1, -1)
	var wall_b := Vector2i(-1, -1)
	for i in range(0, gm.level.walls.size(), 2):
		var wa: Vector2i = gm.level.walls[i]
		var wb: Vector2i = gm.level.walls[i + 1]
		var lo := Vector2i(mini(wa.x, wb.x), mini(wa.y, wb.y))
		if lo.x + 1 < gm.level.board_size.x \
				and lo.y + 1 < gm.level.board_size.y:
			wall_a = wa
			wall_b = wb
			break
	_check(wall_a.x >= 0, "level 1 defines walls the square can span")
	gm._reset_level()
	var span_cell := Vector2i(mini(wall_a.x, wall_b.x),
			mini(wall_a.y, wall_b.y))
	_drag_to(piece, span_cell)
	_check(not piece.placed, "drop spanning a walled edge is rejected")
	gm.wall_edges = {}
	_drag_to(piece, span_cell)
	_check(piece.placed, "same drop is legal without walls")
	gm.wall_edges = PlacementValidator.walls_from_pairs(gm.level.walls)

	# --- Illegal rotation of a placed piece is blocked ------------------
	gm._reset_level()
	var corner: PuzzlePiece = _find_piece("corner")
	corner.placed = true
	corner.set_orientation(0)
	corner.board_position = Vector2i(0, 0)
	hook.placed = true
	hook.set_orientation(0)
	hook.board_position = Vector2i(2, 0)
	gm._refresh_all_pieces()
	gm._rotate_piece(corner)
	_check(corner.orientation == 0, "placed piece rotation blocked when illegal")
	# Same scenario through the tap input path: the piece must stay placed
	# on the board instead of returning to the tray.
	_tap(corner)
	_check(corner.placed and corner.board_position == Vector2i(0, 0),
			"tap keeps blocked piece placed on the board")
	_check(corner.orientation == 0,
			"tap does not rotate placed piece when illegal")

	# --- Rotation that would cross a wall is blocked ---------------------
	gm._reset_level()
	var wall_plank: PuzzlePiece = _find_piece("plank")
	wall_plank.placed = true
	wall_plank.set_orientation(0)
	wall_plank.board_position = Vector2i(0, 0)
	gm._refresh_all_pieces()
	gm.wall_edges = PlacementValidator.walls_from_pairs(
			[Vector2i(0, 0), Vector2i(1, 0)])
	gm._rotate_piece(wall_plank)
	_check(wall_plank.orientation == 0,
			"rotation blocked when it would cross a wall")
	gm.wall_edges = PlacementValidator.walls_from_pairs(gm.level.walls)


	# --- Tray momentum, clamping and the grab-to-stop behaviour ----------
	gm.tray_scroll_velocity = 1200.0
	var glide_steps := 0
	while gm.tray_scroll_velocity != 0.0 and glide_steps < 200:
		gm._integrate_tray_momentum(1.0 / 30.0)
		glide_steps += 1
	_check(glide_steps < 200 and gm.tray_scroll_velocity == 0.0,
			"tray glide dies out from friction")
	_check(gm.tray_scroll > 0.0, "glide carried the tray sideways")
	# Running into the content edge stops the glide dead.
	gm._set_tray_scroll(gm._tray_max_scroll())
	gm.tray_scroll_velocity = 800.0
	gm._integrate_tray_momentum(0.1)
	_check(gm.tray_scroll == gm._tray_max_scroll()
			and gm.tray_scroll_velocity == 0.0,
			"glide clamps at the last slot and stops")
	# Touching the tray stops any glide immediately.
	gm.tray_scroll_velocity = 800.0
	var grab_point: Vector2 = gm.tray_rect.position + Vector2(
			gm.tray_rect.size.x * 0.3, gm.tray_rect.size.y * 0.95)
	_mouse_event(true, grab_point)
	_check(gm.tray_scroll_velocity == 0.0, "touching the tray stops the glide")
	_mouse_event(false, grab_point)

	# --- Win flow replaying the solver-verified solution ----------------
	gm._reset_level()
	_check_level_walls(data["levels"][0])
	var lvl1: Dictionary = data["levels"][0]
	_apply_solution(lvl1)
	_verify_solution_cells(lvl1)
	_check(gm.won, "win detected for solver solution (level 1)")
	_check(gm.win_panel.visible, "completion popup shown")
	_check(gm.win_panel.moves_value.text == str(gm.move_count),
			"popup shows the real move count")
	var shown_time: String = gm.win_panel.time_value.text
	_check(shown_time.length() == 5 and shown_time[2] == ":",
			"popup shows an MM:SS completion time")
	_check(gm.win_panel.stars_img.texture == load("res://assets/UI/3 Stars.png"),
			"clean run reveals the three-star art")
	_check(gm.next_button.visible and not gm.home_button.visible,
			"win shows the Next Level button")
	# Star art follows the rating; the trailing button swaps at group ends.
	gm.win_panel.show_popup(2, gm.move_count, "00:05", false)
	_check(gm.win_panel.stars_img.texture == load("res://assets/UI/2 Stars.png"),
			"two-star result swaps to the 2 Stars art")
	_check(gm.next_button.visible and not gm.home_button.visible,
			"mid-group result offers Next Level")
	gm.win_panel.show_popup(1, gm.move_count, "00:05", true)
	_check(gm.win_panel.stars_img.texture == load("res://assets/UI/1 star.png"),
			"one-star result swaps to the 1 star art")
	_check(not gm.next_button.visible and gm.home_button.visible,
			"last level swaps Next Level for Home")
	# Restore the real result so later checks see the genuine popup state.
	gm.win_panel.show_popup(3, gm.move_count, "00:05", false)
	gm._refresh_play_badge()
	_check(_badge_text() == "Level 2",
			"finishing level 1 advances the play pill to Level 2")
	# The level was reset before this win, so it was NOT a clean clear.
	_check(gm.skill_tracker.clean_clear_streak == 0
			and gm.skill_tracker.skill == "lv2",
			"restarted level 1 win is non-clean: streak stays 0 at lv2")

	# --- Reset -----------------------------------------------------------
	gm._reset_level()
	var any_placed := false
	for p in gm.pieces:
		if p.placed:
			any_placed = true
	_check(not any_placed and not gm.win_panel.visible, "reset clears board")

	# --- Level navigation --------------------------------------------------
	# One continuous sequence: NEXT walks 1 -> 2 -> 3; the walk then jumps
	# around the catalog with _load_level to exercise solver levels quickly.
	gm._next_level()
	_check(gm.level.id == "kitchen_nook_002", "next level is the generator level 2")
	_check(gm.level_label.text == "Level 2 — Kitchen Nook", "level 2 label")
	_check_level_walls(data["levels"][1])
	_apply_solution(data["levels"][1])
	_check(gm.won, "win detected for level 2 solution")
	_check(gm.next_button.visible and not gm.home_button.visible,
			"mid-sequence win continues to the next level")
	gm._refresh_play_badge()
	_check(_badge_text() == "Level 3",
			"finishing level 2 advances the play pill to Level 3")
	_check(gm.skill_tracker.clean_clear_streak == 1,
			"clean level 2 win starts the clean-clear streak")

	gm._next_level()
	_check(gm.level.id == "cheese_shelf_003", "level 3 loaded")
	_check_level_walls(data["levels"][2])
	_apply_solution(data["levels"][2])
	_check(gm.won, "win detected for level 3 solution")
	_check(gm.skill_tracker.clean_clear_streak == 2
			and gm.skill_tracker.skill == "lv2",
			"streak grows pre-level-5 but the tier is not evaluated yet")

	# Level 7 (index 6, the original living room level).
	gm._load_level(6)
	_check(gm.level.id == "living_room_002", "index 6 is the original living room")
	_check(gm.level.mice.size() == 5, "level 7 has 5 mice")
	_check(gm.level_label.text == "Level 7 — Living Room", "level 7 label")
	_check(gm.current_variant == "easy"
			and gm.save_data.assigned_variants.get("7") == "easy",
			"level 7 pins the easy variant at skill lv2")
	_check_level_walls(data["levels"][6])
	_apply_solution(data["levels"][6])
	_check(gm.won, "win detected for level 7 solution")
	_check(gm.next_button.visible and not gm.home_button.visible,
			"level 7 win continues to the next level")
	gm._refresh_play_badge()
	_check(_badge_text() == "Level 8",
			"finishing level 7 advances the play pill to Level 8")
	# Evaluation begins at the level-5 boundary: the 3rd consecutive clean
	# clear (levels 2, 3, 7) exceeds the lv2 threshold of 2 -> upgrade.
	_check(gm.skill_tracker.skill == "lv3"
			and gm.skill_tracker.clean_clear_streak == 0,
			"evaluation starts at level 5: streak upgrades lv2 to lv3")

	# Level 13 (index 12, the original bedroom level).
	gm._load_level(12)
	_check(gm.level.id == "bedroom_003", "index 12 is the original bedroom")
	_check(gm.level_label.text == "Level 13 — Bedroom", "level 13 label")
	_check(gm.current_variant == "medium"
			and gm.save_data.assigned_variants.get("13") == "medium",
			"level 13 pins the medium variant at skill lv3")
	_check_level_walls(data["levels"][12])
	_apply_solution(data["levels"][12])
	_check(gm.won, "win detected for level 13 solution")
	_check(gm.next_button.visible and not gm.home_button.visible,
			"level 13 win continues to the next level")
	gm._refresh_play_badge()
	_check(_badge_text() == "Level 14",
			"finishing level 13 advances the play pill to Level 14")

	# Level 14 (index 13) requires rotation to solve.
	gm._load_level(13)
	_check(gm.level.id == "bathroom_004", "index 13 is the original bathroom")
	_check(gm.level_label.text == "Level 14 — Bathroom", "level 14 label")
	_check_level_walls(data["levels"][13])
	var lvl14: Dictionary = data["levels"][13]
	_apply_solution(lvl14)
	_check(gm.won, "win detected for level 14 solution")
	_check(int(lvl14["min_rotations_required"]) >= 1,
			"level 14 cannot be won without rotation (solver-verified)")
	_check(_solution_uses_rotation(lvl14),
			"level 14 reference solution actually rotates pieces")
	_check(gm.skill_tracker.clean_clear_streak == 2
			and gm.skill_tracker.skill == "lv3",
			"lv3 needs 3 clean clears: streak 2 does not upgrade yet")

	# Level 19 (index 18, generator hard_05) sits mid-sequence: Next shows.
	gm._load_level(18)
	_check(gm.level.id == "closet_run_019", "index 18 is the generator hard_05")
	_check_level_walls(data["levels"][18])
	_apply_solution(data["levels"][18])
	_check(gm.won, "win detected for level 19 solution")
	_check(gm.next_button.visible and not gm.home_button.visible,
			"mid-sequence level 19 offers Next, not Home")
	_check(gm.skill_tracker.skill == "lv4"
			and gm.skill_tracker.clean_clear_streak == 0,
			"lv3 upgrade fires on the 3rd consecutive clean clear")

	# Level 20 (index 19, the original attic level) requires rotation.
	gm._load_level(19)
	_check(gm.level.id == "attic_005", "index 19 is the original attic")
	_check(gm.level.mice.size() == 6, "level 20 has 6 mice")
	_check(gm.level_label.text == "Level 20 — Attic", "level 20 label")
	_check(gm.current_variant == "hard"
			and gm.save_data.assigned_variants.get("20") == "hard",
			"level 20 pins the hard variant at skill lv4")
	_check_level_walls(data["levels"][19])
	var lvl20: Dictionary = data["levels"][19]
	_apply_solution(lvl20)
	_check(gm.won, "win detected for level 20 solution")
	_check(int(lvl20["min_rotations_required"]) >= 1,
			"level 20 cannot be won without rotation (solver-verified)")
	_check(_solution_uses_rotation(lvl20),
			"level 20 reference solution actually rotates pieces")
	_check(gm.next_button.visible and not gm.home_button.visible,
			"level 20 win continues to level 21")
	gm._refresh_play_badge()
	_check(_badge_text() == "Level 21",
			"finishing level 20 advances the play pill to Level 21")

	# NEXT continues to the next numbered level.
	gm._next_level()
	_check(gm.level.id == "boiler_room_021", "level 21 loaded")
	_check_level_walls(data["levels"][20])
	_apply_solution(data["levels"][20])
	_check(gm.won, "win detected for level 21 solution")

	# The last catalog level (index 24, night kitchen) shows HOME.
	gm._load_level(24)
	_check(gm.level.id == "night_kitchen_025", "index 24 is the generator super_hard_05")
	_check_level_walls(data["levels"][24])
	_apply_solution(data["levels"][24])
	_check(gm.won, "win detected for level 25 solution")
	_check(not gm.next_button.visible and gm.home_button.visible,
			"last level shows the Home button")
	_check(gm.skill_tracker.skill == "lv4"
			and gm.skill_tracker.clean_clear_streak == 3,
			"lv4 needs 5 clean clears: streak 3 does not upgrade")

	# --- Save file ---------------------------------------------------------
	# The walk persisted every boundary to the isolated smoke save: verify
	# the file content and that a fresh instance restores the same state.
	var saved := SaveData.new()
	saved.path = SMOKE_SAVE_PATH
	_check(saved.load_save(), "progression save file exists and loads")
	_check(saved.user_level_v1 == "lv4"
			and saved.highest_unlocked_level == 26
			and saved.clean_clear_streak == 3,
			"save mirrors the walk's skill, progress and streak")
	var saved_completed: Array = saved.completed_levels
	var expected_completed := [1, 2, 3, 7, 13, 14, 19, 20, 21, 25]
	var completed_ok: bool = saved_completed.size() == expected_completed.size()
	for n in expected_completed:
		completed_ok = completed_ok and saved_completed.has(n)
	_check(completed_ok, "save lists exactly the levels finished in the walk")
	# The walk pinned each adaptive level's variant at first load: L7 while
	# lv2 (easy), L13/L14/L19 while lv3 (medium), L20/L21/L25 while lv4.
	var expected_pins := {"7": "easy", "13": "medium", "14": "medium",
			"19": "medium", "20": "hard", "21": "hard", "25": "hard"}
	_check(saved.assigned_variants == expected_pins,
			"save pins the wall variants chosen during the walk")

	gm._next_level()
	_check(gm.level.id == "kitchen_001", "next wraps back to level 1")

	# --- Home screen play mapping -----------------------------------------
	# The walk finished levels {0,1,2,6,12,13,18,19,20,24}; highest unlocked
	# is 26, clamped to the catalog: the pill continues at Level 25.
	gm._refresh_play_badge()
	_check(_badge_text() == "Level 25",
			"play pill reflects the walk's progress (clamped at catalog end)")
	gm.play_button.pressed.emit()
	_check(gm.level_index == 24 and gm.level.id == "night_kitchen_025",
			"play button continues at its pill level")
	gm.home_button.pressed.emit()
	_check(gm.menu_open and gm.home_panel.visible,
			"home button returns to the title screen")

	# A progression beyond the catalog (all levels finished) still clamps.
	gm.highest_unlocked_level = LevelLoader.level_count() + 10
	gm._show_home()
	_check(_badge_text() == "Level 25",
			"finished progression clamps to the last catalog level")
	gm.play_button.pressed.emit()
	_check(gm.level_index == 24,
			"play button replays the last level when the catalog is exhausted")

	# Replaying an already completed level never counts as new progression:
	# the skill state must be untouched by the repeated win.
	_apply_solution(data["levels"][24])
	_check(gm.won and gm.skill_tracker.skill == "lv4"
			and gm.skill_tracker.clean_clear_streak == 3,
			"replaying a completed level does not affect the skill rating")

	# --- Wall variants end-to-end -----------------------------------------
	# Level 1 is already completed, so this win cannot perturb the skill
	# state checked above. The easy variant adds hint walls; the reference
	# solution must still be droppable and win through the real input path.
	gm._load_level(0)
	var base_walls: Array = gm.level.walls.duplicate()
	gm.level.walls = gm.level.get_wall_variant("easy")
	_apply_solution(data["levels"][0])
	_check(gm.won, "level 1 solution still wins under the easy wall variant")
	gm.level.walls = base_walls

	# --- Adaptive variant selection ---------------------------------------
	# Levels 1-4 are non-adaptive: even at maximum skill they play the base
	# configuration and never pin an assignment.
	gm.skill_tracker.skill = "lv5"
	gm._load_level(3)
	_check(gm.current_variant == "medium"
			and not gm.save_data.assigned_variants.has("4"),
			"levels 1-4 stay on the base configuration at any skill")
	# An unassigned adaptive level takes the CURRENT skill's variant...
	gm._load_level(4)
	_check(gm.current_variant == "hard"
			and gm.save_data.assigned_variants.get("5") == "hard"
			and gm.active_walls.size() == gm.level.get_wall_variant("hard").size(),
			"level 5 pins the current skill's variant on first load")
	# ...and a pinned level never re-pins when the skill changes.
	gm.skill_tracker.skill = "lv1"
	gm._load_level(4)
	_check(gm.current_variant == "hard",
			"a pinned level keeps its variant after a skill change")
	gm._load_level(24)
	_check(gm.current_variant == "hard",
			"level 25 replays its pinned hard variant at any skill")
	gm._load_level(0)
	_check(gm.current_variant == "medium",
			"level 1 stays on the base configuration")

	# --- Debug overlay -----------------------------------------------------
	# The tracker sits at lv1 (set above) on level 1 (medium variant).
	var f1 := InputEventKey.new()
	f1.keycode = KEY_F1
	f1.pressed = true
	gm._unhandled_input(f1)
	_check(gm.debug_overlay.is_open()
			and gm.debug_overlay.last_text.contains("skill lv1")
			and gm.debug_overlay.last_text.contains("variant medium")
			and gm.debug_overlay.last_text.contains("category normal"),
			"F1 shows the readout with skill, variant and level category")
	_check(gm.debug_overlay.last_text.contains("changes:"),
			"readout lists the walk's skill changes with reasons")
	gm._unhandled_input(f1)
	_check(not gm.debug_overlay.is_open(), "F1 toggles the overlay back off")
	# The toggle is handled before the modal guards: it works on the home
	# screen too.
	gm._show_home()
	gm._unhandled_input(f1)
	_check(gm.debug_overlay.is_open(), "F1 also works on the home screen")
	gm._unhandled_input(f1)
	# The floating side button toggles the same panel.
	gm.debug_overlay.toggle_button.pressed.emit()
	_check(gm.debug_overlay.is_open(), "side button opens the overlay")
	gm.debug_overlay.toggle_button.pressed.emit()
	_check(not gm.debug_overlay.is_open(), "side button closes the overlay")

	# --- Debug controls --------------------------------------------------
	# Skill override mirrors a real tier change (streak/window reset), is
	# logged and persisted, and never rewrites pinned level variants.
	gm.skill_tracker.clean_clear_streak = 1
	gm.skill_tracker.results_since_skill_change = [1]
	gm.debug_set_skill("lv3")
	_check(gm.skill_tracker.skill == "lv3"
			and gm.skill_tracker.clean_clear_streak == 0
			and gm.skill_tracker.results_since_skill_change.is_empty()
			and gm.skill_tracker.change_log[-1].get("reason") == "debug override"
			and gm.save_data.user_level_v1 == "lv3",
			"debug skill override sets the tier, resets history and logs it")
	# A wall preview only re-draws the board; playing a variant swaps the
	# gameplay walls for the session without touching the save's pins.
	gm._load_level(0)
	var pins_before: Dictionary = gm.save_data.assigned_variants.duplicate()
	var medium_edges: Dictionary = PlacementValidator.walls_from_pairs(
			gm.level.get_wall_variant("medium"))
	gm.debug_preview_variant("easy")
	_check(gm.preview_variant == "easy"
			and gm.current_variant == "medium"
			and gm.wall_edges == medium_edges,
			"variant preview changes only the drawing, not the gameplay walls")
	gm.debug_play_variant("hard")
	_check(gm.current_variant == "hard"
			and gm.preview_variant == ""
			and gm.active_walls == gm.level.get_wall_variant("hard")
			and gm.save_data.assigned_variants == pins_before,
			"playing a variant applies it session-only (save pins untouched)")
	# Level jump loads any catalog level through the real path (level 6
	# was never loaded in this run, so it pins the current skill's
	# variant) without granting progression.
	gm.debug_set_skill("lv4")
	var unlocked_before: int = gm.highest_unlocked_level
	gm.debug_jump_to_level(6)
	_check(gm.level_index == 5
			and gm.current_variant == "hard"
			and gm.save_data.assigned_variants.get("6") == "hard"
			and gm.highest_unlocked_level == unlocked_before
			and not gm.menu_open,
			"level jump loads a fresh level and pins its variant, no unlock")
	# Simulated clears replay the solver solution through the real win
	# path: two clean clears from lv1 upgrade the tier...
	gm.debug_set_skill("lv1")
	gm.debug_jump_to_level(8)
	gm.debug_simulate_clear(false)
	_check(gm.won and gm.skill_tracker.clean_clear_streak == 1
			and gm.save_data.completed_levels.has(8)
			and gm.highest_unlocked_level >= 9,
			"simulated clean clear wins through the real completion path")
	gm.debug_jump_to_level(9)
	gm.debug_simulate_clear(false)
	_check(gm.won and gm.skill_tracker.skill == "lv2"
			and gm.skill_tracker.change_log[-1].get("to") == "lv2",
			"two consecutive simulated clean clears upgrade the tier")
	# ...while restarting first marks the completion as problematic.
	gm.debug_jump_to_level(10)
	gm.debug_simulate_clear(true)
	_check(gm.won and gm.skill_tracker.clean_clear_streak == 0
			and gm.skill_tracker.results_since_skill_change == [1]
			and gm.skill_tracker.skill == "lv2",
			"a restarted simulated clear is recorded as problematic")
	# Abandoning mirrors the real quit flow: the attempt is marked, the
	# home screen shows, and no skill result is recorded.
	gm.debug_jump_to_level(11)
	gm.debug_abandon_level()
	_check(gm.menu_open and gm.home_panel.visible
			and gm.attempt_restarted
			and gm.skill_tracker.results_since_skill_change == [1]
			and not gm.save_data.completed_levels.has(11),
			"abandoning marks the attempt and records no skill result")
	# Resetting wipes the save and restores the fresh-player state.
	gm.debug_reset_progression()
	_check(gm.skill_tracker.skill == "lv2"
			and gm.highest_unlocked_level == 1
			and gm.level_index == 0
			and gm.menu_open
			and gm.save_data.assigned_variants.is_empty()
			and FileAccess.file_exists(SMOKE_SAVE_PATH),
			"progression reset restores the fresh-player state and re-saves")
	# The overlay exposes the control rows wired to those helpers.
	_check(gm.debug_overlay._level_picker.item_count == LevelLoader.level_count()
			and gm.debug_overlay._skill_buttons.size() == 5
			and gm.debug_overlay._variant_buttons.size() == 3,
			"debug panel exposes skill, variant and level controls")

	SaveData.delete_file(SMOKE_SAVE_PATH)
	print("== %d failure(s) ==" % failures)
	quit(1 if failures > 0 else 0)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _find_piece(id: String) -> PuzzlePiece:
	for p in gm.pieces:
		if p.definition.id == id:
			return p
	return null


func _badge_text() -> String:
	## Text shown on the Play button's progress pill.
	return (gm.play_badge.get_child(0) as Label).text


func _check_level_walls(lvl: Dictionary) -> void:
	## The level file's wall hints must match the solver-designed walls.
	var expected: Array = lvl.get("walls", [])
	var level_walls: Array[Vector2i] = gm.level.walls
	var walls_match: bool = level_walls.size() == expected.size()
	if walls_match:
		for i in expected.size():
			var cell: Vector2i = level_walls[i]
			if cell.x != int(expected[i][0]) or cell.y != int(expected[i][1]):
				walls_match = false
				break
	_check(walls_match, "level walls match solver design for '%s'" % lvl["id"])


func _wall_key(a: Vector2i, b: Vector2i) -> String:
	## Order-independent key for one wall pair (a shared cell edge).
	var ka := "%d,%d" % [a.x, a.y]
	var kb := "%d,%d" % [b.x, b.y]
	if a.x < b.x or (a.x == b.x and a.y <= b.y):
		return ka + "|" + kb
	return kb + "|" + ka


func _wall_set(flat: Array) -> Dictionary:
	## Normalized set of wall-pair keys from a flat Vector2i pair list.
	var set := {}
	for i in range(0, flat.size(), 2):
		set[_wall_key(flat[i], flat[i + 1])] = true
	return set


func _placement_owners(entry: Dictionary) -> Dictionary:
	## Board cell "x,y" -> owning piece id for the reference solution.
	var owner := {}
	for pid in entry["placements"]:
		for c in entry["placements"][pid]:
			owner["%d,%d" % [int(c[0]), int(c[1])]] = pid
	return owner


func _piece_center(p: PuzzlePiece) -> Vector2:
	## Press point on a cell the piece actually occupies (the bbox center
	## can fall inside a notch for non-rectangular pieces).
	var cells_arr: Array[Vector2i] = p.definition.get_cells_rotated(p.orientation)
	var c: Vector2i = cells_arr[0]
	return p.global_position \
			+ (Vector2(c) + Vector2(0.5, 0.5)) * (PuzzlePiece.CELL_PX * p.scale.x)


func _mouse_event(pressed: bool, pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	gm._unhandled_input(ev)


func _mouse_move(pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	ev.position = pos
	gm._unhandled_input(ev)


func _drag_to(p: PuzzlePiece, cell: Vector2i) -> void:
	var start := _piece_center(p)
	_mouse_event(true, start)
	var target: Vector2 = gm.board.cell_to_world(cell) + gm.grab_offset
	_mouse_move(start.lerp(target, 0.5))
	_mouse_move(target)
	_mouse_event(false, target)


func _tap(p: PuzzlePiece) -> void:
	var pos := _piece_center(p)
	_mouse_event(true, pos)
	_mouse_event(false, pos)


func _swipe_tray(start: Vector2, dx: float) -> void:
	## Simulate a horizontal tray swipe: press, move sideways in steps,
	## release (no tap, no piece drag).
	_mouse_event(true, start)
	var steps := 4
	for i in range(1, steps + 1):
		_mouse_move(start + Vector2(dx * i / float(steps), 0.0))
	_mouse_event(false, start + Vector2(dx, 0.0))


func _solution_uses_rotation(lvl: Dictionary) -> bool:
	## True when the replayed solution places at least one piece in a
	## non-default orientation (i.e. the player must rotate to win).
	for pid in lvl["rotations"]:
		if int(lvl["rotations"][pid]) != 0:
			return true
	return false


func _apply_solution(lvl: Dictionary) -> void:
	for pid in lvl["placements"]:
		var p: PuzzlePiece = _find_piece(pid)
		var cells: Array = lvl["placements"][pid]
		var min_x: int = cells[0][0]
		var min_y: int = cells[0][1]
		for c in cells:
			min_x = mini(min_x, c[0])
			min_y = mini(min_y, c[1])
		p.set_orientation(int(lvl["rotations"][pid]))
		p.board_position = Vector2i(min_x, min_y)
		p.placed = true
	gm._refresh_all_pieces()
	gm._check_win()


func _verify_solution_cells(lvl: Dictionary) -> void:
	## Cross-check: GDScript placement math must match the Python solver.
	for pid in lvl["placements"]:
		var p: PuzzlePiece = _find_piece(pid)
		var expected: Array = lvl["placements"][pid]
		var got: Array[Vector2i] = PlacementValidator.get_world_cells(
				p.definition, p.orientation, p.board_position)
		var cells_match := got.size() == expected.size()
		if cells_match:
			for c in expected:
				if not got.has(Vector2i(c[0], c[1])):
					cells_match = false
		_check(cells_match, "GDScript cells match solver for piece '%s'" % pid)

