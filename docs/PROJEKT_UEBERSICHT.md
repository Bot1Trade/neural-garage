# Neural Garage – Projektübersicht (Stand: Nov. 2026)

Diese Übersicht beschreibt das Projekt so, dass eine andere KI ohne Vorwissen einsteigen kann.

## 1. Was ist das Spiel?
- **Genre:** 3D-Tycoon. Du gründest ein KI-Labor in einer Garage und baust es bis zum ersten AGI-Modell aus.
- **Vorbilder:** „AI Lab Tycoon“ (Steam), Game Dev Tycoon, Mad Games Tycoon 2, Software Inc. und Two Point Hospital/Campus. Die Ideen sind übernommen und weitergedacht, nichts ist kopiert.
- **Zeitrahmen:** 2018–2036 (`END_YEAR`).
  - **Sieg:** zuerst AGI erreichen (Modellqualität `AGI_Q = 180`).
  - **Niederlage:** Bankrott, ein Sicherheits-Gau oder der Rivale Helix erreicht AGI zuerst (etwa ab 2030).
- **Stil:** größtenteils 3D, wenig Text, Icons. Grafik, Sounds und Musik sind CC0-Assets (Kenney, OpenGameArt), siehe `CREDITS.md`.
- **Engine:** Godot 4.7.2 mit GDScript. Renderer ist Forward+ (Vulkan), mit OpenGL als Rückfall.
- **Sprache im Spiel:** Deutsch.
- **Repository:** privat auf GitHub, 19 Commits.

## 2. Spielmechaniken
| Bereich | Inhalt |
|---|---|
| **Modelle** | Modell-Designer mit 10 Fokus-Punkten (statt freier Regler). Training kostet Compute und Zeit, Datenvarianten sind wählbar. Erwartete Qualität je Jahr steht in `EXPECTED_BY_YEAR`. |
| **Beliebtheit** | Jedes Modell hat Nutzer und Marktanteil, gedeckelt bei 90 %. Grundlage ist die Attraktivität gegenüber der Konkurrenz. Einnahmen entstehen pro Nutzer (`ARPU`). Modelle verlieren ihren Wert langsam. |
| **Team** | Rollen: Forschung, Engineering, Sicherheit, Daten, Management. Jede Person hat Energie, Stimmung und Urlaub. Gehaltswünsche kommen ab und zu als Ereignis und steigen nicht ständig. Ein Manager schickt erschöpfte Leute automatisch in den Urlaub. |
| **Forschung** | Forschungsbaum mit drei Ästen: Architektur, Sicherheit, Infrastruktur. Techs werden erst zu realistischen Jahren frei, z. B. MoE 2022, Reasoning 2024, Chip-Fab 2025, Agenten 2027. |
| **Compute / Hardware** | GPUs kaufen oder mieten und wieder verkaufen. Hardware verschleißt und braucht Wartung. Laufende Kosten sind vor allem Strom. Solar, Batterie und eigene Kraftwerke (Solarpark, Windpark) senken die Stromkosten. Später kommen eigene Rechenzentren und eine eigene Chip-Fabrik dazu. |
| **Büros & Ausbau** | 6 Büro-Stufen von der Garage bis zum Campus. Upgrades: Solar, Batterie, Kaffee, Meetingraum, Gym, Hardware-Labor, Kita. Auf der Weltkarte gibt es 11 Grundstücke in drei Gebieten: Innenstadt, Industriegebiet und „Grüne Energie“. |
| **Firmenmarkt** | 8 Firmen (KI-Konkurrenz, Chiphersteller u. a.). Anteile lassen sich in 5-%-Schritten kaufen. Anteile bringen Dividenden, beim Chiphersteller zusätzlich Rabatt auf Karten. Ab 51 % hast du die Kontrolle. |
| **Übernahme-Verhandlung** | Die Gegenseite hat einen geheimen Mindestpreis und 3 Geduldspunkte. Bezahlt wird mit Bargeld und/oder eigenen Anteilen (mit Abschlag bewertet). Ein Angebot unter 75 % des Mindestpreises gilt als Beleidigung und kostet 2 Geduld. Liegt es knapp darunter, kommt ein Gegenangebot (−1 Geduld). Bei Geduld 0 ist ein Jahr Sperre, ein eigener Abbruch kostet 60 Tage. |
| **Geld** | Investoren-Roadshow, zufällige Angebote und ein Notkredit. Werbung gibt es in zwei Stufen: online und groß. Ein Kassenbuch zeigt alle Ein- und Ausgaben nach Kategorie. |
| **Hilfen** | Ein Berater gibt Tipps nach Lage. Dazu kommen 16 Ziele (in beliebiger Reihenfolge erreichbar), Ereignisse mit Entscheidungen, News und ein Tutorial. |
| **Komfort** | 3 Speicherplätze plus Autosave. Tempo: Pause, 1×, 2×, 5×. Grafik-Menü. Tasten: F5 Schnellspeichern, F11 Vollbild, Esc und Tab. |

## 3. Code-Aufbau
```
scripts/sim/data.gd     206 Z.   alle Balance-Konstanten (Rollen, Büros, Techs, Firmen, Preise …)
scripts/sim/lab.gd     1852 Z.   komplette Simulation, RefCounted, ohne UI, headless testbar
scripts/sim/bot.gd      200 Z.   Autopilot für Balance-Tests
scripts/ui/main.gd     2175 Z.   gesamte UI, im Code gebaut (HUD, Werkzeugleiste, Seitenleiste mit 11 Bereichen, Popups)
scripts/ui/office_3d.gd 1207 Z.  3D-Büro + Weltkarte, Kamera (Ziehen/Zoom/Drehen), Effekte
scripts/ui/tutorial.gd, audio.gd, settings.gd
tests/run_tests.gd               142 Unit-Tests der Simulation
tests/ui_test.gd                 Spielstände, Tempo, alle Tabs, Verhandlungsfenster
tests/camera_test.gd             Kamera bleibt nicht hängen
tests/layout_test.gd             echtes Fenster: kein Tab ist breiter als die Seitenleiste
tests/research_test.gd           echtes Fenster: Klick im Forschungsbaum
tests/balance.gd                 Bot spielt viele Runden und gibt eine Statistik aus
docs/DESIGN.md                   Design-Dokument (Abschnitte 1–18)
```
**Wichtige Regeln im Code:**
- Kein `class_name`, nur `preload`.
- Jede Geldbewegung läuft über `lab.book(kategorie, betrag)` (Kassenbuch).
- Simulation und UI reden nur über drei Wege:
  - `revision`: Zähler, nach dessen Änderung die UI neu baut
  - `event_queue` + `resolve_event()`: Ereignisse mit Entscheidungen
  - `fx`: Liste für 3D-Effekte
- Die UI ist komplett im Code gebaut, es gibt kaum `.tscn`-Szenen.

**Werkzeugleiste (11 Bereiche):**
- Modell, Team, Compute, Forschung
- Produkte, Ausbau, Firmen
- Ziele, News, Finanzen, Berater

## 4. Starten & Testen
```
spielen.cmd                                   Spiel starten
godot --headless --path . -s tests/run_tests.gd
godot --headless --path . -s tests/ui_test.gd
godot --headless --path . -s tests/camera_test.gd
godot --path . -s tests/layout_test.gd        (öffnet ein Fenster)
godot --headless --path . -s tests/balance.gd
```
Für Screenshots gibt es diese Startparameter:
- `--shot=datei.png`
- `--days=N`
- `--tab=N`
- `--world` / `--office`
- `--modal`
- `--wait=N`

## 5. Aktueller Stand
- Alle Tests sind grün: 142 Unit-Tests sowie UI-, Kamera-, Layout- und Forschungstest.
- **Balance:** Der Bot gewinnt 30 von 30 Runden, im Median 2027. Das sind etwa 40 Minuten bei 1×. Für erfahrene Spieler ist das Spiel wahrscheinlich **zu leicht**.
- **Zuletzt behoben:**
  - Verhandlungsfenster schloss nicht
  - „Produkte“-Tab war leer bzw. zu breit (jetzt Karten)
  - Forschungsklick verbreiterte die Seitenleiste
  - Kamera blieb beim Ziehen hängen

## 6. Bekannte Schwächen & offene Ideen
- **Schwierigkeit:** Spiel zu leicht. Ideen:
  - Schwierigkeitsgrade
  - stärkerer Rivale
  - teurere späte Techs
  - Regulierungs-Ereignisse
- **Code-Struktur:** `main.gd` (2175 Zeilen) und `lab.gd` (1852 Zeilen) sind groß. Sie ließen sich in mehrere Dateien aufteilen, z. B. einen UI-Builder je Tab und Simulations-Module für Personal, Markt und Firmen.
- **Inhalte:** Konkurrenz ist bisher nur als Zahlen sichtbar. Möglich wären rivalisierende Labore auf der Weltkarte, Mitarbeiter-Abwerbung und Skandale.
- **Ruhm & Langzeitmotivation:** Nach dem AGI-Sieg gibt es kein Endlosspiel und keine Achievements.
- **Spielbarkeit:** Kein Controller-Support, keine Lokalisierung (nur Deutsch).
- **Tests:** Bisher kein echter Spieltest durch Menschen. Alle Tests sind automatisch, inklusive Bot.

## 7. Arbeitsweise bisher
- **Ablauf:** Der Nutzer gibt Wünsche auf Deutsch. Claude (Claude Code) setzt sie um, testet selbst, committet und pusht.
- **Neue Features:** Erst Simulation und Unit-Tests, dann UI, dann ein Test im echten Fenster bzw. Screenshot-Prüfung.
- **Fehler:** Erst einen Test schreiben, der den Fehler zeigt, dann beheben.
