extends Node2D
## Root game flow: level loading, piece instancing, responsive layout,
## drag/tap input, grid snapping, win detection and HUD wiring.
## The HUD itself is authored in scenes/main.tscn (no UI built in code);
## this script only references those nodes and connects their signals.
## Touch input reaches this script as emulated mouse events (Godot's
## default emulate_mouse_from_touch), so one code path serves both inputs.

const PIECE_SCENE := preload("res://scenes/puzzle_piece.tscn")
const TAP_MAX_MOVE := 16.0
const TAP_MAX_SECONDS := 0.45
## Design-time vertical space for the header, instruction and goal labels.
## Doubles as the minimum HUD zone; the live zone scales with canvas height.
const TOP_HUD_HEIGHT := 150.0
## Share of the canvas height given to the HUD zone (150px on the 1280px
## design canvas) so the HUD grows on tall screens like the board does.
const TOP_HUD_ZONE_RATIO := 150.0 / 1280.0
## Fraction of the remaining height given to the board (rest is the tray).
const BOARD_ZONE_RATIO := 0.7
const SCREEN_MARGIN := 8.0
const Z_PLACED := 5
const Z_DRAGGING := 100
## Piece slots visible in the tray carousel at once.
const TRAY_VISIBLE_SLOTS := 3
## Extra horizontal inset of the tray from the usable area's edges, so the
## tray reads as a distinct strip narrower than the board zone.
const TRAY_SIDE_MARGIN := 24.0
## Vertical gap between the board zone and the top of the tray. Sized to
## fit a one-line label (e.g. a "find all the mice" hint panel) with margins
## between the board frame and the tray, should one be added there.
const TRAY_TOP_GAP := 56.0
## A swipe on the tray becomes a scroll (instead of a piece drag) when it
## is this much more horizontal than vertical.
const TRAY_SCROLL_DRAG_BIAS := 1.25
## Scroll speed (canvas px/s) a release must exceed to keep gliding.
const TRAY_MOMENTUM_MIN := 140.0
## Exponential glide friction (higher = the carousel stops sooner).
const TRAY_FRICTION := 4.5

@onready var board: BoardController = %Board
@onready var pieces_root: Node2D = %Pieces
@onready var tray_backdrop = %TrayBackdrop
@onready var tray_clip: Control = %TrayClip
@onready var level_label: Label = %LevelLabel
@onready var goal_label: Label = %GoalLabel
@onready var reset_button: Button = %ResetButton
@onready var win_panel: Control = %WinPanel
@onready var win_subtitle: Label = %WinSubtitle
@onready var next_button: Button = %NextButton
@onready var top_bar: Control = %TopBar
@onready var hint_label: Label = %HintLabel
@onready var goal_panel: Control = %GoalPanel
@onready var win_label: Label = %WinLabel
@onready var restart_button: Button = %RestartButton

var level: LevelDefinition
var level_index := 0
var pieces: Array = []  # Array of PuzzlePiece

var board_scale := 1.0
var tray_rect := Rect2()
## Carousel tray: width of one slot, and the ONE scale shared by every
## tray piece so all pieces render the same size no matter their shape or
## rotation.
var tray_slot_w := 0.0
var tray_piece_scale := 1.0
## Horizontal carousel offset (how far the slot row is scrolled) plus
## swipe / glide state.
var tray_scroll := 0.0
var tray_scroll_velocity := 0.0
var tray_scroll_active := false
## True while a press on a tray piece may still turn into a tray swipe.
var tray_press_armed := false
var tray_last_pos := Vector2.ZERO
var tray_last_time := 0.0
## Wall edges for the current level, as a PlacementValidator lookup built
## from level.walls.
var wall_edges := {}

var dragging: PuzzlePiece = null
var selected: PuzzlePiece = null
var grab_offset := Vector2.ZERO
var press_position := Vector2.ZERO
var press_time := 0.0
var moved_far := false
var won := false


func _ready() -> void:
	get_viewport().size_changed.connect(_layout)
	reset_button.pressed.connect(_reset_level)
	%RestartButton.pressed.connect(_reset_level)
	next_button.pressed.connect(_next_level)
	_load_level(0)


func _load_level(index: int) -> void:
	level_index = index
	level = LevelLoader.load_level(index)
	if level == null:
		push_error("GameManager: level %d failed to load" % index)
		return
	won = false
	dragging = null
	selected = null
	for p in pieces:
		p.queue_free()
	pieces.clear()
	board.setup(level.board_size, level.mice, level.walls)
	wall_edges = PlacementValidator.walls_from_pairs(level.walls)
	for def in level.pieces:
		var pp: PuzzlePiece = PIECE_SCENE.instantiate()
		pieces_root.add_child(pp)
		pp.setup(def)
		pieces.append(pp)
	level_label.text = "Level %d — %s" % [index + 1, level.get_room_title()]
	goal_label.text = "FIND ALL %d MICE" % level.mice.size()
	win_panel.visible = false
	board.clear_preview()
	tray_scroll = 0.0
	tray_scroll_velocity = 0.0
	tray_scroll_active = false
	_layout()


# ---------------------------------------------------------------------------
# Responsive layout (board on top, piece tray below; recomputed on resize)
# ---------------------------------------------------------------------------

func _layout() -> void:
	if level == null or board == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var vp_x: float = max(vp.x, 320.0)
	var vp_y: float = max(vp.y, 480.0)
	# The HUD zone takes a fixed SHARE of the canvas height (never less than
	# the 150px design reservation) and its contents scale with it, so text
	# and panels grow on tall screens exactly like the board and tray.
	var hud_h: float = maxf(vp_y * TOP_HUD_ZONE_RATIO, TOP_HUD_HEIGHT)
	_layout_hud(hud_h / TOP_HUD_HEIGHT)
	# Reserve room for the wooden frame so it never overlaps the header/tray.
	var frame_pad: float = BoardController.FRAME_PAD
	var usable := Rect2(Vector2(SCREEN_MARGIN, hud_h),
			Vector2(vp_x - SCREEN_MARGIN * 2.0, vp_y - hud_h - SCREEN_MARGIN))
	var board_zone_h: float = usable.size.y * BOARD_ZONE_RATIO
	var max_board_w: float = max(usable.size.x - frame_pad * 2.0, 32.0)
	var max_board_h: float = max(board_zone_h - frame_pad * 2.0, 32.0)
	var cell := max_board_w / level.board_size.x
	cell = min(cell, max_board_h / level.board_size.y)
	cell = clamp(cell, 24.0, 512.0)
	board_scale = cell / PuzzlePiece.CELL_PX
	var board_size_px := Vector2(level.board_size) * cell
	var origin := usable.position + Vector2(
			(usable.size.x - board_size_px.x) * 0.5,
			(board_zone_h - board_size_px.y) * 0.5)
	board.layout(origin, cell)
	var tray_top: float = usable.position.y + board_zone_h + TRAY_TOP_GAP
	tray_rect = Rect2(Vector2(usable.position.x + TRAY_SIDE_MARGIN, tray_top),
			Vector2(usable.size.x - TRAY_SIDE_MARGIN * 2.0,
					max(usable.end.y - tray_top - 4.0, 40.0)))
	if tray_backdrop != null:
		tray_backdrop.set_rect(tray_rect)
	# Resting pieces are clipped to the tray's cream interior so a scrolled
	# piece slides UNDER the wooden frame instead of floating over it.
	var clip_rect := tray_rect.grow(-TrayBackdrop.INNER_INSET)
	tray_clip.position = clip_rect.position
	tray_clip.size = clip_rect.size
	# Carousel tray geometry: one row of equal slots and one shared piece
	# scale, derived from the worst-case piece extents over EVERY rotation
	# so rotating a tray piece never changes its rendered size.
	tray_slot_w = tray_rect.size.x / TRAY_VISIBLE_SLOTS
	var max_cells := Vector2i.ZERO
	for pd in level.pieces:
		for o in PieceDefinition.ROTATION_STEPS:
			var s: Vector2i = pd.get_size_rotated(o)
			max_cells.x = maxi(max_cells.x, s.x)
			max_cells.y = maxi(max_cells.y, s.y)
	tray_piece_scale = minf(
			tray_slot_w * 0.88 / (max_cells.x * PuzzlePiece.CELL_PX),
			tray_rect.size.y * 0.88 / (max_cells.y * PuzzlePiece.CELL_PX))
	tray_piece_scale = minf(tray_piece_scale, board_scale)
	_set_tray_scroll(tray_scroll)
	_refresh_all_pieces()


func _layout_hud(s: float) -> void:
	## Scale the scene-authored HUD (fixed pixel metrics on the 720x1280
	## design canvas) by s = live HUD zone / design HUD zone. Fonts get
	## per-control theme overrides so the scene keeps its design values.
	top_bar.offset_top = 8.0 * s
	top_bar.offset_bottom = 74.0 * s
	level_label.add_theme_font_size_override("font_size", _fs(26.0, s))
	reset_button.add_theme_font_size_override("font_size", _fs(20.0, s))
	hint_label.offset_top = 78.0 * s
	hint_label.offset_bottom = 104.0 * s
	hint_label.add_theme_font_size_override("font_size", _fs(18.0, s))
	goal_panel.offset_left = -110.0 * s
	goal_panel.offset_top = 112.0 * s
	goal_panel.offset_right = 110.0 * s
	goal_panel.offset_bottom = 144.0 * s
	goal_label.add_theme_font_size_override("font_size", _fs(16.0, s))
	win_panel.offset_left = -200.0 * s
	win_panel.offset_top = -150.0 * s
	win_panel.offset_right = 200.0 * s
	win_panel.offset_bottom = 150.0 * s
	win_label.add_theme_font_size_override("font_size", _fs(34.0, s))
	win_subtitle.add_theme_font_size_override("font_size", _fs(22.0, s))
	restart_button.add_theme_font_size_override("font_size", _fs(22.0, s))
	next_button.add_theme_font_size_override("font_size", _fs(22.0, s))


func _fs(base: float, s: float) -> int:
	## Font sizes are integer theme overrides; never emit a zero size.
	return maxi(1, int(roundf(base * s)))


# ---------------------------------------------------------------------------
# Carousel tray: horizontal swipe scrolling with glide momentum
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if tray_scroll_velocity != 0.0:
		_integrate_tray_momentum(delta)


func _integrate_tray_momentum(delta: float) -> void:
	## One glide step: momentum moves the row, friction slows it down and
	## clamping at the content edges stops it dead. Split out of _process
	## so tests can drive it deterministically.
	var target: float = tray_scroll + tray_scroll_velocity * delta
	tray_scroll_velocity *= exp(-TRAY_FRICTION * delta)
	if absf(tray_scroll_velocity) < 12.0:
		tray_scroll_velocity = 0.0
	var clamped: float = clampf(target, 0.0, _tray_max_scroll())
	if clamped != target:
		tray_scroll_velocity = 0.0
	if absf(clamped - tray_scroll) > 0.01:
		tray_scroll = clamped
		_update_tray_layout()


func _tray_max_scroll() -> float:
	return maxf(0.0, pieces.size() * tray_slot_w - tray_rect.size.x)


func _set_tray_scroll(value: float) -> void:
	var clamped: float = clampf(value, 0.0, _tray_max_scroll())
	if is_equal_approx(clamped, tray_scroll):
		return
	tray_scroll = clamped
	_update_tray_layout()


func _update_tray_layout() -> void:
	## Re-park every resting tray piece for the current scroll offset
	## (cheap: at most six pieces).
	for p in pieces:
		if p == dragging or p.placed:
			continue
		_apply_tray_slot(p)


func _start_tray_scroll(reference_point: Vector2) -> void:
	## A press on empty tray space: any movement now scrolls the carousel.
	tray_scroll_active = true
	tray_scroll_velocity = 0.0
	tray_last_pos = reference_point
	tray_last_time = Time.get_ticks_msec() / 1000.0


func _convert_press_to_tray_scroll() -> void:
	## A press on a tray piece turned out to be a horizontal swipe: park
	## the piece back in its slot and take over the carousel scroll,
	## counting the swipe from the original press point.
	if dragging != null:
		dragging.set_visual_state(PuzzlePiece.VisualState.NORMAL)
		_apply_tray_slot(dragging)
		dragging = null
	if selected != null:
		selected.set_visual_state(PuzzlePiece.VisualState.NORMAL)
		selected = null
	moved_far = true
	tray_press_armed = false
	_start_tray_scroll(press_position)


func _apply_tray_scroll_delta(world_point: Vector2) -> void:
	var dx := world_point.x - tray_last_pos.x
	var now := Time.get_ticks_msec() / 1000.0
	var dt := now - tray_last_time
	if not is_zero_approx(dx):
		_set_tray_scroll(tray_scroll - dx)
		if dt > 0.005:
			# Smoothed velocity estimate (canvas px/s, leftward positive).
			tray_scroll_velocity = lerpf(
					tray_scroll_velocity, -dx / dt, 0.55)
	tray_last_pos = world_point
	tray_last_time = now


func _end_tray_scroll() -> void:
	tray_scroll_active = false
	# Keep gliding only after a real flick; otherwise stop right here.
	if absf(tray_scroll_velocity) < TRAY_MOMENTUM_MIN:
		tray_scroll_velocity = 0.0


func _refresh_all_pieces() -> void:
	for p in pieces:
		if p == dragging:
			continue
		if p.placed:
			p.z_index = Z_PLACED
			p.scale = Vector2(board_scale, board_scale)
			p.global_position = board.cell_to_world(p.board_position)
			p.visible = true
		else:
			_apply_tray_slot(p)


func _apply_tray_slot(p: PuzzlePiece) -> void:
	## Park an unplaced piece in its carousel slot: a single horizontal row
	## TRAY_VISIBLE_SLOTS wide, scrolled by tray_scroll. Every tray piece
	## uses the one shared tray_piece_scale, so all pieces look the same
	## size no matter their shape or rotation.
	var index := pieces.find(p)
	# Resting pieces live under the tray's clip region (see _layout).
	if p.get_parent() != tray_clip:
		p.reparent(tray_clip)
	var slot_center := Vector2(
			tray_rect.position.x + (index + 0.5) * tray_slot_w - tray_scroll,
			tray_rect.position.y + tray_rect.size.y * 0.5)
	var size_cells := p.definition.get_size_rotated(p.orientation)
	var piece_px := Vector2(size_cells) * (PuzzlePiece.CELL_PX * tray_piece_scale)
	p.z_index = Z_PLACED
	p.scale = Vector2(tray_piece_scale, tray_piece_scale)
	p.global_position = slot_center - piece_px * 0.5
	# Only pieces overlapping the tray's clipped interior are drawn (and
	# can be picked up); the rest wait off to the side until the carousel
	# scrolls them into view. Partially scrolled-in pieces stay visible but
	# are cut off cleanly at the frame by the clip region.
	var clip_rect := Rect2(tray_clip.position, tray_clip.size)
	p.visible = Rect2(p.global_position, piece_px).intersects(clip_rect, false)



# ---------------------------------------------------------------------------
# Input: unified mouse + touch drag, tap-to-rotate, R key rotate
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_press(event.position)
		else:
			_on_release(event.position)
	elif event is InputEventMouseMotion \
			and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) \
			and (dragging != null or tray_scroll_active):
		_on_drag(event.position)
	elif event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_R or event.physical_keycode == KEY_R):
		if selected != null:
			_rotate_piece(selected)
			if not selected.placed and selected != dragging:
				_apply_tray_slot(selected)


func _on_press(world_point: Vector2) -> void:
	# Any new touch takes over the pointer: a gliding tray stops dead, so
	# the carousel can be stopped at any time.
	tray_scroll_velocity = 0.0
	if won or dragging != null:
		return
	var piece := _pick_piece(world_point)
	if piece == null:
		# A press on empty tray space becomes a carousel swipe.
		if tray_rect.has_point(world_point):
			_start_tray_scroll(world_point)
		return
	if selected != null and selected != piece:
		selected.set_visual_state(PuzzlePiece.VisualState.NORMAL)
	selected = piece
	dragging = piece
	# Lift the piece out of the tray's clipped region so it travels freely.
	if piece.get_parent() != pieces_root:
		piece.reparent(pieces_root)
	piece.set_visual_state(PuzzlePiece.VisualState.SELECTED)
	grab_offset = world_point - piece.global_position
	press_position = world_point
	press_time = Time.get_ticks_msec() / 1000.0
	moved_far = false
	# A press on a resting tray piece may still turn into a carousel swipe
	# (see _on_drag); a press on a placed board piece never can.
	tray_press_armed = tray_rect.has_point(world_point) and not piece.placed
	# A placed piece stays placed while it is pressed; it is un-placed only
	# when the press turns into a real drag (see _on_drag) so a quick tap
	# can rotate the piece in place instead of sending it back to the tray.
	var local_point := (world_point - piece.global_position) / piece.scale
	piece.z_index = Z_DRAGGING
	piece.scale = Vector2(board_scale, board_scale)
	# Keep the point under the cursor anchored after the scale change.
	piece.global_position = world_point - local_point * board_scale
	grab_offset = world_point - piece.global_position
	_update_preview()


func _on_drag(world_point: Vector2) -> void:
	if tray_scroll_active:
		_apply_tray_scroll_delta(world_point)
		return
	if dragging == null:
		return
	if world_point.distance_to(press_position) > TAP_MAX_MOVE and not moved_far:
		var dx := world_point.x - press_position.x
		var dy := world_point.y - press_position.y
		# A swipe that started on a tray piece and runs mostly sideways
		# scrolls the carousel instead of dragging the piece.
		if tray_press_armed and absf(dx) > absf(dy) * TRAY_SCROLL_DRAG_BIAS:
			_convert_press_to_tray_scroll()
			return
		moved_far = true
		# The press became a real drag: lift the piece off the board now.
		dragging.placed = false
		dragging.set_visual_state(PuzzlePiece.VisualState.DRAGGING)
	dragging.global_position = world_point - grab_offset
	_update_preview()


func _on_release(world_point: Vector2) -> void:
	if tray_scroll_active:
		_end_tray_scroll()
		return
	if dragging == null:
		return
	var piece := dragging
	dragging = null
	piece.set_visual_state(PuzzlePiece.VisualState.NORMAL)
	var elapsed := Time.get_ticks_msec() / 1000.0 - press_time
	var is_tap := not moved_far and elapsed <= TAP_MAX_SECONDS
	if is_tap:
		_rotate_piece(piece)
		if not piece.placed:
			_apply_tray_slot(piece)
		else:
			# A tapped placed piece stays on the board: restore its resting
			# z-order and re-snap it to its cell.
			piece.z_index = Z_PLACED
			piece.global_position = board.cell_to_world(piece.board_position)
	else:
		_try_place(piece)
	board.clear_preview()
	_check_win()


func _pick_piece(world_point: Vector2) -> PuzzlePiece:
	## Topmost piece under the point (later entries in `pieces` draw on
	## top; pieces scrolled outside the tray window are not pickable).
	for i in range(pieces.size() - 1, -1, -1):
		var p: PuzzlePiece = pieces[i]
		if p.visible and p.is_point_inside(world_point):
			return p
	return null


func _rotate_piece(piece: PuzzlePiece) -> void:
	var new_orientation := (piece.orientation + 1) % 4
	if piece.placed:
		# A placed piece may only rotate if it stays legal where it is.
		var occupied := PlacementValidator.get_occupied_cells(pieces, piece)
		if PlacementValidator.is_placement_legal(piece.definition,
				new_orientation, piece.board_position, level.board_size, occupied,
				wall_edges):
			piece.set_orientation(new_orientation)
			piece.global_position = board.cell_to_world(piece.board_position)
	else:
		piece.set_orientation(new_orientation)


func _try_place(piece: PuzzlePiece) -> void:
	var cell := board.world_to_cell_snapped(piece.global_position)
	var occupied := PlacementValidator.get_occupied_cells(pieces, piece)
	if PlacementValidator.is_placement_legal(piece.definition, piece.orientation,
			cell, level.board_size, occupied, wall_edges):
		piece.placed = true
		piece.board_position = cell
		piece.z_index = Z_PLACED
		piece.visible = true
		piece.scale = Vector2(board_scale, board_scale)
		piece.global_position = board.cell_to_world(cell)
	else:
		# The drop was illegal: the piece returns to the tray un-placed.
		piece.placed = false
		_apply_tray_slot(piece)


func _update_preview() -> void:
	if dragging == null:
		board.clear_preview()
		return
	var cell := board.world_to_cell_snapped(dragging.global_position)
	var world_cells := PlacementValidator.get_world_cells(
			dragging.definition, dragging.orientation, cell)
	var world_openings := PlacementValidator.get_world_openings(
			dragging.definition, dragging.orientation, cell)
	var occupied := PlacementValidator.get_occupied_cells(pieces, dragging)
	var legal := PlacementValidator.is_placement_legal(dragging.definition,
			dragging.orientation, cell, level.board_size, occupied, wall_edges)
	board.set_preview(world_cells, world_openings, legal)



# ---------------------------------------------------------------------------
# Win detection, reset and next-level flow
# ---------------------------------------------------------------------------

func _check_win() -> void:
	if won or level == null:
		return
	if PlacementValidator.is_win(pieces, pieces.size(),
			level.board_size, level.mice):
		won = true
		board.clear_preview()
		var revealed := PlacementValidator.get_revealed_mice(pieces, level.mice)
		win_subtitle.text = "You found all %d mice!" % revealed.size()
		var is_last_level := level_index >= LevelLoader.level_count() - 1
		next_button.text = "Play Again" if is_last_level else "Next Level"
		win_panel.visible = true


func _reset_level() -> void:
	won = false
	dragging = null
	win_panel.visible = false
	board.clear_preview()
	for p in pieces:
		p.placed = false
		p.board_position = Vector2i(-1, -1)
		p.set_orientation(0)
		p.set_visual_state(PuzzlePiece.VisualState.NORMAL)
		p.z_index = Z_PLACED
		_apply_tray_slot(p)


func _next_level() -> void:
	var next := level_index + 1
	if next >= LevelLoader.level_count():
		next = 0
	_load_level(next)
