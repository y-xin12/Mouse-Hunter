class_name PlacementValidator
extends RefCounted
## Pure board-space placement rules: bounds, overlap, coverage and mouse
## reveal checks. Deterministic cell math only -- no rendering, no scenes.
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


static func is_placement_legal(piece: PieceDefinition, orientation: int,
		board_pos: Vector2i, board_size: Vector2i,
		occupied: Dictionary) -> bool:
	var wc := get_world_cells(piece, orientation, board_pos)
	return is_in_bounds(wc, board_size) and has_no_overlap(wc, occupied)


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
