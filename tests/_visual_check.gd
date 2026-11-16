extends SceneTree
## Temporary visual-integrity check (not part of the shipped test suite).

var fails := 0


func _check(cond: bool, label: String) -> void:
	print(("  PASS  " if cond else "  FAIL  ") + label)
	if not cond:
		fails += 1


func _initialize() -> void:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var gm = main
	var board = gm.board
	# Mouse texture resolved (uses res://assets/Mice/mouse.png).
	_check(board._get_mouse_texture() != null, "mouse texture resolved")
	# Goal label derived from level data.
	_check(gm.goal_label.text == "FIND ALL 3 MICE", "goal label from level data")
	# Board frame must not overlap the tray.
	_check(board.frame_rect().end.y <= gm.tray_rect.position.y,
			"board frame does not overlap tray")
	# Square piece: opening cell (0,0) -> hole center (48,48) must be clear.
	var square = null
	for p in gm.pieces:
		if p.definition.id == "square":
			square = p
	var img: Image = square.body_sprite.texture.get_image()
	_check(img.get_pixel(48, 48).a < 0.05, "hole is fully transparent")
	_check(img.get_pixel(144, 48).a > 0.9, "body fill is opaque")
	_check(img.get_pixel(1, 1).a < 0.05, "rounded outer corner is clear")
	_check(square.shadow_sprite.texture != null, "shadow texture built")

	print("== %d visual failure(s) ==" % fails)
	quit(1 if fails > 0 else 0)