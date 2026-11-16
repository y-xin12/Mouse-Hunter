class_name BoardController
extends Node2D
## Presentation of the puzzle board: a rounded wooden frame, cream floor
## tiles, texture-based hidden mice and the drag preview overlay. Also owns
## board-space <-> world-space conversion for the current layout.
##
## Mice are drawn by this node so they always render BELOW the pieces (the
## Pieces node is later in the scene tree) and only show through a piece's
## transparent openings. All geometry is derived from board_size, cell_px and
## board_origin, so any board dimension / resolution is supported.

## Mouse head art. The task-specified path is tried first; the repository's
## supplied art lives at res://assets/Mice/mouse.png, so that is used as a
## fallback. If none exists the procedural placeholder is drawn and a warning
## identifies the missing asset.
const MOUSE_TEXTURE_PATHS := [
	"res://assets/mice/mouse_head.png",
	"res://assets/Mice/mouse_head.png",
	"res://assets/Mice/mouse.png",
]

## Extra border room reserved around the playable cells for the wooden frame.
const FRAME_PAD := 22.0

# Warm palette.
const WOOD_DARK := Color(0.66, 0.42, 0.20)
const WOOD := Color(0.80, 0.55, 0.30)
const INNER_SHADOW := Color(0.35, 0.22, 0.10, 0.28)
const FLOOR := Color(0.86, 0.72, 0.54)
const TILE_LIGHT := Color(0.985, 0.93, 0.83)
const TILE_ALT := Color(0.965, 0.90, 0.79)
const PREVIEW_OK := Color(0.35, 0.80, 0.40, 0.50)
const PREVIEW_BAD := Color(0.90, 0.30, 0.25, 0.50)
const PREVIEW_HOLE := Color(1, 1, 1, 0.8)

var board_size := Vector2i(4, 6)
var mice: Array[Vector2i] = []
var cell_px := 128.0
## World position of board cell (0, 0).
var board_origin := Vector2.ZERO

var preview_cells: Array[Vector2i] = []
var preview_openings: Array[Vector2i] = []
var preview_legal := false

var _box: StyleBoxFlat
var _mouse_texture: Texture2D = null
var _mouse_texture_checked := false


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


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	_ensure_styles()
	_draw_frame()
	_draw_tiles()
	_draw_mice()
	_draw_preview()


func _ensure_styles() -> void:
	if _box == null:
		_box = StyleBoxFlat.new()
		_box.anti_aliasing = true


func _draw_box(rect: Rect2, color: Color, radius: int,
		shadow_size := 0, shadow_color := Color(0, 0, 0, 0),
		shadow_offset := Vector2.ZERO,
		border := 0, border_color := Color(0, 0, 0, 0)) -> void:
	_box.bg_color = color
	_box.set_corner_radius_all(radius)
	_box.shadow_size = shadow_size
	_box.shadow_color = shadow_color
	_box.shadow_offset = shadow_offset
	_box.border_width_left = border
	_box.border_width_top = border
	_box.border_width_right = border
	_box.border_width_bottom = border
	_box.border_color = border_color
	draw_style_box(_box, rect)


func _draw_frame() -> void:
	var frame := frame_rect()
	# Outer dark rim with a soft drop shadow (raised, beveled look).
	_draw_box(frame, WOOD_DARK, 34, 12, Color(0.32, 0.20, 0.08, 0.22), Vector2(0, 7))
	# Lighter wood body, inset so the darker outer edge stays visible.
	_draw_box(frame.grow(-5.0), WOOD, 30)
	# Recess shadow around the playable area for a slightly sunken floor.
	_draw_box(board_rect().grow(7.0), INNER_SHADOW, 18)
	# Cream floor.
	_draw_box(board_rect().grow(2.0), FLOOR, 16)


func _draw_tiles() -> void:
	var inset := 1.5
	for y in board_size.y:
		for x in board_size.x:
			var r := Rect2(board_origin + Vector2(x, y) * cell_px,
					Vector2(cell_px, cell_px)).grow(-inset)
			var shade := TILE_LIGHT if (x + y) % 2 == 0 else TILE_ALT
			_draw_box(r, shade, 7)


func _draw_preview() -> void:
	if preview_cells.is_empty():
		return
	var col := PREVIEW_OK if preview_legal else PREVIEW_BAD
	for c in preview_cells:
		if _is_cell_in_bounds(c):
			var r := Rect2(board_origin + Vector2(c) * cell_px,
					Vector2(cell_px, cell_px)).grow(-3.0)
			_draw_box(r, col, 8)
	for o in preview_openings:
		if _is_cell_in_bounds(o):
			var center := cell_to_world(o) + Vector2(cell_px, cell_px) * 0.5
			draw_arc(center, cell_px * 0.28, 0.0, TAU, 28, PREVIEW_HOLE, 3.0, true)


func _is_cell_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 \
			and cell.x < board_size.x and cell.y < board_size.y


func _draw_mice() -> void:
	var tex := _get_mouse_texture()
	for m in mice:
		if not _is_cell_in_bounds(m):
			continue
		var center := cell_to_world(m) + Vector2(cell_px, cell_px) * 0.5
		# Soft ground shadow under the mouse.
		draw_set_transform(center + Vector2(0, cell_px * 0.28), 0.0,
				Vector2(1.0, 0.42))
		draw_circle(Vector2.ZERO, cell_px * 0.24, Color(0.30, 0.20, 0.10, 0.16))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if tex != null:
			_draw_mouse_texture(tex, center)
		else:
			_draw_mouse_placeholder(center)


func _draw_mouse_texture(tex: Texture2D, center: Vector2) -> void:
	# Fit the sprite into ~78% of the cell, preserving aspect ratio and
	# keeping it centered so mice stay aligned after any resize.
	var box := cell_px * 0.78
	var aspect := float(tex.get_width()) / float(tex.get_height())
	var w := box
	var h := box
	if aspect > 1.0:
		h = box / aspect
	else:
		w = box * aspect
	var dest := Rect2(center - Vector2(w, h) * 0.5, Vector2(w, h))
	draw_texture_rect(tex, dest, false)


func _draw_mouse_placeholder(center: Vector2) -> void:
	## Procedural fallback used only when no mouse texture could be loaded.
	const BODY := Color(0.62, 0.62, 0.66)
	const EAR := Color(0.72, 0.72, 0.76)
	const EAR_INNER := Color(0.95, 0.65, 0.72)
	const EYE := Color(0.12, 0.12, 0.14)
	const NOSE := Color(0.95, 0.55, 0.65)

	var r := cell_px * 0.30
	var ear_r := r * 0.42
	draw_circle(center + Vector2(-r * 0.62, -r * 0.62), ear_r, EAR)
	draw_circle(center + Vector2(r * 0.62, -r * 0.62), ear_r, EAR)
	draw_circle(center + Vector2(-r * 0.62, -r * 0.62), ear_r * 0.5, EAR_INNER)
	draw_circle(center + Vector2(r * 0.62, -r * 0.62), ear_r * 0.5, EAR_INNER)
	draw_circle(center, r, BODY)
	draw_circle(center + Vector2(-r * 0.34, -r * 0.1), r * 0.12, EYE)
	draw_circle(center + Vector2(r * 0.34, -r * 0.1), r * 0.12, EYE)
	draw_circle(center + Vector2(0, r * 0.3), r * 0.16, NOSE)


func _get_mouse_texture() -> Texture2D:
	if _mouse_texture_checked:
		return _mouse_texture
	_mouse_texture_checked = true
	for path in MOUSE_TEXTURE_PATHS:
		if ResourceLoader.exists(path):
			var loaded = load(path)
			if loaded is Texture2D:
				_mouse_texture = loaded
				return _mouse_texture
	push_warning("BoardController: no mouse texture found. Import a mouse "
			+ "head at res://assets/mice/mouse_head.png "
			+ "(or res://assets/Mice/mouse.png). Using placeholder for now.")
	return null