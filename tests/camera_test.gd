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
