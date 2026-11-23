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
	check(lab.build_datacenter("colo", "isl") != "", "Colocation erst ab 2018")
	lab.day = 365 * 3
	check(lab.build_datacenter("colo", "isl") == "", "Colocation in Island")
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
	check(lab.build_fab() == "", "Fabrik bauen")
	check(float(lab.hw_unit("custom")["price"]) < float(chip["price"]), "Fabrik senkt Preis")

func test_audio_files() -> void:
	var A = load("res://scripts/ui/audio.gd")
	for path in A.MUSIC:
		var st: AudioStream = load(path)
		check(st != null and st.get_length() > 20.0, "Musik lädt: %s (%.0f s)" % [path, st.get_length() if st else 0.0])
	for k in A.SFX:
		var st: AudioStream = load(A.S + A.SFX[k][0] + ".ogg")
		check(st != null and st.get_length() > 0.0, "Sound lädt: " + k)

func test_bankrupt() -> void:
	var lab := new_lab()
	lab.money = -1.0
	lab.investor_stage = 99
	for i in range(70):
		lab.step_day()
		while not lab.event_queue.is_empty():
			lab.resolve_event(1)
	check(lab.ending.get("id", "") == "bankrupt", "Pleite-Ende")
