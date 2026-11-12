class_name TrayBackdrop
extends Node2D
## Rounded cream puzzle-piece tray with a subtle wooden border and soft
## shadow. Drawn BEFORE the Pieces node in the scene so it reads as a
## container without covering the pieces. All sizes come from `rect`, which
## GameManager recomputes on every layout pass (responsive).

const WOOD_DARK := Color(0.66, 0.42, 0.20)
const WOOD := Color(0.80, 0.55, 0.30)
const CREAM := Color(0.985, 0.93, 0.83)
const INNER_SHADOW := Color(0.35, 0.22, 0.10, 0.16)

var rect := Rect2()
var _box: StyleBoxFlat


func set_rect(r: Rect2) -> void:
	rect = r
	queue_redraw()


func _draw() -> void:
	if rect.size.x <= 4.0 or rect.size.y <= 4.0:
		return
	_ensure_box()
	# Wooden outer edge with a soft drop shadow.
	_draw_box(rect, WOOD_DARK, 26, 10, Color(0.32, 0.20, 0.08, 0.16), Vector2(0, 4))
	_draw_box(rect.grow(-4.0), WOOD, 22)
	# Recess shadow, then the cream interior the pieces rest on.
	_draw_box(rect.grow(-10.0), INNER_SHADOW, 18)
	_draw_box(rect.grow(-12.0), CREAM, 16)


func _ensure_box() -> void:
	if _box == null:
		_box = StyleBoxFlat.new()
		_box.anti_aliasing = true


func _draw_box(r: Rect2, color: Color, radius: int,
		shadow_size := 0, shadow_color := Color(0, 0, 0, 0),
		shadow_offset := Vector2.ZERO) -> void:
	_box.bg_color = color
	_box.set_corner_radius_all(radius)
	_box.shadow_size = shadow_size
	_box.shadow_color = shadow_color
	_box.shadow_offset = shadow_offset
	_box.border_width_left = 0
	_box.border_width_top = 0
	_box.border_width_right = 0
	_box.border_width_bottom = 0
	draw_style_box(_box, r)