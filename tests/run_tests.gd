extends SceneTree
## Headless-Tests: godot --headless --path . -s tests/run_tests.gd

const Lab = preload("res://scripts/sim/lab.gd")

var failed := 0
var passed := 0

func check(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", msg)

func _init() -> void:
	test_setup()
	test_training_and_release()
	test_hire_and_gpus()
	test_research()
	test_save_load()
	test_bankrupt()
	test_offices()
	test_datacenter()
	test_chips()
	test_audio_files()
	test_focus_budget()
	test_advice_and_ledger()
	test_staff_system()
	test_popularity()
	test_hardware()
	test_market()
	test_ads_investors_plants()
	print("Tests: %d ok, %d fehlgeschlagen" % [passed, failed])
	quit(1 if failed > 0 else 0)

func new_lab() -> RefCounted:
	var lab := Lab.new()
	lab.setup(42)
	return lab

func test_setup() -> void:
	var lab := new_lab()
	check(lab.money == 80000.0, "Startgeld")
	check(lab.staff.size() == 1, "Mitgründung da")
	check(lab.candidates.size() == 4, "4 Kandidaten")
	check(lab.date_string() == "1. Jan. 2016", "Datum: " + lab.date_string())

func test_training_and_release() -> void:
	var lab := new_lab()
	var d: Dictionary = lab.default_design()
	check(lab.start_training(d) == "", "Training startet")
	check(lab.start_training(d) != "", "Kein zweites Training")
	var guard := 0
	while lab.models.is_empty() and guard < 400:
		lab.step_day()
		while not lab.event_queue.is_empty() and lab.event_queue[0]["id"] != "model_ready":
			lab.resolve_event(0)
		guard += 1
	check(lab.models.size() == 1, "Modell fertig nach %d Tagen" % guard)
	check(lab.event_queue[0]["id"] == "model_ready", "Release-Dialog")
	lab.resolve_event(1)  # API
	check(lab.models[0]["status"] == "api", "API-Status")
	check(lab.models[0]["rating"] > 0.0, "Bewertung gesetzt")
	check(lab.event_queue[0]["title"].begins_with("Kritiken"), "Kritik-Popup")
	check(lab.api_revenue() > 0.0, "Umsatz > 0")

func test_hire_and_gpus() -> void:
	var lab := new_lab()
	check(lab.hire(0) == "", "Einstellen")
	check(lab.staff.size() == 2, "2 im Team")
	check(lab.rent_gpus(100) == "", "GPUs mieten (gekappt)")
	check(lab.gpu_count() == 8, "Garage max 8 GPUs, ist %d" % lab.gpu_count())
	lab.return_gpus(3)
	check(lab.gpu_count() == 5, "GPUs zurückgeben")
	check(lab.upgrade_office() != "", "Loft zu teuer am Start")

func test_research() -> void:
	var lab := new_lab()
	check(lab.tech_state("transformer") == "future", "Transformer erst 2017")
	lab.day = 400
	lab.rp = 50.0
	check(lab.research("transformer") == "", "Transformer erforschen")
	check(lab.techs.has("transformer"), "Transformer da")
	check(lab.rp == 10.0, "RP abgezogen")

func test_save_load() -> void:
	var lab := new_lab()
	for i in range(50):
		lab.step_day()
		while not lab.event_queue.is_empty():
			lab.resolve_event(0)
	var json := JSON.stringify(lab.to_dict())
	var lab2 := Lab.new()
	lab2.from_dict(JSON.parse_string(json))
	check(lab2.day == lab.day, "Tag geladen")
	check(absf(lab2.money - lab.money) < 0.01, "Geld geladen")
	check(lab2.staff.size() == lab.staff.size(), "Team geladen")
	lab2.step_day()
	check(lab2.day == lab.day + 1, "Weiterspielen nach Laden")

func test_offices() -> void:
	var lab := new_lab()
	lab.money = 10000000.0
	check(lab.buy_office(3) == "", "Büro-Sprung auf Stufe 3")
	check(lab.office == 3, "Büro ist Tech-Tower")
	check(lab.buy_office(2) != "", "Kein Rückschritt")
	var rp_before: float = lab.rp_per_day()
	check(lab.buy_office_upgrade("coffee") == "", "Kaffeebar kaufen")
	check(lab.rp_per_day() > rp_before, "Kaffeebar wirkt")
	check(lab.buy_office_upgrade("coffee") != "", "Kein Doppelkauf")
	check(lab.buy_office_upgrade("daycare") != "", "Kita braucht Campus")

func test_datacenter() -> void:
	var lab := new_lab()
	lab.money = 100000000.0
	check(lab.buy_plot("p6") != "", "Grundstück erst ab 2020")
	check(lab.build_datacenter("colo", "p3") != "", "Ohne Grundstück kein Bau")
	lab.day = 365 * 3
	check(lab.plot_state("p3") == "for_sale", "Grundstück p3 zu kaufen")
	check(lab.buy_plot("p3") == "", "Grundstück kaufen")
	check(lab.plot_state("p3") == "empty", "Grundstück gehört dir")
	check(lab.build_datacenter("colo", "p3") == "", "Colocation auf p3")
	check(lab.plot_state("p3") == "dc", "Grundstück bebaut")
	check(lab.build_datacenter("colo", "p3") != "", "Kein Doppelbau")
	var p0: float = lab.compute_power()
	check(lab.buy_hardware(0, "market", 100) == "", "100 GPUs kaufen")
	check(lab.dc_used(lab.datacenters[0]) == 100, "100 belegt")
	check(lab.compute_power() > p0, "Mehr Leistung")
	var c0: float = lab.daily_dc_cost()
	check(lab.buy_dc_upgrade(0, "cooling") == "", "Kühlung")
	check(lab.daily_dc_cost() < c0, "Kühlung senkt Strom")
	check(lab.buy_hardware(0, "market", 99999) == "", "Bis voll kaufen")
	check(lab.dc_used(lab.datacenters[0]) == lab.dc_slots(lab.datacenters[0]), "Voll")
	lab.scrap_hardware(0, 12)
	check(lab.dc_used(lab.datacenters[0]) == lab.dc_slots(lab.datacenters[0]) - 12, "Verschrotten")
	var json := JSON.stringify(lab.to_dict())
	var lab2 := Lab.new()
	lab2.from_dict(JSON.parse_string(json))
	check(absf(lab2.compute_power() - lab.compute_power()) < 0.01, "RZ gespeichert")

func test_chips() -> void:
	var lab := new_lab()
	lab.money = 5000000000.0
	check(lab.start_chip_project() != "", "Chip braucht Forschung")
	lab.day = 365 * 5
	lab.techs["chipdesign"] = true
	check(lab.start_chip_project() == "", "Chip-Projekt startet")
	lab.investor_stage = 99
	for i in range(400):
		lab.step_day()
		while not lab.event_queue.is_empty():
			lab.resolve_event(0)
	check(lab.chip_version == 1, "Chip NG-1 fertig")
	var chip: Dictionary = lab.hw_unit("custom")
	var market: Dictionary = lab.hw_unit("market")
	check(float(chip["power"]) > float(market["power"]), "Eigener Chip stärker")
	check(float(chip["price"]) < float(market["price"]) * 1.0, "Eigener Chip billiger")
	lab.techs["fab"] = true
	check(lab.build_fab("p1") != "", "Fabrik braucht eigenes Grundstück")
	lab.buy_plot("p1")
	check(lab.build_fab("p1") == "", "Fabrik bauen")
	check(lab.plot_state("p1") == "fab", "Fabrik steht auf p1")
	check(float(lab.hw_unit("custom")["price"]) < float(chip["price"]), "Fabrik senkt Preis")

func test_audio_files() -> void:
	var A = load("res://scripts/ui/audio.gd")
	for path in A.MUSIC:
		var st: AudioStream = load(path)
		check(st != null and st.get_length() > 20.0, "Musik lädt: %s (%.0f s)" % [path, st.get_length() if st else 0.0])
	for k in A.SFX:
		var st: AudioStream = load(A.S + A.SFX[k][0] + ".ogg")
		check(st != null and st.get_length() > 0.0, "Sound lädt: " + k)

func test_focus_budget() -> void:
	var lab := new_lab()
	var all_max := {"help": 10, "code": 10, "creative": 10, "safety": 10}
	check(lab.focus_spent(lab.clamp_focus(all_max)) == 10, "Alles auf 10 wird auf 10 Punkte gekürzt")
	var d: Dictionary = lab.default_design()
	d["focus"] = all_max
	var balanced: Dictionary = d.duplicate(true)
	balanced["focus"] = {"help": 3, "code": 2, "creative": 3, "safety": 2}
	check(absf(lab.evaluate_design(d)["q"] - lab.evaluate_design(balanced)["q"]) < 0.01, "Überbuchung bringt keinen Vorteil")
	var lazy: Dictionary = d.duplicate(true)
	lazy["focus"] = {"help": 1, "code": 0, "creative": 0, "safety": 0}
	check(lab.evaluate_design(lazy)["q"] < lab.evaluate_design(balanced)["q"], "Ungenutzte Punkte kosten Qualität")
	var sc: Dictionary = lab.scale_focus({"help": 1, "code": 1, "creative": 1, "safety": 0})
	check(lab.focus_spent(sc) == 10, "Skalieren ergibt genau 10")
	lab.start_training(d)
	check(lab.focus_spent(lab.training["design"]["focus"]) == 10, "Training speichert gekürzten Fokus")

func test_advice_and_ledger() -> void:
	var lab := new_lab()
	var tips: Array = lab.advice()
	var has_train := false
	for t in tips:
		if String(t["text"]).contains("kein Training"):
			has_train = true
	check(has_train, "Berater meldet: kein Training")
	check(tips.size() > 0 and int(tips[0]["prio"]) >= int(tips[tips.size() - 1]["prio"]), "Tipps sortiert")
	lab.money = 1000.0
	lab.last_cost = 5000.0
	lab.last_income = 0.0
	check(int(lab.advice()[0]["prio"]) >= 100, "Geldnot steht oben")
	var lab2 := new_lab()
	for i in range(40):
		lab2.step_day()
		while not lab2.event_queue.is_empty():
			lab2.resolve_event(0)
	var month: Dictionary = lab2.ledger_month()
	check(month.has("salary") and float(month["salary"]) < 0.0, "Kassenbuch: Gehälter gebucht")
	check(lab2.ledger_days.size() == 30, "Kassenbuch hält 30 Tage")
	var sum := 0.0
	for k in lab2.ledger_year:
		sum += float(lab2.ledger_year[k])
	check(absf((80000.0 + sum) - lab2.money) < 1.0, "Kassenbuch erklärt den Kontostand")

func test_staff_system() -> void:
	var lab := new_lab()
	lab.staff.append(lab._make_person("research", 3))
	var p: Dictionary = lab.staff[1]
	var sal0: float = p["salary"]
	check(float(p["energy"]) == 100.0 and int(p["vacation"]) == 0, "Neue Leute: volle Energie")
	for i in range(200):
		lab._step_staff()
		lab.day += 1
	check(float(p["energy"]) < 70.0, "Energie sinkt mit der Arbeit (%.0f)" % p["energy"])
	var before: float = lab.eff_skill(p)
	check(lab.send_vacation(1) == "", "Urlaub")
	check(lab.eff_skill(p) == 0.0, "Im Urlaub keine Leistung")
	for i in range(14):
		lab._step_staff()
		lab.day += 1
	check(int(p["vacation"]) == 0 and float(p["energy"]) > 90.0, "Erholt zurück")
	check(lab.eff_skill(p) > before, "Nach Urlaub mehr Leistung")
	lab._grow_staff()
	check(float(p["salary"]) == sal0, "Gehalt steigt nicht automatisch")
	p["next_raise"] = lab.day
	lab.event_queue.clear()
	lab._step_staff()
	check(not lab.event_queue.is_empty() and lab.event_queue[0]["id"] == "raise", "Gehaltswunsch als Ereignis")
	lab.resolve_event(0)
	check(float(p["salary"]) > sal0, "Gehaltserhöhung angenommen")
	# Manager übernimmt
	var lab2 := new_lab()
	lab2.staff.append(lab2._make_person("manager", 5))
	lab2.staff.append(lab2._make_person("research", 3))
	check(lab2.managed(), "Manager betreut das Team")
	lab2.staff[2]["energy"] = 20.0
	lab2.day = 7
	lab2._step_staff()
	check(int(lab2.staff[2]["vacation"]) > 0, "Manager schickt Erschöpfte in Urlaub")
	lab2.staff[2]["next_raise"] = lab2.day
	lab2.event_queue.clear()
	lab2._step_staff()
	check(lab2.event_queue.is_empty(), "Manager verhandelt Gehaltswunsch selbst")

func test_popularity() -> void:
	var lab := new_lab()
	var d: Dictionary = lab.default_design()
	d["arch"] = "rnn"
	lab.start_training(d)
	while lab.models.is_empty():
		lab.step_day()
		while not lab.event_queue.is_empty() and lab.event_queue[0]["id"] != "model_ready":
			lab.resolve_event(0)
	lab.event_queue.clear()
	var id: int = lab.models[0]["id"]
	lab.release_model(id, "api")
	var m: Dictionary = lab.get_model(id)
	var u0: float = m["users"]
	check(u0 > 0.0, "Start-Hype: erste Nutzer")
	for i in range(60):
		lab._step_users()
	check(float(m["users"]) > u0 * 2.0, "Nutzer wachsen (%.0f → %.0f)" % [u0, m["users"]])
	var peak: float = m["users"]
	lab.day += 365 * 2
	for i in range(30):
		lab._step_users()
	check(float(m["users"]) < peak and float(m["users"]) > peak * 0.7, "Veraltetes Modell verliert Nutzer nur langsam")
	check(lab.model_revenue(m) > 0.0 and lab.popularity(m) > 0.0, "Umsatz und Beliebtheit")

func test_hardware() -> void:
	var lab := new_lab()
	lab.money = 1000000.0
	var p0: float = lab.compute_power()
	check(lab.buy_office_hw("market", 4) == "", "GPUs fürs Büro kaufen")
	check(lab.gpu_count() == 6, "Büro: 2 gemietet + 4 gekauft")
	check(lab.compute_power() > p0, "Mehr Leistung")
	check(lab.daily_office_power() > 0.0, "Gekaufte GPUs kosten Strom")
	var pw: float = lab.daily_office_power()
	lab.money = 1000000.0
	lab.office = 1
	lab.buy_office_upgrade("solar")
	check(lab.daily_office_power() < pw * 0.7, "Solaranlage senkt Strom")
	for i in range(300):
		lab._step_hw()
	check(lab.hw_avg_cond(lab.office_hw) < 75.0, "Hardware nutzt sich ab")
	var worn: float = lab.compute_power()
	check(lab.maintain_office() == "", "Wartung")
	check(lab.compute_power() > worn, "Wartung bringt Leistung zurück")
	var m0: float = lab.money
	lab.day += 365
	var v: float = lab.sell_office_hw(2)
	check(v > 0.0 and lab.money > m0 and lab.gpu_count() == 4, "Verkaufen bringt Geld")

func test_market() -> void:
	var lab := new_lab()
	lab.money = 500000000.0
	lab._init_companies()
	var rent0: float = lab.rent_price(1)
	var buy0: float = lab.hw_unit("market")["price"]
	check(lab.buy_stake("skycompute") == "" and lab.stake("skycompute") == 5.0, "5 % SkyCompute gekauft")
	check(lab.rent_price(1) < rent0, "Cloud-Beteiligung senkt Miete")
	for i in range(4):
		lab.buy_stake("siliconix")
	check(float(lab.hw_unit("market")["price"]) < buy0, "Chip-Beteiligung senkt Kaufpreis")
	var m0: float = lab.money
	lab._step_market()
	check(lab.daily_dividends() > 0.0 and lab.ledger_today.has("dividend"), "Dividenden fließen")
	check(lab.sell_stake("skycompute") == "" and lab.money > m0, "Anteile verkaufen")
	for i in range(11):
		lab.buy_stake("helix")
	check(lab.controls("helix") and lab.flags.get("helix_controlled", false), "Helix ab 51 % kontrolliert")
	var cnt: int = lab.rival["count"]
	lab.rival["next_day"] = 0
	lab._step_rival()
	check(int(lab.rival["count"]) == cnt, "Kontrollierte Helix veröffentlicht keine Konkurrenzmodelle")
	for i in range(20):
		lab.buy_stake("nova")
	check(lab.absorbed_labs() == 1, "Nova Minds übernommen")

func test_ads_investors_plants() -> void:
	var lab := new_lab()
	lab.money = 50000000.0
	var d: Dictionary = lab.default_design()
	lab.start_training(d)
	while lab.models.is_empty():
		lab.step_day()
		lab.event_queue.clear()
	var id: int = lab.models[0]["id"]
	lab.release_model(id, "api")
	var m: Dictionary = lab.get_model(id)
	var t0: float = lab.target_users(m)
	check(lab.start_campaign(id, "online") == "", "Werbung starten")
	check(lab.target_users(m) > t0 * 1.2, "Werbung erhöht Nutzer-Potenzial")
	check(lab.start_campaign(id, "big") != "", "Nur eine Kampagne gleichzeitig")
	check(lab.start_roadshow() == "", "Roadshow starten")
	lab.event_queue.clear()
	lab.day = int(lab.flags["roadshow_until"])
	lab._step_roadshow()
	check(not lab.event_queue.is_empty() and lab.event_queue[0]["id"] == "offer", "Roadshow bringt Angebot")
	var eq: float = lab.equity
	var mon: float = lab.money
	lab.resolve_event(0)
	check(lab.equity < eq and lab.money > mon, "Angebot angenommen")
	lab.day = 365 * 6
	lab.buy_plot("p3")
	check(lab.build_plant("solarpark", "p3") == "", "Solarpark bauen")
	check(lab.plot_state("p3") == "plant" and lab.energy_output() > 0.0, "Kraftwerk liefert Strom")
	check(lab._energy_credit(100.0) > 100.0, "Überschuss wird verkauft")

func test_bankrupt() -> void:
	var lab := new_lab()
	lab.money = -1.0
	lab.investor_stage = 99
	for i in range(70):
		lab.step_day()
		while not lab.event_queue.is_empty():
			lab.resolve_event(1)
	check(lab.ending.get("id", "") == "bankrupt", "Pleite-Ende")
