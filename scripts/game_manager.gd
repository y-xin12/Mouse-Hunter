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
## Width of the home-screen design space. The menu is authored at this width
## and scaled to the real canvas (project stretch/scale makes the canvas
## narrower than the 720 px design), so it keeps the reference proportions.
const MENU_DESIGN_WIDTH := 720.0
## Height of the home-screen design space (logo, peeking mouse and the
## Play button fit inside it). The menu scale never exceeds what fits
## BOTH canvas axes, so short desktop windows keep every button reachable.
const MENU_DESIGN_HEIGHT := 1280.0
## Extra drags allowed before the star rating drops from three to two.
const STAR_2_EXTRA_MOVES := 3
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
## Solver-verified winning placements per level, replayed by the debug
## overlay's auto-solve (editor/debug runs only; not part of exports).
const DEBUG_SOLUTIONS_PATH := "res://tests/solutions.json"

@onready var board: BoardController = %Board
@onready var pieces_root: Node2D = %Pieces
@onready var tray_backdrop = %TrayBackdrop
@onready var tray_clip: Control = %TrayClip
@onready var level_label: Label = %LevelLabel
@onready var goal_label: Label = %GoalLabel
@onready var reset_button: Button = %ResetButton
@onready var win_panel = %WinPopup
@onready var next_button: TextureButton = %NextButton
@onready var home_button: TextureButton = %HomeButton
@onready var home_panel: Control = %HomePanel
## Full-canvas home background art; a MenuLayer sibling so it covers the
## screen even when the centered home design is narrower than the canvas.
@onready var home_bg: TextureRect = $MenuLayer/Background
## The single home-screen Play button and its "Level N" progress pill.
@onready var play_button: TextureButton = %PlayButton
@onready var play_badge: TextureRect = %PlayBadge
@onready var top_bar: Control = %TopBar
@onready var hint_label: Label = %HintLabel
@onready var goal_panel: Control = %GoalPanel

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
## True while the home/title screen is covering the game; blocks gameplay input.
var menu_open := true
## Completed legal drops this level (rejected drops and tap-rotations are
## free) and when the level became playable; the completion popup reports both.
var move_count := 0
var level_start_msec := 0
## Global level indices (0-based) completed at least once this session.
## Used to keep level results one-per-level (replays of an already completed
## level do not count as new progression).
var completed_levels := {}
## One continuous numbered progression: the next level the Play button
## continues at (1-based, clamped to the catalog size while the catalog
## has not grown). Winning level N unlocks N+1. Restored from the save.
var highest_unlocked_level := 1
## True when the player pressed Reset during the current attempt: the win
## is then recorded as non-clean (restarted) for the skill evaluation.
var attempt_restarted := false
## Progression save; `save_path` exists so tests can redirect the file
## (set it right after instancing the scene, before the first frame).
var save_path := SaveData.SAVE_PATH
var save_data := SaveData.new()
var skill_tracker := SkillTracker.new()
## Wall variant applied to the loaded level ("easy"/"medium"/"hard") and
## the wall list actually in play. Levels below the skill-evaluation
## boundary always play the base ("medium") configuration; later levels
## pin the variant chosen from the player's skill tier at first load into
## the save file, so a level never changes difficulty mid-progression.
var current_variant := "medium"
var active_walls: Array[Vector2i] = []
## Dev-only adaptive-difficulty readout (F1); created only in debug builds
## so release players can never see the internal skill state.
var debug_overlay: DebugOverlay = null
## Wall variant the debug overlay is previewing on the board ("" = none).
## A preview only changes the drawing; gameplay validation, the active
## variant and the save file all stay untouched.
var preview_variant := ""
## Lazily parsed solver reference for the debug auto-solve, level id -> raw
## entry from DEBUG_SOLUTIONS_PATH.
var _debug_solutions := {}
var _debug_solutions_loaded := false


func _ready() -> void:
	get_viewport().size_changed.connect(_layout)
	reset_button.pressed.connect(_reset_level)
	%RestartButton.pressed.connect(_reset_level)
	next_button.pressed.connect(_next_level)
	home_button.pressed.connect(_on_home_pressed)
	play_button.pressed.connect(_on_play_pressed)
	_restore_progression()
	_load_level(0)
	_show_home()
	if OS.is_debug_build():
		debug_overlay = DebugOverlay.new()
		debug_overlay.setup(self)
		add_child(debug_overlay)


func _refresh_debug() -> void:
	## Repaint the dev readout while it is on screen (level loads, wins,
	## and the F1 toggle call this).
	if debug_overlay != null and debug_overlay.is_open():
		debug_overlay.refresh(self)


func _restore_progression() -> void:
	## Load the save and rebuild the session state from it. Missing fields
	## keep their defaults (fresh player: lv2, Level 1, nothing completed).
	save_data.path = save_path
	save_data.load_save()
	highest_unlocked_level = save_data.highest_unlocked_level
	for n in save_data.completed_levels:
		completed_levels[int(n) - 1] = true
	skill_tracker.skill = save_data.user_level_v1
	skill_tracker.clean_clear_streak = save_data.clean_clear_streak
	skill_tracker.results_since_skill_change = \
			save_data.results_since_skill_change.duplicate()
	skill_tracker.change_log = save_data.change_log.duplicate()


func _persist_progression() -> void:
	## Mirror the live progression/skill state into the save file. Called
	## at attempt boundaries (level load and completion) only, so a crash
	## or app kill mid-attempt simply keeps the previous record.
	save_data.user_level_v1 = skill_tracker.skill
	save_data.clean_clear_streak = skill_tracker.clean_clear_streak
	save_data.results_since_skill_change = \
			skill_tracker.results_since_skill_change.duplicate()
	save_data.change_log = skill_tracker.change_log.duplicate()
	save_data.highest_unlocked_level = highest_unlocked_level
	save_data.current_level = level_index + 1
	save_data.save_game()


func _show_home() -> void:
	## Cover the game with the title screen and swallow input.
	menu_open = true
	home_panel.visible = true
	home_bg.visible = true
	_refresh_play_badge()


func _refresh_play_badge() -> void:
	## Update the Play button's progress pill: the numbered level it will
	## continue at (clamped to the catalog while more content is pending).
	var next := _next_play_level()
	(play_badge.get_child(0) as Label).text = "Level %d" % next


func _next_play_level() -> int:
	## The numbered level the Play button continues at: the highest unlocked
	## level clamped to the catalog size (the catalog is one continuous
	## sequence, so the pill never goes "unavailable").
	return mini(highest_unlocked_level, LevelLoader.level_count())


func _on_home_pressed() -> void:
	## Completion popup's Home button: back to the title screen.
	win_panel.visible = false
	_show_home()


func _on_play_pressed() -> void:
	## The Play button continues the unified progression at the level shown
	## on its pill.
	menu_open = false
	home_panel.visible = false
	home_bg.visible = false
	_load_level(_next_play_level() - 1)


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
	current_variant = _assign_variant(index + 1)
	preview_variant = ""
	active_walls = level.get_wall_variant(current_variant)
	board.setup(level.board_size, level.mice, active_walls)
	wall_edges = PlacementValidator.walls_from_pairs(active_walls)
	for def in level.pieces:
		var pp: PuzzlePiece = PIECE_SCENE.instantiate()
		pieces_root.add_child(pp)
		pp.setup(def)
		pieces.append(pp)
	level_label.text = "Level %d — %s" % [index + 1, level.get_room_title()]
	goal_label.text = "FIND ALL %d MICE" % level.mice.size()
	win_panel.visible = false
	move_count = 0
	attempt_restarted = false
	level_start_msec = Time.get_ticks_msec()
	board.clear_preview()
	tray_scroll = 0.0
	tray_scroll_velocity = 0.0
	tray_scroll_active = false
	# The loaded level is the current attempt; persist it at the boundary.
	save_data.current_level = index + 1
	_persist_progression()
	_refresh_debug()
	_layout()


func _assign_variant(level_number: int) -> String:
	## Wall variant for a numbered level. Levels before the skill-
	## evaluation boundary always play the base ("medium") configuration.
	## Later levels pin the variant selected from the CURRENT skill tier
	## the first time they load, so a level never changes difficulty
	## mid-progression; the pin persists in the save file.
	if level_number < SkillTracker.EVALUATION_START_LEVEL:
		return "medium"
	var key := str(level_number)
	var pinned: Variant = save_data.assigned_variants.get(key, "")
	if pinned is String and not pinned.is_empty():
		return pinned
	var variant: String = skill_tracker.variant_for_current_skill()
	save_data.assigned_variants[key] = variant
	return variant


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
	_layout_home(vp_x, vp_y)
	_refresh_all_pieces()


func _layout_home(vp_x: float, vp_y: float) -> void:
	## Scale the 720x1280 home design uniformly to fit the canvas on BOTH
	## axes and center it, so short desktop windows (clamped by the OS)
	## keep the Play button reachable. The background art is a
	## full-canvas MenuLayer sibling, so it covers the screen even when
	## the centered design is narrower than the canvas.
	if home_panel == null:
		return
	var menu_scale: float = minf(
			vp_x / MENU_DESIGN_WIDTH, vp_y / MENU_DESIGN_HEIGHT)
	home_panel.scale = Vector2(menu_scale, menu_scale)
	home_panel.size = Vector2(MENU_DESIGN_WIDTH, vp_y / menu_scale)
	home_panel.position = Vector2(
			(vp_x - MENU_DESIGN_WIDTH * menu_scale) * 0.5,
			maxf((vp_y - MENU_DESIGN_HEIGHT * menu_scale) * 0.5, 0.0))
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
	# The completion popup (WinPopup) self-centers via full-rect anchors and
	# manages its own fonts/animation, so it takes no part in HUD scaling.

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
	# F1 toggles the dev readout; it works on every screen, so it must run
	# before the modal guards below.
	if debug_overlay != null and event is InputEventKey and event.pressed \
			and not event.echo and event.keycode == KEY_F1:
		debug_overlay.toggle()
		get_viewport().set_input_as_handled()
		return
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
		# Only a legal drop counts as a move; rejected drags are free.
		if _try_place(piece):
			move_count += 1
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


func _try_place(piece: PuzzlePiece) -> bool:
	## True when the drop was legal and the piece landed on the board.
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
		# Winning level N unlocks N+1 in the unified progression (clamped
		# by the catalog when the button reads it back).
		highest_unlocked_level = maxi(highest_unlocked_level, level_index + 2)
		# Skill evaluation: only the FIRST completion of a level counts as
		# progression; replays of an already completed level have no effect.
		var level_number := level_index + 1
		if not save_data.completed_levels.has(level_number):
			save_data.completed_levels.append(level_number)
			skill_tracker.record_result(level_number, not attempt_restarted)
		_persist_progression()
		_refresh_debug()
		board.clear_preview()
		var elapsed_msec: int = Time.get_ticks_msec() - level_start_msec
		win_panel.show_popup(_star_count(move_count), move_count,
				_format_time(elapsed_msec), not _has_next_level())


# ---------------------------------------------------------------------------
# Level progression, star rating and level results
# ---------------------------------------------------------------------------

func _has_next_level() -> bool:
	## True while a next numbered level exists in the catalog (the last
	## level shows Home instead of Next).
	return level_index + 1 < LevelLoader.level_count()


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
	# A restart during the attempt marks it non-clean for the skill
	# evaluation when the level is eventually completed.
	attempt_restarted = true
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


# ---------------------------------------------------------------------------
# Debug controls (called from the DebugOverlay, which exists only in debug
# builds; also exercised headlessly by tests/smoke_test.gd)
# ---------------------------------------------------------------------------

func debug_simulate_clear(restart_first: bool) -> void:
	## Auto-solve the loaded level through the REAL completion path
	## (solver-verified placements -> _check_win: unlock, skill record,
	## popup). restart_first runs the real Reset flow first, so the
	## completion is recorded as a restarted (problematic) result.
	if won or level == null:
		return
	_close_menu()
	if restart_first:
		_reset_level()
	var placements := _debug_solution_placements(level.id)
	if placements.is_empty():
		push_warning("GameManager: no solver data to auto-solve '%s'" % level.id)
		return
	for pid in placements:
		var piece := _find_piece_by_id(pid)
		if piece == null:
			continue
		piece.set_orientation(int(placements[pid]["rotation"]))
		piece.board_position = placements[pid]["position"]
		piece.placed = true
		# Lift the piece out of the tray's clipped region, as a drag would.
		if piece.get_parent() != pieces_root:
			piece.reparent(pieces_root)
	_refresh_all_pieces()
	_check_win()


func debug_abandon_level() -> void:
	## Walk away mid-attempt, mirroring the real quit flow: the attempt is
	## marked restarted (a blemish if this level is completed later) and
	## the home screen shows; abandoning records no skill result.
	if level == null:
		return
	attempt_restarted = true
	_on_home_pressed()


func debug_set_skill(tier: String) -> void:
	## Force the skill tier. Like a real tier change, the streak and the
	## rolling window reset so old results never re-trigger; the override
	## is written to the change log. Already pinned level variants stay.
	if not SkillTracker.TIERS.has(tier) or tier == skill_tracker.skill:
		return
	var old: String = skill_tracker.skill
	skill_tracker.skill = tier
	skill_tracker.clean_clear_streak = 0
	skill_tracker.results_since_skill_change.clear()
	skill_tracker.change_log.append({
			"level": level_index + 1, "from": old, "to": tier,
			"reason": "debug override"})
	_persist_progression()
	_refresh_debug()


func debug_preview_variant(variant_name: String) -> void:
	## Draw a variant's wall hints on the board WITHOUT touching gameplay:
	## wall_edges (placement validation), the active variant and the save
	## all stay as they are, so any variant can be eyeballed risk-free.
	## debug_play_variant() applies a variant for real.
	if level == null:
		return
	preview_variant = variant_name
	board.setup(level.board_size, level.mice,
			level.get_wall_variant(variant_name))
	_refresh_debug()


func debug_play_variant(variant_name: String) -> void:
	## Switch the LOADED level to a wall variant for real play (placement
	## validation included). Session-only: the save file's pinned
	## assignment is never rewritten, so reloading restores the pin.
	if level == null:
		return
	preview_variant = ""
	current_variant = variant_name
	active_walls = level.get_wall_variant(variant_name)
	wall_edges = PlacementValidator.walls_from_pairs(active_walls)
	board.setup(level.board_size, level.mice, active_walls)
	_refresh_all_pieces()
	_refresh_debug()


func debug_jump_to_level(level_number: int) -> void:
	## Load any catalog level directly. Uses the real load path, so a
	## level at or beyond the evaluation boundary pins its variant from
	## the current skill on first load, exactly as in organic play;
	## jumping never grants progression (highest_unlocked_level only
	## moves on wins).
	_close_menu()
	_load_level(clampi(level_number, 1, LevelLoader.level_count()) - 1)


func debug_reset_progression() -> void:
	## Wipe the save and rebuild the fresh-player state in memory (lv2,
	## Level 1, nothing completed or pinned), then reload Level 1 behind
	## the home screen. _load_level persists the fresh save at once.
	SaveData.delete_file(save_path)
	save_data = SaveData.new()
	save_data.path = save_path
	skill_tracker = SkillTracker.new()
	highest_unlocked_level = 1
	completed_levels.clear()
	preview_variant = ""
	_load_level(0)
	_show_home()


func _close_menu() -> void:
	## Debug helpers act on the gameplay screen; dismiss the home menu.
	menu_open = false
	home_panel.visible = false
	home_bg.visible = false


func _find_piece_by_id(piece_id: String) -> PuzzlePiece:
	for p in pieces:
		if p.definition.id == piece_id:
			return p
	return null


func _debug_solution_placements(level_id: String) -> Dictionary:
	## Winning placement for a level id from the solver-verified reference
	## (tests/solutions.json, present in editor/debug runs). Maps piece id
	## -> {"position": Vector2i, "rotation": int}; empty when unknown.
	if not _debug_solutions_loaded:
		_debug_solutions_loaded = true
		if FileAccess.file_exists(DEBUG_SOLUTIONS_PATH):
			var data: Variant = JSON.parse_string(
					FileAccess.get_file_as_string(DEBUG_SOLUTIONS_PATH))
			if data is Dictionary:
				for lvl in data.get("levels", []):
					_debug_solutions[lvl.get("id", "")] = lvl
	var entry: Dictionary = _debug_solutions.get(level_id, {})
	var placements: Dictionary = entry.get("placements", {})
	var rotations: Dictionary = entry.get("rotations", {})
	var out := {}
	for pid in placements:
		var cells: Array = placements[pid]
		if cells.is_empty():
			continue
		var top_left := Vector2i(int(cells[0][0]), int(cells[0][1]))
		for c in cells:
			top_left.x = mini(top_left.x, int(c[0]))
			top_left.y = mini(top_left.y, int(c[1]))
		out[pid] = {"position": top_left, "rotation": int(rotations.get(pid, 0))}
	return out
