extends SceneTree
## Ein Bot-Run mit Forschungs-Diagnose pro Jahr.
const Lab = preload("res://scripts/sim/lab.gd")
const Bot = preload("res://scripts/sim/bot.gd")
func _init() -> void:
	var lab := Lab.new()
	lab.setup(1000)
	while lab.ending.is_empty() and lab.day < 365 * 14:
		lab.step_day()
		while not lab.event_queue.is_empty():
			lab.resolve_event(Bot.choose(lab))
		if lab.day % 7 == 0:
			Bot.manage(lab)
		if lab.day % 365 == 0:
			var roles := {}
			var en := 0.0
			for p in lab.staff:
				roles[p["role"]] = int(roles.get(p["role"], 0)) + 1
				en += float(p.get("energy", 100))
			print("%d Modelle %d | Training %s | Geld %s | Leistung %.0f | Q %.0f" % [lab.year(), lab.models.size(), ("%s %s %.0f/%.0f Tage-rest %.0f" % [lab.training["design"]["arch"], lab.training["phase"], lab.training["progress"], lab.training["gpu_days"], lab.training_days_left()]) if not lab.training.is_empty() else "-", lab.fmt_money(lab.money), lab.compute_power(), lab.best_q])
	print("Ende: ", lab.ending.get("id", "-"), " ", lab.date_string())
	quit()
