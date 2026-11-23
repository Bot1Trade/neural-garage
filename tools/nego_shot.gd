extends SceneTree
## Screenshot: Verhandlung nach einem zu niedrigen Angebot.
func _init() -> void:
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.lab.flags["tut"] = -1
	main.lab.day = 2000
	main.lab.money = 30000000.0
	main.lab._init_companies()
	main._open_tab(9)
	await process_frame
	main.lab.start_negotiation("kestrel")
	var r: Dictionary = main.lab.make_offer("kestrel", main.lab.negotiation("kestrel")["reserve"] * 0.82, 0.0)
	main._open_negotiation("kestrel", r)
	for i in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	main.queue_free()
	await process_frame
	quit()
