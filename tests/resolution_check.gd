extends SceneTree
## Headless responsive-layout regression test for Mouse-Hunter.
## Run:  <godot> --headless --path . --script res://tests/resolution_check.gd
## Exits with code 0 when all checks pass, 1 otherwise.
##
## Verifies the mobile UI across window sizes (720x1280 base, 1080x2400
## and 1440x2960 tall phones):
##   - the project's stretch settings (canvas_items + expand on the
##     720x1280 base) yield a uniform device scale and the expected
##     expanded canvas
##   - board cells stay perfectly square (1:1) at every aspect ratio
##   - the board stays centered, below the HUD and above the tray
##   - simulated drag-and-drop and tap-to-rotate hit exactly at every size
##   - a window resize after load re-runs the responsive layout
##
## `--script` runs bypass the project's window configuration, so the
## stretch settings from project.godot are applied to the root window
## manually before the main scene is measured.

const BASE_SIZE := Vector2(720, 1280)
const TOLERANCE := 0.6

const RESOLUTIONS := [
	Vector2i(720, 1280),   # base portrait phone (project design size)
	Vector2i(1080, 2400),  # 20:9 FHD+ phone
	Vector2i(1440, 2960),  # 18.5:9 tall QHD phone
]

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
	print("== Mouse-Hunter resolution check ==")
	await _prepare_window()
	for res in RESOLUTIONS:
		await _test_resolution(res)
	await _test_live_resize()
	print("== %d failure(s) ==" % failures)
	quit(1 if failures > 0 else 0)


# ---------------------------------------------------------------------------
# Window / stretch setup
# ---------------------------------------------------------------------------

func _prepare_window() -> void:
	## Mirror project.godot's display settings (canvas_items + expand on a
	## 720x1280 base) onto the root window. Warm up first: the headless
	## window can swallow size requests made before it exists.
	await process_frame
	await process_frame
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.content_scale_size = BASE_SIZE


func _set_window_size(sz: Vector2i) -> bool:
	## Request a window size, retrying briefly until it sticks.
	for i in 5:
		root.size = sz
		await process_frame
		await process_frame
		if root.size == sz:
			return true
	return false


# ---------------------------------------------------------------------------
# Per-resolution checks
# ---------------------------------------------------------------------------

func _test_resolution(res: Vector2i) -> void:
	print("-- %d x %d --" % [res.x, res.y])
	var ok := await _set_window_size(res)
	_check(ok, "window resized to %d x %d" % [res.x, res.y])

	# canvas_items + expand math: uniform scale, canvas = window / scale.
	var dev_scale: float = min(res.x / BASE_SIZE.x, res.y / BASE_SIZE.y)
	var expected_canvas: Vector2 = Vector2(res) / dev_scale
	var canvas: Vector2 = root.get_visible_rect().size
	_check(canvas.distance_to(expected_canvas) < TOLERANCE,
		"expanded canvas %s matches window/scale %s"
		% [canvas, expected_canvas])
	var ft := root.get_final_transform().get_scale()
	_check(abs(ft.x - ft.y) < 0.001 and abs(ft.x - dev_scale) < 0.001,
		"device scale uniform at %.2f (got %.3f x %.3f)"
		% [dev_scale, ft.x, ft.y])

	# Fresh main scene so GameManager._layout() runs at this size.
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	gm = main
	_layout_checks(canvas)
	_input_checks()
	main.queue_free()
	await process_frame
	await process_frame



func _layout_checks(canvas: Vector2) -> void:
	var board: BoardController = gm.board
	var board_px: Vector2 = Vector2(gm.level.board_size) * board.cell_px

	# Cells must stay square: cell width == cell height in canvas units.
	var cw: float = board.cell_to_world(Vector2i(1, 1)).x \
			- board.cell_to_world(Vector2i(0, 1)).x
	var ch: float = board.cell_to_world(Vector2i(1, 1)).y \
			- board.cell_to_world(Vector2i(1, 0)).y
	_check(abs(cw / ch - 1.0) < 0.001,
		"cells stay square (aspect %.6f)" % (cw / ch))

	# Board horizontally centered with symmetric side margins.
	_check(abs(board.board_origin.x - (canvas.x - board_px.x) * 0.5)
			< TOLERANCE,
		"board centered (origin.x %.1f, expected ~%.1f)"
		% [board.board_origin.x, (canvas.x - board_px.x) * 0.5])

	# Board frame below the HUD, above the tray, inside the screen.
	var frame: Rect2 = board.frame_rect()
	_check(frame.position.y >= gm.TOP_HUD_HEIGHT - TOLERANCE,
		"frame below the HUD (y %.1f)" % frame.position.y)
	_check(frame.end.y <= gm.tray_rect.position.y + TOLERANCE,
		"frame does not overlap the tray")
	_check(frame.position.x >= 0.0 and frame.end.x <= canvas.x,
		"frame fits the screen width")

	# Pieces keep a uniform scale (never stretched into rectangles).
	var p: PuzzlePiece = gm.pieces[0]
	_check(abs(p.scale.x - p.scale.y) < 0.0001,
		"piece scale uniform (%.3f x %.3f)" % [p.scale.x, p.scale.y])


func _input_checks() -> void:
	## Drag-and-drop and tap-to-rotate must still align exactly at this
	## window size: input positions are canvas-space, so the hit math must
	## line up with the drawn board at every resolution.
	var board: BoardController = gm.board
	var piece: PuzzlePiece = _find_piece("square")

	# (1, 2) is the square's spot in the level 1 reference tiling, so the
	# drop stays legal with the level's wall hints active.
	_drag_to(piece, Vector2i(1, 2))
	_check(piece.placed and piece.board_position == Vector2i(1, 2),
		"drag lands the square on cell (1, 2)")
	_check(piece.global_position.distance_to(
			board.cell_to_world(Vector2i(1, 2))) < 0.01,
		"dragged piece snaps exactly to its cell")

	# Tap on the placed piece rotates it in place without un-placing.
	var orientation_before := piece.orientation
	_tap(piece)
	_check(piece.placed and piece.board_position == Vector2i(1, 2),
		"tap keeps the placed piece on the board")
	_check(piece.orientation == posmod(orientation_before + 1, 4),
		"tap rotates the placed piece in place")

	# A tap slightly off-center inside a cell still hits the piece.
	var cells_arr: Array[Vector2i] = \
			piece.definition.get_cells_rotated(piece.orientation)
	var c: Vector2i = cells_arr[0]
	var off_center: Vector2 = piece.global_position \
			+ (Vector2(c) + Vector2(0.35, 0.35)) \
			* (PuzzlePiece.CELL_PX * piece.scale.x)
	_mouse_event(true, off_center)
	_mouse_event(false, off_center)
	_check(piece.placed and piece.orientation
			== posmod(orientation_before + 2, 4),
		"off-center tap inside the cell still hits the piece")


func _test_live_resize() -> void:
	## A window resize after load must re-run the layout (GameManager
	## connects the viewport's size_changed signal to _layout): simulates
	## moving from a 720p phone to a tall QHD phone mid-game.
	print("-- live resize 720x1280 -> 1440x2960 --")
	await _set_window_size(Vector2i(720, 1280))
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	gm = main
	var small_cell: float = gm.board.cell_px

	await _set_window_size(Vector2i(1440, 2960))
	await process_frame
	await process_frame
	_check(gm.board.cell_px > small_cell,
		"layout recomputed after resize (cell %.1f -> %.1f)"
		% [small_cell, gm.board.cell_px])
	var canvas: Vector2 = root.get_visible_rect().size
	var board_px: Vector2 = Vector2(gm.level.board_size) * gm.board.cell_px
	_check(abs(gm.board.board_origin.x - (canvas.x - board_px.x) * 0.5)
			< TOLERANCE, "board re-centered after resize")
	_check(gm.board.frame_rect().end.y <= gm.tray_rect.position.y
			+ TOLERANCE, "no tray overlap after resize")
	main.queue_free()
	await process_frame
	await process_frame


# ---------------------------------------------------------------------------
# Helpers (mirrored from tests/smoke_test.gd)
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