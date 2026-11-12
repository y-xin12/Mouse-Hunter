class_name PieceDefinition
extends Resource
## Data definition of a puzzle piece: opaque cells plus circular openings.
## Rendering-independent. All rotation math lives here so gameplay code
## stays deterministic in board space (y-down grid, 90° CW steps).

@export var id: String = ""
@export var display_name: String = ""
@export var color: Color = Color.WHITE
@export var cells: Array[Vector2i] = []
@export var openings: Array[Vector2i] = []

const ROTATION_STEPS := 4


static func _rotate_cw(cell: Vector2i, times: int) -> Vector2i:
	var r := cell
	for _i in range(times % ROTATION_STEPS):
		r = Vector2i(-r.y, r.x)
	return r


func get_cells_rotated(rotation: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in cells:
		out.append(_rotate_cw(c, rotation))
	if not out.is_empty():
		var min_v := _min_of(out)
		for i in out.size():
			out[i] = out[i] - min_v
	return out


func get_openings_rotated(rotation: int) -> Array[Vector2i]:
	var rotated: Array[Vector2i] = []
	for c in cells:
		rotated.append(_rotate_cw(c, rotation))
	var min_v := _min_of(rotated)
	var out: Array[Vector2i] = []
	for o in openings:
		out.append(_rotate_cw(o, rotation) - min_v)
	return out


func get_size_rotated(rotation: int) -> Vector2i:
	## Bounding-box size in cells of the piece at a given rotation.
	var rc := get_cells_rotated(rotation)
	if rc.is_empty():
		return Vector2i.ZERO
	var max_x := rc[0].x
	var max_y := rc[0].y
	for c in rc:
		max_x = maxi(max_x, c.x)
		max_y = maxi(max_y, c.y)
	return Vector2i(max_x + 1, max_y + 1)


static func _min_of(cell_list: Array[Vector2i]) -> Vector2i:
	var min_x := cell_list[0].x
	var min_y := cell_list[0].y
	for c in cell_list:
		min_x = mini(min_x, c.x)
		min_y = mini(min_y, c.y)
	return Vector2i(min_x, min_y)
