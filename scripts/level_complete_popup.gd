extends Control
## Full-screen level-completion page: the home screen's kitchen background
## behind a wooden completion board, with the peeking mouse, the LEVEL
## COMPLETE ribbon and star-rating art matching the result. Purely
## presentational -- the GameManager supplies the real results through
## show_popup() and owns the button callbacks.

const DIM_ALPHA := 0.25
const PANEL_POP_TIME := 0.3
const STAR_POP_TIME := 0.24
const STAR_POP_DELAY := 0.35
## The card is authored in the scene at this size (px) and uniformly scaled
## to fit BOTH canvas axes -- the same fitting rule the home screen uses --
## so the composition never clips regardless of the window size.
const CARD_DESIGN_SIZE := Vector2(631.0, 962.0)

const STARS_3 := preload("res://assets/UI/3 Stars.png")
const STARS_2 := preload("res://assets/UI/2 Stars.png")
const STARS_1 := preload("res://assets/UI/1 star.png")

@onready var dimmer: ColorRect = $Dimmer
@onready var card: Control = %Card
@onready var stars_img: TextureRect = %StarsImg
@onready var moves_value: Label = %MovesValue
@onready var time_value: Label = %TimeValue
@onready var next_button: TextureButton = %NextButton
@onready var home_button: TextureButton = %HomeButton

## Uniform card scale for the current canvas; also the pop animation target.
var _fit_scale := 1.0


func _ready() -> void:
	# Responsive scaling, reapplied on every window resize; also runs while
	# the popup is hidden so it is correct the moment it appears.
	card.pivot_offset = CARD_DESIGN_SIZE * 0.5
	get_viewport().size_changed.connect(_apply_ui_scale)
	_apply_ui_scale()


func _apply_ui_scale() -> void:
	## One uniform scale fits the authored card into the live canvas; the
	## card's center anchors and center pivot keep it centered, and every
	## child (art and text alike) scales with it -- no per-control overrides.
	var vp := get_viewport().get_visible_rect().size
	_fit_scale = minf(vp.x / CARD_DESIGN_SIZE.x, vp.y / CARD_DESIGN_SIZE.y)
	card.scale = Vector2(_fit_scale, _fit_scale)


func show_popup(star_count: int, moves: int, time_text: String,
		is_last_level: bool) -> void:
	moves_value.text = str(moves)
	time_value.text = time_text
	next_button.visible = not is_last_level
	home_button.visible = is_last_level
	stars_img.texture = _stars_texture(star_count)
	dimmer.color.a = 0.0
	card.modulate.a = 0.0
	card.scale = Vector2.ONE * _fit_scale * 0.72
	stars_img.scale = Vector2.ZERO
	visible = true
	_animate()


func _stars_texture(star_count: int) -> Texture2D:
	## Star art row matching the earned rating.
	if star_count >= 3:
		return STARS_3
	if star_count == 2:
		return STARS_2
	return STARS_1


func _animate() -> void:
	## Deferred one frame so the stars art has a valid size to pivot on.
	await get_tree().process_frame
	if not visible:
		return
	stars_img.pivot_offset = stars_img.size * 0.5
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(dimmer, "color:a", DIM_ALPHA, 0.2)
	tween.tween_property(card, "modulate:a", 1.0, 0.18)
	tween.tween_property(card, "scale", Vector2.ONE * _fit_scale,
			PANEL_POP_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(stars_img, "scale", Vector2.ONE, STAR_POP_TIME) \
			.set_delay(STAR_POP_DELAY) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)