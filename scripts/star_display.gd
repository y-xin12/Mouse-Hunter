extends Control
## Draws one cute rounded 5-point star for the level-complete popup.
## Earned stars are glossy gold; missed stars are muted grey. The shape is
## polygon-rasterised, so no art asset is required.

const POINTS := 5
const OUTER_RADIUS_RATIO := 0.48
const INNER_RADIUS_RATIO := 0.22

@export var earned := true:
	set(value):
		earned = value
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		pivot_offset = size * 0.5


func _draw() -> void:
	var center := size * 0.5
	var radius: float = minf(size.x, size.y) * OUTER_RADIUS_RATIO
	var inner: float = minf(size.x, size.y) * INNER_RADIUS_RATIO
	var points := PackedVector2Array()
	for i in POINTS * 2:
		var angle := -PI / 2.0 + i * PI / POINTS
		var r: float = radius if i % 2 == 0 else inner
		points.append(center + Vector2(cos(angle), sin(angle)) * r)
	var fill := Color(1.0, 0.82, 0.18) if earned else Color(0.84, 0.81, 0.77)
	var edge := Color(0.86, 0.55, 0.05) if earned else Color(0.66, 0.62, 0.58)
	var shine := Color(1.0, 0.96, 0.66, 0.9) if earned else Color(1, 1, 1, 0.2)
	# Darker edge behind a slightly shrunken fill gives the rounded outline.
	draw_colored_polygon(points, edge)
	var body := PackedVector2Array()
	for p in points:
		body.append(center + (p - center) * 0.88)
	draw_colored_polygon(body, fill)
	draw_circle(center + Vector2(-radius * 0.2, -radius * 0.3),
			radius * 0.11, shine)
	draw_circle(center + Vector2(-radius * 0.32, -radius * 0.12),
			radius * 0.06, shine)