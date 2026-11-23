extends SceneTree
## Regressionstest (echtes Fenster): godot --path . -s tests/research_test.gd
## Nachstellung: frischer Start, Forschung öffnen, auf einen Knoten klicken, Breite der Seitenleiste messen.
func _init() -> void:
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.lab.flags["tut"] = -1
	main.lab.day = 1500
	main.lab.money = 10000000.0
	main.lab.rp = 5000.0
	main.lab.revision += 1
	main._open_tab(3)
	for i in range(5):
		await process_frame
	var w0: float = main.drawer.size.x
	var btn: Button = null
	for n in main.tab_research.find_children("*", "Button", true, false):
		if (n as Button).text.contains("Interpretier"):
			btn = n
	var pos: Vector2 = root.get_final_transform() * btn.get_global_rect().get_center()
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		root.push_input(e)
		await process_frame
	for i in range(10):
		await process_frame
	var ok: bool = absf(main.drawer.size.x - w0) < 1.0 and main.research_sel == "interp"
	print(("ok   " if ok else "FAIL ") + "Klick auf Forschungsknoten: Auswahl %s, Seitenleiste %.0f -> %.0f" % [main.research_sel, w0, main.drawer.size.x])
	main.queue_free()
	await process_frame
	quit(0 if ok else 1)
