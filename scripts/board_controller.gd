class_name BoardController
extends Node2D
## Draws the board frame, grid, placeholder mice and the drag preview
## overlay. Owns board-space <-> world-space conversion for the current
## layout. Mice are drawn by this node so they always render BELOW the
## pieces (the Pieces node is later in the scene tree) and only show
## through a piece's transparent openings.

const FRAME_COLOR := Color(0.42, 0.27, 0.15)
const BOARD_COLOR := Color(0.97, 0.91, 0.79)
const GRID_COLOR := Color(0.85, 0.76, 0.61)
const PREVIEW_OK := Color(0.25, 0.75, 0.3, 0.45)
const PREVIEW_BAD := Color(0.9, 0.25, 0.2, 0.45)
const PREVIEW_HOLE := Color(1, 1, 1, 0.7)
const FRAME_PAD := 14.0

var board_size := Vector2i(4, 6)
var mice: Array[Vector2i] = []
var cell_px := 128.0
## World position of board cell (0, 0).
var board_origin := Vector2.ZERO

var preview_cells: Array[Vector2i] = []
var preview_openings: Array[Vector2i] = []
var preview_legal := false


func setup(size: Vector2i, level_mice: Array[Vector2i]) -> void:
	board_size = size
	mice = level_mice.duplicate()
	preview_cells = []
	preview_openings = []
	queue_redraw()


func layout(origin: Vector2, cell: float) -> void:
	board_origin = origin
	cell_px = max(cell, 16.0)
	queue_redraw()


func board_rect() -> Rect2:
	return Rect2(board_origin, Vector2(board_size) * cell_px)


func frame_rect() -> Rect2:
	return board_rect().grow(FRAME_PAD)


func cell_to_world(cell: Vector2i) -> Vector2:
	return board_origin + Vector2(cell) * cell_px


func world_to_cell_snapped(world_point: Vector2) -> Vector2i:
	## Board cell whose top-left is closest to the given world point.
	var rel := world_point - board_origin + Vector2(cell_px * 0.5, cell_px * 0.5)
	return Vector2i(floor(rel.x / cell_px), floor(rel.y / cell_px))


func is_world_point_on_board(world_point: Vector2) -> bool:
	return board_rect().has_point(world_point)


func set_preview(cells: Array[Vector2i], openings: Array[Vector2i], legal: bool) -> void:
	preview_cells = cells
	preview_openings = openings
	preview_legal = legal
	queue_redraw()


func clear_preview() -> void:
	preview_cells = []
	preview_openings = []
	queue_redraw()


func _draw() -> void:
	draw_rect(frame_rect(), FRAME_COLOR)
	draw_rect(board_rect(), BOARD_COLOR)

	# Grid lines.
	var board_end := board_origin + Vector2(board_size) * cell_px
	for x in board_size.x + 1:
		var gx := board_origin.x + x * cell_px
		draw_line(Vector2(gx, board_origin.y), Vector2(gx, board_end.y), GRID_COLOR, 2.0)
	for y in board_size.y + 1:
		var gy := board_origin.y + y * cell_px
		draw_line(Vector2(board_origin.x, gy), Vector2(board_end.x, gy), GRID_COLOR, 2.0)

	# Hidden mice (below pieces; visible only through openings).
	for m in mice:
		_draw_mouse(cell_to_world(m) + Vector2(cell_px, cell_px) * 0.5)

	# Drag preview overlay.
	if not preview_cells.is_empty():
		var col := PREVIEW_OK if preview_legal else PREVIEW_BAD
		for c in preview_cells:
			if _is_cell_in_bounds(c):
				var r := Rect2(board_origin + Vector2(c) * cell_px,
						Vector2(cell_px, cell_px))
				draw_rect(r, col)
		for o in preview_openings:
			if _is_cell_in_bounds(o):
				draw_circle(cell_to_world(o) + Vector2(cell_px, cell_px) * 0.5,
						cell_px * 0.18, PREVIEW_HOLE)


func _is_cell_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 \
			and cell.x < board_size.x and cell.y < board_size.y


func _draw_mouse(center: Vector2) -> void:
	## Placeholder cartoon mouse drawn procedurally (original art later).
	const BODY := Color(0.62, 0.62, 0.66)
	const EAR := Color(0.72, 0.72, 0.76)
	const EAR_INNER := Color(0.95, 0.65, 0.72)
	const EYE := Color(0.12, 0.12, 0.14)
	const NOSE := Color(0.95, 0.55, 0.65)

	var r := cell_px * 0.30
	var ear_r := r * 0.42
	# Ears behind the body.
	draw_circle(center + Vector2(-r * 0.62, -r * 0.62), ear_r, EAR)
	draw_circle(center + Vector2(r * 0.62, -r * 0.62), ear_r, EAR)
	draw_circle(center + Vector2(-r * 0.62, -r * 0.62), ear_r * 0.5, EAR_INNER)
	draw_circle(center + Vector2(r * 0.62, -r * 0.62), ear_r * 0.5, EAR_INNER)
	# Body.
	draw_circle(center, r, BODY)
	# Face.
	draw_circle(center + Vector2(-r * 0.34, -r * 0.1), r * 0.12, EYE)
	draw_circle(center + Vector2(r * 0.34, -r * 0.1), r * 0.12, EYE)
	draw_circle(center + Vector2(0, r * 0.3), r * 0.16, NOSE)
