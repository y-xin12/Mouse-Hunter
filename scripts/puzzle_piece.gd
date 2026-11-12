class_name PuzzlePiece
extends Node2D
## Visual and interactive representation of one puzzle piece.
## Builds its texture procedurally from PieceDefinition so the opaque cells
## and transparent circular openings always match the gameplay data.
## Hit-testing is done in cell space (no physics bodies needed), and the
## interactive/visual states (brightness, lift scale, shadow) live entirely
## on the child sprites so they never affect rotation or placement.

enum VisualState { NORMAL, SELECTED, DRAGGING }

@onready var body_sprite: Sprite2D = $Sprite
@onready var shadow_sprite: Sprite2D = $Shadow

## Base texture resolution per board cell.
const CELL_PX := 96
const CORNER_R := 15.0
const BORDER_PX := 5.0
const BEVEL_PX := 12.0
const HIGHLIGHT_PX := 11.0
const HOLE_RADIUS_PX := 34.0
const HOLE_RING_PX := 8.0
const SHADOW_OFFSET_NORMAL := Vector2(0, 9)
const SHADOW_OFFSET_DRAGGING := Vector2(0, 16)
const DRAG_SCALE := 1.045

var definition: PieceDefinition
## Orientation index 0..3 (90-degree clockwise steps). NOT named `rotation`
## to avoid clashing with Node2D's own `rotation` property.
var orientation := 0
## Board cell where the piece's local (0, 0) cell sits while placed.
var board_position := Vector2i(-1, -1)
var placed := false
var visual_state: int = VisualState.NORMAL

var _tex_size := Vector2.ZERO


func setup(def: PieceDefinition) -> void:
	_resolve_nodes()
	definition = def
	orientation = 0
	placed = false
	board_position = Vector2i(-1, -1)
	visual_state = VisualState.NORMAL
	_rebuild_texture()


func set_orientation(new_orientation: int) -> void:
	orientation = posmod(new_orientation, 4)
	_rebuild_texture()


func set_visual_state(state: int) -> void:
	visual_state = state
	_apply_visual_state()


func _resolve_nodes() -> void:
	if body_sprite == null:
		body_sprite = get_node_or_null("Sprite")
	if shadow_sprite == null:
		shadow_sprite = get_node_or_null("Shadow")


func _rebuild_texture() -> void:
	if definition == null:
		return
	var size_cells := definition.get_size_rotated(orientation)
	if size_cells.x <= 0 or size_cells.y <= 0:
		return
	var img := Image.create_empty(size_cells.x * CELL_PX, size_cells.y * CELL_PX,
			false, Image.FORMAT_RGBA8)
	_paint_cells(img)
	_draw_paw(img)
	_punch_holes(img)
	_tex_size = Vector2(img.get_width(), img.get_height())
	body_sprite.texture = ImageTexture.create_from_image(img)
	if shadow_sprite != null:
		shadow_sprite.texture = ImageTexture.create_from_image(_make_shadow(img))
	_apply_sprite_transform()
	_apply_visual_state()


func _apply_sprite_transform() -> void:
	var center := _tex_size * 0.5
	body_sprite.centered = true
	body_sprite.position = center
	if shadow_sprite != null:
		shadow_sprite.centered = true
		shadow_sprite.position = center


func _apply_visual_state() -> void:
	if body_sprite == null:
		return
	var s := 1.0
	var tint := Color.WHITE
	var shadow_alpha := 0.18
	var shadow_off := SHADOW_OFFSET_NORMAL
	match visual_state:
		VisualState.SELECTED:
			tint = Color(1.14, 1.14, 1.14)
			shadow_alpha = 0.22
			shadow_off = SHADOW_OFFSET_NORMAL + Vector2(0, 2)
		VisualState.DRAGGING:
			s = DRAG_SCALE
			tint = Color(1.06, 1.06, 1.06)
			shadow_alpha = 0.30
			shadow_off = SHADOW_OFFSET_DRAGGING
	body_sprite.scale = Vector2(s, s)
	body_sprite.modulate = tint
	if shadow_sprite != null:
		shadow_sprite.scale = Vector2(s, s)
		shadow_sprite.modulate = Color(1, 1, 1, shadow_alpha)
		shadow_sprite.position = _tex_size * 0.5 + shadow_off


func _pastel(base: Color) -> Color:
	var c := Color(base.r, base.g, base.b)
	return c.lerp(Color(1, 1, 1), 0.15)


func _paint_cells(img: Image) -> void:
	var cells_arr: Array[Vector2i] = definition.get_cells_rotated(orientation)
	var cell_set := {}
	for c in cells_arr:
		cell_set[c] = true
	var body := _pastel(definition.color)
	var border_col := body.darkened(0.30)
	var bevel_col := body.darkened(0.12)
	var highlight_col := body.lightened(0.35)
	for c in cells_arr:
		var base_x := c.x * CELL_PX
		var base_y := c.y * CELL_PX
		var exp_n := not cell_set.has(c + Vector2i.UP)
		var exp_s := not cell_set.has(c + Vector2i.DOWN)
		var exp_w := not cell_set.has(c + Vector2i.LEFT)
		var exp_e := not cell_set.has(c + Vector2i.RIGHT)
		# Only round a corner that is convex (both adjacent cells missing),
		# so cells that touch inside the piece stay visually merged.
		var round_tl := exp_n and exp_w
		var round_tr := exp_n and exp_e
		var round_bl := exp_s and exp_w
		var round_br := exp_s and exp_e
		for ly in CELL_PX:
			for lx in CELL_PX:
				var px := lx + 0.5
				var py := ly + 0.5
				if not _corner_keeps(px, py, round_tl, round_tr, round_bl, round_br):
					continue
				var d_top := py if exp_n else INF
				var d_bot := (CELL_PX - py) if exp_s else INF
				var d_left := px if exp_w else INF
				var d_right := (CELL_PX - px) if exp_e else INF
				var near_edge: float = min(min(d_top, d_bot), min(d_left, d_right))
				var col := body
				if near_edge < BORDER_PX:
					col = border_col
				elif d_bot < BEVEL_PX or d_right < BEVEL_PX * 0.6:
					col = bevel_col
				elif d_top < HIGHLIGHT_PX:
					col = highlight_col
				img.set_pixel(base_x + lx, base_y + ly, col)


func _corner_keeps(px: float, py: float, tl: bool, tr: bool,
		bl: bool, br: bool) -> bool:
	var r := CORNER_R
	if tl and px < r and py < r:
		return Vector2(px - r, py - r).length() <= r
	if tr and px > CELL_PX - r and py < r:
		return Vector2(px - (CELL_PX - r), py - r).length() <= r
	if bl and px < r and py > CELL_PX - r:
		return Vector2(px - r, py - (CELL_PX - r)).length() <= r
	if br and px > CELL_PX - r and py > CELL_PX - r:
		return Vector2(px - (CELL_PX - r), py - (CELL_PX - r)).length() <= r
	return true


func _punch_holes(img: Image) -> void:
	## Real see-through circles: pixels inside the radius become fully
	## transparent (a darker rim keeps the hole readable) so the mouse drawn
	## by BoardController shows through.
	var openings_arr: Array[Vector2i] = definition.get_openings_rotated(orientation)
	var ring_col := _pastel(definition.color).darkened(0.30)
	var r := HOLE_RADIUS_PX
	for o in openings_arr:
		var cx := float(o.x * CELL_PX) + CELL_PX * 0.5
		var cy := float(o.y * CELL_PX) + CELL_PX * 0.5
		var x0 := maxi(0, int(cx - r) - 1)
		var y0 := maxi(0, int(cy - r) - 1)
		var x1 := mini(img.get_width() - 1, int(cx + r) + 1)
		var y1 := mini(img.get_height() - 1, int(cy + r) + 1)
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var d := Vector2(x + 0.5 - cx, y + 0.5 - cy).length()
				if d <= r:
					if d > r - HOLE_RING_PX:
						img.set_pixel(x, y, ring_col)
					else:
						img.set_pixel(x, y, Color(0, 0, 0, 0))


func _draw_paw(img: Image) -> void:
	## Small paw-print detail in a filled cell away from the opening, only
	## where there is room for it. Purely decorative.
	var cells_arr: Array[Vector2i] = definition.get_cells_rotated(orientation)
	if cells_arr.is_empty():
		return
	var openings_arr: Array[Vector2i] = definition.get_openings_rotated(orientation)
	var opening_cell := Vector2i(-999, -999)
	if not openings_arr.is_empty():
		opening_cell = openings_arr[0]
	var target := cells_arr[0]
	var best := -INF
	for c in cells_arr:
		if c == opening_cell:
			continue
		var score := c.y * 10 + c.x
		if score > best:
			best = score
			target = c
	if target == opening_cell:
		return
	var paw_col := _pastel(definition.color).darkened(0.14)
	var center := Vector2(target.x * CELL_PX + CELL_PX * 0.5,
			target.y * CELL_PX + CELL_PX * 0.5)
	var s := CELL_PX * 0.30
	_fill_circle(img, center + Vector2(0, s * 0.28), s * 0.42, paw_col)
	_fill_circle(img, center + Vector2(-s * 0.42, -s * 0.28), s * 0.20, paw_col)
	_fill_circle(img, center + Vector2(0, -s * 0.48), s * 0.20, paw_col)
	_fill_circle(img, center + Vector2(s * 0.42, -s * 0.28), s * 0.20, paw_col)


func _fill_circle(img: Image, center: Vector2, radius: float, color: Color) -> void:
	var x0 := maxi(0, int(center.x - radius))
	var y0 := maxi(0, int(center.y - radius))
	var x1 := mini(img.get_width() - 1, int(center.x + radius) + 1)
	var y1 := mini(img.get_height() - 1, int(center.y + radius) + 1)
	var r2 := radius * radius
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx := x + 0.5 - center.x
			var dy := y + 0.5 - center.y
			if dx * dx + dy * dy <= r2:
				img.set_pixel(x, y, color)


func _make_shadow(img: Image) -> Image:
	## Solid black silhouette of the piece (holes stay transparent) used as a
	## soft drop shadow behind the body sprite.
	var w := img.get_width()
	var h := img.get_height()
	var sh := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.4:
				sh.set_pixel(x, y, Color(0, 0, 0, 1))
	return sh


func is_point_inside(world_point: Vector2) -> bool:
	## True when the point (in world/canvas space) lands on one of this
	## piece's cells. Accounts for the node's current scale.
	if definition == null:
		return false
	var local := to_local(world_point)
	var cell := Vector2i(floor(local.x / CELL_PX), floor(local.y / CELL_PX))
	return definition.get_cells_rotated(orientation).has(cell)