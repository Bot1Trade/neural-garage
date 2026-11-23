extends Control
## 3D-Ansicht (Vollbild): Büro innen oder Weltansicht (Labor, Rechenzentren, Fabrik, Konkurrenz).
## Modelle: Kenney Furniture Kit, Mini Characters, City Kit Commercial/Roads, Emotes (alle CC0).
## Steuerung: Mausrad = Zoom, rechte Maus = drehen, mittlere/linke Maus ziehen = verschieben, Q/E = drehen.

const D = preload("res://scripts/sim/data.gd")

signal fx_event(fx_name: String)   # für Sounds
signal clicked_ground(pos: Vector3) # Linksklick ohne Ziehen (Grundstücke)
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
var scene_root: Node3D
var tilt_shift := true
var screen_shift_px := 0.0     # Platz, den die Seitenleiste rechts verdeckt
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
var desk_spots: Array = []
var occ: Dictionary = {}       # belegte 0,5-m-Zellen im Büro
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
var drag_moved := false
var press_pos := Vector2.ZERO
var yaw_t := 45.0
var zoom_t := 1.0
var pan_t := Vector3.ZERO
var hover_ground := Vector3(0, -1000, 0)
var plot_highlight: MeshInstance3D
var walls_x: Array = []
var walls_z: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # Eingabe über _unhandled_input (UI hat Vorrang)
	scene_root = Node3D.new()
	add_child(scene_root)
	world = Node3D.new()
	scene_root.add_child(world)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	var ca := CameraAttributesPractical.new()
	ca.dof_blur_far_enabled = true
	ca.dof_blur_near_enabled = true
	ca.dof_blur_amount = 0.025
	camera.attributes = ca
	camera.current = true
	scene_root.add_child(camera)
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
	scene_root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 60.0
	scene_root.add_child(sun)
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


## Grafik-Optionen aus dem Einstellungsmenü anwenden
func apply_graphics(g: Dictionary) -> void:
	tilt_shift = bool(g.get("tilt_shift", true))
	var vp := get_viewport()
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X][int(g.get("msaa", 2))]
	var sc: float = [0.75, 1.0, 1.5, 2.0][int(g.get("scale", 1))]
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = sc
	var sh: int = int(g.get("shadows", 2))
	RenderingServer.directional_shadow_atlas_set_size([2048, 4096, 8192][sh], true)
	RenderingServer.directional_soft_shadow_filter_set_quality([RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH][sh])
	_update_camera()


func set_screen_shift(px: float) -> void:
	screen_shift_px = px
	_update_camera()


func set_mode(m: String) -> void:
	mode = m
	build_key = ""
	pan = Vector3.ZERO
	pan_t = Vector3.ZERO
	zoom = 1.0
	zoom_t = 1.0


# ------------------------------------------------------------------ Eingabe & Kamera
# Mausrad = Zoom zum Mauszeiger · links/mitte ziehen = verschieben (Welt klebt am Zeiger)
# rechts ziehen = drehen · WASD/Pfeile = verschieben · Q/E = 45° drehen · R = zurücksetzen

## Läuft ein Zieh-Vorgang, gehören Bewegung und Loslassen der Kamera – auch über Leisten und Panels.
func _input(ev: InputEvent) -> void:
	if not (drag_pan or drag_rot):
		return
	if ev is InputEventMouseMotion:
		_drag_motion(ev as InputEventMouseMotion)
		get_viewport().set_input_as_handled()
	elif ev is InputEventMouseButton and not ev.pressed:
		var mb := ev as InputEventMouseButton
		if mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE] and drag_pan:
			if mb.button_index == MOUSE_BUTTON_LEFT and not drag_moved:
				clicked_ground.emit(_ground_at(mb.position))
			drag_pan = false
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and drag_rot:
			drag_rot = false
			get_viewport().set_input_as_handled()


func _drag_motion(mm: InputEventMouseMotion) -> void:
	if drag_rot:
		yaw_t -= mm.relative.x * 0.3
	elif drag_pan:
		if mm.position.distance_to(press_pos) > 5.0:
			drag_moved = true
		if drag_moved:
			_pan_pixels(mm.relative)


func _unhandled_input(ev: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom_at(0.85, mb.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom_at(1.0 / 0.85, mb.position)
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE:
				if mb.pressed:
					drag_pan = true
					drag_moved = false
					press_pos = mb.position
				else:
					if mb.button_index == MOUSE_BUTTON_LEFT and not drag_moved:
						clicked_ground.emit(_ground_at(mb.position))
					drag_pan = false
			MOUSE_BUTTON_RIGHT:
				drag_rot = mb.pressed
		get_viewport().set_input_as_handled()
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if drag_rot:
			yaw_t -= mm.relative.x * 0.3
			get_viewport().set_input_as_handled()
		elif drag_pan:
			if mm.position.distance_to(press_pos) > 5.0:
				drag_moved = true
			if drag_moved:
				_pan_pixels(mm.relative)
				get_viewport().set_input_as_handled()
		else:
			hover_ground = _ground_at(mm.position)
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_Q:
				yaw_t += 45.0
			KEY_E:
				yaw_t -= 45.0
			KEY_R, KEY_HOME:
				reset_view()


func reset_view() -> void:
	yaw_t = 45.0
	zoom_t = 1.0
	pan_t = Vector3.ZERO


## Bildschirm-Pixel in Boden-Verschiebung umrechnen (isometrisch, orthografisch)
func _pan_pixels(rel: Vector2) -> void:
	var vh := maxf(1.0, get_viewport().get_visible_rect().size.y)
	var upp := camera.size / vh                 # Welteinheiten pro Pixel
	var r := deg_to_rad(yaw)
	var right := Vector3(cos(r), 0, -sin(r))
	var away := -Vector3(sin(r), 0, cos(r))     # Blickrichtung auf dem Boden
	var pitch_sin := 11.0 / sqrt(11.0 * 11.0 + 14.0 * 14.0)
	var delta := -right * rel.x * upp + away * rel.y * upp / pitch_sin
	pan_t += delta
	_clamp_pan()
	pan = pan_t          # beim Ziehen direkt folgen (Welt klebt am Zeiger)
	_update_camera()


func _zoom_at(factor: float, screen_pos: Vector2) -> void:
	var old_t := zoom_t
	zoom_t = clampf(zoom_t * factor, 0.3, 2.2)
	var f := zoom_t / old_t
	var g := _ground_at(screen_pos)
	if g.y > -100.0:
		var c := cam_center + pan_t
		pan_t += (g - c) * (1.0 - f)
		pan_t.y = 0.0
		_clamp_pan()


func _clamp_pan() -> void:
	var lim := cam_base_size * 1.5
	pan_t = Vector3(clampf(pan_t.x, -lim, lim), 0, clampf(pan_t.z, -lim, lim))


## Punkt auf dem Boden (y = 0) unter einer Bildschirmposition
func _ground_at(screen_pos: Vector2) -> Vector3:
	var o := camera.project_ray_origin(screen_pos)
	var n := camera.project_ray_normal(screen_pos)
	if absf(n.y) < 0.0001:
		return Vector3(0, -1000, 0)
	var t_hit := -o.y / n.y
	return o + n * t_hit


func _smooth_camera(delta: float) -> void:
	# Sicherung: Taste wurde losgelassen, ohne dass wir es mitbekommen haben (z. B. außerhalb des Fensters)
	if DisplayServer.get_name() != "headless":
		if drag_pan and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			drag_pan = false
		if drag_rot and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			drag_rot = false
	var k := 1.0 - exp(-12.0 * delta)
	var moved := false
	var kb := Vector3.ZERO
	var r := deg_to_rad(yaw)
	var right := Vector3(cos(r), 0, -sin(r))
	var away := -Vector3(sin(r), 0, cos(r))
	if not get_viewport().gui_get_focus_owner() is LineEdit:
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			kb += away
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			kb -= away
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			kb += right
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			kb -= right
	if kb != Vector3.ZERO:
		pan_t += kb.normalized() * camera.size * 0.9 * delta
		_clamp_pan()
	if absf(yaw - yaw_t) > 0.05:
		yaw = lerpf(yaw, yaw_t, k)
		moved = true
	if absf(zoom - zoom_t) > 0.0005:
		zoom = lerpf(zoom, zoom_t, k)
		moved = true
	if pan.distance_to(pan_t) > 0.001:
		pan = pan.lerp(pan_t, k)
		moved = true
	if moved:
		_update_camera()


func _update_camera() -> void:
	var r := deg_to_rad(yaw)
	var vh := maxf(1.0, get_viewport().get_visible_rect().size.y)
	var right := Vector3(cos(r), 0, -sin(r))
	var c := cam_center + pan + right * (screen_shift_px * 0.5 * cam_base_size * zoom / vh)
	camera.position = c + Vector3(sin(r) * 14.0, 11.0, cos(r) * 14.0)
	camera.look_at(c, Vector3.UP)
	camera.size = cam_base_size * zoom
	# Tilt-Shift: Mitte scharf, oben/unten leicht unscharf (Miniatur-Look)
	var ca := camera.attributes as CameraAttributesPractical
	if ca != null:
		ca.dof_blur_far_enabled = tilt_shift
		ca.dof_blur_near_enabled = tilt_shift
		var dist := camera.position.distance_to(c)
		ca.dof_blur_far_distance = dist + camera.size * 0.22
		ca.dof_blur_far_transition = camera.size * 0.35
		ca.dof_blur_near_distance = maxf(0.1, dist - camera.size * 0.22)
		ca.dof_blur_near_transition = camera.size * 0.3
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
	_smooth_camera(delta)
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
	if mode == "world" and plot_highlight != null and is_instance_valid(plot_highlight):
		var hp := plot_at(hover_ground)
		plot_highlight.visible = hp != ""
		if hp != "":
			var pl: Dictionary = lab.plot(hp)
			plot_highlight.position = Vector3(float(pl["pos"][0]), 0.03, float(pl["pos"][1]))
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
		for pl in D.PLOTS:
			dcs += String(lab.plot_state(pl["id"])).left(2)
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
	var tier: int = lab.office
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 + tier
	# Gebäudesockel (Schnittkante)
	_box(Vector3(w / 2.0, -0.125, d / 2.0), Vector3(w + 0.3, 0.25, d + 0.3), Color("2b2f37"), 0.0, 0.8)
	_floor(w, d, room["floor"], tier >= 3)
	if tier == 3:
		_build_rooftop(w, d, rng)
		return
	# Rasen + Gehweg ums Haus
	_ground(Vector2(70, 70), Vector3(w / 2.0, -0.12, d / 2.0), Color("4f7d3f"))
	var walk := Color("b9b4aa")
	_box(Vector3(w / 2.0, -0.115, d / 2.0), Vector3(w + 1.6, 0.02, d + 1.6), walk, 0.0, 0.9)
	if tier == 0:
		# Einfahrt + Straße vor der Garage
		_box(Vector3(w + 1.9, -0.11, d / 2.0), Vector3(2.4, 0.02, 2.2), Color("4a4d53"), 0.0, 0.9)
		_place_from(CARS, "sedan", Vector3(w + 1.9, -0.1, d / 2.0), 90.0, Vector3.ONE * 0.32)
		for z in range(-3, d + 5):
			_place_from(ROADS, "road-straight", Vector3(w + 3.7, -0.11, z), 0.0, Vector3.ONE)
		_place_from(ROADS, "light-square", Vector3(w + 3.0, -0.12, d + 1.0), 90.0, Vector3.ONE)
	# Hecken vorne (unterbrochen), Bäume nur hinten
	# geschnittene Hecke mit Lücke als Eingang
	var hedge := Color("2f5e2c")
	_box(Vector3((w + 1.0) * 0.3, 0.05, d + 1.2), Vector3((w + 1.0) * 0.6, 0.34, 0.32), hedge, 0.0, 0.95)
	_box(Vector3((w + 1.0) * 0.85 - 0.2, 0.05, d + 1.2), Vector3((w + 1.0) * 0.3, 0.34, 0.32), hedge, 0.0, 0.95)
	if tier != 0:
		_box(Vector3(w + 1.2, 0.05, (d + 1.0) * 0.35), Vector3(0.32, 0.34, (d + 1.0) * 0.7), hedge, 0.0, 0.95)
	for i in range(16):
		var p := Vector3(rng.randf_range(-4.5, -1.2), -0.12, rng.randf_range(-3.0, d + 2.0)) if i % 2 == 0 else Vector3(rng.randf_range(-3.0, w + 2.0), -0.12, rng.randf_range(-4.5, -1.2))
		_place_from(NATURE, TREES[rng.randi() % TREES.size()], p, rng.randf_range(0, 360), Vector3.ONE * rng.randf_range(1.4, 2.1))
	# Blumenbeete vor den Hecken
	for i in range(10):
		var p := Vector3(rng.randf_range(-0.5, w + 1.5), -0.12, d + rng.randf_range(1.7, 3.2))
		_place_from(NATURE, ["flower_redA", "flower_yellowA", "flower_purpleA"][i % 3], p, rng.randf_range(0, 360), Vector3.ONE * 1.3)


## Tech-Tower: Dachterrasse hoch über der Stadt
func _build_rooftop(w: int, d: int, rng: RandomNumberGenerator) -> void:
	var terr := 2.0
	_box(Vector3(w / 2.0 + 0.5, -0.14, d / 2.0 + 0.5), Vector3(w + terr * 2.0, 0.04, d + terr * 2.0), Color("9a958d"), 0.0, 0.85)
	_box(Vector3(w / 2.0 + 0.5, -2.07, d / 2.0 + 0.5), Vector3(w + terr * 2.0, 3.86, d + terr * 2.0), Color("5d6573"), 0.3, 0.6)
	# Glasgeländer
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.75, 0.88, 1.0, 0.25)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	var x0 := 0.5 - terr + 0.05
	var x1 := w + terr + 0.5 - 0.05
	var z0 := 0.5 - terr + 0.05
	var z1 := d + terr + 0.5 - 0.05
	for seg in [[Vector3((x0 + x1) / 2.0, 0.1, z1), Vector3(x1 - x0, 0.45, 0.03)], [Vector3(x1, 0.1, (z0 + z1) / 2.0), Vector3(0.03, 0.45, z1 - z0)]]:
		var g := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = seg[1]
		g.mesh = bm
		g.material_override = glass
		g.position = seg[0]
		world.add_child(g)
		_box(seg[0] + Vector3(0, 0.23, 0), Vector3(maxf(seg[1].x, 0.05), 0.03, maxf(seg[1].z, 0.05)), Color("c9ccd2"), 0.8, 0.3)
	# Pflanzkübel und Lounge auf der Terrasse
	for i in range(6):
		_place("pottedPlant", Vector3(x1 - 0.4, -0.12, z0 + 0.6 + i * (z1 - z0 - 1.2) / 5.0), rng.randf_range(0, 360), Vector3.ONE * 1.3)
	_place("loungeSofa", Vector3(w * 0.4, -0.12, z1 - 0.45), 180.0)
	_place("tableCoffee", Vector3(w * 0.4, -0.12, z1 - 1.1), 0.0)
	_place("loungeDesignChair", Vector3(w * 0.7, -0.12, z1 - 0.6), 160.0)
	# Stadt unten: Dächer knapp unter der Terrassenkante
	var low_y := -4.0
	_ground(Vector2(90, 90), Vector3(w / 2.0, low_y, d / 2.0), Color("4b5247"))
	for i in range(-12, 13):
		_place_from(ROADS, "road-straight", Vector3(w + terr + 3.0, low_y + 0.005, d / 2.0 + i), 0.0, Vector3.ONE)
	var lows := ["building-a", "building-b", "building-c", "building-d", "building-h", "building-e", "building-k"]
	var placed := 0
	var tries := 0
	while placed < 30 and tries < 300:
		tries += 1
		var p := Vector3(rng.randf_range(-10.0, w + 12.0), low_y, rng.randf_range(-10.0, d + 12.0))
		var inside_x := p.x > 0.5 - terr - 1.2 and p.x < w + terr + 1.7
		var inside_z := p.z > 0.5 - terr - 1.2 and p.z < d + terr + 1.7
		if (inside_x and inside_z) or absf(p.x - (w + terr + 3.0)) < 1.3:
			continue
		_place_from(CITY, lows[rng.randi() % lows.size()], p, [0.0, 90.0, 180.0, 270.0][rng.randi() % 4], Vector3.ONE * rng.randf_range(1.3, 1.8))
		placed += 1
	for i in range(14):
		var p := Vector3(rng.randf_range(-8.0, w + 10.0), low_y, d + terr + rng.randf_range(2.0, 7.0))
		_place_from(NATURE, TREES[rng.randi() % TREES.size()], p, rng.randf_range(0, 360), Vector3.ONE * 1.6)


## Boden: Holzdielen (versetzt) oder Teppichfliesen, je ein MultiMesh
func _floor(w: int, d: int, base: Color, carpet: bool) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var bm := BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.75 if not carpet else 0.95
	bm.material = mat
	var items := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	if carpet:
		bm.size = Vector3(0.49, 0.012, 0.49)
		for x in range(w * 2):
			for z in range(d * 2):
				var c := base.lerp(Color("4a5566"), 0.25)
				c = c.lightened(0.05) if (x + z) % 2 == 0 else c.darkened(0.04)
				items.append([Vector3(x * 0.5 + 0.25, 0.0, z * 0.5 + 0.25), Vector3.ONE, c.lightened(rng.randf_range(-0.03, 0.03))])
	else:
		bm.size = Vector3(1.0, 0.012, 0.19)
		var rows := int(d / 0.2)
		for r in range(rows):
			var x := -rng.randf_range(0.0, 0.8)
			while x < w:
				var length := rng.randf_range(0.8, 1.6)
				var x_a := maxf(x, 0.0)
				var x_b := minf(x + length, float(w))
				if x_b - x_a > 0.05:
					var c := base.lightened(rng.randf_range(-0.07, 0.1))
					items.append([Vector3((x_a + x_b) / 2.0, 0.0, r * 0.2 + 0.1), Vector3(x_b - x_a - 0.012, 1, 1), c])
				x += length
	mm.mesh = bm
	mm.instance_count = items.size()
	for i in range(items.size()):
		var it: Array = items[i]
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(it[1]), it[0]))
		mm.set_instance_color(i, it[2])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	world.add_child(mmi)
	# dunkle Fugen darunter
	_box(Vector3(w / 2.0, -0.007, d / 2.0), Vector3(w, 0.002, d), base.darkened(0.45), 0.0, 0.9)


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
	for pl in D.PLOTS:
		occupied.append(Vector3(float(pl["pos"][0]), 0, float(pl["pos"][1])))
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


func _world_extras() -> void:
	# Parkplatz neben dem Labor
	var lot := LAB_POS + Vector3(2.2, 0.006, 0.4)
	_box(lot, Vector3(1.6, 0.012, 2.0), Color("3b3f46"), 0.0, 0.9)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in range(mini(2 + lab.office, 6)):
		var cp := lot + Vector3(-0.4 + (i % 2) * 0.8, 0.01, -0.7 + floori(i / 2.0) * 0.7)
		_place_from(CARS, CAR_MODELS[rng.randi() % CAR_MODELS.size()], cp, 0.0, Vector3.ONE * 0.24)
	# Park mit Bänken und Brunnen-Rasen
	for park in [Vector3(-9.0, 0, 7.5), Vector3(10.0, 0, 4.0)]:
		_box(park + Vector3(0, 0.004, 0), Vector3(4.0, 0.008, 3.2), Color("4a8a3e"), 0.0, 0.95)
		_box(park + Vector3(0, 0.01, 0), Vector3(3.2, 0.01, 0.35), Color("c8b48a"), 0.0, 0.95)
		_box(park + Vector3(0, 0.01, 0), Vector3(0.35, 0.01, 2.6), Color("c8b48a"), 0.0, 0.95)
		for b in range(4):
			var off: Vector3 = [Vector3(0.6, 0, 0.45), Vector3(-0.6, 0, 0.45), Vector3(0.6, 0, -0.45), Vector3(-0.6, 0, -0.45)][b]
			_place("benchCushion", park + off, 0.0 if off.z < 0 else 180.0, Vector3.ONE * 1.4)
		for tpos in [Vector3(1.5, 0, 1.2), Vector3(-1.5, 0, 1.2), Vector3(1.5, 0, -1.2), Vector3(-1.5, 0, -1.2)]:
			_place_from(NATURE, TREES[rng.randi() % TREES.size()], park + tpos, rng.randf_range(0, 360), Vector3.ONE * 1.8)
		for f in range(10):
			_place_from(NATURE, LOW_PLANTS[rng.randi() % LOW_PLANTS.size()], park + Vector3(rng.randf_range(-1.8, 1.8), 0, rng.randf_range(-1.4, 1.4)), rng.randf_range(0, 360), Vector3.ONE * 1.6)
	# Skyline hinten
	var sky := ["building-skyscraper-a", "building-skyscraper-c", "building-skyscraper-e", "building-l", "building-m"]
	for i in range(9):
		var sp := Vector3(-15.0 + i * 1.6, 0, -15.5) if i % 2 == 0 else Vector3(-15.5, 0, -13.0 + i * 1.6)
		if sp.distance_to(HELIX_POS) < 3.0:
			continue
		_place_from(CITY, sky[i % sky.size()], sp, rng.randf_range(0, 360), Vector3.ONE * rng.randf_range(1.2, 1.7))


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


## Grundstück unter einem Bodenpunkt ("" = keins). margin vergrößert die Fläche.
func plot_at(pos: Vector3, margin := 0.0) -> String:
	var half := D.PLOT_SIZE / 2.0 + margin
	for pl in D.PLOTS:
		if absf(pos.x - float(pl["pos"][0])) <= half and absf(pos.z - float(pl["pos"][1])) <= half:
			return pl["id"]
	return ""


## Brachfläche: Boden, bei Verkauf mit Bauzaun
func _lot(pos: Vector3, col: Color, fence: bool) -> void:
	var sz := D.PLOT_SIZE
	_box(pos + Vector3(0, 0.01, 0), Vector3(sz, 0.02, sz), col, 0.0, 0.95)
	if fence:
		var fc := Color("e8e2d6")
		for side in [[Vector3(0, 0.12, sz / 2.0), Vector3(sz, 0.2, 0.03)], [Vector3(0, 0.12, -sz / 2.0), Vector3(sz, 0.2, 0.03)],
				[Vector3(sz / 2.0, 0.12, 0), Vector3(0.03, 0.2, sz)], [Vector3(-sz / 2.0, 0.12, 0), Vector3(0.03, 0.2, sz)]]:
			_box(pos + side[0], side[1], fc, 0.0, 0.8)
		for c in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1)]:
			_box(pos + c * (sz / 2.0) + Vector3(0, 0.15, 0), Vector3(0.07, 0.3, 0.07), Color("e0752e"), 0.0, 0.7)
	else:
		for c in [Vector3(-0.6, 0, 0.6), Vector3(0.6, 0, -0.6), Vector3(0.7, 0, 0.7)]:
			_box(pos + c + Vector3(0, 0.08, 0), Vector3(0.1, 0.16, 0.1), Color("f08a24"), 0.0, 0.6)


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
	var last_cz := 0.0
	desk_spots.clear()
	var drng := RandomNumberGenerator.new()
	drng.seed = 31
	for i in range(cap):
		var cx := 0.95 + (i % cols) * 1.25
		var cz := 1.1 + floori(i / float(cols)) * 1.35
		if cz > d - 0.5:
			break
		var pos := Vector3(cx, 0, cz)
		last_cz = cz
		desk_spots.append(pos)
		_place("desk", pos, 0.0)
		_desk_clutter(pos, drng)
		if lab.office >= 3:
			_box(pos + Vector3(0, 0.275, -0.24), Vector3(1.05, 0.55, 0.03), Color("6b7a8f"), 0.0, 0.9)
			_box(pos + Vector3(0, 0.555, -0.24), Vector3(1.05, 0.015, 0.04), Color("c9ccd2"), 0.6, 0.4)
		_place("computerScreen", pos + Vector3(0, 0.38, -0.08), 0.0)
		if i < desks:
			_screen_glow(pos + Vector3(0, 0.38 + 0.165, -0.022))
		_place("computerKeyboard", pos + Vector3(0, 0.38, 0.09), 0.0)
		if i < desks:
			_place("chairDesk", pos + Vector3(0, 0, 0.45), 180.0)
			_add_person(lab.staff[i], pos + Vector3(0, SEAT_Y, 0.4))
		else:
			_place("chairDesk", pos + Vector3(0.05, 0, 0.48), 200.0)

	_decorate_office(w, d, last_cz, racks)

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
	# Grundstücke: zu verkaufen / eigen & leer / Rechenzentrum / Fabrik
	var dc_by_plot := {}
	var loose := []
	for dc in lab.datacenters:
		if String(dc.get("plot", "")) != "":
			dc_by_plot[dc["plot"]] = dc
		else:
			loose.append(dc)   # alte Spielstände ohne Grundstück
	for pl in D.PLOTS:
		var pos := Vector3(float(pl["pos"][0]), 0, float(pl["pos"][1]))
		var st: String = lab.plot_state(pl["id"])
		if st in ["locked", "for_sale"] and not loose.is_empty():
			dc_by_plot[pl["id"]] = loose.pop_front()
			st = "dc"
		var region := _find_loc(pl["loc"])
		match st:
			"for_sale":
				_lot(pos, Color("8b7152"), true)
				_label3d("%s
zu verkaufen · %s" % [pl["name"], lab.fmt_money(lab.plot_price(pl["id"]))], pos + Vector3(0, 0.3, 0), Color("ffe08a"), 0.55)
			"empty":
				_lot(pos, Color("a3a5a8"), false)
				_label3d("Dein Grundstück · %s
klicken zum Bauen" % region, pos + Vector3(0, 0.3, 0), Color("9fd0ff"), 0.55)
			"dc":
				var dc: Dictionary = dc_by_plot.get(pl["id"], {})
				var b: Array = DC_BUILDINGS[dc.get("type", "colo")]
				_place_from(CITY, b[0], pos, 0.0, Vector3.ONE * float(b[1]))
				_label3d(region, pos + Vector3(0, 0.15, 1.5), Color("a0e8b0"), 0.7)
				for l in range(2):
					_add_rack(pos + Vector3(-0.5 + l * 0.6, 0, 1.0))
			"plant":
				var kind := String(lab.plots[pl["id"]]).substr(6)
				_lot(pos, Color("6f8f55"), false)
				if kind == "solarpark":
					for r in range(4):
						for c2 in range(4):
							var panel := _box(pos + Vector3(-0.95 + c2 * 0.63, 0.22, -0.95 + r * 0.63), Vector3(0.55, 0.03, 0.42), Color("1d3a66"), 0.6, 0.25)
							panel.rotation_degrees.x = -25.0
				else:
					for k in range(3):
						var tp := pos + Vector3(-0.8 + k * 0.8, 0, -0.5 + (k % 2) * 0.9)
						_box(tp + Vector3(0, 1.1, 0), Vector3(0.08, 2.2, 0.08), Color("e8ecf0"), 0.2, 0.5)
						for bl in range(3):
							var blade := _box(tp + Vector3(0, 2.2, 0.06), Vector3(0.06, 0.9, 0.02), Color("f4f6f8"), 0.1, 0.5)
							blade.rotation_degrees.z = bl * 120.0 + k * 25.0
							blade.position += Vector3(sin(deg_to_rad(blade.rotation_degrees.z)) * -0.42, cos(deg_to_rad(blade.rotation_degrees.z)) * 0.42, 0)
				_label3d(lab.plant(kind)["name"], pos + Vector3(0, 0.15, 1.6), Color("bff0a0"), 0.7)
			"fab":
				_place_from(CITY, "building-m", pos, 0.0, Vector3.ONE * 1.6)
				_label3d("Chipfabrik", pos + Vector3(0, 0.15, 1.8), Color("ffc66b"), 0.8)
	# Hover-Rahmen für Grundstücke
	plot_highlight = MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(D.PLOT_SIZE + 0.2, 0.04, D.PLOT_SIZE + 0.2)
	plot_highlight.mesh = hm
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(1.0, 0.85, 0.3, 0.35)
	hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hmat.emission_enabled = true
	hmat.emission = Color(1.0, 0.8, 0.3)
	hmat.emission_energy_multiplier = 0.6
	hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	plot_highlight.material_override = hmat
	plot_highlight.visible = false
	world.add_child(plot_highlight)
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
		if p.distance_to(LAB_POS) < 3.5 or p.distance_to(HELIX_POS) < 3.0 or (p.x > 3.0 and p.z > 3.0) or plot_at(p, 2.0) != "":
			continue
		_place_from(CITY, fill[rng.randi() % fill.size()], p, rng.randf_range(0, 360), Vector3.ONE * rng.randf_range(1.0, 1.6))
	cam_center = Vector3(-1.0, 0, -2.0)
	_world_extras()
	_world_nature_and_traffic()
	cam_base_size = 23.0


func _find_loc(id: String) -> String:
	for l in D.LOCATIONS:
		if l["id"] == id:
			return l["name"]
	return id


func _label3d(text: String, pos: Vector3, col: Color, scale := 1.0) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 96
	l.pixel_size = 0.006 * scale
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
	_box(pos + Vector3(0, 0.5, 0), Vector3(0.45, 1.0, 0.45), Color("23262e"), 0.5, 0.45)
	_box(pos + Vector3(0, 0.5, 0.226), Vector3(0.38, 0.9, 0.01), Color("12141a"), 0.2, 0.2)
	_box(pos + Vector3(0, 1.005, 0), Vector3(0.45, 0.01, 0.45), Color("3a3f4a"), 0.6, 0.4)
	var strip := _box(pos + Vector3(0, 0.97, 0.232), Vector3(0.38, 0.015, 0.006), Color.BLACK, 0.0, 0.5)
	var sm: StandardMaterial3D = strip.material_override
	sm.emission_enabled = true
	sm.emission = Color("4aa8ff")
	sm.emission_energy_multiplier = 1.5
	for row in range(6):
		for col in range(2):
			var led := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(0.05, 0.022, 0.01)
			led.mesh = lm
			var em := StandardMaterial3D.new()
			em.albedo_color = Color.BLACK
			em.emission_enabled = true
			em.emission = Color("6be38a")
			led.material_override = em
			led.position = pos + Vector3(-0.12 + col * 0.24, 0.16 + row * 0.13, 0.233)
			world.add_child(led)
			rack_lights.append(em)


func _box(pos: Vector3, sz: Vector3, col: Color, metal: float, rough: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.metallic = metal
	mat.roughness = rough
	mi.material_override = mat
	mi.position = pos
	world.add_child(mi)
	return mi


# ------------------------------------------------------------------ Büro-Deko

## Kleinkram auf dem Schreibtisch (fest pro Platz)
func _desk_clutter(pos: Vector3, rng: RandomNumberGenerator) -> void:
	var top := pos + Vector3(0, 0.38, 0)
	var r := rng.randf()
	if r < 0.3:
		_place(["plantSmall1", "plantSmall2", "plantSmall3"][rng.randi() % 3], top + Vector3(0.27, 0, -0.1), rng.randf_range(0, 360))
	elif r < 0.55:
		_place("books", top + Vector3(-0.26, 0, -0.1), rng.randf_range(-20, 20))
	elif r < 0.75:
		_place("lampRoundTable", top + Vector3(-0.27, 0, -0.1), 30.0)
	if rng.randf() < 0.25:
		_place("books", top + Vector3(0.26, 0, 0.05), rng.randf_range(60, 120))


func _decorate_office(w: int, d: int, last_cz: float, racks: int) -> void:
	var up: Dictionary = lab.office_upgrades
	var tier: int = lab.office
	var rack_depth := 0.45 + ceili(racks / 2.0) * 0.6
	# Serverecke: dunkler Doppelboden
	if racks > 0:
		_box(Vector3(w - 0.72, 0.006, rack_depth / 2.0), Vector3(1.3, 0.012, rack_depth + 0.2), Color("1d2027"), 0.3, 0.6)
	# Wandverkleidung (ab Hinterhof-Büro) – hängt an den Wänden, blendet mit ihnen aus
	if tier >= 1:
		for i in range(w * 2):
			walls_z.append(_place("paneling", Vector3(i * 0.5 + 0.25, 0, 0.05), 0.0))
		for i in range(d * 2):
			walls_x.append(_place("paneling", Vector3(0.05, 0, i * 0.5 + 0.25), 90.0))
	# Bilder an den Wänden (zwischen den Fenstern)
	var art := ["emote_idea", "emote_star", "emote_heart", "emote_bars", "emote_music", "emote_cloud"]
	var k := 0
	for x in range(0, w, 2):
		if x + 0.5 < w - 1.6:
			_poster(Vector3(x + 0.5, 0.82, 0.07), 0.0, art[k % art.size()], walls_z)
			k += 1
	for z in range(0, d, 2):
		_poster(Vector3(0.07, 0.82, z + 0.5), 90.0, art[k % art.size()], walls_x)
		k += 1
	# Ecken & Standard-Möbel
	_place("pottedPlant", Vector3(0.35, 0, d - 0.35), 0.0)
	_place("pottedPlant", Vector3(0.35, 0, 0.35), 0.0)
	_place("trashcan", Vector3(0.75, 0, 0.3), 0.0)
	_place("coatRackStanding", Vector3(0.3, 0, d - 0.95), 0.0)
	var free_front := float(d) - (last_cz + 0.85)
	if tier == 0:
		# Garage: Kartons und Werkbank
		_place("cardboardBoxClosed", Vector3(w - 1.7, 0, d - 0.3), 10.0)
		_place("cardboardBoxClosed", Vector3(w - 1.45, 0, d - 0.35), -15.0)
		_place("cardboardBoxClosed", Vector3(w - 1.58, 0.28, d - 0.32), 30.0)
		_place("cardboardBoxOpen", Vector3(w - 2.2, 0, d - 0.3), 0.0)
		_place("radio", Vector3(1.6, 0, 0.2), 0.0)
	if tier >= 2:
		_place("bookcaseOpenLow", Vector3(1.6, 0, 0.2), 0.0)
		_place("bookcaseOpenLow", Vector3(2.05, 0, 0.2), 0.0)
	if up.has("coffee"):
		_place("kitchenBar", Vector3(w - 0.35, 0, d - 0.3), -90.0)
		_place("kitchenCoffeeMachine", Vector3(w - 0.35, 0.42, d - 0.3), -90.0)
		_place("kitchenFridge", Vector3(w - 0.3, 0, d - 0.85), -90.0)
	if up.has("meeting"):
		_place("bookcaseClosed", Vector3(2.6, 0, 0.2), 0.0)
		_place("bookcaseOpen", Vector3(3.05, 0, 0.2), 0.0)
	if up.has("gym"):
		_place("rugRectangle", Vector3(w - 2.2, 0.0, d - 0.9), 0.0)
		_place("loungeSofa", Vector3(w - 2.2, 0, d - 0.35), 180.0)
		_place("tableCoffee", Vector3(w - 2.2, 0, d - 1.0), 0.0)
		_place("lampSquareFloor", Vector3(w - 3.0, 0, d - 0.3), 0.0)
		_place("loungeDesignChair", Vector3(w - 3.2, 0, d - 1.0), 90.0)
	if up.has("hwlab"):
		_place("tableCross", Vector3(w - 1.0, 0, rack_depth + 0.5), 90.0)
		_place("cardboardBoxOpen", Vector3(w - 1.6, 0, rack_depth + 0.3), 15.0)
		_place("speakerSmall", Vector3(w - 1.0, 0.35, rack_depth + 0.35), 0.0)
	if up.has("daycare"):
		_place("bear", Vector3(0.9, 0, d - 0.35), 140.0)
		_place("rugRounded", Vector3(1.1, 0.004, d - 0.5), 0.0, Vector3.ONE * 0.6)
	if tier >= 4:
		walls_x.append(_place("televisionModern", Vector3(0.1, 0.6, d / 2.0), 90.0))
	_auto_fill(w, d, rack_depth, racks)


# ---- Belegungskarte: freie Flächen finden und füllen
func _mark(x0: float, z0: float, x1: float, z1: float) -> void:
	for gx in range(floori(x0 * 2.0), ceili(x1 * 2.0)):
		for gz in range(floori(z0 * 2.0), ceili(z1 * 2.0)):
			occ[Vector2i(gx, gz)] = true


func _free(gx: int, gz: int, n: int, w: int, d: int) -> bool:
	if gx < 0 or gz < 0 or gx + n > w * 2 or gz + n > d * 2:
		return false
	for x in range(gx, gx + n):
		for z in range(gz, gz + n):
			if occ.has(Vector2i(x, z)):
				return false
	return true


func _find_spot(n: int, w: int, d: int) -> Vector3:
	# vorne (große z) zuerst, damit die Fläche zur Kamera hin gefüllt wird
	for gz in range(d * 2 - n, -1, -1):
		for gx in range(0, w * 2 - n + 1):
			if _free(gx, gz, n, w, d):
				_mark(gx / 2.0, gz / 2.0, (gx + n) / 2.0, (gz + n) / 2.0)
				return Vector3((gx + n / 2.0) / 2.0, 0, (gz + n / 2.0) / 2.0)
	return Vector3(-1, -1, -1)


func _auto_fill(w: int, d: int, rack_depth: float, racks: int) -> void:
	occ.clear()
	_mark(0, 0, w, 0.55)                 # Rückwand
	_mark(0, 0, 0.55, d)                 # linke Wand
	_mark(0, d - 1.2, 0.6, d)            # Garderobe/Pflanze
	for dp in desk_spots:
		_mark(dp.x - 0.6, dp.z - 0.35, dp.x + 0.6, dp.z + 0.9)
	if racks > 0:
		_mark(w - 1.45, 0, w, rack_depth + 0.15)
	var up: Dictionary = lab.office_upgrades
	if up.has("coffee"):
		_mark(w - 0.9, d - 1.2, w, d)
	if up.has("gym"):
		_mark(w - 3.5, d - 1.6, w - 1.4, d)
	if up.has("hwlab"):
		_mark(w - 1.8, rack_depth, w - 0.4, rack_depth + 1.0)
	if up.has("daycare"):
		_mark(0.5, d - 1.0, 1.7, d)
	if lab.office == 0:
		_mark(w - 2.6, d - 0.8, w - 1.0, d)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11 + lab.office
	# 1) Besprechungsecke (1,5 m)
	var m := _find_spot(3, w, d)
	if m.y >= 0.0 and lab.office >= 1:
		_place("rugRound", m + Vector3(0, 0.004, 0), 0.0, Vector3.ONE * 1.15)
		_place("tableRound", m, 0.0, Vector3.ONE * 0.9)
		for a in range(4):
			var ang := a * PI / 2.0 + PI / 4.0
			_place("chairCushion", m + Vector3(sin(ang) * 0.42, 0, cos(ang) * 0.42), rad_to_deg(ang) + 180.0)
		_place("laptop", m + Vector3(0, 0.33, 0), 20.0, Vector3.ONE * 0.8)
	# 2) weitere freie Meter: Lounge-Sessel oder Pflanzeninsel
	for i in range(6):
		var q := _find_spot(2, w, d)
		if q.y < 0.0:
			break
		if i % 2 == 0:
			_place("rugSquare", q + Vector3(0, 0.004, 0), 0.0, Vector3.ONE * 0.9)
			_place("loungeChair", q + Vector3(-0.2, 0, 0), 60.0)
			_place("sideTable", q + Vector3(0.28, 0, 0.1), -30.0, Vector3.ONE * 0.6)
			_place("plantSmall2", q + Vector3(0.28, 0.23, 0.1), 0.0)
		else:
			_place("pottedPlant", q + Vector3(-0.15, 0, -0.1), rng.randf_range(0, 360))
			_place_from(NATURE, LOW_PLANTS[rng.randi() % 3], q + Vector3(0.2, 0, 0.15), rng.randf_range(0, 360), Vector3.ONE * 1.3)
			_place("lampSquareFloor", q + Vector3(0.2, 0, -0.2), 0.0)
	# 3) schmale Reste: einzelne Pflanzen
	for i in range(4):
		var r := _find_spot(1, w, d)
		if r.y < 0.0:
			break
		if i % 2 == 0:
			_place("pottedPlant", r, rng.randf_range(0, 360))
		else:
			_place_from(NATURE, "plant_bushLarge", r, rng.randf_range(0, 360), Vector3.ONE * 1.4)


## Gerahmtes Bild an der Wand (Kenney-Emote als Motiv)
func _poster(pos: Vector3, rot_y: float, img: String, wall_list: Array) -> void:
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation_degrees.y = rot_y
	holder.scale = Vector3.ONE * 1.5
	world.add_child(holder)
	var frame := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.36, 0.3, 0.02)
	frame.mesh = fm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("5a4634")
	frame.material_override = mat
	holder.add_child(frame)
	var bg := MeshInstance3D.new()
	var bgm := BoxMesh.new()
	bgm.size = Vector3(0.3, 0.24, 0.005)
	bg.mesh = bgm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color("f1ece2")
	bg.material_override = bmat
	bg.position = Vector3(0, 0, 0.012)
	holder.add_child(bg)
	var sp := Sprite3D.new()
	var tex: Texture2D = load(EMOTES + img + ".png")
	sp.texture = tex
	sp.pixel_size = 0.17 / maxf(1.0, tex.get_width())
	sp.position = Vector3(0, 0, 0.016)
	holder.add_child(sp)
	wall_list.append(holder)


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
	var cm := TorusMesh.new()
	cm.inner_radius = 0.19
	cm.outer_radius = 0.23
	ring.mesh = cm
	ring.scale = Vector3(1.0, 0.25, 1.0)
	var rm := StandardMaterial3D.new()
	var col: Color = D.ROLES[p["role"]]["color"]
	rm.albedo_color = col
	rm.emission_enabled = true
	rm.emission = col
	rm.emission_energy_multiplier = 0.35
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
