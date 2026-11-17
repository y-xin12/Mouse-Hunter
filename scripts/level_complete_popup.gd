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

@onready var dimmer: ColorRect = $Dimmer
@onready var panel: PanelContainer = $Center/Panel
@onready var moves_value: Label = %MovesValue
@onready var time_value: Label = %TimeValue
@onready var next_button: Button = %NextButton
@onready var home_button: Button = %HomeButton
@onready var stars: Array = [%Star1, %Star2, %Star3]


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