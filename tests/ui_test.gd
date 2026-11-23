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
	# Verhandlung: nach Abschluss Ergebnis zeigen, "Schließen" schließt
	main.lab.money = 50000000.0
	main.lab._init_companies()
	main._open_negotiation("nova")
	await process_frame
	check(main.nego_popup.visible, "Verhandlungsfenster offen")
	var r: Dictionary = main.lab.make_offer("nova", main.lab.negotiation("nova")["reserve"] * 1.01, 0.0)
	main._open_negotiation("nova", r)
	await process_frame
	var texts := []
	for n in main.nego_popup.find_children("*", "Label", true, false):
		texts.append((n as Label).text)
	check(" ".join(texts).contains("gehört jetzt dir"), "Ergebnis wird angezeigt")
	var close_btn: Button = null
	for n in main.nego_popup.find_children("*", "Button", true, false):
		if (n as Button).text == "Schließen":
			close_btn = n
	check(close_btn != null, "Knopf Schließen vorhanden")
	if close_btn:
		close_btn.pressed.emit()
	await process_frame
	check(not main.nego_popup.visible, "Fenster geht nach Abschluss zu")
	# Abbruch durch Gegenseite
	main.lab.start_negotiation("kestrel")
	var res: float = main.lab.negotiation("kestrel")["reserve"]
	main._open_negotiation("kestrel")
	for i in range(3):
		r = main.lab.make_offer("kestrel", res * 0.85, 0.0)
	main._open_negotiation("kestrel", r)
	await process_frame
	check(main.nego_popup.visible and r["result"] == "walkaway", "Abbruch wird angezeigt")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://slot_3.json"))
	main.queue_free()
	await process_frame
	await process_frame
	print("UI-Test: %d fehlgeschlagen" % failed)
	quit(1 if failed > 0 else 0)
