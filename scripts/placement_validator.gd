class_name PlacementValidator
extends RefCounted
## Pure board-space placement rules: bounds, overlap, walls, coverage and
## mouse reveal checks. Deterministic cell math only -- no rendering, no
## scenes.
## Mirrors tests/level_solver.py so solver-verified levels stay valid.

const ROTATION_STEPS := 4


static func get_world_cells(piece: PieceDefinition, orientation: int,
		board_pos: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in piece.get_cells_rotated(orientation):
		out.append(board_pos + c)
	return out


static func get_world_openings(piece: PieceDefinition, orientation: int,
		board_pos: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for o in piece.get_openings_rotated(orientation):
		out.append(board_pos + o)
	return out


static func is_in_bounds(world_cells: Array[Vector2i],
		board_size: Vector2i) -> bool:
	for c in world_cells:
		if c.x < 0 or c.y < 0 or c.x >= board_size.x or c.y >= board_size.y:
			return false
	return true


static func has_no_overlap(world_cells: Array[Vector2i],
		occupied: Dictionary) -> bool:
	for c in world_cells:
		if occupied.has(c):
			return false
	return true


## Build the wall-edge lookup used by is_placement_legal. `pairs` is a flat
## list of adjacent cells (a1, b1, a2, b2, ...): the edge shared by each
## pair becomes a wall no single piece may cross.
static func walls_from_pairs(pairs: Array) -> Dictionary:
	var walls := {}
	if pairs.size() % 2 != 0:
		push_warning("PlacementValidator: odd wall pair list, last cell ignored")
	var i := 0
	while i + 1 < pairs.size():
		walls[_edge_key(pairs[i], pairs[i + 1])] = true
		i += 2
	return walls


## True when no two cells in `world_cells` are separated by a walled edge.
static func crosses_no_wall(world_cells: Array[Vector2i],
		walls: Dictionary) -> bool:
	if walls.is_empty():
		return true
	var cell_set := {}
	for c in world_cells:
		cell_set[c] = true
	for c in world_cells:
		var right := c + Vector2i.RIGHT
		var down := c + Vector2i.DOWN
		if cell_set.has(right) and walls.has(_edge_key(c, right)):
			return false
		if cell_set.has(down) and walls.has(_edge_key(c, down)):
			return false
	return true


## Canonical dictionary key for the edge shared by two adjacent cells.
static func _edge_key(a: Vector2i, b: Vector2i) -> String:
	var lo := a
	var hi := b
	if b.x < a.x or (b.x == a.x and b.y < a.y):
		lo = b
		hi = a
	return "%d,%d|%d,%d" % [lo.x, lo.y, hi.x, hi.y]


static func is_placement_legal(piece: PieceDefinition, orientation: int,
		board_pos: Vector2i, board_size: Vector2i,
		occupied: Dictionary, walls: Dictionary = {}) -> bool:
	var wc := get_world_cells(piece, orientation, board_pos)
	return is_in_bounds(wc, board_size) and has_no_overlap(wc, occupied) \
			and crosses_no_wall(wc, walls)


## Build a map of occupied board cells -> piece from every placed piece.
## `placed_pieces` holds PuzzlePiece nodes (with .definition, .orientation,
## .board_position and .placed). `exclude` skips one piece (used while it
## is being dragged or rotated).
static func get_occupied_cells(placed_pieces: Array, exclude: Node = null) -> Dictionary:
	var occ := {}
	for p in placed_pieces:
		if not p.placed or p == exclude:
			continue
		for c in get_world_cells(p.definition, p.orientation, p.board_position):
			occ[c] = p
	return occ


## True when the placed pieces cover every board cell exactly once.
static func is_board_covered(placed_pieces: Array, board_size: Vector2i) -> bool:
	var covered := {}
	for p in placed_pieces:
		if not p.placed:
			continue
		for c in get_world_cells(p.definition, p.orientation, p.board_position):
			if covered.has(c):
				return false
			covered[c] = true
	return covered.size() == board_size.x * board_size.y


## Mice that are visible through a placed piece's opening right now.
static func get_revealed_mice(placed_pieces: Array,
		mice: Array[Vector2i]) -> Array[Vector2i]:
	var openings := {}
	for p in placed_pieces:
		if not p.placed:
			continue
		for o in get_world_openings(p.definition, p.orientation, p.board_position):
			openings[o] = true
	var revealed: Array[Vector2i] = []
	for m in mice:
		if openings.has(m):
			revealed.append(m)
	return revealed


## Win: every piece placed legally, board fully covered, all mice revealed.
static func is_win(placed_pieces: Array, total_pieces: int,
		board_size: Vector2i, mice: Array[Vector2i]) -> bool:
	var placed_count := 0
	for p in placed_pieces:
		if p.placed:
			placed_count += 1
	if placed_count != total_pieces:
		return false
	if not is_board_covered(placed_pieces, board_size):
		return false
	return get_revealed_mice(placed_pieces, mice).size() == mice.size()
