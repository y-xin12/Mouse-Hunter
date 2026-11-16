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
## Vertical space reserved for the header, instruction and goal labels.
const TOP_HUD_HEIGHT := 150.0
## Fraction of the remaining height given to the board (rest is the tray).
const BOARD_ZONE_RATIO := 0.7
const SCREEN_MARGIN := 8.0
const Z_PLACED := 5
const Z_DRAGGING := 100
## Starting level for each home-screen difficulty button (Easy, Medium, Hard,
## Super Hard). Level 4 (index 3) is reached by playing on from Hard.
const DIFFICULTY_LEVELS := [0, 1, 2, 4]
## Width of the home-screen design space. The menu is authored at this width
## and scaled to the real canvas (project stretch/scale makes the canvas
## narrower than the 720 px design), so it keeps the reference proportions.
const MENU_DESIGN_WIDTH := 720.0
## Extra drags allowed before the star rating drops from three to two.
const STAR_2_EXTRA_MOVES := 3

@onready var board: BoardController = %Board
@onready var pieces_root: Node2D = %Pieces
@onready var tray_backdrop = %TrayBackdrop
@onready var level_label: Label = %LevelLabel
@onready var goal_label: Label = %GoalLabel
@onready var reset_button: Button = %ResetButton
@onready var win_panel = %WinPopup
@onready var next_button: Button = %NextButton
@onready var home_button: Button = %HomeButton
@onready var home_panel: Control = %HomePanel
## Difficulty buttons and their progress chips, in DIFFICULTY_LEVELS order.
@onready var difficulty_buttons: Array[Button] = [
	%EasyButton, %MediumButton, %HardButton, %SuperHardButton]
@onready var difficulty_badges: Array[PanelContainer] = [
	%EasyBadge, %MediumBadge, %HardBadge, %SuperHardBadge]

var level: LevelDefinition
var level_index := 0
var pieces: Array = []  # Array of PuzzlePiece

var board_scale := 1.0
var tray_rect := Rect2()
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
## True while the home/title screen is covering the game; blocks gameplay input.
var menu_open := true
## Completed legal drops this level (rejected drops and tap-rotations are
## free) and when the level became playable; the completion popup reports both.
var move_count := 0
var level_start_msec := 0
## Global level indices (0-based) completed at least once this session;
## drives the home-screen progress chips (reset when the app restarts).
var completed_levels := {}


func _ready() -> void:
	get_viewport().size_changed.connect(_layout)
	reset_button.pressed.connect(_reset_level)
	%RestartButton.pressed.connect(_reset_level)
	next_button.pressed.connect(_next_level)
	home_button.pressed.connect(_on_home_pressed)
	%EasyButton.pressed.connect(_on_difficulty_selected.bind(0))
	%MediumButton.pressed.connect(_on_difficulty_selected.bind(1))
	%HardButton.pressed.connect(_on_difficulty_selected.bind(2))
	%SuperHardButton.pressed.connect(_on_difficulty_selected.bind(3))
	_load_level(0)
	_show_home()


func _show_home() -> void:
	## Cover the game with the title/difficulty screen and swallow input.
	menu_open = true
	home_panel.visible = true
	_refresh_home_badges()


func _refresh_home_badges() -> void:
	## Update each difficulty button's progress chip: the next level it will
	## load, or a greyed UNAVAIL (with the button disabled) when none remains.
	for i in DIFFICULTY_LEVELS.size():
		var next := _next_level_for_difficulty(i)
		var available := next >= 0
		var badge: PanelContainer = difficulty_badges[i]
		var label: Label = badge.get_child(0)
		label.text = "LV %d" % next if available else "UNAVAIL"
		label.add_theme_font_size_override("font_size", 26 if available else 20)
		badge.modulate = Color.WHITE if available else Color(0.65, 0.65, 0.68)
		difficulty_buttons[i].disabled = not available


func _on_home_pressed() -> void:
	## Completion popup's Home button: back to the difficulty selection.
	win_panel.visible = false
	_show_home()


func _on_difficulty_selected(button_index: int) -> void:
	## Difficulty buttons continue at the level shown on their progress chip.
	var next := _next_level_for_difficulty(button_index)
	if next < 0:
		return  # UNAVAIL: the whole game is finished
	menu_open = false
	home_panel.visible = false
	_load_level(next - 1)


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
	move_count = 0
	level_start_msec = Time.get_ticks_msec()
	board.clear_preview()
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
	# Reserve room for the wooden frame so it never overlaps the header/tray.
	var frame_pad: float = BoardController.FRAME_PAD
	var usable := Rect2(Vector2(SCREEN_MARGIN, TOP_HUD_HEIGHT),
			Vector2(vp_x - SCREEN_MARGIN * 2.0, vp_y - TOP_HUD_HEIGHT - SCREEN_MARGIN))
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
	var tray_top: float = usable.position.y + board_zone_h + 6.0
	tray_rect = Rect2(Vector2(usable.position.x, tray_top),
			Vector2(usable.size.x, max(usable.end.y - tray_top - 4.0, 40.0)))
	if tray_backdrop != null:
		tray_backdrop.set_rect(tray_rect)
	_layout_home(vp_x, vp_y)
	_refresh_all_pieces()


func _layout_home(vp_x: float, vp_y: float) -> void:
	## Scale the 720 px-wide home design to the real canvas and stretch its
	## background to the full canvas height so it always covers the screen.
	if home_panel == null:
		return
	var menu_scale: float = vp_x / MENU_DESIGN_WIDTH
	home_panel.scale = Vector2(menu_scale, menu_scale)
	home_panel.size = Vector2(MENU_DESIGN_WIDTH, vp_y / menu_scale)


func _refresh_all_pieces() -> void:
	for p in pieces:
		if p == dragging:
			continue
		if p.placed:
			p.z_index = Z_PLACED
			p.scale = Vector2(board_scale, board_scale)
			p.global_position = board.cell_to_world(p.board_position)
		else:
			_apply_tray_slot(p)


func _apply_tray_slot(p: PuzzlePiece) -> void:
	## Park an unplaced piece in its tray slot (3 columns x 2 rows).
	var cols := 3
	var rows := ceili(pieces.size() / float(cols))
	var slot := Vector2(tray_rect.size.x / cols, tray_rect.size.y / max(rows, 1))
	var index := pieces.find(p)
	var col := index % cols
	var row := index / cols
	var slot_center := tray_rect.position + Vector2(
			(col + 0.5) * slot.x, (row + 0.5) * slot.y)
	var size_cells := p.definition.get_size_rotated(p.orientation)
	var board_size_px := Vector2(size_cells) * (PuzzlePiece.CELL_PX * board_scale)
	var fit := 1.0
	if board_size_px.x > 0.0 and board_size_px.y > 0.0:
		fit = min((slot.x * 0.9) / board_size_px.x, (slot.y * 0.9) / board_size_px.y, 1.0)
	var tray_size_px := board_size_px * fit
	p.z_index = Z_PLACED
	p.scale = Vector2(board_scale * fit, board_scale * fit)
	p.global_position = slot_center - tray_size_px * 0.5



# ---------------------------------------------------------------------------
# Input: unified mouse + touch drag, tap-to-rotate, R key rotate
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# The home menu and the completion popup are modal: ignore board input.
	if menu_open or won:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_press(event.position)
		else:
			_on_release(event.position)
	elif event is InputEventMouseMotion \
			and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) \
			and dragging != null:
		_on_drag(event.position)
	elif event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_R or event.physical_keycode == KEY_R):
		if selected != null:
			_rotate_piece(selected)


func _on_press(world_point: Vector2) -> void:
	if won or dragging != null:
		return
	var piece := _pick_piece(world_point)
	if piece == null:
		return
	if selected != null and selected != piece:
		selected.set_visual_state(PuzzlePiece.VisualState.NORMAL)
	selected = piece
	dragging = piece
	piece.set_visual_state(PuzzlePiece.VisualState.SELECTED)
	grab_offset = world_point - piece.global_position
	press_position = world_point
	press_time = Time.get_ticks_msec() / 1000.0
	moved_far = false
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
	if dragging == null:
		return
	if world_point.distance_to(press_position) > TAP_MAX_MOVE and not moved_far:
		moved_far = true
		# The press became a real drag: lift the piece off the board now.
		dragging.placed = false
		dragging.set_visual_state(PuzzlePiece.VisualState.DRAGGING)
	dragging.global_position = world_point - grab_offset
	_update_preview()


func _on_release(world_point: Vector2) -> void:
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
		# Only a legal drop counts as a move; rejected drags are free.
		if _try_place(piece):
			move_count += 1
	board.clear_preview()
	_check_win()


func _pick_piece(world_point: Vector2) -> PuzzlePiece:
	## Topmost piece under the point (later entries in `pieces` draw on top).
	for i in range(pieces.size() - 1, -1, -1):
		var p: PuzzlePiece = pieces[i]
		if p.is_point_inside(world_point):
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


func _try_place(piece: PuzzlePiece) -> bool:
	## True when the drop was legal and the piece landed on the board.
	var cell := board.world_to_cell_snapped(piece.global_position)
	var occupied := PlacementValidator.get_occupied_cells(pieces, piece)
	if PlacementValidator.is_placement_legal(piece.definition, piece.orientation,
			cell, level.board_size, occupied, wall_edges):
		piece.placed = true
		piece.board_position = cell
		piece.z_index = Z_PLACED
		piece.scale = Vector2(board_scale, board_scale)
		piece.global_position = board.cell_to_world(cell)
		return true
	# The drop was illegal: the piece returns to the tray un-placed.
	piece.placed = false
	_apply_tray_slot(piece)
	return false


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
		completed_levels[level_index] = true
		board.clear_preview()
		var elapsed_msec: int = Time.get_ticks_msec() - level_start_msec
		win_panel.show_popup(_star_count(move_count), move_count,
				_format_time(elapsed_msec), not _has_next_level())


# ---------------------------------------------------------------------------
# Difficulty groups, star rating and level results
# ---------------------------------------------------------------------------

func _difficulty_index_for_level(index: int) -> int:
	## Difficulty whose group contains `index` (the last start at or before it).
	var diff := 0
	for i in DIFFICULTY_LEVELS.size():
		if index >= DIFFICULTY_LEVELS[i]:
			diff = i
	return diff


func _difficulty_end_level() -> int:
	## Last level index that still belongs to the current difficulty group.
	return _difficulty_group_end(_difficulty_index_for_level(level_index))


func _difficulty_group_end(diff_index: int) -> int:
	## Last level index that still belongs to difficulty group `diff_index`.
	if diff_index + 1 < DIFFICULTY_LEVELS.size():
		return DIFFICULTY_LEVELS[diff_index + 1] - 1
	return LevelLoader.level_count() - 1


func _next_level_for_difficulty(diff_index: int) -> int:
	## 1-based level number shown on the difficulty button's progress chip:
	## the first uncompleted level counting from the group's start; once the
	## whole group is finished, the next global level. -1 when no level
	## remains (game finished) — displayed as UNAVAIL.
	var next: int = DIFFICULTY_LEVELS[diff_index]
	var end := _difficulty_group_end(diff_index)
	while next <= end and completed_levels.has(next):
		next += 1
	if next > end:
		next = end + 1
	if next >= LevelLoader.level_count():
		return -1
	return next + 1


func _has_next_level() -> bool:
	## True while the next stage still belongs to the current difficulty.
	return level_index + 1 <= _difficulty_end_level()


func _star_count(moves: int) -> int:
	## Three stars for a clean run (one drop per piece), two with a few extra
	## attempts, one otherwise.
	var par: int = maxi(pieces.size(), 1)
	if moves <= par:
		return 3
	if moves <= par + STAR_2_EXTRA_MOVES:
		return 2
	return 1


func _format_time(elapsed_msec: int) -> String:
	## Level results show MM:SS (minutes capped at 99).
	var total_sec: int = maxi(elapsed_msec, 0) / 1000
	var mins: int = mini(total_sec / 60, 99)
	var secs: int = total_sec % 60
	return "%02d:%02d" % [mins, secs]


func _reset_level() -> void:
	won = false
	dragging = null
	move_count = 0
	level_start_msec = Time.get_ticks_msec()
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
