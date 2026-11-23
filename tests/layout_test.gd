extends SceneTree
## Layout-Test (echtes Fenster): Bot spielt bis ~2020, dann wird jeder Bereich der Seitenleiste
## geöffnet und geprüft, dass der Inhalt nicht breiter als die Leiste ist.
## godot --path . -s tests/layout_test.gd [-- <ordner für screenshots>]

const Bot = preload("res://scripts/sim/bot.gd")
var failed := 0

func _init() -> void:
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var lab = main.lab
	lab.setup(1003)
	lab.flags["tut"] = -1
	while lab.day < 365 * 4 + 200 and lab.ending.is_empty():
		lab.step_day()
		while not lab.event_queue.is_empty():
			lab.resolve_event(Bot.choose(lab))
		if lab.day % 7 == 0:
			Bot.manage(lab)
	lab._init_companies()
	lab.start_negotiation("kestrel")
	main._reset_view()
	main.set_process(true)
	await process_frame
	var shot_dir := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else ""
	var w0 := -1.0
	for t in range(main.TOOLS.size()):
		main.drawer.visible = false
		main._open_tab(t)
		for i in range(4):
			await process_frame
		var tab: Control = main.tabs.get_child(t)
		var inner: float = main.tabs.size.x
		var need: float = tab.get_combined_minimum_size().x
		if tab is ScrollContainer and tab.get_child_count() > 0:
			need = (tab.get_child(0) as Control).get_combined_minimum_size().x
		if w0 < 0.0:
			w0 = main.drawer.size.x
		var ok: bool = need <= inner + 0.5 and absf(main.drawer.size.x - w0) < 1.0
		print("%s %-12s Inhalt %4.0f / Platz %4.0f · Leiste %4.0f" % ["ok  " if ok else "FAIL", main.TOOLS[t]["title"], need, inner, main.drawer.size.x])
		if not ok:
			failed += 1
			_widest(tab, inner)
		if shot_dir != "":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/tab_%d.png" % [shot_dir, t])
	print("Layout-Test: %d fehlgeschlagen" % failed)
	main.queue_free()
	await process_frame
	quit(1 if failed > 0 else 0)

## Die breitesten Elemente melden, damit man sieht, wer drückt
func _widest(node: Node, limit: float) -> void:
	var found := []
	for n in node.find_children("*", "Control", true, false):
		var c := n as Control
		var w := c.get_combined_minimum_size().x
		if w > limit * 0.6 and not (c is ScrollContainer or c is MarginContainer or c is VBoxContainer):
			var txt := ""
			if c is Label:
				txt = (c as Label).text.left(50)
			elif c is Button:
				txt = (c as Button).text.left(50)
			found.append([w, c.get_class(), txt])
	found.sort_custom(func(a, b): return a[0] > b[0])
	for f in found.slice(0, 5):
		print("        %4.0f  %s  %s" % [f[0], f[1], f[2]])
