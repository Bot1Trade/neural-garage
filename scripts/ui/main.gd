extends Control
## Hauptbildschirm. Die UI wird komplett im Code gebaut.
## Screenshot-Modus: godot --path . -- --shot=out.png [--days=N] [--tab=I] [--modal]

const Lab = preload("res://scripts/sim/lab.gd")
const D = preload("res://scripts/sim/data.gd")
const Bot = preload("res://scripts/sim/bot.gd")
const Office3D = preload("res://scripts/ui/office_3d.gd")
const Tutorial = preload("res://scripts/ui/tutorial.gd")
const Audio = preload("res://scripts/ui/audio.gd")
const Settings = preload("res://scripts/ui/settings.gd")

const SAVE_PATH := "user://save.json"
const SPEEDS := [0.0, 0.6, 0.25, 0.08]     # Sekunden pro Spieltag
const TOOLS := [
	{"icon": "icons/target", "title": "Modell", "tip": "Modell entwerfen & trainieren (Taste M)"},
	{"icon": "icons/multiplayer", "title": "Team", "tip": "Team & Bewerbungen"},
	{"icon": "icons/signal3", "title": "Compute", "tip": "GPUs mieten"},
	{"icon": "emotes/emote_idea", "title": "Forschung", "tip": "Forschung"},
	{"icon": "icons/shoppingCart", "title": "Produkte", "tip": "Modelle & Produkte"},
	{"icon": "icons/home", "title": "Ausbau", "tip": "Büros, Rechenzentren, Chips"},
	{"icon": "icons/trophy", "title": "Ziele", "tip": "Ziele"},
	{"icon": "icons/exclamation", "title": "Neuigkeiten", "tip": "Alle Neuigkeiten"},
	{"icon": "icons/barsVertical", "title": "Finanzen", "tip": "Wofür geht das Geld raus? (Taste F)"},
	{"icon": "emotes/emote_question", "title": "Berater", "tip": "Tipps, wie du effektiver wirst (Taste B)"},
]

const C_BG := Color("13151b")
const C_PANEL := Color("1c2029")
const C_PANEL2 := Color("272c38")
const C_ACCENT := Color("6fb6ff")
const C_TEXT := Color("e6e8ee")
const C_DIM := Color("8a90a0")
const C_GOOD := Color("7be08f")
const C_BAD := Color("ff7a7a")
const C_WARN := Color("ffc66b")

var lab
var speed := 1
var last_speed := 1
var acc := 0.0
var built_rev := -1
var design_key := ""
var design: Dictionary = {}
var design_model_id := -1
var modal_event = null
var news_seen := 0
var autosave_day := 0

var top := {}
var speed_btns := []
var tabs: TabContainer
var tab_model: VBoxContainer
var tab_team: VBoxContainer
var tab_compute: VBoxContainer
var tab_research: VBoxContainer
var tab_products: VBoxContainer
var tab_infra: VBoxContainer
var tab_finance: VBoxContainer
var tab_advisor: VBoxContainer
var finance_day := -1
var advisor_day := -1
var last_advice_toast := -1000
var last_advice_text := ""
var advice_checked_day := -1
var chip_bar: ProgressBar
var infra_type_sel := 0
var infra_loc_sel := 2
var goals_box: VBoxContainer
var news_box: RichTextLabel
var drawer: PanelContainer
var drawer_title: Label
var drawer_icon: TextureRect
var tool_btns := []
var tut_tool := -1
var view_btn: Button
var toast_box: VBoxContainer
var goal_pill: Label
var audio: Node
var ui_ready := false
var sound_popup: PopupPanel
var gfx_popup: PopupPanel
var plot_popup: PopupPanel
var focus_sliders := {}
var focus_info: Label
var focus_lock := false
var gfx: Dictionary = {"tilt_shift": true, "msaa": 2, "scale": 1, "shadows": 2, "fullscreen": false}
var office_view: Control
var tutorial: PanelContainer
var design_info: RichTextLabel
var design_error: Label
var train_bar: ProgressBar
var train_label: Label
var research_rp_label: Label
var research_btns := []
var product_labels := []
var modal: Control
var modal_title: Label
var modal_text: RichTextLabel
var modal_buttons: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # Kamera bekommt Maus-Events über _unhandled_input
	audio = Audio.new()
	add_child(audio)
	theme = _make_theme()
	_build_ui()
	_load_gfx()
	_new_game()
	ui_ready = true
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--shot="):
			_screenshot_mode(args)
			return


func _new_game() -> void:
	lab = Lab.new()
	lab.setup()
	lab.flags["tut"] = 0
	_reset_view()
	_set_speed(0)


func _reset_view() -> void:
	design = lab.default_design()
	design_model_id = lab.next_model_id
	built_rev = -1
	design_key = ""
	modal_event = null
	modal.visible = false
	news_box.clear()
	news_seen = maxi(0, lab.news_total - lab.news.size())
	autosave_day = lab.day
	office_view.lab = lab
	tutorial.lab = lab


# ================================================================ Spielschleife

func _process(delta: float) -> void:
	if lab == null:
		return
	_check_modal()
	if not modal.visible and lab.ending.is_empty() and speed > 0:
		acc += delta
		var spd: float = SPEEDS[speed]
		var steps := 0
		while acc >= spd and steps < 20:
			acc -= spd
			lab.step_day()
			steps += 1
			if not lab.event_queue.is_empty() or not lab.ending.is_empty():
				acc = 0.0
				break
		if lab.day - autosave_day >= 90:
			autosave_day = lab.day
			_save(true)
	_refresh()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_SPACE:
				_set_speed(0 if speed > 0 else last_speed)
			KEY_1:
				_set_speed(1)
			KEY_2:
				_set_speed(2)
			KEY_3:
				_set_speed(3)
			KEY_F11:
				gfx["fullscreen"] = not bool(gfx["fullscreen"])
				_apply_gfx()
			KEY_ESCAPE:
				drawer.visible = false
				highlight_tool(-2)
			KEY_TAB:
				_toggle_world()
			KEY_M:
				_open_tab(0)
			KEY_F:
				_open_tab(8)
			KEY_B:
				_open_tab(9)


func _set_speed(i: int) -> void:
	if ui_ready and i != speed:
		audio.play("speed")
	if i > 0:
		last_speed = i
	speed = i
	for j in range(speed_btns.size()):
		speed_btns[j].modulate = C_ACCENT if j == speed else Color(1, 1, 1, 0.6)


# ================================================================ Refresh

func _refresh() -> void:
	var net: float = lab.last_income - lab.last_cost
	top["date"].text = lab.date_string()
	top["era"].text = lab.era()["name"]
	goal_pill.text = D.GOALS[lab.goal_index]["text"] if lab.goal_index < D.GOALS.size() else "Alle Ziele erreicht!"
	top["money"].text = "%s  %s%s" % [lab.fmt_money(lab.money), "+" if net >= 0.0 else "", lab.fmt_money(net)]
	top["money"].modulate = C_GOOD if net >= 0.0 else (C_BAD if lab.money < 0.0 else C_WARN)
	top["compute"].text = _short(lab.compute_power())
	top["rep"].text = "%.0f" % lab.reputation
	top["rp"].text = _short(lab.rp)
	top["risk"].text = ("%.1f" % lab.hidden_risk()) if lab.can_see_risk() else "?"
	top["risk"].modulate = C_BAD if lab.can_see_risk() and lab.hidden_risk() > 3.0 else Color.WHITE
	top["equity"].text = "%.0f%%" % lab.equity

	if lab.news_total > news_seen:
		var new_count: int = mini(lab.news_total - news_seen, lab.news.size())
		for i in range(lab.news.size() - new_count, lab.news.size()):
			news_box.append_text(lab.news[i] + "\n")
			if new_count <= 6:
				_toast(lab.news[i])
		news_seen = lab.news_total

	if lab.revision != built_rev:
		built_rev = lab.revision
		_build_team()
		_build_compute()
		_build_research()
		_build_products()
		_build_infra()
		for tb in [tab_team, tab_compute, tab_research, tab_products, tab_infra]:
			_fit_texts(tb)
		_build_goals()
	var key := "%s|%d|%d|%d|%d" % [lab.training.is_empty(), lab.arch_list().size(), _available_data().size(), lab.next_model_id, int(lab.can_see_risk())]
	if key != design_key:
		design_key = key
		_build_model_tab()

	if train_bar != null and not lab.training.is_empty():
		var tr: Dictionary = lab.training
		var days_left: float = lab.training_days_left()
		if tr["phase"] == "train":
			train_bar.value = 100.0 * float(tr["progress"]) / float(tr["gpu_days"])
			train_label.text = "Phase: Training  ·  noch ~%d Tage (+%d Tage Evaluierung)" % [ceili(days_left - int(tr["eval_left"])), int(tr["eval_left"])]
		else:
			train_bar.value = 100.0
			train_label.text = "Phase: Sicherheits-Evaluierung  ·  noch %d Tage" % int(tr["eval_left"])
	if research_rp_label != null:
		research_rp_label.text = "Forschungspunkte: %.0f  (+%.2f pro Tag)" % [lab.rp, lab.rp_per_day()]
	for rb in research_btns:
		rb["btn"].disabled = lab.rp < rb["cost"]
	if drawer.visible and tabs.current_tab == 8 and lab.day != finance_day:
		_build_finance()
	if drawer.visible and tabs.current_tab == 9 and (lab.day - advisor_day >= 3 or lab.revision != built_rev or advisor_day < 0):
		_build_advisor()
	_advisor_toast()
	if chip_bar != null and not lab.chip_project.is_empty():
		chip_bar.value = 100.0 * float(lab.chip_project["progress"])
	for pl in product_labels:
		var m: Dictionary = lab.get_model(pl["id"])
		if not m.is_empty() and m["status"] == "api":
			pl["label"].text = "%s/Tag" % lab.fmt_money(lab.model_revenue(m))


# ================================================================ Tabs

func _build_model_tab() -> void:
	_clear(tab_model)
	train_bar = null
	design_info = null
	if not lab.training.is_empty():
		var tr: Dictionary = lab.training
		tab_model.add_child(_label("Training: %s" % tr["design"]["name"], 22, C_ACCENT))
		train_label = _label("", 16)
		tab_model.add_child(train_label)
		train_bar = ProgressBar.new()
		train_bar.custom_minimum_size.y = 28
		tab_model.add_child(train_bar)
		var dz: Dictionary = tr["design"]
		var parts := []
		for k in D.FOCUS_KEYS:
			parts.append("%s %d" % [D.FOCUS_NAMES[k], int(dz["focus"][k])])
		var datas := []
		for did in dz["data"]:
			datas.append(D.DATA[did]["name"])
		var info := GridContainer.new()
		info.columns = 2
		info.add_theme_constant_override("h_separation", 16)
		info.add_theme_constant_override("v_separation", 6)
		for pair in [["Architektur", lab.tech(dz["arch"])["name"]], ["Größe", _size_name(D.SIZES[int(dz["size_index"])]) + " Parameter"],
				["Daten", ", ".join(datas)], ["Fokus", " · ".join(parts)], ["Evaluierung", "%d Tage" % int(dz["eval_days"])],
				["Leistung", "%.2f× des heutigen Marktniveaus" % (float(tr["q"]) / lab.expected_quality())]]:
			info.add_child(_label(pair[0], 14, C_DIM))
			info.add_child(_wrap(pair[1], C_TEXT))
		tab_model.add_child(info)
		tab_model.add_child(_wrap("Mehr GPUs oder Engineers beschleunigen das Training – neue GPUs zählen sofort. Währenddessen kannst du forschen, einstellen und ausbauen.", C_DIM))
		return
	if design_model_id != lab.next_model_id or not lab.techs.has(design["arch"]):
		var old_focus: Dictionary = design.get("focus", {})
		design = lab.default_design()
		if not old_focus.is_empty():
			design["focus"] = old_focus
		design_model_id = lab.next_model_id
	for id in design["data"].duplicate():
		if not lab.data_available(id):
			design["data"].erase(id)

	tab_model.add_child(_label("Neues Modell entwerfen", 22, C_ACCENT))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	tab_model.add_child(grid)

	grid.add_child(_label("Name", 15, C_DIM))
	var name_edit := LineEdit.new()
	name_edit.text = design["name"]
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_changed.connect(func(t): design["name"] = t if t.strip_edges() != "" else "Modell-%d" % lab.next_model_id)
	grid.add_child(name_edit)

	grid.add_child(_label("Architektur", 15, C_DIM))
	var arch_opt := OptionButton.new()
	var archs: Array = lab.arch_list()
	for i in range(archs.size()):
		arch_opt.add_item("%s  (Qualität ×%.2f, Effizienz ×%.2f)" % [archs[i]["name"], archs[i]["quality"], archs[i]["eff"]])
		arch_opt.set_item_tooltip(i, archs[i]["desc"])
		if archs[i]["id"] == design["arch"]:
			arch_opt.select(i)
	arch_opt.item_selected.connect(func(i): design["arch"] = archs[i]["id"]; _update_design_info())
	grid.add_child(arch_opt)

	grid.add_child(_label("Größe", 15, C_DIM))
	var size_opt := OptionButton.new()
	for i in range(D.SIZES.size()):
		size_opt.add_item("%s Parameter" % _size_name(D.SIZES[i]))
	size_opt.select(int(design["size_index"]))
	size_opt.item_selected.connect(func(i): design["size_index"] = i; _update_design_info())
	grid.add_child(size_opt)

	grid.add_child(_label("Daten", 15, C_DIM))
	var data_box := VBoxContainer.new()
	for id in _available_data():
		var s: Dictionary = D.DATA[id]
		var cb := CheckBox.new()
		cb.text = s["name"] + ("  (%s)" % lab.fmt_money(s["cost"]) if s["cost"] > 0.0 else "  (gratis)")
		cb.tooltip_text = s["desc"]
		cb.button_pressed = id in design["data"]
		cb.focus_mode = Control.FOCUS_NONE
		if id == "gray":
			cb.add_theme_color_override("font_color", C_BAD)
		cb.toggled.connect(func(on):
			if on and not id in design["data"]:
				design["data"].append(id)
			elif not on:
				design["data"].erase(id)
			_update_design_info())
		data_box.add_child(cb)
	grid.add_child(data_box)

	design["focus"] = lab.clamp_focus(design["focus"])
	grid.add_child(_label("Fokus-Punkte", 15, C_DIM))
	focus_info = _label("", 14, C_DIM)
	grid.add_child(focus_info)
	focus_sliders.clear()
	for k in D.FOCUS_KEYS:
		grid.add_child(_label(D.FOCUS_NAMES[k], 15, C_DIM))
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var s := HSlider.new()
		s.min_value = 0
		s.max_value = D.FOCUS_BUDGET
		s.step = 1
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		s.focus_mode = Control.FOCUS_NONE
		var l := _label("", 15)
		l.custom_minimum_size.x = 70
		row.add_child(s)
		row.add_child(l)
		grid.add_child(row)
		focus_sliders[k] = [s, l]
		s.value_changed.connect(_on_focus_slider.bind(k))
	_refresh_focus_ui()

	grid.add_child(_label("Evaluierung", 15, C_DIM))
	grid.add_child(_slider_row(0, 60, design["eval_days"], func(v): design["eval_days"] = int(v); _update_design_info(), " Tage"))

	design_info = RichTextLabel.new()
	design_info.bbcode_enabled = true
	design_info.fit_content = true
	design_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_model.add_child(design_info)
	design_error = _label("", 15, C_BAD)
	tab_model.add_child(design_error)
	var start := _button("Training starten", _on_start_training, "Datenkosten werden sofort fällig. GPU-Miete läuft täglich.")
	start.custom_minimum_size = Vector2(220, 40)
	tab_model.add_child(start)
	_update_design_info()
	_fit_texts(tab_model)


func _update_design_info() -> void:
	if design_info == null:
		return
	var ev: Dictionary = lab.evaluate_design(design)
	var t := ""
	var rel: float = ev["rel"]
	var rc := "#7be08f" if rel >= 1.2 else ("#ffc66b" if rel >= 0.9 else "#ff7a7a")
	t += "Leistung: [color=%s][b]%.2f×[/b][/color] des Marktniveaus  (Qualität %.0f, Markt erwartet %.0f)\n" % [rc, rel, ev["q"], lab.expected_quality()]
	if ev["train_days"] == INF:
		t += "[color=#ff7a7a]Keine GPUs – miete welche im Tab 'Compute'.[/color]\n"
	else:
		var tc := "#ff7a7a" if ev["train_days"] > 365.0 else "#e6e8ee"
		t += "Training: [color=%s]~%d Tage[/color] + %d Tage Evaluierung\n" % [tc, ceili(ev["train_days"]), int(design["eval_days"])]
	t += "Datenkosten: %s\n" % lab.fmt_money(ev["data_cost"])
	if lab.can_see_risk():
		t += "Risiko: [b]%.2f[/b]  (Ziel für eine sichere AGI: unter 1,0)\n" % ev["risk"]
	else:
		t += "Risiko: [color=#8a90a0]??? – stelle jemanden für Safety ein, um es zu sehen[/color]\n"
	if ev["legal"]:
		t += "[color=#ff7a7a]Achtung: Graue Daten können Klagen auslösen.[/color]\n"
	t += "[color=#8a90a0]Zeitgeist: %s. Welche Schwerpunkte gefragt sind, verraten dir die Kritiken.[/color]" % lab.era()["name"]
	if design["arch"] == "agents":
		t += "\n[color=#6fb6ff]AGI-Schwelle: Qualität %.0f mit Agenten-Architektur.[/color]" % D.AGI_Q
	design_info.text = t
	if design_error != null:
		design_error.text = ""


## Mehr Punkte für einen Bereich nehmen automatisch vom stärksten anderen Bereich
func _on_focus_slider(v: float, k: String) -> void:
	if focus_lock:
		return
	design["focus"][k] = int(v)
	var over: int = lab.focus_spent(design["focus"]) - D.FOCUS_BUDGET
	while over > 0:
		var best := ""
		var best_v := 0
		for o in D.FOCUS_KEYS:
			if o != k and int(design["focus"][o]) > best_v:
				best = o
				best_v = int(design["focus"][o])
		if best == "":
			break
		design["focus"][best] = best_v - 1
		over -= 1
	_refresh_focus_ui()
	_update_design_info()


func _refresh_focus_ui() -> void:
	focus_lock = true
	for k in focus_sliders:
		var pair: Array = focus_sliders[k]
		pair[0].value = int(design["focus"][k])
		pair[1].text = "%d" % int(design["focus"][k])
	focus_lock = false
	var free: int = D.FOCUS_BUDGET - lab.focus_spent(design["focus"])
	if free == 0:
		focus_info.text = "Alle %d Punkte verteilt" % D.FOCUS_BUDGET
		focus_info.add_theme_color_override("font_color", C_GOOD)
	else:
		focus_info.text = "%d von %d Punkten frei – ungenutzte Punkte kosten Qualität" % [free, D.FOCUS_BUDGET]
		focus_info.add_theme_color_override("font_color", C_WARN)


func _on_start_training() -> void:
	var err: String = lab.start_training(design)
	if err != "":
		design_error.text = err
		audio.play("error")
	else:
		audio.play("train")


func _build_team() -> void:
	_clear(tab_team)
	var o: Dictionary = lab.office_data()
	var full: bool = lab.staff.size() >= int(o["staff"])
	tab_team.add_child(_label("%s  ·  %d/%d Plätze belegt" % [o["name"], lab.staff.size(), o["staff"]], 20, C_WARN if full else C_ACCENT))
	# Rollen-Übersicht
	var roles := HFlowContainer.new()
	roles.add_theme_constant_override("h_separation", 18)
	for r in D.ROLE_ORDER:
		var n := 0
		for p in lab.staff:
			if p["role"] == r:
				n += 1
		var rl := _label("%s: %d" % [D.ROLES[r]["name"], n], 15, D.ROLES[r]["color"])
		rl.tooltip_text = D.ROLES[r]["desc"]
		rl.mouse_filter = Control.MOUSE_FILTER_STOP
		roles.add_child(rl)
	tab_team.add_child(roles)
	tab_team.add_child(_wrap("Wirkung: Qualität ×%.2f · Training ×%.2f · Risiko −%d %% · Umsatz ×%.2f · %.1f FP/Tag · Gehälter %s/Tag" % [
		lab.team_quality(), lab.engineer_mult(), int(lab.safety_reduction() * 100), lab.sales_mult(), lab.rp_per_day(), lab.fmt_money(lab.daily_salaries())], C_DIM))
	if full and lab.office < D.OFFICES.size() - 1:
		var n2: Dictionary = D.OFFICES[lab.office + 1]
		tab_team.add_child(_label("Büro voll – für mehr Leute umziehen: %s für %s (Haus-Symbol)" % [n2["name"], lab.fmt_money(n2["cost"])], 14, C_WARN))
	# Bewerbungen zuerst
	tab_team.add_child(HSeparator.new())
	tab_team.add_child(_label("Bewerbungen", 18))
	tab_team.add_child(_label("Jeden Monat neu – bei höherem Ruf bessere Leute.", 13, C_DIM))
	for i in range(lab.candidates.size()):
		var c: Dictionary = lab.candidates[i]
		var row := _person_row(c)
		var b := _button("Einstellen", func(): _show_error(lab.hire(i)), "Einstellungsbonus: %s" % lab.fmt_money(float(c["salary"]) * 0.1))
		b.disabled = full
		row.add_child(b)
		tab_team.add_child(row)
	# Team
	tab_team.add_child(HSeparator.new())
	tab_team.add_child(_label("Dein Team (%d)" % lab.staff.size(), 18))
	for i in range(lab.staff.size()):
		var p: Dictionary = lab.staff[i]
		var row := _person_row(p)
		if i > 0:
			var x := _icon_button("icons/cross", func(): lab.fire(i), "Entlassen – Abfindung: %s" % lab.fmt_money(float(p["salary"]) / 12.0), 26)
			x.modulate = Color(1, 1, 1, 0.45)
			x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(x)
		else:
			var sp := Control.new()
			sp.custom_minimum_size.x = 26
			row.add_child(sp)
		tab_team.add_child(row)


func _person_row(p: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var role: Dictionary = D.ROLES[p["role"]]
	var rl := _label(role["name"], 15, role["color"])
	rl.custom_minimum_size.x = 96
	rl.tooltip_text = role["desc"]
	rl.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(rl)
	var nl := _label(p["name"], 15)
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nl.clip_text = true
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nl.custom_minimum_size.x = 60
	nl.tooltip_text = p["name"]
	nl.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(nl)
	var sk := ProgressBar.new()
	sk.max_value = 10
	sk.value = int(p["skill"])
	sk.show_percentage = false
	sk.custom_minimum_size = Vector2(64, 12)
	sk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sk.tooltip_text = "Können %d/10" % int(p["skill"])
	row.add_child(sk)
	var lv := _label("%d" % int(p["skill"]), 13, C_DIM)
	lv.custom_minimum_size.x = 18
	row.add_child(lv)
	var sl := _label("%s/J." % lab.fmt_money(p["salary"]), 15, C_DIM)
	sl.custom_minimum_size.x = 84
	sl.tooltip_text = "Jahresgehalt"
	sl.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(sl)
	return row


func _build_compute() -> void:
	_clear(tab_compute)
	var gen: int = lab.gpu_gen_now()
	var cap: int = lab.office_data()["gpus"]
	tab_compute.add_child(_label("GPUs mieten", 22, C_ACCENT))
	tab_compute.add_child(_label("Leistung %.0f  ·  Miete %s/Tag  ·  Belegung %d/%d" % [lab.compute_power(), lab.fmt_money(lab.daily_gpu_cost()), lab.gpu_count(), cap], 16))
	tab_compute.add_child(_label("Aktuell im Handel: GPU Gen %d  –  Leistung %.0f, Miete %s/Tag pro Stück" % [gen, lab.gpu_power(gen), lab.fmt_money(lab.gpu_cost(gen))], 16))
	if lab.gpu_price_mult > 1.0:
		tab_compute.add_child(_label("GPU-Knappheit! Mieten kosten gerade +80 %%  (noch %d Tage)" % lab.gpu_shortage_days, 16, C_BAD))
	for g in lab.gpus:
		var gg: int = int(g["gen"])
		tab_compute.add_child(_label("   Gen %d: %d Stück  (je %.0f Leistung, %s/Tag)" % [gg, int(g["count"]), lab.gpu_power(gg), lab.fmt_money(lab.gpu_cost(gg))], 15, C_DIM))
	var rent := HBoxContainer.new()
	rent.add_child(_label("Mieten:", 15))
	for n in [1, 5, 25, 100, 500, 2000]:
		if n <= cap:
			var b := _button("+%d" % n, func(): _show_error(lab.rent_gpus(n)), "Kostet %s/Tag" % lab.fmt_money(lab.gpu_cost(gen) * n))
			b.disabled = lab.gpu_count() >= cap
			rent.add_child(b)
	tab_compute.add_child(rent)
	var ret := HBoxContainer.new()
	ret.add_child(_label("Zurückgeben (älteste zuerst):", 15))
	for n in [1, 5, 25, 100, 500, 2000]:
		if n <= cap:
			var b := _button("−%d" % n, func(): lab.return_gpus(n))
			b.disabled = lab.gpu_count() == 0
			ret.add_child(b)
	tab_compute.add_child(ret)
	tab_compute.add_child(_wrap("Alle 2 Jahre kommt eine GPU-Generation mit doppelter Leistung. Alte GPUs zurückgeben und neue mieten spart Geld pro Leistung. Ein größeres Büro erlaubt mehr GPUs.", C_DIM))
	if not lab.datacenters.is_empty():
		tab_compute.add_child(_label("Eigene Rechenzentren: Leistung %.0f, Kosten %s/Tag  (verwalten im Tab 'Ausbau')" % [lab.dc_total_power(), lab.fmt_money(lab.daily_dc_cost())], 15, C_ACCENT))
	else:
		tab_compute.add_child(_wrap("Ab 2018 kannst du unter „Ausbau“ (Haus-Symbol) oder in der Weltansicht Grundstücke kaufen, eigene Rechenzentren bauen und Hardware kaufen statt mieten.", C_DIM))


func _build_research() -> void:
	_clear(tab_research)
	research_btns.clear()
	tab_research.add_child(_label("Forschung", 22, C_ACCENT))
	research_rp_label = _label("", 16)
	tab_research.add_child(research_rp_label)
	tab_research.add_child(_wrap("Forschende erzeugen täglich Punkte. Open-Weights-Modelle bringen zusätzliche Punkte aus der Community.", C_DIM))
	for t in D.TECHS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var kind: String = {"arch": "Architektur", "safety": "Sicherheit", "infra": "Infrastruktur"}[t["kind"]]
		var state: String = lab.tech_state(t["id"])
		v.add_child(_label("%s  ·  %s" % [t["name"], kind], 16, C_GOOD if state == "done" else (C_TEXT if state == "available" else C_DIM)))
		v.add_child(_wrap(t["desc"], C_DIM))
		row.add_child(v)
		match state:
			"done":
				row.add_child(_label("erforscht", 15, C_GOOD))
			"future":
				row.add_child(_label("ab %d" % t["year"], 15, C_DIM))
			"locked":
				row.add_child(_label("braucht %s" % lab.tech(t["req"])["name"], 15, C_DIM))
			_:
				var b := _button("Erforschen (%d)" % t["rp"], func(): _show_error(lab.research(t["id"])))
				research_btns.append({"btn": b, "cost": float(t["rp"])})
				row.add_child(b)
		tab_research.add_child(row)
		tab_research.add_child(HSeparator.new())


func _build_products() -> void:
	_clear(tab_products)
	product_labels.clear()
	tab_products.add_child(_label("Modelle & Produkte", 22, C_ACCENT))
	var risk_text: String = ("Gesamtrisiko deiner veröffentlichten Modelle: %.2f  (Open Weights zählen doppelt)" % lab.hidden_risk()) if lab.can_see_risk() else "Gesamtrisiko: ???  (Safety-Team nötig)"
	tab_products.add_child(_label(risk_text, 15, C_DIM))
	tab_products.add_child(_label("API-Umsatz gesamt: %s/Tag  ·  Helix-Bestwert: Qualität %.0f" % [lab.fmt_money(lab.api_revenue()), lab.rival["best_q"]], 15, C_DIM))
	if lab.models.is_empty():
		tab_products.add_child(_label("Noch keine Modelle. Entwirf dein erstes über die Zielscheibe (Modell).", 15, C_DIM))
	var status_names := {"ready": "bereit", "paper": "Paper", "api": "API", "open": "Open Weights", "withdrawn": "zurückgezogen"}
	var withdrawn_shown := 0
	var withdrawn_hidden := 0
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	for hd in ["Modell", "Status", "Bewertung", "Umsatz/Tag", "Risiko", ""]:
		grid.add_child(_label(hd, 13, C_DIM))
	for i in range(lab.models.size() - 1, -1, -1):
		var m: Dictionary = lab.models[i]
		if m["status"] == "withdrawn":
			withdrawn_shown += 1
			if withdrawn_shown > 3:
				withdrawn_hidden += 1
				continue
		var active: bool = m["status"] in ["ready", "api", "open"]
		var nv := VBoxContainer.new()
		nv.add_theme_constant_override("separation", -4)
		nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nv.add_child(_label(m["name"], 15, C_TEXT if active else C_DIM))
		nv.add_child(_label("%s · %s" % [lab.tech(m["arch"])["name"], _size_name(D.SIZES[int(m["size_index"])])], 12, C_DIM))
		grid.add_child(nv)
		grid.add_child(_label(status_names.get(m["status"], m["status"]), 15, C_ACCENT if active else C_DIM))
		var r := float(m["rating"])
		grid.add_child(_label(("%.1f" % r) if r > 0.0 else "–", 15, C_GOOD if r >= 7.0 else (C_WARN if r >= 4.0 else (C_BAD if r > 0.0 else C_DIM))))
		var rev := _label("–", 15, C_DIM)
		if m["status"] == "api":
			rev.add_theme_color_override("font_color", C_GOOD)
			product_labels.append({"label": rev, "id": int(m["id"])})
		grid.add_child(rev)
		if lab.can_see_risk():
			grid.add_child(_label("%.2f" % m["risk"], 15, C_BAD if float(m["risk"]) >= 1.0 else C_DIM))
		else:
			grid.add_child(_label("?", 15, C_DIM))
		var act := HBoxContainer.new()
		var id: int = int(m["id"])
		match m["status"]:
			"ready":
				act.add_child(_button("Paper", func(): _release(id, "paper"), "Ruf + Forschungszuschuss, kein Umsatz"))
				act.add_child(_button("API", func(): _release(id, "api"), "Täglicher Umsatz"))
				act.add_child(_button("Open", func(): _release(id, "open"), "Viel Ruf und FP, doppeltes Risiko"))
			"api":
				act.add_child(_button("Zurückziehen", func(): lab.withdraw_model(id), "Kein Umsatz mehr, aber auch kein Risiko mehr."))
		grid.add_child(act)
	tab_products.add_child(grid)
	if withdrawn_hidden > 0:
		tab_products.add_child(_label("+ %d ältere zurückgezogene Modelle" % withdrawn_hidden, 14, C_DIM))


func _release(id: int, kind: String) -> void:
	# Release-Dialog dieses Modells aus der Warteschlange entfernen, falls offen
	for ev in lab.event_queue.duplicate():
		if ev["id"] == "model_ready" and int(ev["data"]["model"]) == id:
			lab.event_queue.erase(ev)
	var rep: Dictionary = lab.release_model(id, kind)
	if not rep.is_empty():
		lab.push_report(rep)


func _build_infra() -> void:
	_clear(tab_infra)
	chip_bar = null
	# ---- Büros
	tab_infra.add_child(_label("Büros", 22, C_ACCENT))
	tab_infra.add_child(_wrap("Größere Büros bieten Platz für mehr Personen und gemietete GPUs. Du kannst Stufen überspringen.", C_DIM))
	for i in range(D.OFFICES.size()):
		var o: Dictionary = D.OFFICES[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var col := C_GOOD if i == lab.office else (C_DIM if i < lab.office else C_TEXT)
		v.add_child(_label("%s  ·  %d Personen  ·  %d GPUs" % [o["name"], o["staff"], o["gpus"]], 16, col))
		v.add_child(_wrap(o["desc"], C_DIM))
		row.add_child(v)
		if i == lab.office:
			row.add_child(_label("aktuell", 15, C_GOOD))
		elif i < lab.office:
			row.add_child(_label("—", 15, C_DIM))
		else:
			var idx := i
			row.add_child(_button("Kaufen: %s" % lab.fmt_money(o["cost"]), func(): _show_error(lab.buy_office(idx))))
		tab_infra.add_child(row)

	# ---- Büro-Upgrades
	tab_infra.add_child(HSeparator.new())
	tab_infra.add_child(_label("Büro-Ausstattung", 22, C_ACCENT))
	for u in D.OFFICE_UPGRADES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var owned: bool = lab.office_upgrades.has(u["id"])
		v.add_child(_label(u["name"], 16, C_GOOD if owned else C_TEXT))
		v.add_child(_wrap(u["desc"], C_DIM))
		row.add_child(v)
		if owned:
			row.add_child(_label("vorhanden", 15, C_GOOD))
		elif lab.office < int(u["min_office"]):
			row.add_child(_label("ab %s" % D.OFFICES[int(u["min_office"])]["name"], 15, C_DIM))
		else:
			var id: String = u["id"]
			row.add_child(_button("Kaufen: %s" % lab.fmt_money(u["cost"]), func(): _show_error(lab.buy_office_upgrade(id))))
		tab_infra.add_child(row)

	# ---- Grundstücke & Rechenzentren
	tab_infra.add_child(HSeparator.new())
	tab_infra.add_child(_label("Grundstücke & Rechenzentren", 22, C_ACCENT))
	tab_infra.add_child(_wrap("Kaufe ein Grundstück (auch per Klick in der Weltansicht) und baue darauf ein Rechenzentrum oder die Chipfabrik. Die Gegend bestimmt Strompreis und Baukosten. Hardware im Rechenzentrum kostet einmalig ~%d Tage Miete, danach nur Strom (%d %% der Miete × Gegend)." % [int(D.BUY_DAYS), int(D.UPKEEP_SHARE * 100)], C_DIM))
	for pl in D.PLOTS:
		if lab.plot_state(pl["id"]) != "dc":
			tab_infra.add_child(_plot_box(pl["id"], false))
	for i in range(lab.datacenters.size()):
		tab_infra.add_child(_dc_panel(i))

	# ---- Chips
	tab_infra.add_child(HSeparator.new())
	tab_infra.add_child(_label("Eigene Chips", 22, C_ACCENT))
	if not lab.techs.has("chipdesign"):
		tab_infra.add_child(_wrap("Erforsche 'Eigenes Chip-Design' (ab 2021), um eigene KI-Beschleuniger zu entwickeln. Sie sind %.1f× so stark wie die aktuelle Markt-GPU und kosten nur %d %% davon." % [D.CHIP_POWER, int(D.CHIP_PRICE * 100)], C_DIM))
	else:
		if lab.custom_chip.is_empty():
			tab_infra.add_child(_label("Noch kein eigener Chip.", 15, C_DIM))
		else:
			var u: Dictionary = lab.hw_unit("custom")
			tab_infra.add_child(_label("Aktueller Chip: %s  ·  Leistung %.0f  ·  Preis %s  (Markt-GPU: Leistung %.0f, %s)" % [
				u["name"], u["power"], lab.fmt_money(u["price"]), lab.gpu_power(lab.gpu_gen_now()), lab.fmt_money(lab.hw_unit("market")["price"])], 15))
		if lab.chip_project.is_empty():
			tab_infra.add_child(_button("Chip-Projekt NG-%d starten: %s  (~%d Tage)" % [lab.chip_version + 1, lab.fmt_money(lab.chip_project_cost()), ceili(lab.chip_project_days())],
				func(): _show_error(lab.start_chip_project()), "Engineering beschleunigt die Entwicklung. Der Chip basiert auf der GPU-Generation bei Fertigstellung."))
		else:
			tab_infra.add_child(_label("Entwicklung NG-%d läuft …" % int(lab.chip_project["version"]), 15))
			chip_bar = ProgressBar.new()
			chip_bar.custom_minimum_size.y = 22
			tab_infra.add_child(chip_bar)
		if lab.has_fab:
			tab_infra.add_child(_label("Eigene Chipfabrik in Betrieb: Chips halb so teuer, keine Lieferengpässe.", 15, C_GOOD))
		elif lab.techs.has("fab"):
			tab_infra.add_child(_label("Chipfabrik (%s): auf einem eigenen leeren Grundstück bauen – oben unter „Grundstücke“ oder per Klick in der Weltansicht." % lab.fmt_money(D.FAB_COST * lab.inflation()), 15, C_WARN))
		else:
			tab_infra.add_child(_label("Erforsche 'Chip-Fertigung' (ab 2024) für eine eigene Fabrik.", 15, C_DIM))


## Grundstück mit allen passenden Aktionen (für Ausbau-Tab und Klick-Popup)
func _plot_box(id: String, big: bool) -> Control:
	var pl: Dictionary = lab.plot(id)
	var loc: Dictionary = lab._find(D.LOCATIONS, pl["loc"])
	var st: String = lab.plot_state(id)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var state_txt: String = {"locked": "ab %d im Angebot" % pl["year"], "for_sale": "zu verkaufen", "empty": "dein Grundstück (leer)", "dc": "Rechenzentrum", "fab": "Chipfabrik"}[st]
	v.add_child(_label("%s  ·  %s" % [pl["name"], state_txt], 20 if big else 16, C_ACCENT if st in ["empty", "dc", "fab"] else C_TEXT))
	v.add_child(_label("%s  ·  Strom ×%.2f  ·  Baukosten ×%.1f" % [loc["name"], loc["power"], loc["build"]], 14, C_DIM))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 6)
	match st:
		"for_sale":
			row.add_child(_button("Kaufen: %s" % lab.fmt_money(lab.plot_price(id)), func(): _plot_action(lab.buy_plot(id))))
		"empty":
			for t in D.DATACENTERS:
				if lab.year() >= int(t["year"]):
					var tid: String = t["id"]
					row.add_child(_button("%s bauen: %s" % [t["name"], lab.fmt_money(lab.dc_build_cost(tid, id))], func(): _plot_action(lab.build_datacenter(tid, id)), "%s · %d Plätze" % [t["desc"], t["slots"]]))
			if lab.techs.has("fab") and not lab.has_fab:
				row.add_child(_button("Chipfabrik bauen: %s" % lab.fmt_money(D.FAB_COST * lab.inflation()), func(): _plot_action(lab.build_fab(id))))
			if row.get_child_count() == 0:
				row.add_child(_label("Bauen ab 2018 (Rechenzentrum) bzw. mit Forschung „Chip-Fertigung“ (Fabrik).", 14, C_DIM))
		"dc":
			row.add_child(_button("Rechenzentrum verwalten", func(): _close_plot_popup(); _open_tab(5)))
		"fab":
			row.add_child(_label("Chips halb so teuer, keine Lieferengpässe.", 14, C_GOOD))
	if row.get_child_count() > 0:
		v.add_child(row)
	else:
		row.free()
	if big:
		return v
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("15181e")
	sb.border_color = C_PANEL2
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(v)
	return p


func _plot_action(err: String) -> void:
	_show_error(err)
	if err == "":
		_close_plot_popup()


func _close_plot_popup() -> void:
	if plot_popup != null:
		plot_popup.hide()


## Klick auf den Boden: Grundstück → Menü, eigenes Labor → ins Büro
func _on_ground_click(pos: Vector3) -> void:
	if office_view.mode != "world" or modal.visible:
		return
	var id: String = office_view.plot_at(pos)
	if id != "":
		audio.play("open")
		if plot_popup == null:
			plot_popup = PopupPanel.new()
			plot_popup.add_theme_stylebox_override("panel", _hud_style(Color(0.09, 0.1, 0.13, 0.97), 10))
			add_child(plot_popup)
		for c in plot_popup.get_children():
			plot_popup.remove_child(c)
			c.queue_free()
		var box := _plot_box(id, true)
		box.custom_minimum_size.x = 460
		plot_popup.add_child(box)
		var mp := get_viewport().get_mouse_position()
		plot_popup.popup(Rect2i(Vector2i(mp + Vector2(16, 16)), Vector2i(480, 10)))
	elif pos.distance_to(office_view.LAB_POS) < 2.2:
		_toggle_world()


func _dc_panel(i: int) -> PanelContainer:
	var dc: Dictionary = lab.datacenters[i]
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("15181e")
	sb.border_color = C_PANEL2
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	var plot_name: String = lab.plot(String(dc.get("plot", ""))).get("name", "")
	v.add_child(_label("%s  ·  %s%s" % [lab.dc_type(dc)["name"], lab.dc_loc(dc)["name"], ("  ·  " + plot_name) if plot_name != "" else ""], 17, C_ACCENT))
	v.add_child(_label("Belegt %d/%d  ·  Leistung %.0f  ·  Kosten %s/Tag" % [lab.dc_used(dc), lab.dc_slots(dc), lab.dc_power(dc), lab.fmt_money(lab.dc_daily_cost(dc))], 15))
	for h in dc["hw"]:
		v.add_child(_label("   %s: %d Stück (je %.0f Leistung)" % [h["name"], int(h["count"]), h["power"]], 14, C_DIM))
	var kinds := ["market"]
	if not lab.custom_chip.is_empty():
		kinds.append("custom")
	for kind in kinds:
		var u: Dictionary = lab.hw_unit(kind)
		var row := HFlowContainer.new()
		row.add_child(_label("Kaufen %s (%s/Stück):" % [u["name"], lab.fmt_money(u["price"])], 15))
		for n in [10, 100, 1000, 10000]:
			if n <= lab.dc_slots(dc):
				var k: String = kind
				var nn: int = n
				row.add_child(_button("+%d" % n, func(): _show_error(lab.buy_hardware(i, k, nn)), "Kostet %s" % lab.fmt_money(float(u["price"]) * n)))
		v.add_child(row)
	var scrap := HFlowContainer.new()
	scrap.add_child(_label("Verschrotten (schwächste zuerst):", 15))
	for n in [10, 100, 1000]:
		var nn: int = n
		scrap.add_child(_button("−%d" % n, func(): lab.scrap_hardware(i, nn)))
	v.add_child(scrap)
	var ups := HFlowContainer.new()
	ups.add_theme_constant_override("h_separation", 8)
	ups.add_theme_constant_override("v_separation", 6)
	for u in D.DC_UPGRADES:
		if dc["upgrades"].has(u["id"]):
			ups.add_child(_label("✔ " + u["name"], 14, C_GOOD))
		else:
			var id: String = u["id"]
			ups.add_child(_button("%s: %s" % [u["name"], lab.fmt_money(lab.dc_upgrade_cost(dc, id))], func(): _show_error(lab.buy_dc_upgrade(i, id)), u["desc"]))
	v.add_child(ups)
	return p


func _build_finance() -> void:
	_clear(tab_finance)
	finance_day = lab.day
	var net: float = lab.last_income - lab.last_cost
	tab_finance.add_child(_label("Kontostand: %s" % lab.fmt_money(lab.money), 22, C_GOOD if lab.money >= 0.0 else C_BAD))
	tab_finance.add_child(_label("Heute: %s Einnahmen  ·  %s Kosten  ·  Bilanz %s%s" % [lab.fmt_money(lab.last_income), lab.fmt_money(lab.last_cost), "+" if net >= 0.0 else "", lab.fmt_money(net)], 15, C_GOOD if net >= 0.0 else C_WARN))
	# Verlauf
	tab_finance.add_child(_label("Kontostand der letzten 2 Jahre", 16, C_ACCENT))
	var chart := Control.new()
	chart.custom_minimum_size = Vector2(0, 150)
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hist: Array = lab.money_hist.duplicate()
	hist.append(lab.money)
	chart.draw.connect(func():
		var sz := chart.size
		chart.draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.25))
		if hist.size() < 2:
			return
		var lo: float = minf(0.0, hist.min())
		var hi: float = maxf(1.0, hist.max())
		var pts := PackedVector2Array()
		for i in range(hist.size()):
			var x := sz.x * i / float(hist.size() - 1)
			var y := sz.y - (float(hist[i]) - lo) / (hi - lo) * (sz.y - 10.0) - 5.0
			pts.append(Vector2(x, y))
		var zero_y := sz.y - (0.0 - lo) / (hi - lo) * (sz.y - 10.0) - 5.0
		chart.draw_line(Vector2(0, zero_y), Vector2(sz.x, zero_y), Color(1, 1, 1, 0.15), 1.0)
		chart.draw_polyline(pts, C_ACCENT, 2.5, true)
		var f := chart.get_theme_default_font()
		chart.draw_string(f, Vector2(6, 16), lab.fmt_money(hi), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_DIM)
		chart.draw_string(f, Vector2(6, sz.y - 6), lab.fmt_money(lo), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_DIM))
	tab_finance.add_child(chart)
	# Letzte 30 Tage nach Kategorie
	var month: Dictionary = lab.ledger_month()
	var inc := 0.0
	var exp := 0.0
	for k in month:
		if float(month[k]) >= 0.0:
			inc += float(month[k])
		else:
			exp += float(month[k])
	tab_finance.add_child(_label("Letzte 30 Tage: %s rein · %s raus · Saldo %s" % [lab.fmt_money(inc), lab.fmt_money(-exp), lab.fmt_money(inc + exp)], 16, C_ACCENT))
	var keys := month.keys()
	keys.sort_custom(func(a, b): return float(month[a]) > float(month[b]))
	var max_abs := 1.0
	for k in keys:
		max_abs = maxf(max_abs, absf(float(month[k])))
	for k in keys:
		var val := float(month[k])
		if absf(val) < 1.0:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var nl := _label(D.LEDGER_NAMES.get(k, k), 14)
		nl.custom_minimum_size.x = 200
		row.add_child(nl)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = max_abs
		bar.value = absf(val)
		bar.custom_minimum_size = Vector2(120, 14)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := StyleBoxFlat.new()
		fill.bg_color = C_GOOD.darkened(0.2) if val >= 0.0 else C_BAD.darkened(0.15)
		fill.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("fill", fill)
		row.add_child(bar)
		var vl := _label("%s%s" % ["+" if val >= 0.0 else "−", lab.fmt_money(absf(val))], 14, C_GOOD if val >= 0.0 else C_BAD)
		vl.custom_minimum_size.x = 100
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(vl)
		tab_finance.add_child(row)
	if keys.is_empty():
		tab_finance.add_child(_label("Noch keine Buchungen.", 14, C_DIM))
	# Laufende Kosten pro Tag
	tab_finance.add_child(HSeparator.new())
	tab_finance.add_child(_label("Laufende Kosten pro Tag", 16, C_ACCENT))
	for item in [["Gehälter (%d Personen)" % lab.staff.size(), lab.daily_salaries()], ["GPU-Miete (%d GPUs)" % lab.gpu_count(), lab.daily_gpu_cost()], ["Rechenzentren: Strom & Wartung", lab.daily_dc_cost()]]:
		var share: float = float(item[1]) / maxf(1.0, lab.last_cost) * 100.0
		tab_finance.add_child(_label("%s:  %s  (%d %%)" % [item[0], lab.fmt_money(item[1]), int(share)], 14))
	# Jahresbilanz
	tab_finance.add_child(HSeparator.new())
	for pair in [["Dieses Jahr", lab.ledger_year], ["Letztes Jahr", lab.ledger_last_year]]:
		var dct: Dictionary = pair[1]
		if dct.is_empty():
			continue
		var a := 0.0
		var b := 0.0
		for k in dct:
			if float(dct[k]) >= 0.0:
				a += float(dct[k])
			else:
				b += float(dct[k])
		tab_finance.add_child(_label("%s: %s Einnahmen · %s Ausgaben · Saldo %s" % [pair[0], lab.fmt_money(a), lab.fmt_money(-b), lab.fmt_money(a + b)], 14, C_DIM))


func _build_advisor() -> void:
	_clear(tab_advisor)
	advisor_day = lab.day
	var tips: Array = lab.advice()
	if tips.is_empty():
		tab_advisor.add_child(_label("Alles im grünen Bereich – weiter so!", 16, C_GOOD))
		return
	tab_advisor.add_child(_wrap("Die wichtigsten Hinweise zuerst. Der Knopf öffnet den passenden Bereich.", C_DIM))
	for tip in tips.slice(0, 7):
		var p := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("15181e")
		sb.border_color = C_BAD if int(tip["prio"]) >= 85 else (C_WARN if int(tip["prio"]) >= 60 else C_PANEL2)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(6)
		sb.set_content_margin_all(10)
		p.add_theme_stylebox_override("panel", sb)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		p.add_child(h)
		h.add_child(_icon_rect("emotes/" + String(tip["icon"]), 34))
		var l := _wrap(tip["text"], C_TEXT)
		l.add_theme_font_size_override("font_size", 15)
		h.add_child(l)
		var tab_i: int = tip["tab"]
		var b := _button(String(TOOLS[tab_i]["title"]), func(): _open_tab(tab_i))
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(b)
		tab_advisor.add_child(p)


## Wichtige Warnung ab und zu als Meldung
func _advisor_toast() -> void:
	if lab.day - last_advice_toast < 45 or lab.day == advice_checked_day:
		return
	advice_checked_day = lab.day
	var tips: Array = lab.advice()
	if tips.is_empty() or int(tips[0]["prio"]) < 80:
		return
	var txt: String = tips[0]["text"]
	if txt == last_advice_text:
		return
	last_advice_toast = lab.day
	last_advice_text = txt
	_toast("[color=#ffc66b]Berater:[/color] " + txt)


func _build_goals() -> void:
	_clear(goals_box)
	for i in range(D.GOALS.size()):
		var g: Dictionary = D.GOALS[i]
		var l: Label
		if lab.goal_reached(g["id"]):
			l = _label("✔ " + g["text"], 14, C_GOOD)
		elif i == lab.goal_index:
			l = _label("► " + g["text"], 15, C_ACCENT)
		else:
			l = _label("   " + g["text"], 14, C_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		goals_box.add_child(l)


func _available_data() -> Array:
	var a := []
	for id in D.DATA:
		if lab.data_available(id):
			a.append(id)
	return a


# ================================================================ Popups

func _confirm_new_game() -> void:
	modal_event = "confirm_new"
	_show_modal("Neues Spiel starten?", "Der aktuelle Fortschritt geht verloren, wenn du nicht gespeichert hast.",
		[{"label": "Ja, neues Spiel", "tip": ""}, {"label": "Abbrechen", "tip": ""}])


func _check_modal() -> void:
	if modal_event is String and modal_event == "confirm_new":
		return
	if not lab.ending.is_empty():
		if not (modal_event is String and modal_event == "ending"):
			modal_event = "ending"
			audio.play("win" if lab.ending.get("id", "") == "aligned" else "lose")
			var e: Dictionary = lab.ending
			_show_modal(e["title"], "%s\n\n[b]Punkte: %d[/b]\nDatum: %s · Reputation %.0f · Bestes Modell: Qualität %.0f · Ziele: %d/%d" % [
				e["text"], e["score"], e["date"], lab.reputation, lab.best_q, lab.goals_count(), D.GOALS.size()], [{"label": "Neues Spiel", "tip": ""}])
		return
	if lab.event_queue.is_empty():
		if modal.visible:
			modal.visible = false
		modal_event = null
		return
	var ev: Dictionary = lab.event_queue[0]
	if modal_event is Dictionary and is_same(modal_event, ev):
		return
	modal_event = ev
	_show_modal(ev["title"], ev["text"], ev["choices"])
	if not ev["title"].begins_with("Kritiken"):
		audio.play("event")


func _show_modal(title: String, text: String, choices: Array) -> void:
	modal_title.text = title
	modal_text.text = text
	_clear(modal_buttons)
	for i in range(choices.size()):
		var c: Dictionary = choices[i]
		var b := _button(c["label"], _on_modal_choice.bind(i), c.get("tip", ""))
		b.custom_minimum_size.y = 38
		if c.get("tip", "") != "":
			b.text = "%s   —   %s" % [c["label"], c["tip"]]
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		modal_buttons.add_child(b)
	modal.visible = true


func _on_modal_choice(i: int) -> void:
	audio.play("click")
	if modal_event is String and modal_event == "ending":
		_new_game()
		return
	if modal_event is String and modal_event == "confirm_new":
		modal_event = null
		modal.visible = false
		if i == 0:
			_new_game()
		return
	lab.resolve_event(i)
	modal_event = null
	modal.visible = false


func _show_error(err: String) -> void:
	audio.play("error" if err != "" else "confirm")
	if err != "":
		_toast("[color=#ff7a7a]%s[/color]" % err)


# ================================================================ Speichern

func _save(auto := false) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		_show_error("Speichern fehlgeschlagen.")
		return
	f.store_string(JSON.stringify(lab.to_dict()))
	f.close()
	if not auto:
		_toast("[color=#8a90a0]Gespeichert.[/color]")


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_show_error("Kein Spielstand vorhanden.")
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(d) != TYPE_DICTIONARY:
		_show_error("Spielstand ist beschädigt.")
		return
	lab = Lab.new()
	lab.from_dict(d)
	_reset_view()
	_set_speed(0)


# ================================================================ UI-Aufbau

func _build_ui() -> void:
	# 3D füllt den ganzen Bildschirm (direkt im Hauptfenster → native Auflösung)
	office_view = Office3D.new()
	office_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(office_view)
	office_view.fx_event.connect(func(f): audio.play(f))
	office_view.clicked_ground.connect(_on_ground_click)

	# Obere Leiste
	var topm := MarginContainer.new()
	topm.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	topm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top"]:
		topm.add_theme_constant_override("margin_" + side, 10)
	add_child(topm)
	topm.add_child(_build_topbar())

	# Aktuelles Ziel als Pille oben mittig
	var gp_wrap := CenterContainer.new()
	gp_wrap.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	gp_wrap.offset_top = 72
	gp_wrap.offset_bottom = 110
	gp_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(gp_wrap)
	var gp := PanelContainer.new()
	gp.add_theme_stylebox_override("panel", _hud_style(Color(0.08, 0.09, 0.12, 0.8), 18))
	gp.tooltip_text = "Aktuelles Ziel – alle Ziele über den Pokal unten"
	gp_wrap.add_child(gp)
	var gph := HBoxContainer.new()
	gph.add_theme_constant_override("separation", 8)
	gp.add_child(gph)
	gph.add_child(_icon_rect("icons/trophy", 22))
	goal_pill = _label("", 15, C_WARN)
	gph.add_child(goal_pill)

	# Seitenleiste rechts (Details nur bei Bedarf)
	drawer = PanelContainer.new()
	drawer.anchor_left = 1.0
	drawer.anchor_right = 1.0
	drawer.anchor_bottom = 1.0
	drawer.offset_left = -620
	drawer.offset_right = -10
	drawer.offset_top = 70
	drawer.offset_bottom = -104
	drawer.add_theme_stylebox_override("panel", _hud_style(Color(0.09, 0.1, 0.13, 0.94), 10))
	drawer.visible = false
	add_child(drawer)
	var dv := VBoxContainer.new()
	drawer.add_child(dv)
	var dh := HBoxContainer.new()
	dv.add_child(dh)
	drawer_icon = TextureRect.new()
	drawer_icon.custom_minimum_size = Vector2(30, 30)
	drawer_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	drawer_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	dh.add_child(drawer_icon)
	drawer_title = _label("", 20, C_ACCENT)
	drawer_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dh.add_child(drawer_title)
	dh.add_child(_icon_button("icons/cross", func(): drawer.visible = false; highlight_tool(-2), "Schließen (Esc)", 32))
	tabs = TabContainer.new()
	tabs.tabs_visible = false
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dv.add_child(tabs)
	tab_model = _add_tab("Modell")
	tab_team = _add_tab("Team")
	tab_compute = _add_tab("Compute")
	tab_research = _add_tab("Forschung")
	tab_products = _add_tab("Produkte")
	tab_infra = _add_tab("Ausbau")
	goals_box = _add_tab("Ziele")
	news_box = RichTextLabel.new()
	news_box.name = "Neuigkeiten"
	news_box.bbcode_enabled = true
	news_box.scroll_following = true
	news_box.add_theme_font_size_override("normal_font_size", 14)
	news_box.add_theme_font_size_override("bold_font_size", 14)
	tabs.add_child(news_box)
	tab_finance = _add_tab("Finanzen")
	tab_advisor = _add_tab("Berater")

	# Werkzeugleiste unten
	var bar_wrap := CenterContainer.new()
	bar_wrap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar_wrap.offset_top = -96
	bar_wrap.offset_bottom = -10
	bar_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar_wrap)
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", _hud_style(Color(0.08, 0.09, 0.12, 0.85), 14))
	bar_wrap.add_child(bar)
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 8)
	bar.add_child(bh)
	for i in range(TOOLS.size()):
		var t: Dictionary = TOOLS[i]
		var b := _tool_button(t["icon"], {7: "News"}.get(i, t["title"]), t["tip"])
		b.pressed.connect(_open_tab.bind(i))
		tool_btns.append(b)
		bh.add_child(b)
		if i in [3, 5, 7]:
			bh.add_child(VSeparator.new())   # Gruppen: Labor | Geschäft | Überblick
	bh.add_child(VSeparator.new())
	view_btn = _tool_button("icons/zoomOut", "Welt", "Weltansicht: Labor, Grundstücke, Konkurrenz (Tab)")
	view_btn.pressed.connect(_toggle_world)
	bh.add_child(view_btn)

	# Tutorial über der Werkzeugleiste
	tutorial = Tutorial.new()
	tutorial.position = Vector2(10, 122)
	tutorial.custom_minimum_size.x = 520
	tutorial.size = Vector2(520, 0)
	add_child(tutorial)
	tutorial.setup(self, tabs)

	# Meldungen unten links
	toast_box = VBoxContainer.new()
	toast_box.anchor_top = 1.0
	toast_box.anchor_bottom = 1.0
	toast_box.offset_left = 12
	toast_box.offset_right = 440
	toast_box.offset_top = -330
	toast_box.offset_bottom = -104
	toast_box.alignment = BoxContainer.ALIGNMENT_END
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_box.add_theme_constant_override("separation", 4)
	add_child(toast_box)
	_build_modal()


func _build_topbar() -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _hud_style(Color(0.08, 0.09, 0.12, 0.85), 10))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	p.add_child(h)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", -4)
	top["date"] = _label("", 16)
	top["era"] = _label("", 12, C_DIM)
	top["era"].tooltip_text = "Markt-Ära: Was Nutzer wollen, ändert sich mit der Zeit."
	top["era"].mouse_filter = Control.MOUSE_FILTER_STOP
	dv.add_child(top["date"])
	dv.add_child(top["era"])
	h.add_child(dv)
	var chips := [
		["money", "emotes/emote_cash", "Geld und Tagesbilanz (Umsatz − Gehälter − Hardware)", "Geld · pro Tag"],
		["compute", "icons/signal3", "Rechenleistung (gemietet + eigene Rechenzentren)", "Rechenleistung"],
		["rep", "emotes/emote_star", "Ruf (0–100): lockt Investoren, Talente und Kundschaft an", "Ruf"],
		["rp", "emotes/emote_idea", "Forschungspunkte", "Forschungspunkte"],
		["risk", "emotes/emote_alert", "Risiko deiner veröffentlichten Modelle (nur mit Safety-Team sichtbar)", "Risiko"],
		["equity", "icons/leaderboardsSimple", "Deine Firmenanteile", "deine Anteile"],
	]
	for c in chips:
		var ch := HBoxContainer.new()
		ch.add_theme_constant_override("separation", 6)
		ch.tooltip_text = c[2]
		ch.mouse_filter = Control.MOUSE_FILTER_STOP
		var ic := _icon_rect(c[1], 28)
		ic.mouse_filter = Control.MOUSE_FILTER_PASS
		ch.add_child(ic)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", -5)
		vb.mouse_filter = Control.MOUSE_FILTER_PASS
		var l := _label("", 17)
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		top[c[0]] = l
		vb.add_child(l)
		var cap := _label(c[3], 11, C_DIM)
		cap.mouse_filter = Control.MOUSE_FILTER_PASS
		vb.add_child(cap)
		ch.add_child(vb)
		h.add_child(ch)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	var speed_icons := ["icons/pause", "icons/right", "icons/fastForward", "icons/next"]
	for i in range(speed_icons.size()):
		var b := _icon_button(speed_icons[i], _set_speed.bind(i), ["Pause (Leertaste)", "Tempo 1 (Taste 1)", "Tempo 2 (Taste 2)", "Tempo 3 (Taste 3)"][i], 38)
		speed_btns.append(b)
		h.add_child(b)
	h.add_child(VSeparator.new())
	var snd := _icon_button("icons/musicOn", func(): pass, "Musik & Effekte", 38)
	snd.pressed.connect(func(): _open_sound_popup(snd))
	h.add_child(snd)
	var gb := _icon_button("icons/gear", func(): pass, "Grafik (F11 = Vollbild)", 38)
	gb.pressed.connect(func(): _open_gfx_popup(gb))
	h.add_child(gb)
	h.add_child(_icon_button("icons/save", _save.bind(false), "Speichern", 38))
	h.add_child(_icon_button("icons/import", _load, "Laden", 38))
	h.add_child(_icon_button("icons/information", func(): lab.flags["tut"] = 0, "Tutorial neu starten", 38))
	h.add_child(_icon_button("icons/return", _confirm_new_game, "Neues Spiel", 38))
	return p


# ---------------------------------------------------------------- HUD-Helfer

## Lange Texte in der Seitenleiste umbrechen, damit nichts über den Rand ragt
func _fit_texts(root_node: Node) -> void:
	for n in root_node.find_children("*", "Label", true, false):
		var l := n as Label
		if l.autowrap_mode == TextServer.AUTOWRAP_OFF and l.text.length() > 28:
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.custom_minimum_size.x = maxf(l.custom_minimum_size.x, 140.0)
	for n in root_node.find_children("*", "Button", true, false):
		var b := n as Button
		if b.text.length() > 26 and not (b is CheckBox) and not (b is OptionButton):
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.custom_minimum_size.x = maxf(b.custom_minimum_size.x, 160.0)


func _load_gfx() -> void:
	var d := Settings.load_all()
	for k in gfx.keys():
		if d.has("gfx_" + k):
			gfx[k] = d["gfx_" + k]
	_apply_gfx()


func _apply_gfx() -> void:
	office_view.apply_graphics(gfx)
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if bool(gfx["fullscreen"]) else DisplayServer.WINDOW_MODE_MAXIMIZED
	if DisplayServer.get_name() != "headless" and DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)
	var out := {}
	for k in gfx.keys():
		out["gfx_" + k] = gfx[k]
	Settings.save_keys(out)


func _open_gfx_popup(anchor: Control) -> void:
	if gfx_popup == null:
		gfx_popup = PopupPanel.new()
		gfx_popup.add_theme_stylebox_override("panel", _hud_style(Color(0.09, 0.1, 0.13, 0.97), 10))
		var g := GridContainer.new()
		g.columns = 2
		g.add_theme_constant_override("h_separation", 14)
		g.add_theme_constant_override("v_separation", 10)
		gfx_popup.add_child(g)
		g.add_child(_label("Kantenglättung", 15, C_DIM))
		g.add_child(_gfx_option("msaa", ["Aus", "2×", "4×", "8×"]))
		g.add_child(_label("Render-Auflösung", 15, C_DIM))
		g.add_child(_gfx_option("scale", ["75 %", "100 %", "150 % (schärfer)", "200 % (max.)"]))
		g.add_child(_label("Schatten", 15, C_DIM))
		g.add_child(_gfx_option("shadows", ["Mittel", "Hoch", "Ultra"]))
		g.add_child(_label("Tilt-Shift", 15, C_DIM))
		g.add_child(_gfx_check("tilt_shift"))
		g.add_child(_label("Vollbild (F11)", 15, C_DIM))
		g.add_child(_gfx_check("fullscreen"))
		add_child(gfx_popup)
	var pos := anchor.get_global_rect().position + Vector2(-300, anchor.size.y + 8)
	gfx_popup.popup(Rect2i(Vector2i(pos), Vector2i(360, 230)))


func _gfx_option(key: String, items: Array) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(it)
	o.select(int(gfx[key]))
	o.item_selected.connect(func(i): gfx[key] = i; _apply_gfx(); audio.play("click"))
	return o


func _gfx_check(key: String) -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = bool(gfx[key])
	c.toggled.connect(func(on): gfx[key] = on; _apply_gfx(); audio.play("click"))
	return c


func _open_sound_popup(anchor: Control) -> void:
	if sound_popup == null:
		sound_popup = PopupPanel.new()
		sound_popup.add_theme_stylebox_override("panel", _hud_style(Color(0.09, 0.1, 0.13, 0.97), 10))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 10)
		sound_popup.add_child(v)
		v.add_child(_volume_row("icons/musicOn", audio.music_volume, func(x): audio.set_music(true, x)))
		v.add_child(_volume_row("icons/audioOn", audio.sfx_volume, func(x): audio.set_sfx(true, x); audio.play("click")))
		add_child(sound_popup)
	var pos := anchor.get_global_rect().position + Vector2(-220, anchor.size.y + 8)
	sound_popup.popup(Rect2i(Vector2i(pos), Vector2i(270, 100)))


func _volume_row(icon: String, value: float, cb: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_icon_rect(icon, 28))
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.custom_minimum_size.x = 200
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(cb)
	row.add_child(s)
	return row


func _open_tab(i: int) -> void:
	if drawer.visible and tabs.current_tab == i:
		drawer.visible = false
		highlight_tool(-2)
		audio.play("close")
		return
	audio.play("open")
	tabs.current_tab = i
	drawer_title.text = TOOLS[i]["title"]
	drawer_icon.texture = _tex(TOOLS[i]["icon"])
	drawer.visible = true
	highlight_tool(-2)
	if i == 8:
		_build_finance()
	elif i == 9:
		_build_advisor()


## Tutorial markiert ein Werkzeug (-1 = keins). -2 = nur aktiven Zustand neu setzen.
func highlight_tool(idx: int) -> void:
	if idx != -2:
		tut_tool = idx
	office_view.set_screen_shift(drawer.size.x + 10.0 if drawer.visible else 0.0)
	for i in range(tool_btns.size()):
		var active := drawer.visible and tabs.current_tab == i
		tool_btns[i].modulate = C_WARN if i == tut_tool else (C_ACCENT if active else Color.WHITE)


func _toggle_world() -> void:
	office_view.set_mode("office" if office_view.mode == "world" else "world")
	view_btn.icon = _tex("icons/zoomIn" if office_view.mode == "world" else "icons/zoomOut")
	view_btn.text = "Büro" if office_view.mode == "world" else "Welt"
	view_btn.tooltip_text = "Zurück ins Büro (Tab)" if office_view.mode == "world" else "Weltansicht: Labor, Rechenzentren, Konkurrenz (Tab)"


func _toast(text: String) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _hud_style(Color(0.08, 0.09, 0.12, 0.8), 8))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.custom_minimum_size.x = 400
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_size_override("normal_font_size", 14)
	r.add_theme_font_size_override("bold_font_size", 14)
	r.text = text
	p.add_child(r)
	toast_box.add_child(p)
	while toast_box.get_child_count() > 4:
		var old := toast_box.get_child(0)
		toast_box.remove_child(old)
		old.queue_free()
	var tw := p.create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(p, "modulate:a", 0.0, 1.0)
	tw.tween_callback(p.queue_free)


func _tex(path: String) -> Texture2D:
	return load("res://assets/kenney/%s.png" % path)


## Werkzeug-Knopf: Symbol oben, kurze Beschriftung darunter
func _tool_button(icon: String, caption: String, tip: String) -> Button:
	var b := Button.new()
	b.icon = _tex(icon)
	b.text = caption
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.add_theme_font_size_override("font_size", 12)
	b.custom_minimum_size = Vector2(70, 66)
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_entered.connect(func(): b.scale = Vector2(1.06, 1.06))
	b.mouse_exited.connect(func(): b.scale = Vector2.ONE)
	b.resized.connect(func(): b.pivot_offset = b.size / 2.0)
	return b


func _icon_rect(path: String, px: int) -> TextureRect:
	var t := TextureRect.new()
	t.texture = _tex(path)
	t.custom_minimum_size = Vector2(px, px)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return t


func _icon_button(path: String, cb: Callable, tip: String, px: int) -> Button:
	var b := Button.new()
	b.icon = _tex(path)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(px, px)
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	b.mouse_entered.connect(func(): b.scale = Vector2(1.06, 1.06))
	b.mouse_exited.connect(func(): b.scale = Vector2.ONE)
	b.resized.connect(func(): b.pivot_offset = b.size / 2.0)
	return b


func _hud_style(col: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(10)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	return sb


func _build_modal() -> void:
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.visible = false
	add_child(modal)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(center)
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_PANEL
	sb.border_color = C_ACCENT.darkened(0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(20)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(680, 0)
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	modal_title = _label("", 24, C_ACCENT)
	v.add_child(modal_title)
	modal_text = RichTextLabel.new()
	modal_text.bbcode_enabled = true
	modal_text.fit_content = true
	modal_text.custom_minimum_size = Vector2(640, 0)
	v.add_child(modal_text)
	modal_buttons = VBoxContainer.new()
	modal_buttons.add_theme_constant_override("separation", 8)
	v.add_child(modal_buttons)


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_PANEL
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	t.set_stylebox("panel", "PanelContainer", sb)
	var bn := StyleBoxFlat.new()
	bn.bg_color = C_PANEL2
	bn.set_corner_radius_all(4)
	bn.content_margin_left = 10
	bn.content_margin_right = 10
	bn.content_margin_top = 5
	bn.content_margin_bottom = 5
	var bh: StyleBoxFlat = bn.duplicate()
	bh.bg_color = C_PANEL2.lightened(0.15)
	var bp: StyleBoxFlat = bn.duplicate()
	bp.bg_color = C_ACCENT.darkened(0.45)
	var bd: StyleBoxFlat = bn.duplicate()
	bd.bg_color = C_PANEL2.darkened(0.35)
	for cls in ["Button", "OptionButton"]:
		t.set_stylebox("normal", cls, bn)
		t.set_stylebox("hover", cls, bh)
		t.set_stylebox("pressed", cls, bp)
		t.set_stylebox("hover_pressed", cls, bp)
		t.set_stylebox("disabled", cls, bd)
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		t.set_color("font_color", cls, C_TEXT)
		t.set_color("font_disabled_color", cls, C_DIM)
	for st in ["normal", "pressed", "hover", "hover_pressed", "focus", "disabled"]:
		t.set_stylebox(st, "CheckBox", StyleBoxEmpty.new())
	t.set_color("font_color", "CheckBox", C_TEXT)
	t.set_color("font_pressed_color", "CheckBox", C_TEXT)
	t.set_color("font_hover_color", "CheckBox", C_ACCENT)
	t.set_color("font_hover_pressed_color", "CheckBox", C_ACCENT)
	t.set_color("font_color", "Label", C_TEXT)
	t.set_color("default_color", "RichTextLabel", C_TEXT)
	var tp := StyleBoxFlat.new()
	tp.bg_color = C_PANEL
	tp.set_corner_radius_all(6)
	t.set_stylebox("panel", "TabContainer", tp)
	var ts: StyleBoxFlat = bn.duplicate()
	ts.bg_color = C_PANEL
	ts.content_margin_left = 16
	ts.content_margin_right = 16
	ts.content_margin_top = 8
	ts.content_margin_bottom = 8
	var tu: StyleBoxFlat = ts.duplicate()
	tu.bg_color = C_BG
	var th: StyleBoxFlat = ts.duplicate()
	th.bg_color = C_PANEL2
	t.set_stylebox("tab_selected", "TabContainer", ts)
	t.set_stylebox("tab_unselected", "TabContainer", tu)
	t.set_stylebox("tab_hovered", "TabContainer", th)
	t.set_color("font_selected_color", "TabContainer", C_ACCENT)
	t.set_color("font_unselected_color", "TabContainer", C_DIM)
	t.set_font_size("font_size", "TabContainer", 16)
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = C_BG
	pb_bg.set_corner_radius_all(4)
	var pb_fill := StyleBoxFlat.new()
	pb_fill.bg_color = C_ACCENT.darkened(0.1)
	pb_fill.set_corner_radius_all(4)
	t.set_stylebox("background", "ProgressBar", pb_bg)
	t.set_stylebox("fill", "ProgressBar", pb_fill)
	return t


# ================================================================ Helfer

func _add_tab(title: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = title
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(sc)
	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 14)
	sc.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(v)
	return v

func _panel() -> PanelContainer:
	return PanelContainer.new()

func _label(text: String, font_size := 15, color := C_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l

func _wrap(text: String, color := C_TEXT) -> Label:
	var l := _label(text, 14, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 200
	return l

func _button(text: String, cb: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b

func _slider_row(lo: int, hi: int, value, cb: Callable, suffix: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 1
	s.value = float(value)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	var l := _label("%d%s" % [int(value), suffix], 15)
	l.custom_minimum_size.x = 70
	s.value_changed.connect(func(v): l.text = "%d%s" % [int(v), suffix]; cb.call(v))
	row.add_child(s)
	row.add_child(l)
	return row

func _short(v: float) -> String:
	if v >= 1e6:
		return "%.1fM" % (v / 1e6)
	if v >= 1e4:
		return "%.0fk" % (v / 1e3)
	return "%.0f" % v

func _size_name(p: float) -> String:
	if p < 1.0:
		return "%dM" % int(round(p * 1000.0))
	if p >= 1000.0:
		return "%dT" % int(p / 1000.0)
	return "%dB" % int(p)

func _clear(c: Node) -> void:
	for ch in c.get_children():
		c.remove_child(ch)
		ch.queue_free()


# ================================================================ Screenshot-Modus

func _screenshot_mode(args: PackedStringArray) -> void:
	var path := "user://shot.png"
	var days := 0
	var tab := -1
	var world := false
	var show_modal := false
	var office_only := false
	var tut := -1
	var scroll := 0
	var wait := 0.0
	for a in args:
		if a.begins_with("--shot="):
			path = a.substr(7)
		elif a.begins_with("--days="):
			days = int(a.substr(7))
		elif a.begins_with("--tab="):
			tab = int(a.substr(6))
		elif a == "--modal":
			show_modal = true
		elif a.begins_with("--tut="):
			tut = int(a.substr(6))
		elif a.begins_with("--scroll="):
			scroll = int(a.substr(9))
		elif a.begins_with("--wait="):
			wait = float(a.substr(7))
		elif a == "--world":
			world = true
		elif a == "--office":
			office_only = true
	set_process(false)
	lab = Lab.new()
	lab.setup(7)
	lab.flags["tut"] = tut
	_reset_view()
	for i in range(days):
		lab.step_day()
		if i < days - 1 or not show_modal:
			while not lab.event_queue.is_empty():
				lab.resolve_event(Bot.choose(lab))
		if i % 7 == 0:
			Bot.manage(lab)
	if show_modal and lab.event_queue.is_empty():
		lab._info("Beispiel-Ereignis", "So sehen Ereignisse aus.")
	if tab >= 0:
		_open_tab(tab)
	if world:
		_toggle_world()
	_refresh()
	if scroll > 0:
		await get_tree().process_frame
		(tabs.get_child(tab) as ScrollContainer).scroll_vertical = scroll
	if show_modal:
		_check_modal()
	else:
		modal.visible = false
	for i in range(4):
		await get_tree().process_frame
	if wait > 0.0:
		await get_tree().create_timer(wait).timeout
	if office_only:
		for ch in get_children():
			if ch != office_view and ch is CanvasItem:
				ch.visible = false
		office_view.info_label.visible = false
		for i in range(3):
			await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(path)
	print("Screenshot: ", path)
	get_tree().quit()
