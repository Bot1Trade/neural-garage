# Neural Garage – Projektregeln

KI-Labor-Tycoon in Godot 4.7 (GDScript). Design: `docs/DESIGN.md` (zuerst lesen, bei Änderungen aktuell halten).

## Aufbau
- `scripts/sim/data.gd` – alle Balance-Werte (Techs, Daten, Büros, Investoren, Markt-Kurve `EXPECTED_BY_YEAR`, Ziele, Texte)
- `scripts/sim/lab.gd` – komplette Simulation (kein Node, headless testbar). UI ruft `step_day()` und arbeitet `event_queue` mit `resolve_event()` ab.
- `scripts/sim/bot.gd` – Autopilot (Balance-Test + Screenshot-Modus)
- `scripts/ui/audio.gd` – Musik-Playlist + Effekte (`audio.play("name")`, Namen in `SFX`)
- `scripts/ui/main.gd` – ganze UI im Code gebaut; `scripts/ui/office_3d.gd` – Vollbild-3D: Büro + Weltansicht, Kamera, Effekte aus `lab.fx`; `scripts/ui/tutorial.gd` – Tutorial (Schritt in `lab.flags.tut`)
- UI-Prinzip: 3D zuerst, wenig Text. Neue Infos als Icon/3D-Effekt, Details nur in der Seitenleiste. Fertige CC0-Assets (Kenney) statt selbst bauen.
- Geld nur über `lab.book(kategorie, betrag)` ändern (Kassenbuch/Finanz-Übersicht, Test prüft Vollständigkeit). Tipps in `lab.advice()`.
- Keine `class_name`, nur `preload` → kein Import-Cache-Problem bei neuen Dateien.

## Befehle (`G` = `$LOCALAPPDATA/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe`)
- Tests: `"$G" --headless --path . -s tests/run_tests.gd` → muss „0 fehlgeschlagen“ zeigen
- Balance: `"$G" --headless --path . -s tests/balance.gd -- 30 v` → Enden + Median-Jahr je Ziel
- Kamera-Eingabe: `"$G" --headless --path . -s tests/camera_test.gd` (simuliert Maus/Tasten)
- Smoke: `"$G" --headless --path . --quit-after 300` → keine `SCRIPT ERROR`
- Screenshot: `"$G" --path . -- --shot=<scratchpad>/x.png --days=1500 --tab=0 [--modal] [--tut=N] [--office]` (Seitenleiste: 0 Modell, 1 Team, 2 Compute, 3 Forschung, 4 Produkte, 5 Ausbau, 6 Ziele, 7 News, 8 Finanzen, 9 Berater; ohne --tab bleibt sie zu; `--world` = Weltansicht; `--scroll=N` scrollt; `--wait=S` wartet S Sekunden vor dem Bild (Animationen); `--office` = nur 3D-Büro groß), danach PNG ansehen
- Modellgrößen/Animationen: `"$G" --headless --path . -s tools/inspect_models.gd`
- Spielen: `spielen.cmd`

## Arbeitsweise
- Nach jeder Änderung: Tests + Smoke; bei UI-Änderungen Screenshot ansehen; bei Balance-Änderungen Balance-Lauf.
- Balance-Ziel: Bot (Experte) gewinnt um 2025–2026, Bewertungen mittendrin meist 5–8, nicht dauerhaft 10.
- Godot-API über context7 prüfen (Godot 4.x). Typinferenz: `var x: Typ = dict[...]` statt `:=` bei Variant-Werten.

## Assets
- Nur CC0 oder klar freie Lizenz (Kenney, Quaternius, Poly Haven, OpenGameArt mit Lizenzcheck).
- Jedes Asset sofort in `CREDITS.md`. Downloads nach `assets/<quelle>/`. Vor Downloads den Nutzer fragen.
- Keine echten Firmen, Marken oder Personen im Spiel.
