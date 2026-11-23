extends SceneTree
## UI-Test: Spielstände speichern/laden, Tempo, Bereiche öffnen.
## godot --headless --path . -s tests/ui_test.gd

var failed := 0

func check(cond: bool, msg: String) -> void:
	print(("ok   " if cond else "FAIL ") + msg)
	if not cond:
		failed += 1

func _init() -> void:
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	# Spiel laufen lassen, speichern, weiterlaufen, laden
	for i in range(40):
		main.lab.step_day()
		main.lab.event_queue.clear()
	var saved_day: int = main.lab.day
	var saved_money: float = main.lab.money
	main._save(false, 3)
	check(FileAccess.file_exists("user://slot_3.json"), "Platz 3 gespeichert")
	check(main._slot_info("user://slot_3.json").contains(main.lab.date_string()), "Platz-Info zeigt Datum")
	for i in range(30):
		main.lab.step_day()
		main.lab.event_queue.clear()
	main._load_slot("user://slot_3.json")
	check(main.lab.day == saved_day and absf(main.lab.money - saved_money) < 0.5, "Laden stellt Stand wieder her")
	check(main.speed == 0, "Nach dem Laden pausiert")
	main._save(true)
	check(FileAccess.file_exists("user://autosave.json"), "Autosave")
	# Tempo
	main._set_speed(3)
	check(main.speed == 3 and main.SPEEDS[3] < main.SPEEDS[1], "5× schneller als 1×")
	# Alle Bereiche öffnen ohne Fehler
	for t in range(main.TOOLS.size()):
		main._open_tab(t)
		await process_frame
	check(main.drawer.visible, "Seitenleiste offen")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://slot_3.json"))
	main.queue_free()
	await process_frame
	await process_frame
	print("UI-Test: %d fehlgeschlagen" % failed)
	quit(1 if failed > 0 else 0)
