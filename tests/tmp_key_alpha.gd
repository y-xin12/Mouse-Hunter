extends SceneTree
## One-off asset prep (NOT part of the game): the delivered "1 star.png" has
## an opaque white background; key the border-connected near-white pixels to
## transparent so it composites on the completion board. Interior white
## highlights (star shine) are kept. Original backed up outside the repo.

const SRC := "res://assets/UI/1 star.png"
const THRESH := 235.0 / 255.0


func _initialize() -> void:
	var img := Image.load_from_file(SRC)
	if img == null:
		push_error("could not load " + SRC)
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	print("size %dx%d; corners: %s %s %s %s" % [w, h,
			img.get_pixel(0, 0), img.get_pixel(w - 1, 0),
			img.get_pixel(0, h - 1), img.get_pixel(w - 1, h - 1)])
	var seen := PackedByteArray()
	seen.resize(w * h)
	var stack: Array[Vector2i] = []
	for x in w:
		_seed(img, x, 0, w, seen, stack)
		_seed(img, x, h - 1, w, seen, stack)
	for y in h:
		_seed(img, 0, y, w, seen, stack)
		_seed(img, w - 1, y, w, seen, stack)
	var cleared := 0
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		var c := img.get_pixel(p.x, p.y)
		img.set_pixel(p.x, p.y, Color(c.r, c.g, c.b, 0.0))
		cleared += 1
		for d in dirs:
			var n: Vector2i = p + d
			if n.x >= 0 and n.x < w and n.y >= 0 and n.y < h:
				_seed(img, n.x, n.y, w, seen, stack)
	print("cleared %d of %d px" % [cleared, w * h])
	var err := img.save_png(SRC)
	print("save_png -> ", err)
	quit(0 if err == OK else 1)


func _seed(img: Image, x: int, y: int, w: int, seen: PackedByteArray,
		stack: Array[Vector2i]) -> void:
	var idx := y * w + x
	if seen[idx] == 1:
		return
	var c := img.get_pixel(x, y)
	if c.r >= THRESH and c.g >= THRESH and c.b >= THRESH:
		seen[idx] = 1
		stack.append(Vector2i(x, y))
