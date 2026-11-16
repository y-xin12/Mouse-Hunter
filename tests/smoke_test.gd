extends SceneTree
## Headless smoke test for the Mouse-Hunter MVP.
## Run:  <godot> --headless --path . --script res://tests/smoke_test.gd
## Exits with code 0 when all checks pass, 1 otherwise.
## Uses tests/solutions.json (written by tests/level_solver.py) to replay
## solver-verified solutions and cross-check GDScript vs Python cell math.

const SOLUTIONS_PATH := "res://tests/solutions.json"

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
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	# Node _ready runs on the first process frame, not during add_child in
	# _initialize, so let two frames pass before inspecting game state.
	await process_frame
	await process_frame
	gm = main
	_check(gm.level != null, "level 1 loaded")
	_check(gm.pieces.size() == 6, "6 pieces instanced")
	_check(LevelLoader.level_count() == 5, "5 levels discovered")
	_check(gm.level.mice.size() == 3, "level 1 has 3 mice")
	_check(gm.level_label.text == "Level 1 — Kitchen", "level label text")
	_check(gm.menu_open and gm.home_panel.visible, "home screen shown on boot")
	_check(_badge_text(0) == "LV 1" and _badge_text(1) == "LV 2"
			and _badge_text(2) == "LV 3" and _badge_text(3) == "LV 5",
			"chips show each difficulty's first level on a fresh game")
	gm.home_panel.get_node("EasyButton").pressed.emit()
	_check(not gm.home_panel.visible and not gm.menu_open,
			"difficulty button closes the home screen")
	_check(gm.level_index == 0, "easy starts at level 1")
	_check(not gm.win_panel.visible, "popup stays hidden until the level is complete")

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
	# Hook lives in slot 4, beyond the visible window. A horizontal swipe
	# starting on a tray piece (the plank) must scroll the carousel instead
	# of dragging the piece, and bring hook into view.
	_check(not hook.visible, "hook hidden before scrolling")
	_swipe_tray(_piece_center(plank), -1.4 * gm.tray_slot_w)
	_check(gm.tray_scroll > 0.0, "swipe scrolled the tray")
	_check(not plank.placed and plank.visible,
			"swiped piece stayed parked in the tray")
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
			1.4 * gm.tray_slot_w)
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
	var data: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string(SOLUTIONS_PATH))
	_check(not data.is_empty(), "solutions.json parsed")
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
	_check(gm.win_panel.stars[0].earned and gm.win_panel.stars[1].earned
			and gm.win_panel.stars[2].earned,
			"clean run reveals three stars")
	_check(not gm.next_button.visible and gm.home_button.visible,
			"easy group ends with the Home button")
	gm._refresh_home_badges()
	_check(_badge_text(0) == "LV 2" and _badge_text(1) == "LV 2",
			"finishing level 1 advances the easy chip to LV 2")

	# --- Reset -----------------------------------------------------------
	gm._reset_level()
	var any_placed := false
	for p in gm.pieces:
		if p.placed:
			any_placed = true
	_check(not any_placed and not gm.win_panel.visible, "reset clears board")

	# --- Level navigation --------------------------------------------------
	gm._next_level()
	_check(gm.level.id == "living_room_002", "next level loaded")
	_check(gm.level.mice.size() == 5, "level 2 has 5 mice")
	_check(gm.level_label.text == "Level 2 — Living Room", "level 2 label")
	_check_level_walls(data["levels"][1])
	_apply_solution(data["levels"][1])
	_check(gm.won, "win detected for level 2 solution")
	gm._refresh_home_badges()
	_check(_badge_text(1) == "LV 3",
			"finishing level 2 advances the medium chip to LV 3")

	gm._next_level()
	_check(gm.level.id == "bedroom_003", "level 3 loaded")
	_check_level_walls(data["levels"][2])
	_apply_solution(data["levels"][2])
	_check(gm.won, "win detected for level 3 solution")
	_check(gm.next_button.visible and not gm.home_button.visible,
			"hard group continues to the next level")

	# --- Rotation-required levels 4 and 5 ---------------------------------
	gm._next_level()
	_check(gm.level.id == "bathroom_004", "level 4 loaded")
	_check(gm.level_label.text == "Level 4 — Bathroom", "level 4 label")
	_check_level_walls(data["levels"][3])
	var lvl4: Dictionary = data["levels"][3]
	_apply_solution(lvl4)
	_check(gm.won, "win detected for level 4 solution")
	_check(not gm.next_button.visible and gm.home_button.visible,
			"hard group ends with the Home button")
	gm._refresh_home_badges()
	_check(_badge_text(2) == "LV 5",
			"finishing the hard group advances its chip to LV 5")
	_check(int(lvl4["min_rotations_required"]) >= 1,
			"level 4 cannot be won without rotation (solver-verified)")
	_check(_solution_uses_rotation(lvl4),
			"level 4 reference solution actually rotates pieces")

	gm._next_level()
	_check(gm.level.id == "attic_005", "level 5 loaded")
	_check(gm.level.mice.size() == 6, "level 5 has 6 mice")
	_check_level_walls(data["levels"][4])
	var lvl5: Dictionary = data["levels"][4]
	_apply_solution(lvl5)
	_check(gm.won, "win detected for level 5 solution")
	_check(int(lvl5["min_rotations_required"]) >= 1,
			"level 5 cannot be won without rotation (solver-verified)")
	_check(_solution_uses_rotation(lvl5),
			"level 5 reference solution actually rotates pieces")
	_check(not gm.next_button.visible and gm.home_button.visible,
			"last level shows the Home button")
	gm._refresh_home_badges()
	_check(_badge_text(3) == "UNAVAIL" and gm.difficulty_buttons[3].disabled,
			"finishing the last level marks super hard UNAVAIL and disables it")

	gm._next_level()
	_check(gm.level.id == "kitchen_001", "next wraps back to level 1")

	# --- Home screen difficulty mapping -----------------------------------
	gm._refresh_home_badges()
	_check(_badge_text(0) == "LV 2" and _badge_text(1) == "LV 3"
			and _badge_text(2) == "LV 5" and _badge_text(3) == "UNAVAIL",
			"home chips reflect the finished game")
	gm.home_panel.get_node("SuperHardButton").pressed.emit()
	_check(gm.level_index == 0, "unavailable difficulty loads nothing")
	gm.home_panel.get_node("EasyButton").pressed.emit()
	_check(gm.level_index == 1, "finished easy continues at level 2")
	gm.home_button.pressed.emit()
	_check(gm.menu_open and gm.home_panel.visible,
			"home button returns to the difficulty selection")

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


func _badge_text(i: int) -> String:
	## Text shown on the i-th difficulty button's progress chip.
	return (gm.difficulty_badges[i].get_child(0) as Label).text


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

