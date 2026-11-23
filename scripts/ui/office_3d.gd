extends SubViewportContainer
## 3D-Ansicht (Vollbild): Büro innen oder Weltansicht (Labor, Rechenzentren, Fabrik, Konkurrenz).
## Modelle: Kenney Furniture Kit, Mini Characters, City Kit Commercial/Roads, Emotes (alle CC0).
## Steuerung: Mausrad = Zoom, rechte Maus = drehen, mittlere/linke Maus ziehen = verschieben, Q/E = drehen.

const D = preload("res://scripts/sim/data.gd")

signal fx_event(fx_name: String)   # für Sounds
const FURN := "res://assets/kenney/furniture/"
const CHARS := "res://assets/kenney/characters/"
const CITY := "res://assets/kenney/city/"
const ROADS := "res://assets/kenney/roads/"
const EMOTES := "res://assets/kenney/emotes/"
const NATURE := "res://assets/kenney/nature/"
const CARS := "res://assets/kenney/cars/"
const CAR_MODELS := ["sedan", "suv", "taxi", "van", "hatchback-sports", "delivery", "police", "truck"]
const TREES := ["tree_default", "tree_oak", "tree_detailed", "tree_fat", "tree_cone", "tree_simple"]
const LOW_PLANTS := ["plant_bush", "plant_bushLarge", "flower_redA", "flower_yellowA", "flower_purpleA", "grass_large"]
## Außengelände je Büro-Stufe (Garage = Einfahrt, Tower-Etage = Dachterrasse, sonst Rasen)
const OUTSIDE := [Color("5d6168"), Color("47703b"), Color("47703b"), Color("6b6f78"), Color("47703b"), Color("47703b")]
const CHAR_MODELS := ["character-female-a", "character-female-b", "character-female-c", "character-female-d",
	"character-female-e", "character-female-f", "character-male-a", "character-male-b", "character-male-c",
	"character-male-d", "character-male-e", "character-male-f", "character-male-g"]
## Raumgröße (Kacheln) und Bodenfarbe je Büro
const ROOMS := [
	{"w": 5, "d": 4, "floor": Color("4a3e33"), "max_desks": 4},
	{"w": 6, "d": 5, "floor": Color("504436"), "max_desks": 7},
	{"w": 7, "d": 5, "floor": Color("5a4c3e"), "max_desks": 10},
	{"w": 8, "d": 6, "floor": Color("3f4650"), "max_desks": 14},
	{"w": 9, "d": 7, "floor": Color("3d4a52"), "max_desks": 20},
	{"w": 11, "d": 8, "floor": Color("343d4a"), "max_desks": 30},
]
## Labor-Gebäude in der Weltansicht je Büro-Stufe: [Modell, Skalierung]
const LAB_BUILDINGS := [["building-c", 1.4], ["building-h", 1.6], ["building-g", 1.7], ["building-skyscraper-a", 1.5], ["building-n", 1.8], ["building-skyscraper-e", 1.7]]
const LAB_POS := Vector3(-4.5, 0, 3.5)
const HELIX_POS := Vector3(-9, 0, -9)
const FAB_POS := Vector3(5, 0, 6)
const DC_BUILDINGS := {"colo": ["building-k", 1.4], "dc": ["building-j", 2.0], "hyper": ["building-e", 3.2]}
const MAX_RACKS := 12
const SEAT_Y := 0.16

var lab
var mode := "office"
var viewport: SubViewport
var world: Node3D
var camera: Camera3D
var info_label: Label
var build_key := ""
var rack_lights: Array = []
var rack_nodes: Array = []
var people: Array = []          # [{anim, node}]
var money_anchor := Vector3.ZERO
var released_seen := -1
var t := 0.0
var cars: Array = []
var coffee_timer := 0.0
var fx_timer := 0.0
var money_ticks := 0
var aabb_cache := {}
# Kamera
var cam_center := Vector3.ZERO
var cam_base_size := 10.0
var yaw := 45.0
var zoom := 1.0
var pan := Vector3.ZERO
var drag_rot := false
var drag_pan := false
var walls_x: Array = []
var walls_z: Array = []


func _ready() -> void:
	stretch = true
	viewport = SubViewport.new()
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.own_world_3d = true
	add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	viewport.add_child(camera)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("1b2a44")
	sm.sky_horizon_color = Color("44587a")
	sm.ground_horizon_color = Color("44587a")
	sm.ground_bottom_color = Color("161b24")
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.72, 0.78, 0.9)
	e.ambient_light_energy = 0.45
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.ssao_enabled = true
	e.ssao_radius = 0.6
	e.ssao_intensity = 1.8
	e.glow_enabled = true
	e.glow_intensity = 0.45
	e.glow_bloom = 0.04
	e.glow_hdr_threshold = 0.9
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.15
	e.adjustment_contrast = 1.05
	env.environment = e
	viewport.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 60.0
	viewport.add_child(sun)
	info_label = Label.new()
	info_label.add_theme_font_size_override("font_size", 14)
	info_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	info_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	info_label.add_theme_constant_override("outline_size", 4)
	info_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	info_label.offset_left = -420
	info_label.offset_top = -40
	info_label.offset_right = -14
	info_label.offset_bottom = -12
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(info_label)


func set_mode(m: String) -> void:
	mode = m
	build_key = ""
	pan = Vector3.ZERO
	zoom = 1.0


# ------------------------------------------------------------------ Eingabe & Kamera

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom * 0.9, 0.3, 2.0)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom * 1.1, 0.3, 2.0)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			drag_rot = mb.pressed
		elif mb.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_LEFT]:
			drag_pan = mb.pressed
		_update_camera()
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if drag_rot:
			yaw = fmod(yaw - mm.relative.x * 0.35, 360.0)
			_update_camera()
		elif drag_pan:
			var k := camera.size / maxf(1.0, size.y)
			var right := camera.global_transform.basis.x
			var fwd := Vector3(-right.z, 0, right.x)
			pan += (-right * mm.relative.x + fwd * mm.relative.y * 1.4) * k
			_update_camera()


func _unhandled_key_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed:
		if ev.keycode == KEY_Q:
			yaw += 15.0
			_update_camera()
		elif ev.keycode == KEY_E:
			yaw -= 15.0
			_update_camera()


func _update_camera() -> void:
	var c := cam_center + pan
	var r := deg_to_rad(yaw)
	camera.position = c + Vector3(sin(r) * 14.0, 11.0, cos(r) * 14.0)
	camera.look_at(c, Vector3.UP)
	camera.size = cam_base_size * zoom
	# Wände zwischen Kamera und Raum ausblenden
	for w in walls_z:
		w.visible = cos(r) > -0.2
	for w in walls_x:
		w.visible = sin(r) > -0.2


# ------------------------------------------------------------------ Laufzeit

func _process(delta: float) -> void:
	if lab == null:
		return
	t += delta
	var key := _scene_key()
	if key != build_key:
		build_key = key
		_build()
	var training: bool = not lab.training.is_empty()
	for i in range(rack_lights.size()):
		var on := sin(t * (9.0 if training else 2.0) + i * 1.7) > 0.0
		var m: StandardMaterial3D = rack_lights[i]
		m.emission = Color("ffb347") if training else Color("6be38a")
		m.emission_energy_multiplier = 2.5 if on else 0.2
	# Ereignisse aus der Simulation als 3D-Effekte
	for f in lab.fx:
		_play_fx(f)
	lab.fx.clear()
	for c in cars:
		c["pos"] = float(c["pos"]) + float(c["speed"]) * float(c["dir"]) * delta
		if absf(c["pos"]) > 15.0:
			c["pos"] = -15.0 * float(c["dir"])
		_set_car(c)
	if mode == "office" and lab.office_upgrades.has("coffee") and not people.is_empty():
		coffee_timer += delta
		if coffee_timer > 6.0:
			coffee_timer = 0.0
			var p: Dictionary = people[randi() % people.size()]
			if not p["busy"]:
				_coffee_walk(p)
	# Laufende Effekte: Geld steigt auf, Leute denken beim Training nach
	fx_timer += delta
	if fx_timer > 1.6:
		fx_timer = 0.0
		if lab.last_income > lab.last_cost and lab.last_income > 0.0:
			var src := money_anchor
			if mode == "office" and not rack_nodes.is_empty():
				src = rack_nodes[randi() % rack_nodes.size()] + Vector3(0, 1.1, 0)
			_float_sprite("emote_cash", src, 0.5)
			money_ticks += 1
			if money_ticks % 4 == 0:
				fx_event.emit("money")
		if training and mode == "office" and not people.is_empty():
			_emote_person(people[randi() % people.size()], "emote_dots3")
	var released := 0
	for m in lab.models:
		if m["status"] != "ready":
			released += 1
	if released_seen >= 0 and released > released_seen:
		_celebrate()
		fx_event.emit("release")
	released_seen = released
	var o: Dictionary = lab.office_data()
	info_label.text = "%s  ·  %d/%d  ·  %s" % [o["name"], lab.staff.size(), o["staff"], "Weltansicht" if mode == "world" else "Büro"]


func _scene_key() -> String:
	if mode == "world":
		var dcs := ""
		for dc in lab.datacenters:
			dcs += dc["type"]
		return "w|%d|%s|%s|%d" % [lab.office, dcs, lab.has_fab, int(lab.rival["count"]) / 3]
	var room: Dictionary = ROOMS[lab.office]
	return "o|%d|%d|%d|%d" % [lab.office, mini(lab.staff.size(), room["max_desks"]), _rack_count(), lab.office_upgrades.size()]


func _rack_count() -> int:
	if lab.gpu_count() == 0 and lab.datacenters.is_empty():
		return 0
	var per_rack := maxf(2.0, float(lab.office_data()["gpus"]) / MAX_RACKS)
	return clampi(ceili(lab.gpu_count() / per_rack), 1, MAX_RACKS)


func _play_fx(f: String) -> void:
	fx_event.emit(f)
	match f:
		"release":
			_celebrate()
		"research":
			_emote_some("emote_idea", 3)
		"incident":
			_emote_some("emote_faceSad", 6)
		"hire":
			if not people.is_empty():
				_emote_person(people[people.size() - 1], "emote_heart")
		"goal":
			_emote_some("emote_star", 4)
		"build":
			_emote_some("emote_exclamation", 3)


func _celebrate() -> void:
	for p in people:
		var ap: AnimationPlayer = p["anim"]
		ap.play("emote-yes")
		ap.queue("sit")
	_emote_some("emote_stars", 6)


func _emote_some(e: String, n: int) -> void:
	if mode == "world" or people.is_empty():
		_float_sprite(e, money_anchor + Vector3(0, 0.5, 0), 0.9)
		return
	var idx := range(people.size())
	idx.shuffle()
	for i in range(mini(n, idx.size())):
		_emote_person(people[idx[i]], e)


func _emote_person(p: Dictionary, e: String) -> void:
	var node: Node3D = p["node"]
	if is_instance_valid(node):
		_float_sprite(e, node.position + Vector3(0, 0.95, 0), 0.35)


# ------------------------------------------------------------------ Leben & Umgebung

func _build_surroundings(w: int, d: int, room: Dictionary) -> void:
	_ground(Vector2(70, 70), Vector3(w / 2.0, -0.12, d / 2.0), OUTSIDE[lab.office])
	var slab := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w + 0.3, 0.25, d + 0.3)
	slab.mesh = bm
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color("2b2f37")
	slab.material_override = smat
	slab.position = Vector3(w / 2.0, -0.125, d / 2.0)
	world.add_child(slab)
	# Bodenkacheln/Dielen im Schachbrett
	var base: Color = room["floor"]
	var mat_a := StandardMaterial3D.new()
	mat_a.albedo_color = base.lightened(0.06)
	mat_a.roughness = 0.8
	var mat_b := StandardMaterial3D.new()
	mat_b.albedo_color = base.darkened(0.05)
	mat_b.roughness = 0.8
	var pm := PlaneMesh.new()
	pm.size = Vector2(1.0, 1.0)
	for x in range(w):
		for z in range(d):
			var tile := MeshInstance3D.new()
			tile.mesh = pm
			tile.material_override = mat_a if (x + z) % 2 == 0 else mat_b
			tile.position = Vector3(x + 0.5, 0.0, z + 0.5)
			world.add_child(tile)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 + lab.office
	if lab.office == 0:
		_place_from(CARS, "sedan", Vector3(w + 1.2, -0.12, d * 0.5), 0.0, Vector3.ONE * 0.32)
	# Hohe Bäume nur hinter den Wänden, vorne nur niedrige Pflanzen (verdecken nichts)
	if lab.office != 0 and lab.office != 3:
		for i in range(14):
			var p := Vector3(rng.randf_range(-4.0, -0.9), -0.12, rng.randf_range(-3.0, d + 2.0)) if i % 2 == 0 else Vector3(rng.randf_range(-3.0, w + 2.0), -0.12, rng.randf_range(-4.0, -0.9))
			_place_from(NATURE, TREES[rng.randi() % TREES.size()], p, rng.randf_range(0, 360), Vector3.ONE * rng.randf_range(1.3, 2.0))
		for i in range(16):
			var p := Vector3(w + rng.randf_range(0.5, 3.0), -0.12, rng.randf_range(0.0, d + 2.0)) if i % 2 == 0 else Vector3(rng.randf_range(0.0, w + 2.0), -0.12, d + rng.randf_range(0.5, 3.0))
			_place_from(NATURE, LOW_PLANTS[rng.randi() % LOW_PLANTS.size()], p, rng.randf_range(0, 360), Vector3.ONE * rng.randf_range(1.2, 2.0))


func _screen_glow(pos: Vector3) -> void:
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.3, 0.19)
	q.mesh = qm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.55, 0.8, 1.0)
	m.emission_enabled = true
	m.emission = Color(0.35, 0.65, 1.0)
	m.emission_energy_multiplier = 1.4
	q.material_override = m
	q.position = pos
	world.add_child(q)


func _world_nature_and_traffic() -> void:
	var occupied: Array = [LAB_POS, HELIX_POS, FAB_POS]
	for b in world.get_children():
		if b is Node3D and b.scale.x >= 1.0 and b.position.y == 0.0:
			occupied.append(b.position)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in range(90):
		var p := Vector3(rng.randf_range(-16, 16), 0, rng.randf_range(-16, 16))
		if absf(p.x) < 1.0 or absf(p.z) < 1.0:
			continue
		var free := true
		for o in occupied:
			if p.distance_to(o) < 1.6:
				free = false
				break
		if not free:
			continue
		occupied.append(p)
		var tall := rng.randf() < 0.7
		var m: String = TREES[rng.randi() % TREES.size()] if tall else LOW_PLANTS[rng.randi() % LOW_PLANTS.size()]
		_place_from(NATURE, m, p, rng.randf_range(0, 360), Vector3.ONE * rng.randf_range(1.4, 2.2))
	for i in range(12):
		var holder := _place_from(CARS, CAR_MODELS[i % CAR_MODELS.size()], Vector3.ZERO, 0.0, Vector3.ONE * 0.27)
		var dir := 1.0 if i % 4 < 2 else -1.0
		var c := {"node": holder, "axis": "x" if i % 2 == 0 else "z", "dir": dir, "lane": 0.22 * dir, "pos": rng.randf_range(-14.0, 14.0), "speed": rng.randf_range(1.0, 2.0)}
		cars.append(c)
		_set_car(c)


func _set_car(c: Dictionary) -> void:
	var n: Node3D = c["node"]
	var p := float(c["pos"])
	var lane := float(c["lane"])
	if c["axis"] == "x":
		n.position = Vector3(p, 0.01, lane)
		n.rotation_degrees.y = 90.0 if float(c["dir"]) > 0.0 else -90.0
	else:
		n.position = Vector3(-lane, 0.01, p)
		n.rotation_degrees.y = 0.0 if float(c["dir"]) > 0.0 else 180.0


## Person geht zur Kaffeebar und zurück (über den Gang hinter den Stühlen)
func _coffee_walk(p: Dictionary) -> void:
	var node: Node3D = p["node"]
	var ap: AnimationPlayer = p["anim"]
	if not is_instance_valid(node):
		return
	p["busy"] = true
	var room: Dictionary = ROOMS[lab.office]
	var seat: Vector3 = p["seat"]
	var target := Vector3(float(room["w"]) - 0.85, 0.0, float(room["d"]) - 0.35)
	var aisle := minf(seat.z + 0.5, float(room["d"]) - 0.25)
	var path := [Vector3(seat.x, 0, aisle), Vector3(target.x, 0, aisle), target]
	var tw := node.create_tween()
	var prev := Vector3(seat.x, 0.0, seat.z)
	tw.tween_callback(func(): node.position.y = 0.0; ap.play("walk"))
	for q in path:
		tw.tween_callback(_face.bind(node, prev, q))
		tw.tween_property(node, "position", q, prev.distance_to(q) / 0.8)
		prev = q
	tw.tween_callback(func(): ap.play("idle"))
	tw.tween_interval(2.5)
	var back := [Vector3(target.x, 0, aisle), Vector3(seat.x, 0, aisle), Vector3(seat.x, 0, seat.z)]
	tw.tween_callback(func(): ap.play("walk"))
	for q in back:
		tw.tween_callback(_face.bind(node, prev, q))
		tw.tween_property(node, "position", q, prev.distance_to(q) / 0.8)
		prev = q
	tw.tween_callback(func():
		node.position = seat
		node.rotation_degrees.y = 180.0
		ap.play("sit")
		p["busy"] = false)


func _face(node: Node3D, a: Vector3, b: Vector3) -> void:
	var dvec := b - a
	if dvec.length() > 0.01:
		node.rotation.y = atan2(dvec.x, dvec.z)


## Sprite steigt auf und verblasst
func _float_sprite(e: String, pos: Vector3, rise: float) -> void:
	var s := Sprite3D.new()
	s.texture = load(EMOTES + e + ".png")
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.no_depth_test = true
	s.pixel_size = 0.015 * (cam_base_size / 10.0)
	s.position = pos
	world.add_child(s)
	var tw := s.create_tween()
	tw.set_parallel(true)
	tw.tween_property(s, "position:y", pos.y + rise, 1.6).set_ease(Tween.EASE_OUT)
	tw.tween_property(s, "modulate:a", 0.0, 1.6).set_delay(0.6)
	tw.chain().tween_callback(s.queue_free)


# ------------------------------------------------------------------ Aufbau

func _clear_world() -> void:
	for c in world.get_children():
		world.remove_child(c)
		c.queue_free()
	rack_lights.clear()
	rack_nodes.clear()
	people.clear()
	walls_x.clear()
	walls_z.clear()
	cars.clear()


func _build() -> void:
	_clear_world()
	if mode == "world":
		_build_world()
	else:
		_build_office()
	_update_camera()


func _build_office() -> void:
	var room: Dictionary = ROOMS[lab.office]
	var w: int = room["w"]
	var d: int = room["d"]
	_build_surroundings(w, d, room)
	for x in range(w):
		walls_z.append(_place("wallWindow" if x % 2 == 1 else "wall", Vector3(x + 0.5, 0, 0.03), 0.0, Vector3.ONE, true))
	for z in range(d):
		walls_x.append(_place("wallWindow" if z % 2 == 1 else "wall", Vector3(0.03, 0, z + 0.5), 90.0, Vector3.ONE, true))

	var racks := _rack_count()
	for i in range(racks):
		_add_rack(Vector3(w - 0.45 - (i % 2) * 0.55, 0, 0.45 + floori(i / 2.0) * 0.6))

	var desks: int = mini(lab.staff.size(), room["max_desks"])
	var cap: int = room["max_desks"]
	var cols := maxi(1, floori((float(w) - 1.8) / 1.25))
	for i in range(cap):
		var cx := 0.95 + (i % cols) * 1.25
		var cz := 1.1 + floori(i / float(cols)) * 1.35
		if cz > d - 0.5:
			break
		var pos := Vector3(cx, 0, cz)
		_place("desk", pos, 0.0)
		_place("computerScreen", pos + Vector3(0, 0.38, -0.08), 0.0)
		if i < desks:
			_screen_glow(pos + Vector3(0, 0.38 + 0.165, -0.022))
		_place("computerKeyboard", pos + Vector3(0, 0.38, 0.09), 0.0)
		if i < desks:
			_place("chairDesk", pos + Vector3(0, 0, 0.45), 180.0)
			_add_person(lab.staff[i], pos + Vector3(0, SEAT_Y, 0.4))
		else:
			_place("chairDesk", pos + Vector3(0.05, 0, 0.48), 200.0)

	_place("pottedPlant", Vector3(0.35, 0, d - 0.35), 0.0)
	_place("trashcan", Vector3(0.3, 0, 0.35), 0.0)
	var up: Dictionary = lab.office_upgrades
	if up.has("coffee"):
		_place("kitchenBar", Vector3(w - 0.35, 0, d - 0.3), -90.0)
		_place("kitchenCoffeeMachine", Vector3(w - 0.35, 0.42, d - 0.3), -90.0)
	if up.has("meeting"):
		_place("bookcaseClosed", Vector3(1.5, 0, 0.2), 0.0)
		_place("bookcaseOpen", Vector3(2.0, 0, 0.2), 0.0)
	if up.has("gym"):
		_place("rugRectangle", Vector3(w - 2.2, 0.0, d - 0.9), 0.0)
		_place("loungeSofa", Vector3(w - 2.2, 0, d - 0.35), 180.0)
		_place("tableCoffee", Vector3(w - 2.2, 0, d - 1.0), 0.0)
		_place("lampSquareFloor", Vector3(w - 3.0, 0, d - 0.3), 0.0)
	if up.has("hwlab"):
		_place("cardboardBoxOpen", Vector3(w - 1.6, 0, 0.3), 15.0)
		_place("cardboardBoxClosed", Vector3(w - 1.6, 0, 0.6), -10.0)
	if lab.office >= 4:
		walls_x.append(_place("televisionModern", Vector3(0.1, 0.6, d / 2.0), 90.0))
		_place("pottedPlant", Vector3(w - 0.35, 0, d / 2.0 + 1.0), 0.0)

	# Warmes Raumlicht
	for lx in range(1, w, 3):
		for lz in range(1, d, 3):
			var l := OmniLight3D.new()
			l.position = Vector3(lx + 0.5, 1.7, lz + 0.5)
			l.light_color = Color(1.0, 0.84, 0.62)
			l.light_energy = 0.8
			l.omni_range = 3.2
			world.add_child(l)
	cam_center = Vector3(w / 2.0, 0.3, d / 2.0)
	cam_base_size = (w + d) * 0.55 + 1.0
	money_anchor = Vector3(w - 0.7, 1.2, 0.8)


func _build_world() -> void:
	_ground(Vector2(80, 80), Vector3.ZERO, Color("35552f"))
	# Straßenkreuz
	for i in range(-14, 15):
		_place_from(ROADS, "road-crossroad" if i == 0 else "road-straight", Vector3(i, 0.005, 0), 90.0, Vector3.ONE)
		if i != 0:
			_place_from(ROADS, "road-straight", Vector3(0, 0.005, i), 0.0, Vector3.ONE)
		if i % 4 == 2:
			_place_from(ROADS, "light-square", Vector3(i, 0, -0.6), 0.0, Vector3.ONE)
	# Dein Labor
	var lb: Array = LAB_BUILDINGS[lab.office]
	_place_from(CITY, lb[0], LAB_POS, 45.0, Vector3.ONE * float(lb[1]))
	_label3d("Dein Labor", LAB_POS + Vector3(0, 0.15, 2.0), Color("6fb6ff"))
	money_anchor = LAB_POS + Vector3(0, 3.0, 0)
	# Rechenzentren
	var slots := [Vector3(3.5, 0, -3), Vector3(7, 0, -3), Vector3(10.5, 0, -3), Vector3(3.5, 0, -7), Vector3(7, 0, -7), Vector3(10.5, 0, -7),
		Vector3(3.5, 0, -10.5), Vector3(7, 0, -10.5), Vector3(10.5, 0, -10.5)]
	for i in range(mini(lab.datacenters.size(), slots.size())):
		var dc: Dictionary = lab.datacenters[i]
		var b: Array = DC_BUILDINGS[dc["type"]]
		_place_from(CITY, b[0], slots[i], 0.0, Vector3.ONE * float(b[1]))
		_label3d(_find_loc(dc["loc"]), slots[i] + Vector3(0, 0.15, 1.5), Color("a0e8b0"))
		for l in range(2):
			_add_rack(slots[i] + Vector3(-0.5 + l * 0.6, 0, 1.0))
	# Chipfabrik
	if lab.has_fab:
		_place_from(CITY, "building-m", FAB_POS, 0.0, Vector3.ONE * 1.6)
		_label3d("Chipfabrik", FAB_POS + Vector3(0, 0.15, 1.8), Color("ffc66b"))
	# Konkurrenz: Helix wächst mit jedem Modell
	var hs := 1.6 + minf(int(lab.rival["count"]) * 0.08, 1.4)
	_place_from(CITY, "building-skyscraper-b", HELIX_POS, 0.0, Vector3.ONE * hs)
	_label3d("Helix Dynamics", HELIX_POS + Vector3(0, 0.15, 2.0), Color("ff8a8a"))
	# Stadt-Füllung (fest, damit es nicht flackert)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var fill := ["building-a", "building-b", "building-d", "building-f", "building-h", "building-i", "building-l", "building-m"]
	for i in range(26):
		var p := Vector3(rng.randf_range(-14, 14), 0, rng.randf_range(-14, 14))
		if absf(p.x) < 1.5 or absf(p.z) < 1.5:
			continue
		if p.distance_to(LAB_POS) < 3.5 or p.distance_to(HELIX_POS) < 3.0 or (p.x > 1.5 and p.x < 12.5 and p.z < -1.5 and p.z > -12.5) or p.distance_to(FAB_POS) < 3.0 or (p.x > 3.0 and p.z > 3.0):
			continue
		_place_from(CITY, fill[rng.randi() % fill.size()], p, rng.randf_range(0, 360), Vector3.ONE * rng.randf_range(1.0, 1.6))
	cam_center = Vector3(-1.0, 0, -2.0)
	_world_nature_and_traffic()
	cam_base_size = 23.0


func _find_loc(id: String) -> String:
	for l in D.LOCATIONS:
		if l["id"] == id:
			return l["name"]
	return id


func _label3d(text: String, pos: Vector3, col: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 96
	l.pixel_size = 0.006
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.modulate = col
	l.outline_size = 16
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = pos
	world.add_child(l)


func _ground(sz: Vector2, center: Vector3, col: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.9
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = sz
	mi.mesh = pm
	mi.material_override = mat
	mi.position = center
	world.add_child(mi)


func _add_rack(pos: Vector3) -> void:
	rack_nodes.append(pos)
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.45, 1.0, 0.45)
	body.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("2a2e38")
	mat.metallic = 0.4
	mat.roughness = 0.5
	body.material_override = mat
	body.position = pos + Vector3(0, 0.5, 0)
	world.add_child(body)
	for l in range(4):
		var led := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.3, 0.035, 0.02)
		led.mesh = lm
		var em := StandardMaterial3D.new()
		em.albedo_color = Color.BLACK
		em.emission_enabled = true
		em.emission = Color("6be38a")
		led.material_override = em
		led.position = pos + Vector3(0, 0.2 + l * 0.2, 0.235)
		world.add_child(led)
		rack_lights.append(em)


func _add_person(p: Dictionary, pos: Vector3) -> void:
	var model_name: String = CHAR_MODELS[absi(hash(p["name"])) % CHAR_MODELS.size()]
	var holder := _place_from(CHARS, model_name, pos, 180.0, Vector3(0.85, 0.85, 0.85))
	var anims := holder.find_children("*", "AnimationPlayer", true, false)
	if anims.size() > 0:
		var ap: AnimationPlayer = anims[0]
		for a in ["sit", "idle"]:
			if ap.has_animation(a):
				ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
		ap.play("sit")
		ap.seek(randf() * 0.5)
		people.append({"anim": ap, "node": holder, "seat": pos, "busy": false})
	var ring := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.26
	cm.bottom_radius = 0.26
	cm.height = 0.01
	ring.mesh = cm
	var rm := StandardMaterial3D.new()
	var col: Color = D.ROLES[p["role"]]["color"]
	rm.albedo_color = col
	rm.emission_enabled = true
	rm.emission = col
	rm.emission_energy_multiplier = 0.6
	ring.material_override = rm
	ring.position = Vector3(pos.x, 0.012, pos.z)
	world.add_child(ring)


func _place(model: String, pos: Vector3, rot_y: float, scl := Vector3.ONE, wall := false) -> Node3D:
	return _place_from(FURN, model, pos, rot_y, scl, wall)


## Setzt ein Modell so, dass die Unterseite mittig auf `pos` steht.
func _place_from(dir: String, model: String, pos: Vector3, rot_y: float, scl := Vector3.ONE, wall := false) -> Node3D:
	var path := dir + model + ".glb"
	var inst: Node3D = load(path).instantiate()
	var aabb := _model_aabb(path, inst)
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation_degrees.y = rot_y
	holder.scale = scl
	var off := -Vector3(aabb.position.x + aabb.size.x / 2.0, aabb.position.y, aabb.position.z + aabb.size.z / 2.0)
	if wall:
		off.z = -(aabb.position.z + aabb.size.z)
	inst.position = off
	holder.add_child(inst)
	world.add_child(holder)
	return holder


func _model_aabb(path: String, inst: Node) -> AABB:
	if aabb_cache.has(path):
		return aabb_cache[path]
	var aabb := AABB()
	var first := true
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		var a: AABB = (m as MeshInstance3D).get_aabb()
		var xf := Transform3D.IDENTITY
		var n: Node = m
		while n != null and n != inst:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		a = xf * a
		aabb = a if first else aabb.merge(a)
		first = false
	aabb_cache[path] = aabb
	return aabb
