extends PanelContainer
## Geführtes Tutorial unter den Tabs. Fortschritt steht in lab.flags["tut"] (-1 = aus) → wird mitgespeichert.
## Schritte mit done == "next" warten auf den Weiter-Knopf, alle anderen auf eine Spielaktion.

const STEPS := [
	{"title": "Willkommen", "tab": -1, "done": "next",
		"text": "Es ist 2016, du sitzt mit deiner Mitgründung in einer Garage. Ihr wollt ein KI-Labor aufbauen – und irgendwann eine AGI, die der Menschheit hilft.\nDas Spiel ist pausiert, bis du loslegst."},
	{"title": "Dein erstes Modell", "tab": 0, "done": "training",
		"text": "Klick unten auf die Zielscheibe (leuchtet gelb): Dort entwirfst du KI-Modelle. Hake 'Web-Crawl' und 'Open-Source-Code' an, lass die Größe auf 100M und klicke 'Training starten'. Die Regler kannst du nach Gefühl setzen – was gefragt ist, lernst du später aus den Kritiken."},
	{"title": "Team aufbauen", "tab": 1, "done": "staff2",
		"text": "Die Zeit läuft jetzt (oben rechts: Tempo, Leertaste = Pause). Allein dauert alles ewig: Stelle über das Team-Symbol eine weitere Person ein. Engineering beschleunigt das Training, Forschung bringt Qualität und Forschungspunkte."},
	{"title": "Mehr Rechenleistung", "tab": 2, "done": "gpu4",
		"text": "Mehr GPUs = schnelleres Training. Miete über das Signal-Symbol ein paar dazu. Behalte oben die Tagesbilanz im Blick – GPUs und Gehälter kosten jeden Tag Geld."},
	{"title": "Veröffentlichen", "tab": -1, "done": "released",
		"text": "Warte, bis das Training fertig ist. Dann entscheidest du: Paper (Reputation + Zuschuss), API (täglicher Umsatz) oder Open Weights (viel Reputation, doppeltes Risiko). Für den Anfang ist 'API' gut."},
	{"title": "Kritiken lesen", "tab": -1, "done": "next",
		"text": "Das Feedback der Kritiken ist dein wichtigstes Werkzeug: 'Nutzer wünschen sich mehr …' sagt dir, wie du die Regler beim nächsten Modell stellen solltest. Der Geschmack des Marktes ändert sich über die Jahre (Ären)."},
	{"title": "Forschung", "tab": 3, "done": "next",
		"text": "Forschende sammeln Forschungspunkte. Die Glühbirne öffnet die Forschung. Ab 2017 gibt es den Transformer – ein riesiger Qualitätssprung. Später kommen bessere Architekturen und Sicherheits-Techniken dazu."},
	{"title": "Risiko", "tab": 4, "done": "next",
		"text": "Jedes veröffentlichte Modell kann Schaden anrichten. Das Risiko siehst du erst mit einem Safety-Team. Der Sicherheits-Regler, Evaluierungstage und Sicherheits-Forschung senken es. Zu viel Risiko führt zu Skandalen – oder zur Katastrophe."},
	{"title": "Los geht's!", "tab": -1, "done": "next",
		"text": "Das aktuelle Ziel steht oben, alle Ziele unter dem Pokal. Mit Tab (oder der Lupe) wechselst du in die Weltansicht. Maus: Rad = Zoom, rechte Taste = drehen, ziehen = verschieben. Investoren melden sich, wenn deine Reputation steigt. Und Helix Dynamics schläft nicht … Viel Erfolg!"},
]

var lab
var main_ui            # für _set_speed
var tabs: TabContainer
var tab_names: Array = []
var title_l: Label
var text_l: Label
var next_b: Button
var shown := -2


func setup(p_main, p_tabs: TabContainer) -> void:
	main_ui = p_main
	tabs = p_tabs
	tab_names.clear()
	for i in range(tabs.get_tab_count()):
		tab_names.append(tabs.get_tab_title(i))


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1f2a3a")
	sb.border_color = Color("6fb6ff")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(12)
	add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	title_l = Label.new()
	title_l.add_theme_font_size_override("font_size", 17)
	title_l.add_theme_color_override("font_color", Color("6fb6ff"))
	title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(title_l)
	var skip := Button.new()
	skip.text = "Tutorial beenden"
	skip.focus_mode = Control.FOCUS_NONE
	skip.pressed.connect(func(): lab.flags["tut"] = -1)
	h.add_child(skip)
	text_l = Label.new()
	text_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_l.custom_minimum_size.x = 300
	text_l.add_theme_font_size_override("font_size", 15)
	v.add_child(text_l)
	next_b = Button.new()
	next_b.focus_mode = Control.FOCUS_NONE
	next_b.size_flags_horizontal = Control.SIZE_SHRINK_END
	next_b.custom_minimum_size.x = 140
	next_b.pressed.connect(func(): lab.flags["tut"] = step() + 1)
	v.add_child(next_b)
	visible = false


func step() -> int:
	return int(lab.flags.get("tut", -1)) if lab != null else -1


func _process(_delta: float) -> void:
	var s := step()
	var active := s >= 0 and s < STEPS.size()
	visible = active
	if not active:
		if shown != -1:
			shown = -1
			_mark_tab(-1)
		return
	var st: Dictionary = STEPS[s]
	if _done(st["done"]):
		lab.flags["tut"] = s + 1
		if st["done"] == "training" and main_ui != null and main_ui.speed == 0:
			main_ui._set_speed(1)
		return
	if s != shown:
		shown = s
		title_l.text = "Tutorial %d/%d  ·  %s" % [s + 1, STEPS.size(), st["title"]]
		text_l.text = st["text"]
		next_b.visible = st["done"] == "next"
		next_b.text = "Fertig" if s == STEPS.size() - 1 else "Weiter"
		_mark_tab(int(st["tab"]))


func _done(cond: String) -> bool:
	match cond:
		"training":
			return not lab.training.is_empty() or lab.models.size() > 0
		"staff2":
			return lab.staff.size() >= 2
		"gpu4":
			return lab.gpu_count() >= 4
		"released":
			return lab.best_rating > 0.0
	return false


func _mark_tab(idx: int) -> void:
	if main_ui != null and main_ui.has_method("highlight_tool"):
		main_ui.highlight_tool(idx)
