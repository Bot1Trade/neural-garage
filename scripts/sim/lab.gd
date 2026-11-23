extends RefCounted
## Komplette Simulation des KI-Labors. Keine Node-Abhängigkeit → headless testbar.
## Die UI ruft step_day() auf und arbeitet event_queue ab (resolve_event).

const D = preload("res://scripts/sim/data.gd")

const SAVE_KEYS := ["day", "money", "total_revenue", "reputation", "equity", "office", "staff", "candidates",
	"gpus", "techs", "rp", "models", "training", "data_unlocked", "flags", "cooldowns", "rival", "goal_index",
	"investor_stage", "investor_next_day", "broke_days", "best_rating", "best_q", "gpu_price_mult",
	"gpu_shortage_days", "ending", "news", "news_total", "ledger_days", "ledger_today", "plots", "fab_plot", "office_hw", "companies", "last_feedback", "ledger_year", "ledger_last_year", "money_hist", "office_upgrades", "datacenters", "chip_version", "chip_project", "custom_chip", "has_fab", "event_queue", "next_model_id", "era_index"]
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
var plots: Dictionary = {}            # Grundstück-ID -> "" (leer) | "dc" | "fab"
var fab_plot: String = ""
var office_hw: Array = []              # gekaufte GPUs im Büro
var companies: Dictionary = {}         # Firmen-ID -> {value, stake}
var last_feedback: Array = []         # letztes Kritik-Feedback (für den Berater)
var ledger_days: Array = []          # letzte 30 Tage: [{kategorie: betrag}]
var ledger_today: Dictionary = {}
var ledger_year: Dictionary = {}       # laufendes Jahr
var ledger_last_year: Dictionary = {}
var money_hist: Array = []             # Kontostand alle 7 Tage (2 Jahre)
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
	return pow(1.25, minf(years(), 10.0)) * pow(1.06, maxf(0.0, years() - 10.0))

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
	return 25.0 * pow(1.3, gen - 1) * gpu_price_mult

## GPUs im Büro: gemietet + gekauft (teilen sich die Plätze)
func gpu_count() -> int:
	return rented_count() + hw_count(office_hw)

## Gesamte Rechenleistung: gemietete + eigene Büro-GPUs + Rechenzentren
func compute_power() -> float:
	return rented_power() + hw_power(office_hw) + dc_total_power()

func rented_power() -> float:
	var p := 0.0
	for g in gpus:
		p += int(g["count"]) * gpu_power(int(g["gen"]))
	return p

func daily_gpu_cost() -> float:
	var c := 0.0
	for g in gpus:
		c += int(g["count"]) * rent_price(int(g["gen"]))
	return c


# ---------------------------------------------------------------- Team

func office_data() -> Dictionary:
	return D.OFFICES[office]

func role_skill(role: String) -> float:
	var s := 0.0
	for p in staff:
		if p["role"] == role:
			s += eff_skill(p)
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
	return minf(1.8, 1.0 + 0.04 * role_skill("sales"))

func safety_reduction() -> float:
	return minf(0.5, 0.04 * role_skill("safety"))

func can_see_risk() -> bool:
	for p in staff:
		if p["role"] == "safety":
			return true
	return false

func daily_salaries() -> float:
	var s := 0.0
	for p in staff:
		s += float(p["salary"]) / 365.0
	return s

func rp_per_day() -> float:
	var r := 0.16 * role_skill("research")
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
	book("data", -(ev["data_cost"]))
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
	if kind == "api":
		m["fit"] = fit
		m["users"] = target_users(m) * (0.4 if rating >= 8.0 else 0.25)   # Start-Hype
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
	book("grant", (money_gain))
	var fine := 0.0
	if flags.get("regulation", false) and kind != "paper" and int(m["eval_days"]) < 14:
		fine = 20000.0 * market()
		book("fines", -(fine))
	last_feedback = _feedback(m["focus"])
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
		m["users"] = 0.0
		_news("%s wurde vom Markt genommen." % m["name"])
		revision += 1

# ---- Beliebtheit & Nutzer

func market_users() -> float:
	return D.MARKET_USERS * market()

## Attraktivität eines Modells: Qualität relativ zum Markt (gedämpft) × passender Fokus
func model_appeal(m: Dictionary) -> float:
	var rel: float = float(m["q"]) / expected_quality()
	return pow(clampf(rel, 0.05, 2.5), 1.6) * float(m["fit"])

func _total_appeal() -> float:
	var rival_rel: float = float(rival["best_q"]) / expected_quality()
	var rival_w := 0.4 if flags.get("helix_controlled", false) else 1.0
	var total := pow(clampf(rival_rel, 0.3, 2.0), 1.6) * rival_w + D.OTHER_APPEAL * (1.0 - 0.3 * absorbed_labs())
	for m in models:
		if m["status"] == "api":
			total += model_appeal(m)
	return total

## Wie viele Nutzer das Modell langfristig gewinnen kann
func target_users(m: Dictionary, total := -1.0) -> float:
	if total < 0.0:
		total = _total_appeal()
	return market_users() * model_appeal(m) / total * (0.55 + reputation / 110.0) * sales_mult() * (1.0 + ad_boost(m))

func _step_users() -> void:
	var total := _total_appeal()
	for m in models:
		if m["status"] != "api":
			continue
		var target := target_users(m, total)
		var u := float(m.get("users", 0.0))
		u += (target - u) * (D.USER_GROWTH if target > u else D.USER_DECAY)
		m["users"] = u

## Beliebtheit = Marktanteil in Prozent
func popularity(m: Dictionary) -> float:
	return float(m.get("users", 0.0)) / maxf(1.0, market_users()) * 100.0

func model_revenue(m: Dictionary) -> float:
	if m["status"] != "api":
		return 0.0
	return float(m.get("users", 0.0)) * D.ARPU

func api_revenue() -> float:
	var total := 0.0
	for m in models:
		total += model_revenue(m)
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
	book("hire", -(bonus))
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
	book("hire", -(float(p["salary"]) / 12.0))
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
	book("building", -(float(o["cost"])))
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
	book("building", -(float(u["cost"])))
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
	var m := float(dc_loc(dc)["power"]) * (1.0 - energy_discount())
	for u in D.DC_UPGRADES:
		if dc["upgrades"].has(u["id"]) and u.has("power"):
			m *= float(u["power"])
	return m

func dc_perf(dc: Dictionary) -> float:
	return 1.15 if dc["upgrades"].has("network") else 1.0

func dc_power(dc: Dictionary) -> float:
	return hw_power(dc["hw"]) * dc_perf(dc)

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

# ---- Grundstücke

func plot(id: String) -> Dictionary:
	return _find(D.PLOTS, id)

## "locked" (noch nicht im Angebot), "for_sale", "empty" (gehört dir), "dc", "fab"
func plot_state(id: String) -> String:
	if plots.has(id):
		var v := String(plots[id])
		return "empty" if v == "" else ("plant" if v.begins_with("plant:") else v)
	if year() < int(plot(id)["year"]):
		return "locked"
	return "for_sale"

func plot_price(id: String) -> float:
	return float(plot(id)["price"]) * inflation()

func buy_plot(id: String) -> String:
	if plot_state(id) != "for_sale":
		return "Grundstück steht nicht zum Verkauf."
	var price := plot_price(id)
	if money < price:
		return "Nicht genug Geld."
	book("building", -price)
	plots[id] = ""
	_news("Grundstück gekauft: [b]%s[/b] (%s)." % [plot(id)["name"], _find(D.LOCATIONS, plot(id)["loc"])["name"]])
	revision += 1
	return ""

func empty_plots() -> Array:
	var out := []
	for p in D.PLOTS:
		if plot_state(p["id"]) == "empty":
			out.append(p["id"])
	return out

func dc_build_cost(type_id: String, plot_id: String) -> float:
	var p := plot(plot_id)
	var build := float(_find(D.LOCATIONS, p["loc"])["build"]) if not p.is_empty() else 1.0
	return float(_find(D.DATACENTERS, type_id)["cost"]) * build * inflation()

func build_datacenter(type_id: String, plot_id: String) -> String:
	var t := _find(D.DATACENTERS, type_id)
	if t.is_empty():
		return "Unbekannter Typ."
	if plot_state(plot_id) != "empty":
		return "Kaufe zuerst ein freies Grundstück (Weltansicht)."
	if year() < int(t["year"]):
		return "Verfügbar ab %d." % t["year"]
	var cost := dc_build_cost(type_id, plot_id)
	if money < cost:
		return "Nicht genug Geld."
	book("building", -(cost))
	var loc_id: String = plot(plot_id)["loc"]
	datacenters.append({"type": type_id, "loc": loc_id, "plot": plot_id, "upgrades": {}, "hw": []})
	plots[plot_id] = "dc"
	fx.append("build")
	_news("[color=#7fd]Bau:[/color] %s auf „%s“ ist in Betrieb." % [t["name"], plot(plot_id)["name"]])
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
	book("building", -(cost))
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
		var price := float(custom_chip["base"]) * D.BUY_DAYS * D.CHIP_PRICE * (0.5 if has_fab else 1.0) * (1.0 - chip_discount())
		if not has_fab:
			price *= gpu_price_mult
		return {"name": custom_chip["name"], "power": float(custom_chip["power"]), "price": price, "upkeep": float(custom_chip["base"]) * D.UPKEEP_SHARE}
	var gen := gpu_gen_now()
	return {"name": "GPU Gen %d" % gen, "power": gpu_power(gen), "price": gpu_cost(gen) * D.BUY_DAYS * (1.0 - chip_discount()), "upkeep": gpu_cost(gen) / gpu_price_mult * D.UPKEEP_SHARE}

func buy_hardware(dc_index: int, kind: String, n: int) -> String:
	var dc: Dictionary = datacenters[dc_index]
	n = mini(n, dc_slots(dc) - dc_used(dc))
	if n > 0 and not hw_unit(kind).is_empty():
		n = mini(n, int(money / float(hw_unit(kind)["price"])))
		if n <= 0:
			return "Nicht genug Geld."
		book("hardware", -(float(hw_unit(kind)["price"]) * n))
		_hw_add(dc["hw"], hw_unit(kind), n)
		revision += 1
		return ""
	if n <= 0:
		return "Rechenzentrum ist voll."
	var u := hw_unit(kind)
	if u.is_empty():
		return "Noch kein eigener Chip."
	n = mini(n, int(money / float(u["price"])))
	if n <= 0:
		return "Nicht genug Geld."
	book("hardware", -(float(u["price"]) * n))
	for h in dc["hw"]:
		if h["name"] == u["name"]:
			h["count"] = int(h["count"]) + n
			revision += 1
			return ""
	dc["hw"].append({"name": u["name"], "power": u["power"], "count": n, "upkeep": u["upkeep"]})
	revision += 1
	return ""

## Schwächste Hardware zuerst verkaufen (Erlös je nach Alter und Zustand)
func scrap_hardware(dc_index: int, n: int) -> float:
	return _sell(datacenters[dc_index]["hw"], n)

func chip_project_cost() -> float:
	return D.CHIP_BASE_COST * pow(1.5, chip_version) * inflation()

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
	book("chips", -(cost))
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

func build_fab(plot_id: String) -> String:
	if not techs.has("fab"):
		return "Erforsche zuerst 'Chip-Fertigung'."
	if has_fab:
		return "Du hast schon eine Fabrik."
	if plot_state(plot_id) != "empty":
		return "Kaufe zuerst ein freies Grundstück (Weltansicht)."
	var cost := D.FAB_COST * inflation()
	if money < cost:
		return "Nicht genug Geld."
	book("building", -(cost))
	has_fab = true
	fab_plot = plot_id
	plots[plot_id] = "fab"
	fx.append("build")
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
				book("invest", (float(inv["money"])))
				equity -= equity * float(inv["equity"]) / 100.0
				investor_stage += 1
				investor_next_day = day + 90
				_news("[color=#fd7]%s:[/color] +%s für %d %% der Anteile." % [inv["name"], fmt_money(inv["money"]), int(inv["equity"])])
			else:
				investor_next_day = day + 120
		"offer":
			if choice == 0:
				book("invest", float(data["amount"]))
				equity -= equity * float(data["pct"]) / 100.0
				_news("[color=#fd7]Investor:[/color] +%s für %.0f %% der Anteile." % [fmt_money(data["amount"]), data["pct"]])
		"buyout":
			if choice == 0:
				_set_ending("sold", "Verkauft", "Du verkaufst dein Labor für %s. Dein Anteil: %s. Die AGI baut jetzt jemand anderes." % [fmt_money(data["price"]), fmt_money(float(data["price"]) * equity / 100.0)])
		"rescue":
			if choice == 0:
				book("invest", (float(data["amount"])))
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
				book("fines", -(cost))
				_news("Vergleich: %s gezahlt." % fmt_money(cost))
			elif rng.randf() < (0.25 if flags.get("denied", false) else 0.5):
				reputation = minf(100.0, reputation + 3.0)
				_info("Prozess gewonnen", "Das Gericht sieht keine ausreichenden Beweise. Glück gehabt.")
			else:
				book("fines", -(cost * 3.0))
				reputation = maxf(0.0, reputation - 10.0)
				_info("Prozess verloren", "Das Gericht verurteilt dein Labor zu %s Schadensersatz." % fmt_money(cost * 3.0))
		"raise":
			_resolve_raise(data, choice)
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
				book("fines", -(300000.0 * inflation()))
				flags["lobby"] = true
		"jailbreak":
			var m := get_model(int(data["model"]))
			if not m.is_empty():
				if choice == 0:
					withdraw_model(int(m["id"]))
				elif choice == 1:
					book("other", -(float(data["cost"])))
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
	_step_users()
	last_cost = daily_salaries() + daily_gpu_cost() + daily_dc_cost() + daily_office_power()
	last_income = api_revenue()
	book("api", last_income)
	book("salary", -daily_salaries())
	book("rent", -daily_gpu_cost())
	book("dc", -daily_dc_cost())
	book("power", -daily_office_power())
	var credit := _energy_credit(daily_office_power() + daily_dc_cost())
	if credit > 0.0:
		book("energy", credit)
		last_cost -= minf(credit, daily_office_power() + daily_dc_cost())
	_step_market()
	_step_roadshow()
	_random_offers()
	total_revenue += last_income
	rp += rp_per_day()
	if day - _last_release_day() > 180:
		reputation = maxf(0.0, reputation - 0.02)
	_step_training()
	_step_staff()
	_step_hw()
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
	_close_ledger_day()

func _step_risk() -> void:
	var hr := hidden_risk()
	if hr > 0.0 and rng.randf() < hr * 0.0006:
		var sev := rng.randf_range(0.5, 1.5) * hr
		var rep_loss := clampf(4.0 + sev * 3.0, 4.0, 30.0)
		var fine := 3000.0 * market() * sev
		reputation = maxf(0.0, reputation - rep_loss)
		book("fines", -(fine))
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
	if day < int(rival["next_day"]) or flags.get("helix_controlled", false):
		return
	var q := expected_quality() * rng.randf_range(0.95, 1.3)
	rival["count"] = int(rival["count"]) + 1
	rival["best_q"] = maxf(float(rival["best_q"]), q)
	rival["next_day"] = day + rng.randi_range(150, 260)
	_news("[color=#f99]Helix Dynamics[/color] veröffentlicht Helix-%d (Qualität %.0f)." % [rival["count"], q])
	if year() >= D.RIVAL_AGI_YEAR and q >= D.AGI_Q:
		_set_ending("rival_agi", "Helix war schneller",
			"Helix Dynamics verkündet die erste AGI. Dein Labor wird über Nacht zur Fußnote der Geschichte.")

func _grow_staff() -> void:
	for p in staff:
		if int(p["skill"]) < 10 and rng.randf() < 0.35:
			p["skill"] = int(p["skill"]) + 1   # mehr Können → irgendwann ein Gehaltswunsch
	revision += 1

func _make_person(role: String, skill: int, salary_factor: float = 1.0) -> Dictionary:
	var first: String = D.FIRST_NAMES[rng.randi() % D.FIRST_NAMES.size()]
	var last: String = D.LAST_NAMES[rng.randi() % D.LAST_NAMES.size()]
	var salary := (D.SALARY_BASE + skill * D.SALARY_PER_SKILL) * inflation() * salary_factor * rng.randf_range(0.9, 1.15)
	return {"name": first + " " + last, "role": role, "skill": skill, "salary": round(salary),
		"energy": 100.0, "morale": 70.0, "vacation": 0, "next_raise": day + rng.randi_range(D.RAISE_MIN_DAYS, D.RAISE_MAX_DAYS)}

func _refresh_candidates() -> void:
	candidates.clear()
	var max_skill := clampi(2 + int(reputation / 12.0) + (1 if office_upgrades.has("daycare") else 0), 2, 10)
	for i in range(4):
		var role: String = D.ROLE_ORDER[i] if i < 4 and rng.randf() < 0.5 else D.ROLE_ORDER[rng.randi() % 4]
		if rng.randf() < 0.14:
			role = "manager"
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

## Ziele zählen in beliebiger Reihenfolge; goal_index = erstes offenes Ziel (für die Anzeige)
func goal_reached(id: String) -> bool:
	return flags.get("goals", {}).has(id)

func goals_count() -> int:
	return flags.get("goals", {}).size()

func _step_goals() -> void:
	if not flags.has("goals"):
		var old := {}
		for i in range(goal_index):   # alte Spielstände übernehmen
			old[D.GOALS[i]["id"]] = true
		flags["goals"] = old
	var done: Dictionary = flags["goals"]
	for g in D.GOALS:
		if not done.has(g["id"]) and goal_done(g["id"]):
			done[g["id"]] = day
			var reward := 5000.0 * market()
			book("reward", reward)
			reputation = minf(100.0, reputation + 1.0)
			_news("[color=#9f9]Ziel erreicht:[/color] %s (+%s, +1 Reputation)" % [g["text"], fmt_money(reward)])
			fx.append("goal")
			revision += 1
	goal_index = D.GOALS.size()
	for i in range(D.GOALS.size()):
		if not done.has(D.GOALS[i]["id"]):
			goal_index = i
			break

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
	var s := reputation * 1000.0 + best_q * 200.0 + total_revenue / 10000.0 * equity / 100.0 + goals_count() * 2000.0
	if ending.get("id", "") == "aligned":
		s *= 2.0
	return int(s)


# ---------------------------------------------------------------- Personal: Energie, Stimmung, Urlaub, Gehaltswünsche

## Wirksames Können: erschöpfte oder unzufriedene Leute leisten weniger, Urlauber gar nichts
func eff_skill(p: Dictionary) -> float:
	if int(p.get("vacation", 0)) > 0:
		return 0.0
	var energy := float(p.get("energy", 100.0))
	var morale := float(p.get("morale", 70.0))
	return float(p["skill"]) * (0.55 + 0.45 * energy / 100.0) * (0.85 + 0.3 * morale / 100.0)

func managers() -> Array:
	var out := []
	for p in staff:
		if p["role"] == "manager" and int(p.get("vacation", 0)) == 0:
			out.append(p)
	return out

## Wie viele Leute die Manager betreuen können
func manager_capacity() -> int:
	var c := 0
	for m in managers():
		c += 6 + int(float(m["skill"]) * 1.5)
	return c

func managed() -> bool:
	return not managers().is_empty() and manager_capacity() >= staff.size() - managers().size()

func away_count() -> int:
	var n := 0
	for p in staff:
		if int(p.get("vacation", 0)) > 0:
			n += 1
	return n

func send_vacation(index: int) -> String:
	if index < 0 or index >= staff.size():
		return "Unbekannte Person."
	var p: Dictionary = staff[index]
	if int(p.get("vacation", 0)) > 0:
		return "%s ist schon im Urlaub." % p["name"]
	p["vacation"] = D.VACATION_DAYS
	p["morale"] = minf(100.0, float(p.get("morale", 70.0)) + 5.0)
	_news("%s ist für %d Tage im Urlaub." % [p["name"], D.VACATION_DAYS])
	revision += 1
	return ""

func _step_staff() -> void:
	var training_on := not training.is_empty()
	var managed_now := managed()
	var mood_bonus := (6.0 if office_upgrades.has("coffee") else 0.0) + (8.0 if office_upgrades.has("gym") else 0.0) + (8.0 if managed_now else 0.0)
	var quitters := []
	for i in range(staff.size()):
		var p: Dictionary = staff[i]
		var energy := float(p.get("energy", 100.0))
		var morale := float(p.get("morale", 70.0))
		var vac := int(p.get("vacation", 0))
		if vac > 0:
			vac -= 1
			energy = minf(100.0, energy + 6.0)
			if vac == 0:
				_news("%s ist erholt zurück aus dem Urlaub." % p["name"])
				revision += 1
		else:
			var drain := D.ENERGY_DRAIN + (D.ENERGY_DRAIN_TRAINING if training_on else 0.0)
			if office_upgrades.has("gym"):
				drain *= 0.8
			energy = maxf(0.0, energy - drain)
		var target := 55.0 + mood_bonus + (energy - 50.0) * 0.3
		morale += (target - morale) * 0.01
		if energy < 15.0:
			morale -= 0.15
		p["energy"] = energy
		p["morale"] = clampf(morale, 0.0, 100.0)
		p["vacation"] = vac
		if i > 0 and morale < 22.0 and rng.randf() < 0.003:
			quitters.append(i)
	for i in range(quitters.size() - 1, -1, -1):
		var q: Dictionary = staff[quitters[i]]
		_news("[color=#f77]Kündigung:[/color] %s war zu unzufrieden und hat das Team verlassen." % q["name"])
		staff.remove_at(quitters[i])
		fx.append("incident")
		revision += 1
	# Manager: Erschöpfte rechtzeitig in Urlaub schicken (höchstens 15 % gleichzeitig)
	if managed_now and day % 7 == 0:
		var tired := []
		for i in range(staff.size()):
			if int(staff[i].get("vacation", 0)) == 0 and float(staff[i].get("energy", 100.0)) < 35.0:
				tired.append(i)
		tired.sort_custom(func(a, b): return float(staff[a].get("energy", 100.0)) < float(staff[b].get("energy", 100.0)))
		var limit := maxi(1, int(staff.size() * 0.15))
		for i in tired:
			if away_count() >= limit:
				break
			staff[i]["vacation"] = D.VACATION_DAYS
			_news("Manager schickt %s in den Urlaub." % staff[i]["name"])
			revision += 1
	# Gehaltswünsche
	for i in range(staff.size()):
		var p: Dictionary = staff[i]
		if day >= int(p.get("next_raise", day + 1)) and int(p.get("vacation", 0)) == 0:
			p["next_raise"] = day + rng.randi_range(D.RAISE_MIN_DAYS, D.RAISE_MAX_DAYS)
			var pct := rng.randf_range(0.06, 0.14) + 0.01 * maxf(0.0, float(p["skill"]) - 5.0)
			if managed_now:
				if float(p.get("morale", 70.0)) < 55.0 or int(p["skill"]) >= 6:
					p["salary"] = round(float(p["salary"]) * (1.0 + pct))
					p["morale"] = minf(100.0, float(p["morale"]) + 12.0)
					_news("Manager bewilligt %s +%d %% Gehalt." % [p["name"], int(pct * 100)])
				else:
					p["salary"] = round(float(p["salary"]) * (1.0 + pct * 0.5))
					p["morale"] = minf(100.0, float(p["morale"]) + 3.0)
					_news("Manager einigt sich mit %s auf +%d %% Gehalt." % [p["name"], int(pct * 50)])
				revision += 1
			elif event_queue.size() < 3:
				_push_event("raise", "Gehaltswunsch",
					"%s (%s, Können %d) möchte %d %% mehr Gehalt: %s statt %s pro Jahr." % [p["name"], D.ROLES[p["role"]]["name"], int(p["skill"]), int(pct * 100), fmt_money(float(p["salary"]) * (1.0 + pct)), fmt_money(p["salary"])],
					[["Annehmen", "Stimmung deutlich besser."], ["Halbe Erhöhung anbieten", "Kompromiss – kleine Verbesserung."], ["Ablehnen", "Spart Geld, Stimmung sinkt stark (Kündigungsgefahr)."]],
					{"name": p["name"], "pct": pct})


func _resolve_raise(data: Dictionary, choice: int) -> void:
	for p in staff:
		if p["name"] == data["name"]:
			var pct := float(data["pct"])
			match choice:
				0:
					p["salary"] = round(float(p["salary"]) * (1.0 + pct))
					p["morale"] = minf(100.0, float(p.get("morale", 70.0)) + 15.0)
				1:
					p["salary"] = round(float(p["salary"]) * (1.0 + pct * 0.5))
					p["morale"] = clampf(float(p.get("morale", 70.0)) + (2.0 if rng.randf() < 0.7 else -8.0), 0.0, 100.0)
				_:
					p["morale"] = maxf(0.0, float(p.get("morale", 70.0)) - 18.0)
			revision += 1
			return


# ---------------------------------------------------------------- Eigene Hardware (Büro + Rechenzentren)
# Einträge: {name, power, count, upkeep (Strom/Tag je Stück), price (Kaufpreis je Stück), day, cond (0–100)}

func _hw_cond(h: Dictionary) -> float:
	return float(h.get("cond", 100.0))

## Leistung sinkt mit dem Zustand (bei 0 % nur noch halbe Leistung)
func hw_power(list: Array) -> float:
	var p := 0.0
	for h in list:
		p += float(h["power"]) * int(h["count"]) * (0.5 + 0.5 * _hw_cond(h) / 100.0)
	return p

func hw_count(list: Array) -> int:
	var n := 0
	for h in list:
		n += int(h["count"])
	return n

func hw_upkeep(list: Array) -> float:
	var c := 0.0
	for h in list:
		c += float(h["upkeep"]) * int(h["count"])
	return c

func hw_avg_cond(list: Array) -> float:
	var n := hw_count(list)
	if n == 0:
		return 100.0
	var s := 0.0
	for h in list:
		s += _hw_cond(h) * int(h["count"])
	return s / n

func _hw_price(h: Dictionary) -> float:
	return float(h.get("price", float(h["upkeep"]) / D.UPKEEP_SHARE * D.BUY_DAYS))

func hw_maint_cost(list: Array) -> float:
	var c := 0.0
	for h in list:
		c += _hw_price(h) * int(h["count"]) * D.MAINT_SHARE * (100.0 - _hw_cond(h)) / 100.0
	return c

func _maintain(list: Array, factor := 1.0) -> String:
	var cost := hw_maint_cost(list) * factor
	if cost < 1.0:
		return "Alles in bestem Zustand."
	if money < cost:
		return "Nicht genug Geld für die Wartung."
	book("maint", -cost)
	for h in list:
		h["cond"] = 100.0
	revision += 1
	return ""

## Wiederverkaufswert je Stück: −20 % pro Jahr, schlechter Zustand mindert
func hw_resale(h: Dictionary) -> float:
	var years := maxf(0.0, (day - int(h.get("day", day))) / 365.0)
	return _hw_price(h) * pow(0.8, years) * (0.5 + 0.5 * _hw_cond(h) / 100.0) * 0.7

## Schwächste und älteste zuerst verkaufen
func _sell(list: Array, n: int) -> float:
	list.sort_custom(func(a, b): return float(a["power"]) < float(b["power"]) or (float(a["power"]) == float(b["power"]) and int(a.get("day", 0)) < int(b.get("day", 0))))
	var value := 0.0
	while n > 0 and list.size() > 0:
		var take := mini(n, int(list[0]["count"]))
		value += hw_resale(list[0]) * take
		list[0]["count"] = int(list[0]["count"]) - take
		n -= take
		if int(list[0]["count"]) <= 0:
			list.remove_at(0)
	if value > 0.0:
		book("hw_sale", value)
	revision += 1
	return value

func _hw_add(list: Array, u: Dictionary, n: int) -> void:
	for h in list:
		if h["name"] == u["name"] and int(h.get("day", -1)) == day:
			h["count"] = int(h["count"]) + n
			return
	list.append({"name": u["name"], "power": u["power"], "count": n, "upkeep": u["upkeep"], "price": u["price"], "day": day, "cond": 100.0})

func _step_hw() -> void:
	var lists: Array = [office_hw]
	for dc in datacenters:
		lists.append(dc["hw"])
	for list in lists:
		for h in list:
			h["cond"] = maxf(0.0, _hw_cond(h) - D.WEAR_PER_DAY)
		# Hardware-Labor wartet automatisch zum halben Preis
		if office_upgrades.has("hwlab") and hw_count(list) > 0 and hw_avg_cond(list) < 70.0:
			_maintain(list, 0.5)

# ---- Büro-Hardware

func office_power_mult() -> float:
	var m := D.OFFICE_POWER * (1.0 - energy_discount())
	if office_upgrades.has("solar"):
		m *= 0.6
	if office_upgrades.has("battery"):
		m *= 0.8
	return m

func daily_office_power() -> float:
	return hw_upkeep(office_hw) * office_power_mult()

func rented_count() -> int:
	var n := 0
	for g in gpus:
		n += int(g["count"])
	return n

func buy_office_hw(kind: String, n: int) -> String:
	n = mini(n, int(office_data()["gpus"]) - gpu_count())
	if n <= 0:
		return "Kein Platz im Büro. Gemietete GPUs zurückgeben oder größeres Büro."
	var u := hw_unit(kind)
	if u.is_empty():
		return "Noch kein eigener Chip."
	n = mini(n, int(money / float(u["price"])))
	if n <= 0:
		return "Nicht genug Geld."
	book("hardware", -(float(u["price"]) * n))
	_hw_add(office_hw, u, n)
	revision += 1
	return ""

func sell_office_hw(n: int) -> float:
	return _sell(office_hw, n)

func maintain_office() -> String:
	return _maintain(office_hw)

func maintain_dc(dc_index: int) -> String:
	return _maintain(datacenters[dc_index]["hw"])


# ---------------------------------------------------------------- Firmenmarkt, Werbung, Investoren, Kraftwerke

func _init_companies() -> void:
	if not companies.is_empty():
		return
	for c in D.COMPANIES:
		companies[c["id"]] = {"value": float(c["value"]), "stake": 0.0}

func company(id: String) -> Dictionary:
	return _find(D.COMPANIES, id)

func stake(id: String) -> float:
	return float(companies.get(id, {}).get("stake", 0.0))

func company_value(id: String) -> float:
	return float(companies.get(id, {}).get("value", 0.0))

func stake_buy_price(id: String) -> float:
	return company_value(id) * D.STAKE_STEP / 100.0 * D.STAKE_PREMIUM

func stake_sell_price(id: String) -> float:
	return company_value(id) * D.STAKE_STEP / 100.0 * 0.95

func buy_stake(id: String) -> String:
	_init_companies()
	if not companies.has(id):
		return "Unbekannte Firma."
	if stake(id) >= 100.0:
		return "Gehört dir schon ganz."
	var price := stake_buy_price(id)
	if money < price:
		return "Nicht genug Geld."
	book("stake", -price)
	var before := stake(id)
	companies[id]["stake"] = minf(100.0, before + D.STAKE_STEP)
	_news("Beteiligung: %d %% an [b]%s[/b]." % [int(stake(id)), company(id)["name"]])
	_check_takeover(id, before)
	revision += 1
	return ""

func sell_stake(id: String) -> String:
	if stake(id) <= 0.0:
		return "Keine Anteile."
	if controls(id) and stake(id) - D.STAKE_STEP < 51.0 and company(id)["kind"] == "ai" and id != "helix":
		return "Übernommene Firmen kann man nicht mehr verkaufen."
	book("stake", stake_sell_price(id))
	companies[id]["stake"] = maxf(0.0, stake(id) - D.STAKE_STEP)
	revision += 1
	return ""

func controls(id: String) -> bool:
	return stake(id) >= 51.0

## Rabatt aus allen Beteiligungen einer Art (anteilig zum Anteil)
func _kind_discount(kind: String) -> float:
	var d := 0.0
	for c in D.COMPANIES:
		if c["kind"] == kind:
			d += float(c.get("perk", 0.0)) * stake(c["id"]) / 100.0
	return minf(d, 0.5)

func chip_discount() -> float:
	return _kind_discount("chip")

func cloud_discount() -> float:
	return _kind_discount("cloud")

func energy_discount() -> float:
	return _kind_discount("energy")

func media_discount() -> float:
	return _kind_discount("media")

func rent_price(gen: int) -> float:
	return gpu_cost(gen) * (1.0 - cloud_discount())

func daily_dividends() -> float:
	var d := 0.0
	for c in D.COMPANIES:
		d += company_value(c["id"]) * float(c["yield"]) / 365.0 * stake(c["id"]) / 100.0
	return d

func _check_takeover(id: String, before: float) -> void:
	var c := company(id)
	if c["kind"] != "ai":
		return
	if id == "helix" and before < 51.0 and stake(id) >= 51.0:
		flags["helix_controlled"] = true
		reputation = minf(100.0, reputation + 8.0)
		_info("Helix Dynamics gehört dir!", "Mit %d %% kontrollierst du deinen größten Rivalen. Helix arbeitet jetzt für dich – von dort droht keine AGI mehr, und du kassierst die Dividenden." % int(stake(id)))
	elif id != "helix" and before < 100.0 and stake(id) >= 100.0:
		flags["absorbed_" + id] = true
		reputation = minf(100.0, reputation + 4.0)
		for i in range(2):
			if staff.size() < int(office_data()["staff"]):
				staff.append(_make_person(["research", "engineer"][i], rng.randi_range(4, 7)))
		_info("%s übernommen" % c["name"], "Das Labor gehört jetzt komplett dir: weniger Konkurrenz am Markt, +4 Ruf und (falls Platz im Büro) zwei erfahrene Leute fürs Team.")

func absorbed_labs() -> int:
	var n := 0
	for c in D.COMPANIES:
		if flags.get("absorbed_" + String(c["id"]), false):
			n += 1
	return n

func _step_market() -> void:
	_init_companies()
	var y := 1.0 / 365.0
	for c in D.COMPANIES:
		var e: Dictionary = companies[c["id"]]
		var g := float(c["growth"])
		if c["kind"] == "ai" and c["id"] == "helix":
			g += 0.02 * float(rival["count"]) / maxf(1.0, years() + 1.0)
		e["value"] = float(e["value"]) * (1.0 + g * y) * (1.0 + rng.randf_range(-0.012, 0.012))
	var div := daily_dividends()
	if div > 0.0:
		book("dividend", div)

# ---- Werbung

func ad_cost(ad_id: String) -> float:
	return float(_find(D.ADS, ad_id)["cost"]) * market() * (1.0 - media_discount())

func start_campaign(model_id: int, ad_id: String) -> String:
	var m := get_model(model_id)
	if m.is_empty() or m["status"] != "api":
		return "Werbung nur für API-Modelle."
	if int(m.get("ad_until", 0)) > day:
		return "Für dieses Modell läuft schon eine Kampagne."
	var a := _find(D.ADS, ad_id)
	var cost := ad_cost(ad_id)
	if money < cost:
		return "Nicht genug Geld."
	book("ads", -cost)
	m["ad_boost"] = float(a["boost"])
	m["ad_until"] = day + int(a["days"])
	_news("Werbung: %s für [b]%s[/b] läuft %d Tage." % [a["name"], m["name"], a["days"]])
	revision += 1
	return ""

func ad_boost(m: Dictionary) -> float:
	return float(m.get("ad_boost", 0.0)) if int(m.get("ad_until", 0)) > day else 0.0

# ---- Investoren

## Grober Firmenwert: Umsatz, Kasse, Ruf, Hardware
func valuation() -> float:
	var v := maxf(0.0, last_income - last_cost) * 365.0 * 8.0 + last_income * 365.0 * 2.0 + maxf(0.0, money)
	v += reputation / 100.0 * 3000000.0 * market()
	return maxf(v, 500000.0)

func start_roadshow() -> String:
	if int(flags.get("roadshow_until", 0)) > day:
		return "Die Roadshow läuft schon."
	var cost := D.ROADSHOW_COST * inflation()
	if money < cost:
		return "Nicht genug Geld."
	book("other", -cost)
	flags["roadshow_until"] = day + D.ROADSHOW_DAYS
	_news("Roadshow gestartet: Du stellst dein Labor %d Tage lang Investoren vor." % D.ROADSHOW_DAYS)
	revision += 1
	return ""

func _step_roadshow() -> void:
	if int(flags.get("roadshow_until", 0)) == day:
		var pct := 10.0
		var amount := valuation() * pct / 100.0 * rng.randf_range(0.8, 1.2) * (0.7 + reputation / 200.0)
		_push_event("offer", "Angebot nach der Roadshow",
			"Ein Investor bietet %s für %d %% deiner Anteile (Firmenwert ~%s). Du hältst %.1f %%." % [fmt_money(amount), int(pct), fmt_money(valuation()), equity],
			[["Annehmen", "Geld sofort, deine Anteile sinken."], ["Ablehnen", "Du kannst jederzeit eine neue Roadshow starten."]], {"amount": amount, "pct": pct})

func _random_offers() -> void:
	if not event_queue.is_empty() or not _cooldown_ok("offer", 240):
		return
	if rng.randf() < 0.0025 and equity > 25.0:
		cooldowns["offer"] = day
		var pct := rng.randf_range(4.0, 9.0)
		var amount := valuation() * pct / 100.0 * rng.randf_range(0.9, 1.4)
		_push_event("offer", "Unerwartete Anfrage",
			"Ein strategischer Investor möchte einsteigen: %s für %.0f %% deiner Anteile." % [fmt_money(amount), pct],
			[["Annehmen", "Geld sofort, deine Anteile sinken."], ["Ablehnen", "Kein Problem."]], {"amount": amount, "pct": pct})
	elif year() >= 2023 and rng.randf() < 0.0006:
		cooldowns["offer"] = day
		var price := valuation() * rng.randf_range(1.3, 2.0)
		_push_event("buyout", "Übernahmeangebot",
			"Ein Tech-Konzern will dein komplettes Labor kaufen – für %s. Dein Anteil wäre %s wert." % [fmt_money(price), fmt_money(price * equity / 100.0)],
			[["Verkaufen (Spielende)", "Du gehst mit dem Geld – keine AGI mehr von dir."], ["Ablehnen", "Weiter für die AGI."]], {"price": price})

# ---- Kraftwerke

func plant(id: String) -> Dictionary:
	return _find(D.PLANTS, id)

func build_plant(type_id: String, plot_id: String) -> String:
	var pl := plant(type_id)
	if pl.is_empty():
		return "Unbekanntes Kraftwerk."
	if plot_state(plot_id) != "empty":
		return "Kaufe zuerst ein freies Grundstück (Weltansicht)."
	if year() < int(pl["year"]):
		return "Verfügbar ab %d." % pl["year"]
	var cost := float(pl["cost"]) * inflation()
	if money < cost:
		return "Nicht genug Geld."
	book("building", -cost)
	plots[plot_id] = "plant:" + type_id
	fx.append("build")
	_news("[color=#7fd]Kraftwerk:[/color] %s auf „%s“ liefert jetzt Strom." % [pl["name"], plot(plot_id)["name"]])
	revision += 1
	return ""

## Wert des eigenen Stroms pro Tag ($)
func energy_output() -> float:
	var o := 0.0
	for pid in plots:
		var st := String(plots[pid])
		if st.begins_with("plant:"):
			o += float(plant(st.substr(6))["output"])
	return o * inflation()

## Eigene Kraftwerke decken zuerst die eigenen Stromkosten, Überschuss wird zu 40 % verkauft
func _energy_credit(power_costs: float) -> float:
	var out := energy_output()
	if out <= 0.0:
		return 0.0
	var used := minf(out, power_costs)
	return used + (out - used) * 0.4


# ---------------------------------------------------------------- Berater

## Tipps nach Wichtigkeit: [{prio, text, tab, icon}] – tab = Seitenleisten-Bereich (UI)
func advice() -> Array:
	var tips := []
	var burn := last_cost - last_income
	# Geld
	if burn > 0.0 and money > 0.0 and money / burn < 90.0:
		var biggest := _biggest_cost()
		tips.append({"prio": 100, "icon": "emote_alert", "tab": 8,
			"text": "Dein Geld reicht nur noch ~%d Tage. Größter Kostenblock: %s (%s/Tag). Kosten senken (GPUs zurückgeben, weniger Personal) oder ein neues Modell als API veröffentlichen." % [int(money / burn), biggest[0], fmt_money(biggest[1])]})
	elif money < 0.0:
		tips.append({"prio": 110, "icon": "emote_alert", "tab": 8, "text": "Konto im Minus! Nach 60 Tagen ist das Labor pleite. Sofort Kosten senken oder Geld beschaffen."})
	# Modelle
	for m in models:
		if m["status"] == "ready":
			tips.append({"prio": 85, "icon": "emote_exclamation", "tab": 4, "text": "„%s“ ist fertig, aber noch nicht veröffentlicht – es bringt so weder Geld noch Ruf." % m["name"]})
			break
	if training.is_empty() and compute_power() > 0.0:
		tips.append({"prio": 80, "icon": "emote_dots3", "tab": 0, "text": "Gerade läuft kein Training – deine Rechenleistung (%s/Tag) bleibt ungenutzt. Starte ein neues Modell." % fmt_money(daily_gpu_cost() + daily_dc_cost())})
	var best_rel := 0.0
	var has_api := false
	for m in models:
		if m["status"] == "api":
			has_api = true
			best_rel = maxf(best_rel, float(m["q"]) / expected_quality())
	if has_api and best_rel < 0.85:
		tips.append({"prio": 65, "icon": "emote_faceSad", "tab": 0, "text": "Deine API-Modelle sind veraltet (bestes: %d %% des Marktniveaus) – der Umsatz sinkt jeden Tag. Zeit für ein größeres oder moderneres Modell." % int(best_rel * 100)})
	if not last_feedback.is_empty() and not " ".join(last_feedback).contains("genau"):
		tips.append({"prio": 55, "icon": "emote_idea", "tab": 0, "text": "Letzte Kritik: „%s“ Verteile die Fokus-Punkte beim nächsten Modell entsprechend." % " ".join(last_feedback)})
	# Risiko
	var released := 0
	for m in models:
		if m["status"] in ["api", "open"]:
			released += 1
	if released > 0 and not can_see_risk():
		tips.append({"prio": 70, "icon": "emote_question", "tab": 1, "text": "Du kannst das Risiko deiner Modelle nicht sehen. Stell jemanden für Safety ein – das senkt es auch."})
	elif hidden_risk() > 3.0:
		tips.append({"prio": 90, "icon": "emote_alert", "tab": 4, "text": "Risiko %.1f: Sicherheitsvorfälle werden wahrscheinlich. Riskante Modelle zurückziehen, mehr Sicherheits-Punkte und Evaluierungstage, Safety-Forschung." % hidden_risk()})
	# Forschung
	for t in D.TECHS:
		if tech_state(t["id"]) == "available" and rp >= float(t["rp"]):
			tips.append({"prio": 60, "icon": "emote_idea", "tab": 3, "text": "Du kannst „%s“ erforschen (%d FP vorhanden). %s" % [t["name"], int(rp), t["desc"]]})
			break
	# Hardware
	var old := 0
	for g in gpus:
		if int(g["gen"]) < gpu_gen_now():
			old += int(g["count"])
	if old > 0:
		tips.append({"prio": 50, "icon": "emote_swirl", "tab": 2, "text": "%d deiner gemieteten GPUs sind veraltet. Gen %d hat doppelte Leistung – alte zurückgeben und neue mieten." % [old, gpu_gen_now()]})
	if year() >= 2018 and datacenters.is_empty() and gpu_count() >= 64 and money > 1000000.0:
		tips.append({"prio": 40, "icon": "emote_cash", "tab": 5, "text": "Du zahlst %s/Tag GPU-Miete. Ein eigenes Rechenzentrum (Grundstück in der Weltansicht kaufen) kostet langfristig nur ~%d %% davon." % [fmt_money(daily_gpu_cost()), int(D.UPKEEP_SHARE * 100 * 0.85)]})
	# Team & Büro
	var cap := int(office_data()["staff"])
	if staff.size() < cap and last_income > last_cost * 1.2:
		tips.append({"prio": 45, "icon": "emote_heart", "tab": 1, "text": "Platz für %d weitere Leute und du machst Gewinn – mehr Team bedeutet bessere und schnellere Modelle." % (cap - staff.size())})
	elif staff.size() >= cap and office < D.OFFICES.size() - 1 and money > float(D.OFFICES[office + 1]["cost"]) * 2.0:
		tips.append({"prio": 40, "icon": "emote_star", "tab": 5, "text": "Dein Büro ist voll. Ein Umzug (%s) bringt Platz für mehr Personal und GPUs." % D.OFFICES[office + 1]["name"]})
	# Geld arbeiten lassen
	var has_stakes := false
	for c in D.COMPANIES:
		if stake(c["id"]) > 0.0:
			has_stakes = true
	if money > 6000000.0 and not has_stakes:
		tips.append({"prio": 35, "icon": "emote_cash", "tab": 9, "text": "%s liegen ungenutzt auf dem Konto. Beteiligungen an Chip-, Cloud- oder Energiefirmen bringen Dividenden und senken deine Kosten." % fmt_money(money)})
	var power := daily_office_power() + daily_dc_cost()
	if power > 3000.0 and energy_output() <= 0.0 and year() >= 2018:
		tips.append({"prio": 38, "icon": "emote_idea", "tab": 5, "text": "Strom kostet dich %s/Tag. Ein eigener Solar- oder Windpark auf einem Grundstück deckt das größtenteils." % fmt_money(power)})
	# Konkurrenz
	if float(rival["best_q"]) > best_q * 1.15 and best_q > 0.0 and not flags.get("helix_controlled", false):
		tips.append({"prio": 30, "icon": "emote_anger", "tab": 0, "text": "Helix ist dir voraus (Qualität %.0f gegen deine %.0f). Größere Modelle, bessere Daten und mehr Forschende helfen." % [rival["best_q"], best_q]})
	tips.sort_custom(func(a, b): return int(a["prio"]) > int(b["prio"]))
	return tips


func _biggest_cost() -> Array:
	var items := [["Gehälter", daily_salaries()], ["GPU-Miete", daily_gpu_cost()], ["Rechenzentren", daily_dc_cost()]]
	items.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	return items[0]


# ---------------------------------------------------------------- Kassenbuch

## Jede Geldbewegung läuft hier durch → Finanz-Übersicht
func book(cat: String, amount: float) -> void:
	money += amount
	ledger_today[cat] = float(ledger_today.get(cat, 0.0)) + amount
	ledger_year[cat] = float(ledger_year.get(cat, 0.0)) + amount

func _close_ledger_day() -> void:
	ledger_days.append(ledger_today)
	ledger_today = {}
	if ledger_days.size() > 30:
		ledger_days.pop_front()
	if day % 7 == 0:
		money_hist.append(money)
		if money_hist.size() > 104:
			money_hist.pop_front()
	if day % 365 == 0:
		ledger_last_year = ledger_year
		ledger_year = {}

## Summe je Kategorie der letzten 30 Tage
func ledger_month() -> Dictionary:
	var out := {}
	for dd in ledger_days:
		for k in dd:
			out[k] = float(out.get(k, 0.0)) + float(dd[k])
	return out


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
