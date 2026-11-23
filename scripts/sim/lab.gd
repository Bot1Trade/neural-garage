extends RefCounted
## Komplette Simulation des KI-Labors. Keine Node-Abhängigkeit → headless testbar.
## Die UI ruft step_day() auf und arbeitet event_queue ab (resolve_event).

const D = preload("res://scripts/sim/data.gd")

const SAVE_KEYS := ["day", "money", "total_revenue", "reputation", "equity", "office", "staff", "candidates",
	"gpus", "techs", "rp", "models", "training", "data_unlocked", "flags", "cooldowns", "rival", "goal_index",
	"investor_stage", "investor_next_day", "broke_days", "best_rating", "best_q", "gpu_price_mult",
	"gpu_shortage_days", "ending", "news", "news_total", "office_upgrades", "datacenters", "chip_version", "chip_project", "custom_chip", "has_fab", "event_queue", "next_model_id", "era_index"]
const INT_KEYS := ["day", "office", "goal_index", "investor_stage", "investor_next_day", "broke_days",
	"gpu_shortage_days", "next_model_id", "era_index", "news_total", "chip_version"]

var rng := RandomNumberGenerator.new()
var day: int = 0
var money: float = 0.0
var total_revenue: float = 0.0
var reputation: float = 0.0
var equity: float = 100.0
var office: int = 0
var staff: Array = []
var candidates: Array = []
var gpus: Array = []            # [{gen, count}]
var techs: Dictionary = {}
var rp: float = 0.0
var models: Array = []
var training: Dictionary = {}
var data_unlocked: Dictionary = {}
var flags: Dictionary = {}
var cooldowns: Dictionary = {}
var rival: Dictionary = {}
var goal_index: int = 0
var investor_stage: int = 0
var investor_next_day: int = 0
var broke_days: int = 0
var best_rating: float = 0.0
var best_q: float = 0.0
var gpu_price_mult: float = 1.0
var gpu_shortage_days: int = 0
var ending: Dictionary = {}
var news: Array = []
var news_total: int = 0           # zählt alle News (UI erkennt neue)
var event_queue: Array = []
var next_model_id: int = 1
var era_index: int = 0
var office_upgrades: Dictionary = {}   # id -> true
var datacenters: Array = []           # [{type, loc, upgrades:{}, hw:[{name, power, count, upkeep}]}]
var chip_version: int = 0
var chip_project: Dictionary = {}     # {progress, version}
var custom_chip: Dictionary = {}      # {name, power, base}  (base = Tagesmiete-Äquivalent bei Fertigstellung)
var has_fab: bool = false
var fx: Array = []                    # Effekte für die 3D-Ansicht (nicht gespeichert)
var revision: int = 0           # steigt bei Strukturänderungen → UI baut Listen neu
var last_income: float = 0.0
var last_cost: float = 0.0


func setup(seed_value: int = 0) -> void:
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	money = 80000.0
	techs = {"rnn": true}
	data_unlocked = {"web": true, "code": true, "books": true}
	gpus = [{"gen": 1, "count": 2}]
	var cofounder := _make_person("research", 3, 0.5)
	cofounder["name"] += " (Mitgründung)"
	staff = [cofounder]
	_refresh_candidates()
	rival = {"name": "Helix Dynamics", "best_q": 9.0, "count": 0, "next_day": 160}
	investor_next_day = 25
	_news("Jan. 2016: Du gründest dein KI-Labor in einer Garage. Erstes Ziel: ein eigenes Modell trainieren.")


# ---------------------------------------------------------------- Zeit & Markt

func years() -> float:
	return day / 365.0

func year() -> int:
	return D.START_YEAR + floori(day / 365.0)

func date_string() -> String:
	var doy := day % 365
	var m := 0
	while m < 11 and doy >= D.MONTH_DAYS_CUM[m + 1]:
		m += 1
	return "%d. %s %d" % [doy - D.MONTH_DAYS_CUM[m] + 1, D.MONTH_NAMES[m], year()]

## Was der Markt an Modellqualität erwartet. Schnelles Wachstum bis 2024, danach langsamer.
func expected_quality(at_day: int = -1) -> float:
	var y := (day if at_day < 0 else at_day) / 365.0
	var i := clampi(floori(y), 0, D.EXPECTED_BY_YEAR.size() - 2)
	return lerpf(D.EXPECTED_BY_YEAR[i], D.EXPECTED_BY_YEAR[i + 1], clampf(y - i, 0.0, 1.0))

func market() -> float:
	return pow(1.45, minf(years(), 10.0)) * pow(1.15, maxf(0.0, years() - 10.0))

func inflation() -> float:
	return pow(1.05, years())

func era() -> Dictionary:
	var e: Dictionary = D.ERAS[0]
	for x in D.ERAS:
		if year() >= x["from"]:
			e = x
	return e


# ---------------------------------------------------------------- Compute

func gpu_gen_now() -> int:
	return clampi(1 + floori(years() / 2.0), 1, 6)

func gpu_power(gen: int) -> float:
	return pow(2.0, gen - 1)

func gpu_cost(gen: int) -> float:
	return 25.0 * pow(1.55, gen - 1) * gpu_price_mult

func gpu_count() -> int:
	var n := 0
	for g in gpus:
		n += int(g["count"])
	return n

## Gesamte Rechenleistung: gemietete GPUs im Büro + eigene Hardware in Rechenzentren
func compute_power() -> float:
	return rented_power() + dc_total_power()

func rented_power() -> float:
	var p := 0.0
	for g in gpus:
		p += int(g["count"]) * gpu_power(int(g["gen"]))
	return p

func daily_gpu_cost() -> float:
	var c := 0.0
	for g in gpus:
		c += int(g["count"]) * gpu_cost(int(g["gen"]))
	return c


# ---------------------------------------------------------------- Team

func office_data() -> Dictionary:
	return D.OFFICES[office]

func role_skill(role: String) -> float:
	var s := 0.0
	for p in staff:
		if p["role"] == role:
			s += float(p["skill"])
	return s

func team_quality() -> float:
	var q := clampf(0.85 + 0.025 * role_skill("research"), 0.85, 1.4)
	if office_upgrades.has("meeting"):
		q += 0.04
	return q

func engineer_mult() -> float:
	var m := clampf(1.0 + 0.04 * role_skill("engineer"), 1.0, 2.5)
	if office_upgrades.has("hwlab"):
		m *= 1.1
	return m

func sales_mult() -> float:
	return 1.0 + 0.04 * role_skill("sales")

func safety_reduction() -> float:
	return minf(0.5, 0.04 * role_skill("safety"))

func can_see_risk() -> bool:
	return role_skill("safety") > 0.0

func daily_salaries() -> float:
	var s := 0.0
	for p in staff:
		s += float(p["salary"]) / 365.0
	return s

func rp_per_day() -> float:
	var r := 0.12 * role_skill("research")
	if office_upgrades.has("coffee"):
		r *= 1.1
	for m in models:
		if m["status"] == "open":
			r += float(m["rating"]) * 0.02
	return r


# ---------------------------------------------------------------- Forschung

func tech(id: String) -> Dictionary:
	for t in D.TECHS:
		if t["id"] == id:
			return t
	return {}

func tech_state(id: String) -> String:
	if techs.has(id):
		return "done"
	var t := tech(id)
	if year() < int(t["year"]):
		return "future"
	if t["req"] != "" and not techs.has(t["req"]):
		return "locked"
	return "available"

func research(id: String) -> String:
	if tech_state(id) != "available":
		return "Noch nicht verfügbar."
	var t := tech(id)
	if rp < float(t["rp"]):
		return "Zu wenig Forschungspunkte."
	rp -= float(t["rp"])
	techs[id] = true
	fx.append("research")
	_news("[color=#7fd]Forschung:[/color] %s freigeschaltet." % t["name"])
	revision += 1
	return ""

func arch_list() -> Array:
	var a := []
	for t in D.TECHS:
		if t["kind"] == "arch" and techs.has(t["id"]):
			a.append(t)
	return a

func risk_tech_mult() -> float:
	var m := 1.0
	for t in D.TECHS:
		if t["kind"] == "safety" and techs.has(t["id"]):
			m *= float(t["risk"])
	return m

func data_available(id: String) -> bool:
	var s: Dictionary = D.DATA[id]
	if id == "gray":
		return data_unlocked.has("gray")
	if year() < int(s["year"]):
		return false
	if s.has("needs_rating") and best_rating < float(s["needs_rating"]):
		return false
	return true


# ---------------------------------------------------------------- Modelle

func default_design() -> Dictionary:
	var archs := arch_list()
	return {"name": "Modell-%d" % next_model_id, "arch": archs[archs.size() - 1]["id"], "size_index": 2,
		"data": ["web"], "focus": {"help": 3, "code": 2, "creative": 3, "safety": 2}, "eval_days": 0}

func focus_spent(focus: Dictionary) -> int:
	var s := 0
	for k in D.FOCUS_KEYS:
		s += int(focus[k])
	return s

## Verteilt die Punkte so, dass die Summe genau `total` ist (Verhältnisse bleiben erhalten).
func scale_focus(focus: Dictionary, total: int = D.FOCUS_BUDGET) -> Dictionary:
	var sum := focus_spent(focus)
	var out := {}
	if sum <= 0:
		for k in D.FOCUS_KEYS:
			out[k] = 0
		out["help"] = total
		return out
	var rest := total
	var fracs := []
	for k in D.FOCUS_KEYS:
		var raw := float(focus[k]) * total / sum
		out[k] = floori(raw)
		rest -= int(out[k])
		fracs.append([raw - floorf(raw), k])
	fracs.sort_custom(func(a, b): return a[0] > b[0])
	for i in range(rest):
		out[fracs[i % fracs.size()][1]] = int(out[fracs[i % fracs.size()][1]]) + 1
	return out

## Mehr als das Budget wird anteilig gekürzt, weniger bleibt (kostet Qualität).
func clamp_focus(focus: Dictionary) -> Dictionary:
	if focus_spent(focus) > D.FOCUS_BUDGET:
		return scale_focus(focus)
	var out := {}
	for k in D.FOCUS_KEYS:
		out[k] = maxi(0, int(focus[k]))
	return out

func focus_fit(focus: Dictionary, ideal: Dictionary = {}) -> float:
	if ideal.is_empty():
		ideal = era()["ideal"]
	var ps := 0.0
	var is_sum := 0.0
	for k in D.FOCUS_KEYS:
		ps += float(focus[k])
		is_sum += float(ideal[k])
	if ps <= 0.0:
		return 0.3
	var l1 := 0.0
	for k in D.FOCUS_KEYS:
		l1 += absf(float(focus[k]) / ps - float(ideal[k]) / is_sum)
	return clampf(1.0 - 0.4 * l1, 0.3, 1.0)

func _model_risk(q: float, focus: Dictionary, data_risk: float, eval_days: int) -> float:
	var ps := 0.0
	for k in D.FOCUS_KEYS:
		ps += float(focus[k])
	var safety_share := float(focus["safety"]) / ps if ps > 0.0 else 0.0
	var r := (q / 60.0) * clampf(1.3 - safety_share * 2.5, 0.2, 1.3) * data_risk
	r *= 1.0 - clampf(eval_days / 90.0, 0.0, 0.66)
	r *= 1.0 - safety_reduction()
	r *= risk_tech_mult()
	return r

func evaluate_design(d: Dictionary) -> Dictionary:
	var t := tech(d["arch"])
	var params: float = D.SIZES[int(d["size_index"])]
	var focus: Dictionary = clamp_focus(d["focus"])
	var data_q := 1.0
	var data_risk := 0.0
	var data_cost := 0.0
	var legal := false
	var size_factor := 1.0 + log(params * 1000.0) / log(10.0) / 4.0
	for id in d["data"]:
		var s: Dictionary = D.DATA[id]
		data_q += float(s["quality"])
		if id == "code":
			data_q += 0.025 * float(focus["code"])
		data_risk += float(s["risk"])
		data_cost += float(s["cost"]) * inflation() * sqrt(market()) * size_factor
		if s.get("legal", false):
			legal = true
	data_risk /= maxf(1.0, d["data"].size())
	var q: float = float(t["quality"]) * 10.0 * log(params * 1000.0) / log(10.0) * data_q * team_quality()
	q *= 0.7 + 0.3 * float(focus_spent(focus)) / D.FOCUS_BUDGET   # ungenutzte Fokus-Punkte kosten Qualität
	var gpu_days: float = 300.0 * pow(params, 1.3) / float(t["eff"])
	var per_day := compute_power() * engineer_mult()
	var train_days := INF if per_day <= 0.0 else gpu_days / per_day
	return {"q": q, "rel": q / expected_quality(), "gpu_days": gpu_days, "train_days": train_days,
		"data_cost": data_cost, "risk": _model_risk(q, focus, data_risk, int(d["eval_days"])), "legal": legal}

func start_training(d: Dictionary) -> String:
	if not training.is_empty():
		return "Es läuft schon ein Training."
	if d["data"].is_empty():
		return "Wähle mindestens eine Datenquelle."
	if not techs.has(d["arch"]):
		return "Architektur nicht erforscht."
	d["focus"] = clamp_focus(d["focus"])
	if compute_power() <= 0.0:
		return "Du brauchst GPUs."
	var ev := evaluate_design(d)
	if ev["train_days"] > 365.0:
		return "Das Training würde über ein Jahr dauern. Mehr GPUs oder ein kleineres Modell."
	if money < ev["data_cost"]:
		return "Nicht genug Geld für die Daten."
	money -= ev["data_cost"]
	training = {"design": d.duplicate(true), "q": ev["q"], "risk": ev["risk"], "legal": ev["legal"],
		"gpu_days": ev["gpu_days"], "progress": 0.0, "phase": "train", "eval_left": int(d["eval_days"]), "start_day": day}
	if "gray" in d["data"]:
		flags["used_gray"] = true
	_news("Training von [b]%s[/b] gestartet." % d["name"])
	revision += 1
	return ""

func training_days_left() -> float:
	if training.is_empty():
		return 0.0
	var per_day := compute_power() * engineer_mult()
	var left: float = float(training["eval_left"])
	if training["phase"] == "train":
		left += INF if per_day <= 0.0 else (float(training["gpu_days"]) - float(training["progress"])) / per_day
	return left

func _step_training() -> void:
	if training.is_empty():
		return
	if training["phase"] == "train":
		training["progress"] = float(training["progress"]) + compute_power() * engineer_mult()
		if float(training["progress"]) >= float(training["gpu_days"]):
			training["phase"] = "eval"
			if int(training["eval_left"]) <= 0:
				_finish_training()
	else:
		training["eval_left"] = int(training["eval_left"]) - 1
		if int(training["eval_left"]) <= 0:
			_finish_training()

func _finish_training() -> void:
	var d: Dictionary = training["design"]
	var m := {"id": next_model_id, "name": d["name"], "arch": d["arch"], "size_index": int(d["size_index"]),
		"data": d["data"], "focus": d["focus"], "eval_days": int(d["eval_days"]), "q": training["q"],
		"risk": training["risk"], "legal": training["legal"], "status": "ready", "rating": 0.0, "fit": 0.0,
		"release_day": -1, "gamed": false}
	next_model_id += 1
	models.append(m)
	training = {}
	flags["trained_any"] = true
	revision += 1
	_push_event("model_ready", "%s ist fertig!" % m["name"],
		"Das Training ist abgeschlossen. Wie willst du das Modell veröffentlichen?",
		[["Paper veröffentlichen", "Kein Umsatz, aber Reputation und ein Forschungszuschuss."],
		["Als API verkaufen", "Täglicher Umsatz, solange das Modell konkurrenzfähig ist. Das Risiko zählt."],
		["Open Weights", "Viel Reputation und Forschungspunkte aus der Community. Kein Umsatz, doppeltes Risiko, nicht rückholbar."],
		["Später entscheiden", "Das Modell wartet unter dem Warenkorb-Symbol."]], {"model": m["id"]})

func get_model(id: int) -> Dictionary:
	for m in models:
		if int(m["id"]) == id:
			return m
	return {}

func release_model(id: int, kind: String) -> Dictionary:
	var m := get_model(id)
	if m.is_empty() or m["status"] != "ready":
		return {}
	var fit := focus_fit(m["focus"])
	var rel: float = float(m["q"]) / expected_quality()
	var rating := clampf(rel * fit * 6.0, 0.5, 10.0)
	if flags.get("bench_gaming_pending", false):
		rating = minf(10.0, rating + 1.5)
		m["gamed"] = true
		flags.erase("bench_gaming_pending")
	rating = snappedf(rating, 0.1)
	m["rating"] = rating
	m["fit"] = fit
	m["status"] = kind
	m["release_day"] = day
	best_rating = maxf(best_rating, rating)
	best_q = maxf(best_q, float(m["q"]))
	var rep_gain := 0.0
	var money_gain := 0.0
	match kind:
		"paper":
			rep_gain = maxf(0.0, rating - 3.0) * 1.6
			money_gain = rating * rating * 500.0 * market()
		"api":
			rep_gain = maxf(0.0, rating - 4.0) * 1.0
		"open":
			rep_gain = maxf(0.0, rating - 3.0) * 2.0
	if rating < 3.0:
		rep_gain -= 2.0
	if rep_gain > 0.0:
		rep_gain *= pow(1.0 - reputation / 100.0, 1.5)
	reputation = clampf(reputation + rep_gain, 0.0, 100.0)
	money += money_gain
	var fine := 0.0
	if flags.get("regulation", false) and kind != "paper" and int(m["eval_days"]) < 14:
		fine = 20000.0 * market()
		money -= fine
	var report := {"name": m["name"], "kind": kind, "rating": rating, "rep_gain": rep_gain, "money_gain": money_gain,
		"quotes": _quotes(rating), "feedback": _feedback(m["focus"]), "rival_q": rival["best_q"], "q": m["q"], "fine": fine}
	var kind_name: String = {"paper": "als Paper", "api": "als API", "open": "mit offenen Gewichten"}[kind]
	_news("[b]%s[/b] %s veröffentlicht – Bewertung [b]%.1f[/b]/10." % [m["name"], kind_name, rating])
	revision += 1
	if kind != "paper" and m["arch"] == "agents" and float(m["q"]) >= D.AGI_Q:
		_agi_ending(m)
	return report

func withdraw_model(id: int) -> void:
	var m := get_model(id)
	if not m.is_empty() and m["status"] == "api":
		m["status"] = "withdrawn"
		_news("%s wurde vom Markt genommen." % m["name"])
		revision += 1

func model_revenue(m: Dictionary) -> float:
	var rel: float = float(m["q"]) / expected_quality()
	return 1000.0 * pow(minf(rel, 2.0), 2.0) * float(m["fit"]) * (0.3 + reputation / 60.0) * sales_mult() * market()

func api_revenue() -> float:
	var list := []
	for m in models:
		if m["status"] == "api":
			list.append(model_revenue(m))
	list.sort()
	list.reverse()
	var total := 0.0
	for i in range(list.size()):
		total += list[i] * (D.STACK_WEIGHTS[i] if i < D.STACK_WEIGHTS.size() else 0.02)
	return total

func hidden_risk() -> float:
	var r := 0.0
	for m in models:
		if m["status"] == "api":
			r += float(m["risk"])
		elif m["status"] == "open":
			r += float(m["risk"]) * 2.0
	return r

func _quotes(rating: float) -> Array:
	var band := clampi(floori(rating / 2.0), 0, 4)
	var out := []
	var outlets: Array = D.OUTLETS.duplicate()
	for i in range(2):
		var o: String = outlets.pop_at(rng.randi() % outlets.size())
		var qs: Array = D.QUOTES[band]
		out.append("%s: „%s“" % [o, qs[rng.randi() % qs.size()]])
	return out

func _feedback(focus: Dictionary) -> Array:
	var ideal: Dictionary = era()["ideal"]
	var ps := 0.0
	var is_sum := 0.0
	for k in D.FOCUS_KEYS:
		ps += float(focus[k])
		is_sum += float(ideal[k])
	var lo_k := ""
	var lo := 0.08
	var hi_k := ""
	var hi := 0.08
	for k in D.FOCUS_KEYS:
		var diff := (float(focus[k]) / maxf(ps, 0.001)) - float(ideal[k]) / is_sum
		if -diff > lo:
			lo = -diff
			lo_k = k
		if diff > hi:
			hi = diff
			hi_k = k
	var out := []
	if lo_k != "":
		out.append("Nutzer wünschen sich mehr %s." % D.FOCUS_NAMES[lo_k])
	if hi_k != "":
		out.append("%s war weniger gefragt, als du dachtest." % D.FOCUS_NAMES[hi_k])
	if out.is_empty():
		out.append("Der Fokus traf den Zeitgeist genau.")
	return out


# ---------------------------------------------------------------- Aktionen

func hire(index: int) -> String:
	if staff.size() >= int(office_data()["staff"]):
		return "Kein Platz mehr. Zieh in ein größeres Büro."
	var p: Dictionary = candidates[index]
	var bonus := float(p["salary"]) * 0.1
	if money < bonus:
		return "Nicht genug Geld für den Einstellungsbonus."
	money -= bonus
	staff.append(p)
	candidates.remove_at(index)
	fx.append("hire")
	_news("%s (%s) ist jetzt im Team." % [p["name"], D.ROLES[p["role"]]["name"]])
	revision += 1
	return ""

func fire(index: int) -> void:
	if index <= 0 or index >= staff.size():
		return  # Mitgründung bleibt
	var p: Dictionary = staff[index]
	money -= float(p["salary"]) / 12.0
	staff.remove_at(index)
	_news("%s hat das Team verlassen (Abfindung bezahlt)." % p["name"])
	revision += 1

func rent_gpus(n: int) -> String:
	n = mini(n, int(office_data()["gpus"]) - gpu_count())
	if n <= 0:
		return "Kein Platz für weitere GPUs. Größeres Büro nötig."
	var gen := gpu_gen_now()
	for g in gpus:
		if int(g["gen"]) == gen:
			g["count"] = int(g["count"]) + n
			revision += 1
			return ""
	gpus.append({"gen": gen, "count": n})
	revision += 1
	return ""

func return_gpus(n: int) -> void:
	gpus.sort_custom(func(a, b): return int(a["gen"]) < int(b["gen"]))
	while n > 0 and gpus.size() > 0:
		var take := mini(n, int(gpus[0]["count"]))
		gpus[0]["count"] = int(gpus[0]["count"]) - take
		n -= take
		if int(gpus[0]["count"]) <= 0:
			gpus.remove_at(0)
	revision += 1

func upgrade_office() -> String:
	if office >= D.OFFICES.size() - 1:
		return "Größer geht es nicht."
	return buy_office(office + 1)

## Umzug in ein beliebiges größeres Büro (auch Stufen überspringen)
func buy_office(index: int) -> String:
	if index <= office or index >= D.OFFICES.size():
		return "Nur größere Büros möglich."
	var o: Dictionary = D.OFFICES[index]
	if money < float(o["cost"]):
		return "Nicht genug Geld."
	money -= float(o["cost"])
	office = index
	_news("Umzug: Willkommen im [b]%s[/b]!" % o["name"])
	revision += 1
	return ""

func buy_office_upgrade(id: String) -> String:
	var u := _find(D.OFFICE_UPGRADES, id)
	if u.is_empty() or office_upgrades.has(id):
		return "Schon vorhanden."
	if office < int(u["min_office"]):
		return "Braucht mindestens: %s" % D.OFFICES[int(u["min_office"])]["name"]
	if money < float(u["cost"]):
		return "Nicht genug Geld."
	money -= float(u["cost"])
	office_upgrades[id] = true
	_news("Neu im Büro: [b]%s[/b]." % u["name"])
	revision += 1
	return ""


# ---------------------------------------------------------------- Rechenzentren & Chips

func _find(list: Array, id: String) -> Dictionary:
	for x in list:
		if x["id"] == id:
			return x
	return {}

func dc_type(dc: Dictionary) -> Dictionary:
	return _find(D.DATACENTERS, dc["type"])

func dc_loc(dc: Dictionary) -> Dictionary:
	return _find(D.LOCATIONS, dc["loc"])

func dc_slots(dc: Dictionary) -> int:
	var s := float(dc_type(dc)["slots"])
	if dc["upgrades"].has("expand"):
		s *= 1.5
	return int(s)

func dc_used(dc: Dictionary) -> int:
	var n := 0
	for h in dc["hw"]:
		n += int(h["count"])
	return n

func dc_power_mult(dc: Dictionary) -> float:
	var m := float(dc_loc(dc)["power"])
	for u in D.DC_UPGRADES:
		if dc["upgrades"].has(u["id"]) and u.has("power"):
			m *= float(u["power"])
	return m

func dc_perf(dc: Dictionary) -> float:
	return 1.15 if dc["upgrades"].has("network") else 1.0

func dc_power(dc: Dictionary) -> float:
	var p := 0.0
	for h in dc["hw"]:
		p += float(h["power"]) * int(h["count"])
	return p * dc_perf(dc)

func dc_total_power() -> float:
	var p := 0.0
	for dc in datacenters:
		p += dc_power(dc)
	return p

func dc_daily_cost(dc: Dictionary) -> float:
	var c := float(dc_type(dc)["base"]) * inflation()
	for h in dc["hw"]:
		c += float(h["upkeep"]) * int(h["count"])
	return c * dc_power_mult(dc)

func daily_dc_cost() -> float:
	var c := 0.0
	for dc in datacenters:
		c += dc_daily_cost(dc)
	return c

func dc_build_cost(type_id: String, loc_id: String) -> float:
	return float(_find(D.DATACENTERS, type_id)["cost"]) * float(_find(D.LOCATIONS, loc_id)["build"]) * inflation()

func build_datacenter(type_id: String, loc_id: String) -> String:
	var t := _find(D.DATACENTERS, type_id)
	if t.is_empty() or _find(D.LOCATIONS, loc_id).is_empty():
		return "Unbekannter Typ oder Standort."
	if year() < int(t["year"]):
		return "Verfügbar ab %d." % t["year"]
	var cost := dc_build_cost(type_id, loc_id)
	if money < cost:
		return "Nicht genug Geld."
	money -= cost
	datacenters.append({"type": type_id, "loc": loc_id, "upgrades": {}, "hw": []})
	fx.append("build")
	_news("[color=#7fd]Bau:[/color] %s in %s ist in Betrieb." % [t["name"], _find(D.LOCATIONS, loc_id)["name"]])
	revision += 1
	return ""

func dc_upgrade_cost(dc: Dictionary, up_id: String) -> float:
	return float(dc_type(dc)["cost"]) * float(_find(D.DC_UPGRADES, up_id)["cost"]) * inflation()

func buy_dc_upgrade(dc_index: int, up_id: String) -> String:
	var dc: Dictionary = datacenters[dc_index]
	var u := _find(D.DC_UPGRADES, up_id)
	if u.is_empty() or dc["upgrades"].has(up_id):
		return "Schon vorhanden."
	var cost := dc_upgrade_cost(dc, up_id)
	if money < cost:
		return "Nicht genug Geld."
	money -= cost
	dc["upgrades"][up_id] = true
	if u.has("rep"):
		reputation = minf(100.0, reputation + float(u["rep"]))
	_news("Rechenzentrum %s: %s eingebaut." % [dc_loc(dc)["name"], u["name"]])
	revision += 1
	return ""

## Kaufpreis einer Einheit: "market" = aktuelle GPU-Generation, "custom" = eigener Chip
func hw_unit(kind: String) -> Dictionary:
	if kind == "custom":
		if custom_chip.is_empty():
			return {}
		var price := float(custom_chip["base"]) * D.BUY_DAYS * D.CHIP_PRICE * (0.5 if has_fab else 1.0)
		if not has_fab:
			price *= gpu_price_mult
		return {"name": custom_chip["name"], "power": float(custom_chip["power"]), "price": price, "upkeep": float(custom_chip["base"]) * D.UPKEEP_SHARE}
	var gen := gpu_gen_now()
	return {"name": "GPU Gen %d" % gen, "power": gpu_power(gen), "price": gpu_cost(gen) * D.BUY_DAYS, "upkeep": gpu_cost(gen) / gpu_price_mult * D.UPKEEP_SHARE}

func buy_hardware(dc_index: int, kind: String, n: int) -> String:
	var dc: Dictionary = datacenters[dc_index]
	n = mini(n, dc_slots(dc) - dc_used(dc))
	if n <= 0:
		return "Rechenzentrum ist voll."
	var u := hw_unit(kind)
	if u.is_empty():
		return "Noch kein eigener Chip."
	n = mini(n, int(money / float(u["price"])))
	if n <= 0:
		return "Nicht genug Geld."
	money -= float(u["price"]) * n
	for h in dc["hw"]:
		if h["name"] == u["name"]:
			h["count"] = int(h["count"]) + n
			revision += 1
			return ""
	dc["hw"].append({"name": u["name"], "power": u["power"], "count": n, "upkeep": u["upkeep"]})
	revision += 1
	return ""

## Schwächste Hardware zuerst verschrotten (kein Erlös, spart Strom und Platz)
func scrap_hardware(dc_index: int, n: int) -> void:
	var dc: Dictionary = datacenters[dc_index]
	dc["hw"].sort_custom(func(a, b): return float(a["power"]) < float(b["power"]))
	while n > 0 and dc["hw"].size() > 0:
		var take := mini(n, int(dc["hw"][0]["count"]))
		dc["hw"][0]["count"] = int(dc["hw"][0]["count"]) - take
		n -= take
		if int(dc["hw"][0]["count"]) <= 0:
			dc["hw"].remove_at(0)
	revision += 1

func chip_project_cost() -> float:
	return D.CHIP_BASE_COST * pow(1.6, chip_version) * inflation()

func chip_project_days() -> float:
	return D.CHIP_DAYS / engineer_mult()

func start_chip_project() -> String:
	if not techs.has("chipdesign"):
		return "Erforsche zuerst 'Eigenes Chip-Design'."
	if not chip_project.is_empty():
		return "Es läuft schon ein Chip-Projekt."
	var cost := chip_project_cost()
	if money < cost:
		return "Nicht genug Geld."
	money -= cost
	chip_project = {"progress": 0.0, "version": chip_version + 1}
	_news("Chip-Projekt [b]NG-%d[/b] gestartet." % (chip_version + 1))
	revision += 1
	return ""

func _step_chip() -> void:
	if chip_project.is_empty():
		return
	chip_project["progress"] = float(chip_project["progress"]) + 1.0 / chip_project_days()
	if float(chip_project["progress"]) >= 1.0:
		chip_version = int(chip_project["version"])
		var gen := gpu_gen_now()
		custom_chip = {"name": "NG-%d" % chip_version, "power": gpu_power(gen) * D.CHIP_POWER, "base": gpu_cost(gen) / gpu_price_mult}
		chip_project = {}
		revision += 1
		_info("Eigener Chip fertig: %s" % custom_chip["name"],
			"Dein Team hat einen eigenen KI-Beschleuniger entwickelt: %.0f Leistung pro Chip (Markt-GPU: %.0f) zu %.0f %% des Marktpreises.\n\nKaufen kannst du ihn für deine Rechenzentren unter dem Haus-Symbol (Ausbau)." % [custom_chip["power"], gpu_power(gen), D.CHIP_PRICE * 100.0 * (0.5 if has_fab else 1.0)])

func build_fab() -> String:
	if not techs.has("fab"):
		return "Erforsche zuerst 'Chip-Fertigung'."
	if has_fab:
		return "Du hast schon eine Fabrik."
	var cost := D.FAB_COST * inflation()
	if money < cost:
		return "Nicht genug Geld."
	money -= cost
	has_fab = true
	reputation = minf(100.0, reputation + 3.0)
	_news("[color=#7fd]Eigene Chipfabrik eröffnet![/color] Chips halb so teuer, keine Lieferengpässe mehr.")
	revision += 1
	return ""


# ---------------------------------------------------------------- Events

func _push_event(id: String, title: String, text: String, choices: Array, data: Dictionary = {}) -> void:
	var cs := []
	for c in choices:
		cs.append({"label": c[0], "tip": c[1] if c.size() > 1 else ""})
	event_queue.append({"id": id, "title": title, "text": text, "choices": cs, "data": data})

func _info(title: String, text: String) -> void:
	_push_event("info", title, text, [["OK"]])

func resolve_event(choice: int) -> void:
	if event_queue.is_empty():
		return
	var ev: Dictionary = event_queue.pop_front()
	var data: Dictionary = ev["data"]
	match ev["id"]:
		"model_ready":
			var kinds := ["paper", "api", "open"]
			if choice < 3:
				var rep := release_model(int(data["model"]), kinds[choice])
				if not rep.is_empty():
					push_report(rep)
		"investor":
			var inv: Dictionary = D.INVESTORS[investor_stage]
			if choice == 0:
				money += float(inv["money"])
				equity -= equity * float(inv["equity"]) / 100.0
				investor_stage += 1
				investor_next_day = day + 90
				_news("[color=#fd7]%s:[/color] +%s für %d %% der Anteile." % [inv["name"], fmt_money(inv["money"]), int(inv["equity"])])
			else:
				investor_next_day = day + 120
		"rescue":
			if choice == 0:
				money += float(data["amount"])
				equity *= 0.8
		"gray_offer":
			if choice == 0:
				data_unlocked["gray"] = true
				_news("Du hast die grauen Daten gekauft. Niemand muss davon erfahren …")
			else:
				reputation = minf(100.0, reputation + 1.0)
		"journalist":
			if choice == 0:
				flags["denied"] = true
			else:
				reputation = maxf(0.0, reputation - 8.0)
				flags["confessed"] = true
				_news("Du legst offen, welche Daten du genutzt hast. Die Presse ist hart, aber fair.")
		"lawsuit":
			var cost: float = data["cost"]
			if choice == 0:
				money -= cost
				_news("Vergleich: %s gezahlt." % fmt_money(cost))
			elif rng.randf() < (0.25 if flags.get("denied", false) else 0.5):
				reputation = minf(100.0, reputation + 3.0)
				_info("Prozess gewonnen", "Das Gericht sieht keine ausreichenden Beweise. Glück gehabt.")
			else:
				money -= cost * 3.0
				reputation = maxf(0.0, reputation - 10.0)
				_info("Prozess verloren", "Das Gericht verurteilt dein Labor zu %s Schadensersatz." % fmt_money(cost * 3.0))
		"poach":
			var idx: int = data["staff"]
			if idx < staff.size():
				if choice == 0:
					staff[idx]["salary"] = round(float(staff[idx]["salary"]) * 1.4)
				else:
					_news("%s wechselt zu Helix Dynamics." % staff[idx]["name"])
					staff.remove_at(idx)
		"bench_gaming":
			if choice == 0:
				flags["bench_gaming_pending"] = true
			else:
				reputation = minf(100.0, reputation + 2.0)
		"hearing":
			if choice == 0:
				reputation = minf(100.0, reputation + 6.0)
				flags["regulation"] = true
				_news("Neues Gesetz: API-Modelle brauchen mindestens 14 Tage Sicherheits-Evaluierung.")
			else:
				money -= 300000.0 * inflation()
				flags["lobby"] = true
		"jailbreak":
			var m := get_model(int(data["model"]))
			if not m.is_empty():
				if choice == 0:
					withdraw_model(int(m["id"]))
				elif choice == 1:
					money -= float(data["cost"])
					m["risk"] = float(m["risk"]) * 0.6
				else:
					reputation = maxf(0.0, reputation - 5.0)
					m["risk"] = float(m["risk"]) * 1.2
	revision += 1

func push_report(r: Dictionary) -> void:
	var t := "[font_size=28][b]%.1f / 10[/b][/font_size]\n\n" % r["rating"]
	for q in r["quotes"]:
		t += "[i]%s[/i]\n" % q
	t += "\n[b]Feedback:[/b]\n"
	for f in r["feedback"]:
		t += "• %s\n" % f
	t += "\nQualität %.0f · Markt erwartet %.0f · Helix-Bestwert %.0f\n" % [r["q"], expected_quality(), r["rival_q"]]
	if r["rep_gain"] != 0.0:
		t += "Reputation %+.1f\n" % r["rep_gain"]
	if r["money_gain"] > 0.0:
		t += "Forschungszuschuss: +%s\n" % fmt_money(r["money_gain"])
	if r["fine"] > 0.0:
		t += "[color=#f77]Strafe wegen fehlender Evaluierung: −%s[/color]\n" % fmt_money(r["fine"])
	var ev := {"id": "info", "title": "Kritiken: %s" % r["name"], "text": t, "choices": [{"label": "OK", "tip": ""}], "data": {}}
	event_queue.insert(0, ev)

func _cooldown_ok(id: String, days: int) -> bool:
	if day - int(cooldowns.get(id, -100000)) < days:
		return false
	return true

func _step_events() -> void:
	if not event_queue.is_empty():
		return
	# Investoren
	if investor_stage < D.INVESTORS.size() and day >= investor_next_day:
		var inv: Dictionary = D.INVESTORS[investor_stage]
		if reputation >= float(inv["rep"]) and year() >= int(inv["year"]):
			_push_event("investor", inv["name"],
				"Investoren bieten dir [b]%s[/b] für [b]%d %%[/b] deiner Anteile.\nDu hältst aktuell %.1f %%." % [fmt_money(inv["money"]), int(inv["equity"]), equity],
				[["Annehmen", "Sofort Geld. Deine Anteile sinken."], ["Ablehnen", "In 4 Monaten fragen sie wieder."]])
			return
	# Markt-Ära
	var ei := D.ERAS.find(era())
	if ei != era_index:
		era_index = ei
		_info("Neue Ära: %s" % era()["name"], "%s\n\nWas Nutzer wollen, hat sich verschoben. Achte auf das Feedback der Kritiken." % era()["hint"])
		return
	if gpu_shortage_days > 0:
		gpu_shortage_days -= 1
		if gpu_shortage_days == 0:
			gpu_price_mult = 1.0
			_news("Die GPU-Knappheit ist vorbei. Preise normal.")
	var roll := rng.randf()
	if not flags.has("ev_gray") and day > 240 and roll < 0.01:
		flags["ev_gray"] = true
		_push_event("gray_offer", "Ein zwielichtiges Angebot",
			"Ein anonymer Händler bietet dir 40 TB „Bücher und Foren-Daten“. Woher sie kommen, will er nicht sagen.",
			[["Kaufen", "Schaltet 'Graue Daten' frei: +30 % Datenqualität, aber rechtlich und ethisch heikel."], ["Ablehnen", "+1 Reputation"]])
	elif flags.get("used_gray", false) and not flags.has("ev_journalist") and _released_with_gray() > 0 and roll < 0.006:
		flags["ev_journalist"] = true
		_push_event("journalist", "Eine Journalistin fragt nach",
			"„Stimmt es, dass Ihr Modell mit raubkopierten Büchern trainiert wurde?“",
			[["Abstreiten", "Keine Folgen – vorerst. Spätere Prozesse werden schwerer zu gewinnen."], ["Offenlegen", "−8 Reputation sofort, dafür ehrlich."]])
	elif _released_with_gray() > 0 and _cooldown_ok("lawsuit", 300) and roll < 0.0015 * _released_with_gray():
		cooldowns["lawsuit"] = day
		var cost := 40000.0 * market()
		_push_event("lawsuit", "Klage wegen Urheberrecht",
			"Ein Verlagsverband verklagt dein Labor. Vergleichskosten: %s." % fmt_money(cost),
			[["Vergleich zahlen", "Sicher, aber teuer."], ["Vor Gericht ziehen", "Gewinnen: +3 Reputation. Verlieren: dreifache Kosten, −10 Reputation."]], {"cost": cost})
	elif _cooldown_ok("poach", 300) and roll < (0.001 if office_upgrades.has("gym") else 0.002) and _best_researcher() >= 0:
		cooldowns["poach"] = day
		var i := _best_researcher()
		_push_event("poach", "Abwerbeversuch!",
			"Helix Dynamics will %s abwerben und bietet deutlich mehr Gehalt." % staff[i]["name"],
			[["Gegenangebot (+40 % Gehalt)", "Die Person bleibt."], ["Gehen lassen", "Spart Geld, kostet Forschungskraft."]], {"staff": i})
	elif best_rating > 0.0 and not flags.has("ev_bench") and roll < 0.003:
		flags["ev_bench"] = true
		_push_event("bench_gaming", "Ein kleiner Trick",
			"Dein Team hat die Testfragen der wichtigsten Benchmarks gefunden. Man könnte sie … mittrainieren.",
			[["Machen", "Nächstes Modell +1,5 Bewertung. Fliegt es auf, kostet es viel Reputation."], ["Ablehnen", "+2 Reputation, das Team ist stolz."]])
	elif reputation >= 45.0 and not flags.has("ev_hearing") and roll < 0.01:
		flags["ev_hearing"] = true
		_push_event("hearing", "Anhörung im Parlament",
			"Abgeordnete wollen wissen, wie gefährlich deine Modelle sind.",
			[["Offen aussagen", "+6 Reputation. Ein Gesetz verlangt danach 14 Tage Evaluierung für API-Modelle."], ["Lobbyisten bezahlen", "Kostet Geld, keine Regulierung."]])
	elif _cooldown_ok("jailbreak", 250) and roll < 0.003 and _unsafe_api_model() >= 0:
		cooldowns["jailbreak"] = day
		var m := get_model(_unsafe_api_model())
		var cost := 15000.0 * market()
		_push_event("jailbreak", "Jailbreak geht viral",
			"Nutzer bringen %s dazu, gefährliche Anleitungen zu schreiben. Screenshots überall." % m["name"],
			[["Modell zurückziehen", "Kein Umsatz mehr aus diesem Modell, Risiko weg."], ["Notfall-Patch (%s)" % fmt_money(cost), "Risiko des Modells −40 %."], ["Ignorieren", "−5 Reputation, Risiko steigt."]],
			{"model": m["id"], "cost": cost})
	elif year() >= 2020 and _cooldown_ok("gpu", 500) and roll < 0.0015:
		cooldowns["gpu"] = day
		gpu_price_mult = 1.8
		gpu_shortage_days = 90
		_info("GPU-Knappheit", "Die Nachfrage nach Chips explodiert. Für 90 Tage kosten Markt-GPUs 80 % mehr (Miete und Kauf). Eine eigene Chipfabrik macht dich unabhängig.")

func _last_release_day() -> int:
	var d := 0
	for m in models:
		d = maxi(d, int(m["release_day"]))
	return d

func _released_with_gray() -> int:
	var n := 0
	for m in models:
		if m["legal"] and m["status"] in ["api", "open", "paper"]:
			n += 1
	return n

func _best_researcher() -> int:
	var best := -1
	for i in range(1, staff.size()):
		if staff[i]["role"] == "research" and int(staff[i]["skill"]) >= 5:
			if best < 0 or int(staff[i]["skill"]) > int(staff[best]["skill"]):
				best = i
	return best

func _unsafe_api_model() -> int:
	for m in models:
		if m["status"] == "api":
			var f: Dictionary = m["focus"]
			var ps := float(f["help"]) + float(f["code"]) + float(f["creative"]) + float(f["safety"])
			if ps > 0.0 and float(f["safety"]) / ps < 0.15:
				return int(m["id"])
	return -1


# ---------------------------------------------------------------- Tageslauf

func step_day() -> void:
	if not ending.is_empty():
		return
	day += 1
	if fx.size() > 40:
		fx.clear()
	last_cost = daily_salaries() + daily_gpu_cost() + daily_dc_cost()
	last_income = api_revenue()
	money += last_income - last_cost
	total_revenue += last_income
	rp += rp_per_day()
	if day - _last_release_day() > 180:
		reputation = maxf(0.0, reputation - 0.02)
	_step_training()
	_step_chip()
	_step_risk()
	_step_rival()
	_step_events()
	_step_goals()
	if day % 30 == 0:
		_refresh_candidates()
	if day % 180 == 0:
		_grow_staff()
	_check_endings()

func _step_risk() -> void:
	var hr := hidden_risk()
	if hr > 0.0 and rng.randf() < hr * 0.0006:
		var sev := rng.randf_range(0.5, 1.5) * hr
		var rep_loss := clampf(4.0 + sev * 3.0, 4.0, 30.0)
		var fine := 3000.0 * market() * sev
		reputation = maxf(0.0, reputation - rep_loss)
		money -= fine
		flags["incidents"] = int(flags.get("incidents", 0)) + 1
		fx.append("incident")
		if hr >= 8.0 and rng.randf() < 0.25:
			_set_ending("catastrophe", "Katastrophe",
				"Eines deiner Modelle hat außer Kontrolle gehandelt. Die Regierung schließt dein Labor. Zu viel Risiko, zu wenig Vorsicht.")
			return
		_info("Sicherheitsvorfall", "Ein Modell von dir hat echten Schaden angerichtet.\nReputation −%.0f, Strafe %s.\n\nTipp: Mehr Sicherheitsfokus, Evaluierungstage und ein Safety-Team senken das Risiko." % [rep_loss, fmt_money(fine)])
	for m in models:
		if m.get("gamed", false) and not m.get("gamed_exposed", false) and rng.randf() < 0.002:
			m["gamed_exposed"] = true
			reputation = maxf(0.0, reputation - 15.0)
			_info("Benchmark-Betrug aufgeflogen", "Forschende haben gezeigt, dass %s die Testfragen kannte. Reputation −15." % m["name"])

func _step_rival() -> void:
	if day < int(rival["next_day"]):
		return
	var q := expected_quality() * rng.randf_range(0.95, 1.3)
	rival["count"] = int(rival["count"]) + 1
	rival["best_q"] = maxf(float(rival["best_q"]), q)
	rival["next_day"] = day + rng.randi_range(150, 260)
	_news("[color=#f99]Helix Dynamics[/color] veröffentlicht Helix-%d (Qualität %.0f)." % [rival["count"], q])
	if year() >= 2027 and q >= D.AGI_Q:
		_set_ending("rival_agi", "Helix war schneller",
			"Helix Dynamics verkündet die erste AGI. Dein Labor wird über Nacht zur Fußnote der Geschichte.")

func _grow_staff() -> void:
	for p in staff:
		if int(p["skill"]) < 10 and rng.randf() < 0.35:
			p["skill"] = int(p["skill"]) + 1
			p["salary"] = round(float(p["salary"]) * (1.04 if office_upgrades.has("gym") else 1.08))
	revision += 1

func _make_person(role: String, skill: int, salary_factor: float = 1.0) -> Dictionary:
	var first: String = D.FIRST_NAMES[rng.randi() % D.FIRST_NAMES.size()]
	var last: String = D.LAST_NAMES[rng.randi() % D.LAST_NAMES.size()]
	var salary := (45000.0 + skill * 15000.0) * inflation() * salary_factor * rng.randf_range(0.9, 1.15)
	return {"name": first + " " + last, "role": role, "skill": skill, "salary": round(salary)}

func _refresh_candidates() -> void:
	candidates.clear()
	var max_skill := clampi(2 + int(reputation / 12.0) + (1 if office_upgrades.has("daycare") else 0), 2, 10)
	for i in range(4):
		var role: String = D.ROLE_ORDER[i] if i < 4 and rng.randf() < 0.5 else D.ROLE_ORDER[rng.randi() % 4]
		candidates.append(_make_person(role, rng.randi_range(maxi(1, max_skill - 3), max_skill)))
	revision += 1


# ---------------------------------------------------------------- Ziele & Enden

func goal_done(id: String) -> bool:
	match id:
		"train1": return flags.get("trained_any", false)
		"release1": return best_rating > 0.0
		"staff3": return staff.size() >= 3
		"transformer": return techs.has("transformer")
		"rating7": return best_rating >= 7.0
		"loft": return office >= 2
		"rev1m": return total_revenue >= 1000000.0
		"beat_rival": return best_q > float(rival["best_q"])
		"rlhf": return techs.has("rlhf")
		"campus": return office >= 4
		"datacenter": return not datacenters.is_empty()
		"chip": return chip_version > 0
		"rating9": return best_rating >= 9.0
		"reasoning": return techs.has("reasoning")
		"agents": return techs.has("agents")
		"agi": return ending.get("id", "") == "aligned"
	return false

func _step_goals() -> void:
	while goal_index < D.GOALS.size() and goal_done(D.GOALS[goal_index]["id"]):
		var reward := 5000.0 * market()
		money += reward
		reputation = minf(100.0, reputation + 1.0)
		_news("[color=#9f9]Ziel erreicht:[/color] %s (+%s, +1 Reputation)" % [D.GOALS[goal_index]["text"], fmt_money(reward)])
		goal_index += 1
		fx.append("goal")
		revision += 1

func _agi_ending(m: Dictionary) -> void:
	if float(m["risk"]) < 1.0 and hidden_risk() < 3.0:
		_set_ending("aligned", "Sichere AGI",
			"%s ist die erste allgemeine KI – und sie ist auf der Seite der Menschheit. Dein Labor schreibt Geschichte." % m["name"])
	else:
		_set_ending("misaligned", "Misaligned AGI",
			"%s ist klüger als alle Menschen zusammen. Leider verfolgt es eigene Ziele. Du hättest mehr in Sicherheit investieren sollen." % m["name"])

func _check_endings() -> void:
	if not ending.is_empty():
		return
	broke_days = broke_days + 1 if money < 0.0 else 0
	if broke_days == 1:
		_news("[color=#f77]Konto im Minus![/color] Nach 60 Tagen ist das Labor pleite.")
		if equity > 20.0 and _cooldown_ok("rescue", 365):
			cooldowns["rescue"] = day
			var amount := (last_cost - last_income) * 90.0 + absf(money)
			_push_event("rescue", "Notfinanzierung",
				"Ein Geier-Fonds bietet dir %s, um die Pleite abzuwenden – für 20 %% deiner Anteile." % fmt_money(amount),
				[["Annehmen", "Rettet das Labor vorerst. Du verlierst viel Kontrolle."], ["Ablehnen", "Du musst es selbst schaffen: Kosten senken, GPUs zurückgeben."]], {"amount": amount})
	if broke_days >= 60:
		_set_ending("bankrupt", "Pleite", "Das Geld ist weg. Die Server werden abgeschaltet, das Team geht.")
	elif year() >= D.END_YEAR:
		_set_ending("time", "Übernahme", "2032: Ein Tech-Konzern kauft dein Labor. Keine AGI – aber ein ordentlicher Abgang.")

func _set_ending(id: String, title: String, text: String) -> void:
	ending = {"id": id, "title": title, "text": text, "score": score(), "date": date_string()}
	_news("[b]Ende: %s[/b]" % title)
	revision += 1

func score() -> int:
	var s := reputation * 1000.0 + best_q * 200.0 + total_revenue / 10000.0 * equity / 100.0 + goal_index * 2000.0
	if ending.get("id", "") == "aligned":
		s *= 2.0
	return int(s)


# ---------------------------------------------------------------- Hilfen & Speichern

func _news(text: String) -> void:
	news.append("[color=#889]%s[/color]  %s" % [date_string(), text])
	news_total += 1
	if news.size() > 200:
		news.pop_front()

static func fmt_money(v: float) -> String:
	var a := absf(v)
	var s := "-" if v < 0.0 else ""
	if a >= 1e9:
		return "%s%.2f Mrd. $" % [s, a / 1e9]
	if a >= 1e6:
		return "%s%.2f Mio. $" % [s, a / 1e6]
	if a >= 1e4:
		return "%s%.0fk $" % [s, a / 1e3]
	return "%s%.0f $" % [s, a]

func to_dict() -> Dictionary:
	var d := {}
	for k in SAVE_KEYS:
		d[k] = get(k)
	d["rng_seed"] = str(rng.seed)
	d["rng_state"] = str(rng.state)
	return d

func from_dict(d: Dictionary) -> void:
	for k in SAVE_KEYS:
		if d.has(k):
			set(k, int(d[k]) if k in INT_KEYS else d[k])
	rng.seed = int(d.get("rng_seed", "1"))
	rng.state = int(d.get("rng_state", "1"))
	revision += 1
