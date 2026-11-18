extends SceneTree
## TEMPORARY visual validation for the completion page redesign: captures
## screenshots of the popup variants (3/2/1 stars, Next vs Home button)
## to /tmp. Deleted after validation -- not part of the game or test suite.

func _initialize() -> void:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var gm = main
	gm.home_panel.visible = false
	gm.home_bg.visible = false
	gm.win_panel.show_popup(3, 6, "01:23", false)
	await _settle()
	root.get_texture().get_image().save_png("/tmp/mh_popup_3star.png")
	gm.win_panel.show_popup(2, 9, "02:45", false)
	await _settle()
	root.get_texture().get_image().save_png("/tmp/mh_popup_2star.png")
	gm.win_panel.show_popup(1, 14, "03:07", true)
	await _settle()
	root.get_texture().get_image().save_png("/tmp/mh_popup_1star_home.png")
	quit()


func _settle() -> void:
	for i in 90:
		await process_frame
