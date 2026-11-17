extends Control
## Full-screen level-completion popup: dims the game, pops the wooden card in
## and reveals the earned stars one by one. Purely presentational -- the
## GameManager supplies the real results through show_popup() and owns the
## button callbacks.

const DIM_ALPHA := 0.45
const PANEL_POP_TIME := 0.3
const STAR_POP_TIME := 0.24
const STAR_STAGGER := 0.16
const STAR_BASE_DELAY := 0.22
## Canvas height this card's metrics were designed against. Every fixed
## font size and minimum size scales by live canvas height / DESIGN_HEIGHT
## (the same ratio rule GameManager applies to the HUD), so the card grows
## on taller screens instead of staying at raw design pixels.
const DESIGN_HEIGHT := 1280.0
## Design-time enlargement of the whole card, independent of the responsive
## ratio (1.0 = exactly as authored in the scene; 1.3 = 30% bigger overall).
const CARD_SCALE := 1.45

@onready var dimmer: ColorRect = $Dimmer
@onready var panel: PanelContainer = $Center/Panel
@onready var win_label: Label = %WinLabel
@onready var moves_caption: Label = %MovesCaption
@onready var time_caption: Label = %TimeCaption
@onready var moves_value: Label = %MovesValue
@onready var time_value: Label = %TimeValue
@onready var next_button: Button = %NextButton
@onready var home_button: Button = %HomeButton
@onready var restart_button: Button = %RestartButton
@onready var stars: Array = [%Star1, %Star2, %Star3]


func _ready() -> void:
	# Responsive scaling, reapplied on every window resize; also runs while
	# the popup is hidden so it is correct the moment it appears.
	get_viewport().size_changed.connect(_apply_ui_scale)
	_apply_ui_scale()


func _apply_ui_scale() -> void:
	## Scale the scene-authored design metrics (720x1280 canvas) by the
	## canvas-height ratio, never below the design size. The scene keeps
	## its design values; everything here is a per-control override.
	var s: float = maxf(get_viewport().get_visible_rect().size.y
			/ DESIGN_HEIGHT, 1.0) * CARD_SCALE
	panel.custom_minimum_size = Vector2(320.0 * s, 0.0)
	win_label.add_theme_font_size_override("font_size", _fs(26.0, s))
	win_label.add_theme_constant_override("outline_size", _fs(5.0, s))
	for i in stars.size():
		var star: Control = stars[i]
		star.custom_minimum_size = Vector2(58.0 * s, 58.0 * s)
	moves_caption.add_theme_font_size_override("font_size", _fs(14.0, s))
	time_caption.add_theme_font_size_override("font_size", _fs(14.0, s))
	moves_value.add_theme_font_size_override("font_size", _fs(26.0, s))
	time_value.add_theme_font_size_override("font_size", _fs(26.0, s))
	next_button.add_theme_font_size_override("font_size", _fs(22.0, s))
	home_button.add_theme_font_size_override("font_size", _fs(22.0, s))
	restart_button.add_theme_font_size_override("font_size", _fs(16.0, s))
	next_button.add_theme_constant_override("outline_size", _fs(8.0, s))
	home_button.add_theme_constant_override("outline_size", _fs(8.0, s))
	next_button.custom_minimum_size = Vector2(0.0, 52.0 * s)
	home_button.custom_minimum_size = Vector2(0.0, 52.0 * s)
	restart_button.custom_minimum_size = Vector2(0.0, 40.0 * s)


func _fs(base: float, s: float) -> int:
	## Font/outline sizes are integer theme overrides; never emit a zero.
	return maxi(1, int(roundf(base * s)))


func show_popup(star_count: int, moves: int, time_text: String,
		is_last_level: bool) -> void:
	moves_value.text = str(moves)
	time_value.text = time_text
	next_button.visible = not is_last_level
	home_button.visible = is_last_level
	for i in stars.size():
		var star: Control = stars[i]
		star.earned = i < star_count
		star.scale = Vector2.ZERO
		star.modulate.a = 1.0
	dimmer.color.a = 0.0
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.72, 0.72)
	visible = true
	_animate(star_count)


func _animate(star_count: int) -> void:
	## Deferred one frame so the containers have a valid size to pivot on.
	await get_tree().process_frame
	if not visible:
		return
	panel.pivot_offset = panel.size * 0.5
	for i in stars.size():
		var star: Control = stars[i]
		star.pivot_offset = star.size * 0.5
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(dimmer, "color:a", DIM_ALPHA, 0.2)
	tween.tween_property(panel, "modulate:a", 1.0, 0.18)
	tween.tween_property(panel, "scale", Vector2.ONE, PANEL_POP_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i in stars.size():
		var star: Control = stars[i]
		var delay: float = STAR_BASE_DELAY + i * STAR_STAGGER
		if i < star_count:
			tween.tween_property(star, "scale", Vector2.ONE, STAR_POP_TIME) \
					.set_delay(delay) \
					.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			star.scale = Vector2.ONE
			star.modulate.a = 0.0
			tween.tween_property(star, "modulate:a", 1.0, STAR_POP_TIME) \
					.set_delay(delay)