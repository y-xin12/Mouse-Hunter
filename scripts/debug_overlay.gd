class_name DebugOverlay
extends CanvasLayer
## Dev-only adaptive-difficulty panel, toggled with F1 or the floating
## side button in debug builds (GameManager creates it only when
## OS.is_debug_build()). Shows the internal skill state and provides
## controls to simulate results, override the skill tier, preview/play
## wall variants, jump to any level and reset progression. Players never
## see any of it: release exports never create the overlay.

const BUTTON_SIZE := 56.0
const VARIANTS: Array[String] = ["easy", "medium", "hard"]

var last_text := ""
## Always-visible circular toggle docked on the right edge of the screen.
var toggle_button: Button
## Wall variant picked in the Walls row, applied for real by "Play it".
var pending_variant := "medium"

var _gm: Node2D
var _panel: PanelContainer
var _label: Label
var _skill_buttons := {}
var _variant_buttons := {}
var _level_picker: OptionButton
var _reset_button: Button
## The destructive reset needs two presses: the first only arms it.
var _reset_armed := false


func _init() -> void:
	layer = 10  # above the home menu (layer 4)
	_panel = PanelContainer.new()
	_panel.position = Vector2(8, 170)  # below the HUD top bar
	_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.65)
	style.set_content_margin_all(10.0)
	_panel.add_theme_stylebox_override("panel", style)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.6))
	vbox.add_child(_label)
	vbox.add_child(HSeparator.new())
	_build_controls(vbox)
	add_child(_panel)
	toggle_button = _make_toggle_button()
	add_child(toggle_button)


func _build_controls(vbox: VBoxContainer) -> void:
	## One row per control group; every button funnels into _act().
	var sim_row := _make_row(vbox, "Simulate")
	sim_row.add_child(_make_button("Clean clear", _act.bind("simulate_clean")))
	sim_row.add_child(_make_button("Restarted", _act.bind("simulate_restarted")))
	sim_row.add_child(_make_button("Abandon", _act.bind("abandon")))
	var skill_row := _make_row(vbox, "Skill")
	for tier in SkillTracker.TIERS:
		var skill_button := _make_button(tier, _act.bind("skill", tier), true)
		_skill_buttons[tier] = skill_button
		skill_row.add_child(skill_button)
	var walls_row := _make_row(vbox, "Walls")
	for variant_name in VARIANTS:
		var variant_button := _make_button(variant_name,
				_act.bind("preview", variant_name), true)
		_variant_buttons[variant_name] = variant_button
		walls_row.add_child(variant_button)
	walls_row.add_child(_make_button("Play it", _act.bind("play")))
	var level_row := _make_row(vbox, "Level")
	_level_picker = OptionButton.new()
	_style_small(_level_picker)
	_level_picker.item_selected.connect(_on_level_picked)
	level_row.add_child(_level_picker)
	_reset_button = _make_button("Reset progression", _act.bind("reset"))
	vbox.add_child(_reset_button)


func _make_row(parent: VBoxContainer, title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.55))
	title_label.custom_minimum_size = Vector2(64, 0)
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title_label)
	parent.add_child(row)
	return row


func _make_button(text: String, on_press: Callable, toggler := false) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = toggler
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 34)
	_style_small(button)
	button.pressed.connect(on_press)
	return button


func _style_small(button: Button) -> void:
	## Compact dark-chrome style shared by the control buttons and the
	## level picker; the pressed state marks the active tier/variant.
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.0, 0.0, 0.0, 0.35)
	normal.set_corner_radius_all(6)
	normal.set_border_width_all(1)
	normal.border_color = Color(1.0, 1.0, 0.6, 0.3)
	normal.set_content_margin_all(6.0)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(1.0, 1.0, 0.6, 0.35)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", Color(1.0, 1.0, 0.6, 0.9))
	button.add_theme_color_override("font_pressed_color", Color(0.15, 0.12, 0.0))
	button.add_theme_font_size_override("font_size", 14)


func setup(gm: Node2D) -> void:
	## Wire the live GameManager so toggles can repaint the readout, and
	## fill the level picker from the catalog.
	_gm = gm
	_level_picker.clear()
	for i in range(LevelLoader.level_count()):
		var lvl := LevelLoader.load_level(i)
		_level_picker.add_item("%d — %s" % [i + 1,
				lvl.get_room_title() if lvl != null else "?"])
	pending_variant = gm.current_variant


func is_open() -> bool:
	return _panel.visible


func toggle() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible and _gm != null:
		refresh(_gm)
	if not _panel.visible:
		_reset_armed = false


func _act(action: String, arg: Variant = null) -> void:
	## Run one debug control against the live GameManager, then repaint.
	if _gm == null:
		return
	if action == "reset" and not _reset_armed:
		# Destructive: the first press only arms the button ("Sure?").
		_reset_armed = true
		refresh(_gm)
		return
	match action:
		"simulate_clean":
			_gm.debug_simulate_clear(false)
		"simulate_restarted":
			_gm.debug_simulate_clear(true)
		"abandon":
			_gm.debug_abandon_level()
		"skill":
			_gm.debug_set_skill(arg)
		"preview":
			pending_variant = arg
			_gm.debug_preview_variant(arg)
		"play":
			_gm.debug_play_variant(pending_variant)
		"jump":
			_gm.debug_jump_to_level(int(arg))
		"reset":
			_gm.debug_reset_progression()
	_reset_armed = false
	refresh(_gm)


func _on_level_picked(index: int) -> void:
	_act("jump", index + 1)


func _make_toggle_button() -> Button:
	## Small semi-transparent circle on the right edge, ~40% down: clear of
	## the Reset button (top-right) and the piece tray (bottom).
	var button := Button.new()
	button.text = "DBG"
	button.tooltip_text = "Toggle debug readout (F1)"
	button.focus_mode = Control.FOCUS_NONE
	button.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	button.offset_left = -BUTTON_SIZE - 8.0
	button.offset_right = -8.0
	button.offset_top = -BUTTON_SIZE * 0.5 - 128.0
	button.offset_bottom = BUTTON_SIZE * 0.5 - 128.0
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.0, 0.0, 0.0, 0.35)
	normal.set_corner_radius_all(int(BUTTON_SIZE / 2.0))
	normal.set_border_width_all(2)
	normal.border_color = Color(1.0, 1.0, 0.6, 0.45)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(1.0, 1.0, 0.6, 0.35)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", Color(1.0, 1.0, 0.6, 0.9))
	button.add_theme_font_size_override("font_size", 16)
	button.pressed.connect(toggle)
	return button


func refresh(gm: Node2D) -> void:
	## Rebuild the readout and sync the control states from the live
	## GameManager.
	var st: SkillTracker = gm.skill_tracker
	var lines: Array[String] = []
	lines.append("DEBUG  (F1 toggles)")
	var state_line := "skill %s   variant %s   category %s" % [
			st.skill, gm.current_variant,
			LevelDefinition.get_level_category(gm.level_index + 1)]
	if gm.preview_variant != "":
		state_line += "   (previewing %s)" % gm.preview_variant
	lines.append(state_line)
	var req := st.upgrade_requirement()
	lines.append("clean streak %d / %s" % [
			st.clean_clear_streak, "max" if req == 0 else str(req)])
	lines.append("window %s / %d" % [
			str(st.results_since_skill_change), st.downgrade_window()])
	lines.append("save: %s" % gm.save_data.path)
	if st.change_log.is_empty():
		lines.append("changes: none")
	else:
		lines.append("changes:")
		for e in st.change_log.slice(maxi(0, st.change_log.size() - 4)):
			lines.append("  L%d  %s -> %s  (%s)" % [
					int(e.get("level", 0)), e.get("from", "?"),
					e.get("to", "?"), e.get("reason", "")])
	last_text = "\n".join(lines)
	_label.text = last_text
	# Sync the controls: active skill/variant highlighted, the picker on
	# the loaded level, the reset button showing its armed state.
	for tier in _skill_buttons:
		(_skill_buttons[tier] as Button).set_pressed_no_signal(tier == st.skill)
	var shown_variant: String = gm.preview_variant \
			if gm.preview_variant != "" else gm.current_variant
	for variant_name in _variant_buttons:
		(_variant_buttons[variant_name] as Button).set_pressed_no_signal(
				variant_name == shown_variant)
	if gm.preview_variant == "":
		pending_variant = gm.current_variant
	if _level_picker.item_count > 0:
		_level_picker.select(clampi(gm.level_index, 0,
				_level_picker.item_count - 1))
	_reset_button.text = "Sure?" if _reset_armed else "Reset progression"
