extends SceneTree
## Simuliert Maus/Tastatur im echten Hauptbildschirm und prüft die Kamera.
## godot --headless --path . -s tests/camera_test.gd

var failed := 0

func check(cond: bool, msg: String) -> void:
	print(("ok   " if cond else "FAIL ") + msg)
	if not cond:
		failed += 1

func _init() -> void:
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var ov = main.office_view
	var center := root.get_visible_rect().size / 2.0

	var z0: float = ov.zoom_t
	_wheel(MOUSE_BUTTON_WHEEL_UP, center)
	check(ov.zoom_t < z0, "Mausrad hoch zoomt rein (%.2f → %.2f)" % [z0, ov.zoom_t])
	_wheel(MOUSE_BUTTON_WHEEL_DOWN, center)
	_wheel(MOUSE_BUTTON_WHEEL_DOWN, center)
	check(ov.zoom_t > z0, "Mausrad runter zoomt raus")

	var p0: Vector3 = ov.pan_t
	_button(MOUSE_BUTTON_LEFT, true, center)
	for i in range(10):
		_motion(center + Vector2(10 * (i + 1), 0), Vector2(10, 0))
	_button(MOUSE_BUTTON_LEFT, false, center + Vector2(100, 0))
	check(ov.pan_t.distance_to(p0) > 0.1, "Ziehen verschiebt die Karte")
	# Welt klebt am Zeiger: Bodenpunkt unter Startposition liegt jetzt unter der Endposition
	for i in range(60):
		await process_frame

	var y0: float = ov.yaw_t
	_button(MOUSE_BUTTON_RIGHT, true, center)
	_motion(center + Vector2(50, 0), Vector2(50, 0))
	_button(MOUSE_BUTTON_RIGHT, false, center)
	check(absf(ov.yaw_t - y0) > 5.0, "Rechte Maus dreht")

	var y1: float = ov.yaw_t
	_key(KEY_Q)
	check(absf(ov.yaw_t - y1 - 45.0) < 0.01, "Q dreht um 45°")
	_key(KEY_R)
	check(ov.pan_t == Vector3.ZERO and ov.zoom_t == 1.0, "R setzt zurück")

	# Ziehen über die Werkzeugleiste unten: Kamera muss weiterlaufen und Loslassen ankommen
	var vs := root.get_visible_rect().size
	var toolbar := Vector2(vs.x / 2.0, vs.y - 40.0)
	_button(MOUSE_BUTTON_LEFT, true, center)
	var steps := 12
	var p_mid := Vector3.ZERO
	for i in range(steps):
		var pos := center.lerp(toolbar, float(i + 1) / steps)
		_motion(pos, (toolbar - center) / steps)
		if i == steps / 2:
			p_mid = ov.pan_t
	var p_before_ui: Vector3 = ov.pan_t
	for i in range(5):
		_motion(toolbar + Vector2(20 * (i + 1), 0), Vector2(20, 0))
	check(ov.pan_t.distance_to(p_before_ui) > 0.05, "Ziehen läuft über der Werkzeugleiste weiter")
	_button(MOUSE_BUTTON_LEFT, false, toolbar + Vector2(100, 0))
	check(not ov.drag_pan, "Loslassen über der Leiste beendet das Ziehen")
	var p_after: Vector3 = ov.pan_t
	_motion(center, Vector2(-50, 0))
	check(ov.pan_t.distance_to(p_after) < 0.0001, "Nach Loslassen bewegt sich nichts mehr")
	# Weit ziehen: darf nicht nach kurzer Strecke hängen bleiben
	ov.reset_view()
	_button(MOUSE_BUTTON_LEFT, true, center)
	for i in range(200):
		_motion(center + Vector2(0, 2 * (i % 40)), Vector2(-25, 0))
	_button(MOUSE_BUTTON_LEFT, false, center)
	check(ov.pan_t.length() > ov.cam_base_size * 1.4, "Weites Ziehen bleibt nicht früh stecken (%.1f)" % ov.pan_t.length())

	# Klick ohne Ziehen meldet Bodenpunkt
	var hits := []
	ov.clicked_ground.connect(func(p): hits.append(p))
	_button(MOUSE_BUTTON_LEFT, true, center)
	_button(MOUSE_BUTTON_LEFT, false, center)
	check(hits.size() == 1 and absf(hits[0].y) < 0.01, "Klick liefert Bodenpunkt")

	print("Kamera-Test: %d fehlgeschlagen" % failed)
	quit(1 if failed > 0 else 0)

func _wheel(btn: MouseButton, pos: Vector2) -> void:
	_button(btn, true, pos)
	_button(btn, false, pos)

func _button(btn: MouseButton, pressed: bool, pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	root.push_input(e)

func _motion(pos: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = rel
	root.push_input(e)

func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	root.push_input(e)
	var r := InputEventKey.new()
	r.keycode = code
	r.pressed = false
	root.push_input(r)
