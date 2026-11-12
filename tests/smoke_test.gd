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

	# --- Drag & drop via simulated input events ------------------------
	_drag_to(piece, Vector2i(0, 0))
	_check(piece.placed and piece.board_position == Vector2i(0, 0),
			"drag placed square at (0, 0)")
	_check(piece.global_position == gm.board.cell_to_world(Vector2i(0, 0)),
			"piece snapped to cell position")

	var plank: PuzzlePiece = _find_piece("plank")
	_drag_to(plank, Vector2i(0, 0))
	_check(not plank.placed, "overlapping drop rejected (plank over square)")

	var hook: PuzzlePiece = _find_piece("hook")
	var old_orientation := hook.orientation
	_tap(hook)
	_check(hook.orientation == posmod(old_orientation + 1, 4),
			"tap rotates tray piece")
	_check(not hook.placed, "tap-rotated piece parked in tray")

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


	# --- Win flow replaying the solver-verified solution ----------------
	gm._reset_level()
	var data: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string(SOLUTIONS_PATH))
	_check(not data.is_empty(), "solutions.json parsed")
	var lvl1: Dictionary = data["levels"][0]
	_apply_solution(lvl1)
	_verify_solution_cells(lvl1)
	_check(gm.won, "win detected for solver solution (level 1)")
	_check(gm.win_panel.visible, "win panel shown")
	_check(gm.win_subtitle.text == "You found all 3 mice!", "win subtitle text")
	_check(gm.next_button.text == "Next Level", "next button text")

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
	_apply_solution(data["levels"][1])
	_check(gm.won, "win detected for level 2 solution")

	gm._next_level()
	_check(gm.level.id == "bedroom_003", "level 3 loaded")
	_apply_solution(data["levels"][2])
	_check(gm.won, "win detected for level 3 solution")

	# --- Rotation-required levels 4 and 5 ---------------------------------
	gm._next_level()
	_check(gm.level.id == "bathroom_004", "level 4 loaded")
	_check(gm.level_label.text == "Level 4 — Bathroom", "level 4 label")
	var lvl4: Dictionary = data["levels"][3]
	_apply_solution(lvl4)
	_check(gm.won, "win detected for level 4 solution")
	_check(int(lvl4["min_rotations_required"]) >= 1,
			"level 4 cannot be won without rotation (solver-verified)")
	_check(_solution_uses_rotation(lvl4),
			"level 4 reference solution actually rotates pieces")

	gm._next_level()
	_check(gm.level.id == "attic_005", "level 5 loaded")
	_check(gm.level.mice.size() == 6, "level 5 has 6 mice")
	var lvl5: Dictionary = data["levels"][4]
	_apply_solution(lvl5)
	_check(gm.won, "win detected for level 5 solution")
	_check(int(lvl5["min_rotations_required"]) >= 1,
			"level 5 cannot be won without rotation (solver-verified)")
	_check(_solution_uses_rotation(lvl5),
			"level 5 reference solution actually rotates pieces")
	_check(gm.next_button.text == "Play Again", "last level button text")

	gm._next_level()
	_check(gm.level.id == "kitchen_001", "next wraps back to level 1")

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

