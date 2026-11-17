extends BaseButton
## Press feedback for menu buttons: shrinks and darkens while held, then
## springs back with a slight overshoot on release. Purely visual -- it works
## on Button and TextureButton alike and never interferes with pressed.

const PRESS_SCALE := 0.92
const PRESS_TINT := 0.72
const PRESS_TIME := 0.08
const RELEASE_TIME := 0.35

var _tween: Tween
var time = 0.0
var init_pos = Vector2.ZERO

func _process(delta: float) -> void:
	time += delta
	self.get_parent().get_child(0).global_position.y = init_pos.y - sin (time*2) * 5
	

func _ready() -> void:
	self.get_parent().get_child(0).global_position.y -= 5
	init_pos = self.get_parent().get_child(0).global_position
	pivot_offset = size * 0.5
	resized.connect(_on_resized)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)


func _on_resized() -> void:
	pivot_offset = size * 0.5


func _on_button_down() -> void:
	if disabled:
		return
	_restart_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "scale", Vector2.ONE * PRESS_SCALE, PRESS_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "self_modulate",
			Color(PRESS_TINT, PRESS_TINT, PRESS_TINT), PRESS_TIME)


func _on_button_up() -> void:
	_restart_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "scale", Vector2.ONE, RELEASE_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "self_modulate", Color.WHITE, RELEASE_TIME * 0.5)


func _restart_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
