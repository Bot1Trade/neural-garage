extends SceneTree
## Balance-Bot: spielt N Runs automatisch und misst das Pacing.
## godot --headless --path . -s tests/balance.gd -- [runs] [verbose]

const Lab = preload("res://scripts/sim/lab.gd")
const D = preload("res://scripts/sim/data.gd")
const Bot = preload("res://scripts/sim/bot.gd")

## Echtzeit bei 1x-Tempo (muss zu SPEEDS[1] in scripts/ui/main.gd passen)
const SEC_PER_DAY := 0.6

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var runs := int(args[0]) if args.size() > 0 else 20
	var verbose := args.size() > 1
	var goal_days := {}
	var endings := {}
	var end_years := []
	for r in range(runs):
		var lab := play(1000 + r)
		var e: String = lab.ending.get("id", "none")
		endings[e] = int(endings.get(e, 0)) + 1
		end_years.append(lab.year())
		if verbose and r < 3:
			print("Run %d: %s %s | Geld %s | Rep %.0f | Anteile %.0f%% | bestQ %.0f" % [r, e, lab.date_string(), lab.fmt_money(lab.money), lab.reputation, lab.equity, lab.best_q])
			for y in lab.get_meta("snap", []):
				print("   ", y)
		var gd: Dictionary = lab.get_meta("goal_days", {})
		for g in gd:
			if not goal_days.has(g):
				goal_days[g] = []
			goal_days[g].append(gd[g])
	print("=== %d Runs ===" % runs)
	print("Enden: ", endings)
	end_years.sort()
	print("End-Jahr Median: ", end_years[end_years.size() / 2])
	print("Ziel                                   | erreicht | Median-Jahr | Median-Min (1x)")
	for g in D.GOALS:
		var arr: Array = goal_days.get(g["id"], [])
		if arr.is_empty():
			print("%-38s |   0/%d" % [g["text"].left(38), runs])
			continue
		arr.sort()
		var med: int = arr[arr.size() / 2]
		print("%-38s | %3d/%d   | %.1f      | %.0f" % [g["text"].left(38), arr.size(), runs, 2016 + med / 365.0, med * SEC_PER_DAY / 60.0])
	quit()

func play(seed_value: int) -> RefCounted:
	var lab := Lab.new()
	lab.setup(seed_value)
	var goal_days := {}
	var snaps := []
	while lab.ending.is_empty() and lab.day < 365 * 17:
		lab.step_day()
		while not lab.event_queue.is_empty():
			lab.resolve_event(Bot.choose(lab))
		if lab.day % 7 == 0:
			Bot.manage(lab)
		if lab.day % 365 == 0:
			snaps.append("%d: Geld %s, +%s/-%s pro Tag, Rep %.0f, bestQ %.0f/erw %.0f, Büro %d, Team %d, GPUs %d" % [lab.year(), lab.fmt_money(lab.money), lab.fmt_money(lab.last_income), lab.fmt_money(lab.last_cost), lab.reputation, lab.best_q, lab.expected_quality(), lab.office, lab.staff.size(), lab.gpu_count()])
		for gid in lab.flags.get("goals", {}):
			if not goal_days.has(gid):
				goal_days[gid] = lab.day
	if lab.ending.get("id", "") == "aligned":
		goal_days["agi"] = lab.day
	lab.set_meta("goal_days", goal_days)
	lab.set_meta("snap", snaps)
	return lab
