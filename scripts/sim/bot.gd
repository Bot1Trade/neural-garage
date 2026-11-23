extends RefCounted
## Autopilot: spielt wie ein erfahrener Spieler. Genutzt vom Balance-Test und vom Screenshot-Modus.

const D = preload("res://scripts/sim/data.gd")

static func choose(lab) -> int:
	var ev: Dictionary = lab.event_queue[0]
	match ev["id"]:
		"model_ready": return 1  # API
		"gray_offer", "journalist", "bench_gaming", "jailbreak", "raise": return 1
	return 0

static func manage(lab) -> void:
	# Forschung: günstigste verfügbare zuerst
	var best := ""
	var best_cost := INF
	for t in D.TECHS:
		if lab.tech_state(t["id"]) == "available" and float(t["rp"]) * (1.6 if t["kind"] == "infra" else 1.0) < best_cost:
			best = t["id"]
			best_cost = float(t["rp"]) * (1.6 if t["kind"] == "infra" else 1.0)
	if best != "" and lab.rp >= float(lab.tech(best)["rp"]):
		lab.research(best)
	# Büro
	if lab.office < D.OFFICES.size() - 1 and lab.money > float(D.OFFICES[lab.office + 1]["cost"]) * 1.5:
		lab.upgrade_office()
	var burn: float = lab.last_cost - lab.last_income
	var runway: float = lab.money / maxf(1.0, burn)
	# Einstellen, wenn das Geld reicht
	if lab.staff.size() < int(lab.office_data()["staff"]) and (burn < -lab.last_cost * 0.1 or runway > 400.0) and lab.candidates.size() > 0:
		var counts := {}
		for p in lab.staff:
			counts[p["role"]] = int(counts.get(p["role"], 0)) + 1
		var pick := 0
		var pick_score := -INF
		for i in range(lab.candidates.size()):
			var c: Dictionary = lab.candidates[i]
			var s := float(c["skill"]) - 2.0 * int(counts.get(c["role"], 0))
			if c["role"] == "research":
				s += 1.0
			if c["role"] == "manager":
				s += 10.0 if (lab.staff.size() >= 5 and not lab.managed()) else -20.0
			if s > pick_score:
				pick_score = s
				pick = i
		lab.hire(pick)
	# Personal: ohne Manager selbst in Urlaub schicken
	if not lab.managed():
		var limit := maxi(1, int(lab.staff.size() * 0.15))
		for i in range(lab.staff.size()):
			if lab.away_count() >= limit:
				break
			if float(lab.staff[i].get("energy", 100.0)) < 30.0 and int(lab.staff[i].get("vacation", 0)) == 0:
				lab.send_vacation(i)
	# Hardware warten
	if lab.hw_count(lab.office_hw) > 0 and lab.hw_avg_cond(lab.office_hw) < 65.0:
		lab.maintain_office()
	for i in range(lab.datacenters.size()):
		if lab.hw_avg_cond(lab.datacenters[i]["hw"]) < 65.0:
			lab.maintain_dc(i)
	# GPUs nach Budget: mit Polster kaufen, sonst mieten
	var free: int = int(lab.office_data()["gpus"]) - lab.gpu_count()
	var budget: float = 0.5 * lab.last_income - lab.daily_salaries() * 0.5 + lab.money / 1000.0 - lab.daily_gpu_cost()
	var unit: float = lab.gpu_cost(lab.gpu_gen_now())
	var buy_price: float = lab.hw_unit("market")["price"]
	if free > 0 and lab.money > 3000000.0 and burn <= 0.0:
		lab.buy_office_hw("market", mini(free, int(lab.money * 0.15 / buy_price)))
	elif free > 0 and budget > unit:
		lab.rent_gpus(mini(free, int(budget / unit)))
	elif burn > 0.0 and runway < 45.0 and lab.rented_count() > 2:
		lab.return_gpus(lab.rented_count() / 3)
	manage_infra(lab)
	# Training
	if lab.training.is_empty():
		var d: Dictionary = lab.default_design()
		d["focus"] = era_focus(lab)
		d["eval_days"] = 20 if lab.year() >= 2020 else 0
		var data := []
		for id in D.DATA:
			if id != "gray" and lab.data_available(id):
				data.append(id)
		d["data"] = data
		# Volle Daten vs. Gratis-Daten: die Variante mit der höheren Qualität nehmen
		var best_d := {}
		var best_q := -1.0
		for data_set in [data, ["web", "code"]]:
			var cand: Dictionary = d.duplicate(true)
			cand["data"] = data_set
			var si := _pick_size(lab, cand)
			if si >= 0:
				cand["size_index"] = si
				var q: float = lab.evaluate_design(cand)["q"]
				if q > best_q:
					best_q = q
					best_d = cand
		if not best_d.is_empty():
			lab.start_training(best_d)
	# Ältestes API-Modell zurückziehen, wenn mehr als 2 laufen
	var apis := []
	for m in lab.models:
		if m["status"] == "api":
			apis.append(m)
	if apis.size() > 2:
		apis.sort_custom(func(a, b): return float(a["q"]) < float(b["q"]))
		lab.withdraw_model(int(apis[0]["id"]))

static func _pick_size(lab, d: Dictionary) -> int:
	var chosen := -1
	for si in range(D.SIZES.size()):
		d["size_index"] = si
		var ev: Dictionary = lab.evaluate_design(d)
		if ev["train_days"] <= 60.0 and ev["data_cost"] < lab.money * 0.5:
			chosen = si
	return chosen

## Büro-Upgrades, Rechenzentren, Chips
static func manage_infra(lab) -> void:
	for u in D.OFFICE_UPGRADES:
		if not lab.office_upgrades.has(u["id"]) and lab.office >= int(u["min_office"]) and lab.money > float(u["cost"]) * 5.0:
			lab.buy_office_upgrade(u["id"])
	if lab.techs.has("chipdesign") and lab.chip_project.is_empty() and lab.money > lab.chip_project_cost() * 4.0:
		if lab.custom_chip.is_empty() or float(lab.custom_chip["power"]) < lab.gpu_power(lab.gpu_gen_now()) * 1.5:
			lab.start_chip_project()
	if lab.techs.has("fab") and not lab.has_fab and lab.money > D.FAB_COST * lab.inflation() * 3.0:
		var fp := pick_plot(lab, 0.0)
		if fp != "":
			lab.build_fab(fp)
	# Neues RZ, wenn keins da ist oder alle fast voll sind
	var full := true
	for dc in lab.datacenters:
		if lab.dc_used(dc) < lab.dc_slots(dc) * 0.95:
			full = false
	if full:
		for i in range(D.DATACENTERS.size() - 1, -1, -1):
			var t: Dictionary = D.DATACENTERS[i]
			if i == 0 and lab.datacenters.size() >= 2:
				break  # ab zwei Standorten nur noch größere Rechenzentren
			if lab.year() >= int(t["year"]) and lab.money > lab.dc_build_cost(t["id"], "p3") * 1.5 + 600000.0:
				var pp := pick_plot(lab, lab.dc_build_cost(t["id"], "p3") * 1.5)
				if pp != "":
					lab.build_datacenter(t["id"], pp)
				break
	# Hardware kaufen: max. 30 % des Geldes pro Woche
	var kind := "custom" if not lab.custom_chip.is_empty() else "market"
	for i in range(lab.datacenters.size()):
		var dc: Dictionary = lab.datacenters[i]
		var free: int = lab.dc_slots(dc) - lab.dc_used(dc)
		if free <= 0:
			continue
		if lab.last_income <= lab.last_cost or lab.money < 3000000.0:
			break
		var price: float = lab.hw_unit(kind)["price"]
		var n: int = mini(free, int(lab.money * 0.2 / price))
		if n > 0:
			lab.buy_hardware(i, kind, n)
		if not dc["upgrades"].has("cooling") and lab.money > lab.dc_upgrade_cost(dc, "cooling") * 4.0:
			lab.buy_dc_upgrade(i, "cooling")

## Freies eigenes Grundstück nehmen oder das günstigste (Strom zählt mit) kaufen
static func pick_plot(lab, reserve: float) -> String:
	var own: Array = lab.empty_plots()
	if not own.is_empty():
		return own[0]
	var best := ""
	var best_score := INF
	for p in D.PLOTS:
		if lab.plot_state(p["id"]) == "for_sale":
			var power: float = lab._find(D.LOCATIONS, p["loc"])["power"]
			var score: float = lab.plot_price(p["id"]) * (0.5 + power)
			if score < best_score:
				best_score = score
				best = p["id"]
	if best != "" and lab.money > lab.plot_price(best) + reserve:
		lab.buy_plot(best)
		return best
	return ""

## Bot kennt den Zeitgeist ungefähr (wie ein erfahrener Spieler)
static func era_focus(lab) -> Dictionary:
	var ideal: Dictionary = lab.era()["ideal"]
	var f := {}
	for k in D.FOCUS_KEYS:
		f[k] = maxi(0, int(ideal[k]) + lab.rng.randi_range(-1, 1))
	return lab.scale_focus(f)
