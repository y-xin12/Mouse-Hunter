class_name PuzzlePiece
extends Node2D
## Visual and interactive representation of one puzzle piece.
## Builds its texture procedurally from PieceDefinition so the opaque cells
## and transparent circular openings always match the gameplay data.
## Hit-testing is done in cell space (no physics bodies needed).

@onready var sprite: Sprite2D = $Sprite

## Base texture resolution per board cell.
const CELL_PX := 96
const BORDER_PX := 9
const HOLE_RADIUS_PX := 34
const HOLE_RING_PX := 9

var definition: PieceDefinition
## Orientation index 0..3 (90-degree clockwise steps). NOT named `rotation`
## to avoid clashing with Node2D's own `rotation` property.
var orientation := 0
## Board cell where the piece's local (0, 0) cell sits while placed.
var board_position := Vector2i(-1, -1)
var placed := false


func setup(def: PieceDefinition) -> void:
	definition = def
	orientation = 0
	placed = false
	board_position = Vector2i(-1, -1)
	_rebuild_texture()


func set_orientation(new_orientation: int) -> void:
	orientation = posmod(new_orientation, 4)
	_rebuild_texture()


func _rebuild_texture() -> void:
	if definition == null:
		return
	var size_cells := definition.get_size_rotated(orientation)
	var img := Image.create_empty(size_cells.x * CELL_PX, size_cells.y * CELL_PX,
			false, Image.FORMAT_RGBA8)
	_paint_cells(img)
	_punch_holes(img)
	sprite.texture = ImageTexture.create_from_image(img)



func _paint_cells(img: Image) -> void:
	var cells_arr: Array[Vector2i] = definition.get_cells_rotated(orientation)
	var cell_set := {}
	for c in cells_arr:
		cell_set[c] = true
	var border_col := definition.color.darkened(0.45)
	for c in cells_arr:
		var rect := Rect2i(c.x * CELL_PX, c.y * CELL_PX, CELL_PX, CELL_PX)
		img.fill_rect(rect, border_col)
		# Inset the inner fill only on silhouette edges so cells that touch
		# inside the same piece stay visually joined.
		var left := 0 if cell_set.has(c + Vector2i.LEFT) else BORDER_PX
		var right := 0 if cell_set.has(c + Vector2i.RIGHT) else BORDER_PX
		var top := 0 if cell_set.has(c + Vector2i.UP) else BORDER_PX
		var bottom := 0 if cell_set.has(c + Vector2i.DOWN) else BORDER_PX
		var inner := Rect2i(
				rect.position + Vector2i(left, top),
				Vector2i(CELL_PX - left - right, CELL_PX - top - bottom))
		img.fill_rect(inner, definition.color)


func _punch_holes(img: Image) -> void:
	## Real see-through circles: pixels inside the radius become fully
	## transparent (a darker ring around the rim keeps the hole readable).
	var openings_arr: Array[Vector2i] = definition.get_openings_rotated(orientation)
	var ring_col := definition.color.darkened(0.45)
	for o in openings_arr:
		var cx := float(o.x * CELL_PX) + CELL_PX * 0.5
		var cy := float(o.y * CELL_PX) + CELL_PX * 0.5
		var x0 := maxi(0, int(cx - HOLE_RADIUS_PX) - 1)
		var y0 := maxi(0, int(cy - HOLE_RADIUS_PX) - 1)
		var x1 := mini(img.get_width() - 1, int(cx + HOLE_RADIUS_PX) + 1)
		var y1 := mini(img.get_height() - 1, int(cy + HOLE_RADIUS_PX) + 1)
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var d := Vector2(x - cx, y - cy).length()
				if d <= HOLE_RADIUS_PX:
					if d > HOLE_RADIUS_PX - HOLE_RING_PX:
						img.set_pixel(x, y, ring_col)
					else:
						img.set_pixel(x, y, Color(0, 0, 0, 0))


func is_point_inside(world_point: Vector2) -> bool:
	## True when the point (in world/canvas space) lands on one of this
	## piece's cells. Accounts for the node's current scale.
	if definition == null:
		return false
	var local := to_local(world_point)
	var cell := Vector2i(floor(local.x / CELL_PX), floor(local.y / CELL_PX))
	return definition.get_cells_rotated(orientation).has(cell)
