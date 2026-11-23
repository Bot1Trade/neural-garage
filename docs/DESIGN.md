# Neural Garage – Design-Dokument (Arbeitstitel)

Genre: Management-/Tycoon-Sim. Du führst ein KI-Labor von der Garage bis zur Superintelligenz (oder zum Absturz).
Engine: Godot 4.7 (GDScript), 2D-UI + isometrisches Büro. Ziel: Steam (PC).

## 1. Marktanalyse (Stand 23.11.2026)

| Spiel | Steam | Was wir lernen |
|---|---|---|
| AI Lab Tycoon (18.11.2026, 24,49 €) | 10 % positiv (19) | Thema zieht – Umsetzung scheitert |
| Game Dev Tycoon (2013, 9,49 €) | 94 % positiv (22k) | Einfacher, lesbarer Kern-Loop + klares Feedback |
| Mad Games Tycoon 2 (2023, 20,99 €) | 93 % positiv (2,2k) | Tiefe, Sandbox, bis 100 Rivalen kaufen/zerstören |
| Recursion: Alignment (kommt) | – | Ethik/Alignment als Mechanik, 8 Enden |
| LLM Tycoon (27.11.2026) | – | Weltkarte, Länder, Rival-CEOs im Social Feed |

**Warum AI Lab Tycoon schlecht bewertet wird (Reviews):**
- Nur ~3 Std. Inhalt, zweiter Durchlauf identisch → kein Wiederspielwert
- Pacing kaputt: erst zu langsam, dann alles auf einmal
- „Komplexer Idler“: Entscheidungen ohne Tiefe, schlechte Erklärungen
- Eindruck von „AI slop“ (generische Assets/Texte) – im KI-Thema doppelt schädlich
- Preis passt nicht zum Umfang, Freezes

**Warum die Vorbilder funktionieren:**
- Game Dev Tycoon: Ein Kern-Loop (Spiel entwerfen → Bewertung), den man *lernt*. Spieler entdeckt Kombinationen selbst. Historie-Parodie mit Wiedererkennung.
- Mad Games Tycoon 2: Viele Systeme, die ineinandergreifen, Rivalen mit Gewicht, Sandbox + Startjahr wählbar.
- Two Point Hospital/Parkitect: Humor, sichtbares Gewusel im Gebäude, viele kleine Ziele.

## 2. Design-Säulen

1. **Modelle entwerfen ist der Kern** – wie Spiele-Design in GDT, aber tiefer: Daten-Mix, Architektur, Größe, Trainingsdauer, Safety-Budget. Ergebnis = Benchmarks + öffentliche Reaktion. Gute Kombis sind lernbar, nicht zufällig.
2. **Ethik hat echte Folgen** – Abkürzungen (schmutzige Daten, Safety streichen, Benchmarks schönen) bringen kurzfristig Geld, bauen aber versteckt „Risiko“ auf → Skandale, Regulierung, misaligned Ende.
3. **Jeder Run anders** – Gründer-Traits, zufällige Welt-Events, Rivalen mit Persönlichkeit, wählbares Startjahr, mehrere Enden (Roguelite-Prinzip in einer Tycoon-Hülle).
4. **Pacing als Feature** – alle 10–15 Min. ein Meilenstein, neue Mechanik wird einzeln eingeführt und erklärt. Zielspielzeit: 15–25 Std. pro Kampagne + Sandbox.
5. **Handgemacht wirken** – einheitlicher Stil (CC0-Basis-Assets + eigene Anpassung), Texte mit Humor und Satire, keine generischen Platzhalter im Release.

## 3. Kern-Loop

```
Geld/Investoren → Compute + Team kaufen → Modell entwerfen & trainieren
      ↑                                            ↓
 Reputation  ←  Produkt/API launchen  ←  Evaluieren (Benchmarks, Red-Teaming)
```

Pro Modell wählt der Spieler:
- **Daten**: Web, Code, Bücher, Lizenzdaten, synthetisch (Kosten vs. Qualität vs. Rechtsrisiko)
- **Architektur** (per Forschung freigeschaltet): Transformer, MoE, Reasoning, Multimodal …
- **Größe & Trainingszeit**: Compute-Budget, Skalierungsgesetz als lernbare Kurve
- **Fokus-Regler** (wie GDT-Slider): Hilfsbereitschaft, Sicherheit, Kreativität, Coding, Geschwindigkeit
- **Safety-Budget**: Red-Teaming, Evals – senkt Risiko, kostet Zeit

## 4. Systeme (Ausbaustufen)

**MVP (Vertical Slice, ~1 Std. spielbar)**
- Garage → Büro 1, 3–6 Mitarbeiter (Rollen: Forscher, Engineer, Safety, Sales)
- Modell-Designer + Training + Bewertungs-Screen
- Geld, Compute (GPU-Miete), Reputation, verstecktes Risiko
- 1 Rivale, 5 Events, 1 Ende
- Speichern/Laden

**Version 0.2**
- Tech-Tree (Forschung), Büro-Ausbau isometrisch, Mitarbeiter mit Traits/Burnout
- Investoren-Runden (Equity verwässert, Board stellt Forderungen)
- Produkte: Chat-App, API, Enterprise-Deals, Open-Source-Release
- 3–5 Rivalen mit KI-Persönlichkeit, News-Feed + Social-Feed

**Version 0.3+**
- Rechenzentren bauen (Strom, Kühlung, Standort), Chip-Knappheit
- Regulierung/Politik je Region, Spionage & Abwerben
- Gründer-Traits, Startjahr wählbar, 6+ Enden, Sandbox, Steam-Achievements, Mod-Support

## 5. Was wir besser machen als AI Lab Tycoon

| Problem dort | Unsere Lösung |
|---|---|
| 3 Std. Inhalt | Ausbaustufen bis 20 Std., Sandbox, Enden, zufällige Runs |
| Pacing-Sprünge | Meilensteinkurve, Kosten skalieren mit, Tests für die Balance |
| Keine Tiefe | Modell-Designer mit lernbaren Kombinationen, Trade-offs überall |
| Schlechte Erklärung | Kontext-Tooltips, Tutorial pro neuer Mechanik, Bewertungsbericht mit Begründung |
| „AI slop“-Eindruck | Einheitlicher Stil, eigene Texte, Credits offen |
| Preis vs. Umfang | Early Access mit fairem Preis (~10–15 €), Demo zum Next Fest |

## 6. Technik

- Godot 4.7, GDScript, GL-Compatibility-Renderer (läuft auf schwachen PCs)
- Simulation in reinen Datenklassen (`scripts/sim/`), UI getrennt → headless testbar
- Tests: GUT (Godot Unit Test), Balance-Skript simuliert 100 Runs automatisch
- Steam-Anbindung später über GodotSteam
- Assets: Kenney.nl (CC0, UI + isometrische Möbel), Quaternius/Poly Haven (CC0), alles in `CREDITS.md`

## 7. Offene Fragen

- Finaler Name (Markenprüfung auf Steam nötig)
- Ton: eher satirisch (Two Point) oder ernster (Recursion)? Vorschlag: satirisch mit ernstem Kern
- Echte Firmennamen/Personen: **nein**, nur Parodien ohne erkennbare Marken

## 8. Stand MVP (23.11.2026)

**Fertig und getestet**
- Modell-Designer: Architektur, Größe (10M–1T), Datenquellen, 4 Fokus-Regler, Evaluierungstage → Qualität, Trainingsdauer, Kosten, Risiko
- Veröffentlichen als Paper / API / Open Weights, Kritiken mit Feedback zum Zeitgeist (5 Markt-Ären, lernbar)
- Team mit 4 Rollen und Können, Bewerbungen jeden Monat, 4 Büros, GPU-Miete mit 6 Generationen
- 10 Techs (7 Architektur, 3 Sicherheit), Forschungspunkte
- Verstecktes Risiko → Vorfälle, Katastrophe. Nur mit Safety-Team sichtbar.
- Rivale Helix Dynamics, 6 Investoren-Runden + Notfinanzierung, 9 Ereignisse mit Entscheidungen (graue Daten, Journalistin, Klage, Abwerben, Benchmark-Trick, Anhörung, Jailbreak, GPU-Knappheit, Notkredit)
- 14 Ziele als Pacing-Leitfaden, 6 Enden (sichere AGI, misaligned AGI, Katastrophe, Helix zuerst, Pleite, Übernahme 2032)
- Speichern/Laden + Autosave alle 90 Tage, Tempo 1x/2x/4x, Leertaste = Pause
- 27 Unit-Tests, Balance-Bot (30 Runs: Experte gewinnt ~2025, ~33 Min. reine Spielzeit bei 1x)

**Bekannte Lücken / nächste Schritte**
- ~~Kein Tutorial~~ → geführtes Tutorial in 9 Schritten (erledigt)
- ~~Produkte-Liste zu lang~~ → alte zurückgezogene Modelle eingeklappt (erledigt)
- ~~Platzhalter-Büro~~ → 3D-Büro (isometrisch) mit Kenney-Möbeln + Figuren, sitzend animiert, jubeln bei Releases (erledigt)
- Figuren laufen nicht herum (nur sitzen/jubeln), keine Kaffeepausen
- Kein Sound
- Nur 1 Rivale, keine Gründer-Traits, kein Startjahr wählbar (→ Version 0.2/0.3)
- Balance mit echten Spielern prüfen. Der Bot kennt den Zeitgeist, Menschen lernen ihn erst.

## 9. Ausbau-System (23.11.2026)

**Büros:** 6 Stufen (Garage → Hinterhof-Büro → Loft → Tech-Tower-Etage → Campus → Mega-Campus). Kaufen im Tab „Ausbau“, auch mit Sprüngen. Bestimmen Teamgröße und Platz für gemietete GPUs.

**Büro-Ausstattung** (einmal kaufen, gilt dauerhaft, im 3D-Büro sichtbar):
Kaffeebar (+10 % Forschung) · Konferenzräume (+Qualität) · Fitness & Ruheraum (Gehälter steigen langsamer, weniger Abwerben) · Hardware-Labor (+10 % Training) · Kita (bessere Bewerbungen)

**Eigene Rechenzentren** (ab 2018): Colocation (512 Plätze) → Rechenzentrum (8.192, ab 2020) → Hyperscale (131.072, ab 2023).
- Standorte: Frankfurt (teurer Strom), Texas (günstig), Island (sehr günstiger Strom, teurer Bau)
- Hardware kaufen statt mieten: einmalig ~250 Tage Miete, danach 12 % der Miete als Strom/Wartung × Standort
- Upgrades je Rechenzentrum: Flüssigkühlung (−30 % Strom), Solarpark (−40 %, +Ruf), Netz (+15 % Leistung), Erweiterung (+50 % Plätze)
- Gekaufte GPUs veralten → Verschrotten und neu kaufen ist eine echte Abwägung

**Eigene Chips:** Forschung „Eigenes Chip-Design“ (2021) → Chip-Projekte (15 Mio. $, ×1,6 pro Version, ~300 Tage, Engineering beschleunigt). Ergebnis: NG-x mit 2,2× der Leistung der Markt-GPU zu 60 % des Preises. „Chip-Fertigung“ (2024) → eigene Fabrik (1,5 Mrd. $): Chips halb so teuer, keine GPU-Knappheit.

**Balance (Bot, 30 Runs):** 22 sichere AGI, 5 Mal Helix schneller, 3 Mal pleite. Große Infrastruktur-Investitionen sind ein echtes Risiko.

## 10. 3D-First-Oberfläche (23.11.2026)

- Das 3D-Büro füllt den ganzen Bildschirm. Kamera: Mausrad = Zoom, rechte Maus/Q/E = drehen, ziehen = verschieben. Wände vor der Kamera blenden sich aus.
- **Weltansicht** (Tab-Taste oder Lupe): Dein Labor als Gebäude (wächst mit der Büro-Stufe), jedes Rechenzentrum als eigenes Gebäude, Chipfabrik, Helix-Hochhaus (wächst mit jedem Helix-Modell), Straßen und Stadt drumherum.
- **Wenig Text:** Die obere Leiste zeigt nur Icons und Zahlen (Details im Tooltip). Unten gibt es eine Icon-Leiste. Details öffnen sich nur bei Klick als Seitenleiste (Esc schließt). Das aktuelle Ziel steht als Pille oben. Neuigkeiten erscheinen kurz als Meldung unten links.
- **3D-Feedback:** Geld-Symbole steigen aus den Servern auf, wenn du Gewinn machst. Bei Training erscheinen Denkblasen, bei Forschung Glühbirnen, bei Zielen Sterne, bei Vorfällen traurige Gesichter. Bei Releases jubelt das Team.
- Alle Grafiken stammen aus fertigen Kenney-Paketen (CC0), siehe CREDITS.md.

## 11. Sound & Musik (23.11.2026)

- **Musik:** Playlist aus 3 CC0-Stücken (Lofi, Chill-Lofi, Elektro), läuft nacheinander mit Einblendung. Startet bei einem zufälligen Stück.
- **Effekte** (Kenney, CC0): Klick, Seitenleiste auf/zu, Bestätigung/Fehler bei Aktionen, Tempo-Wechsel, Ereignis-Popup, Training-Start, Einstellung (Herz), Forschung (Power-up), Bau (Power-up), Vorfall (tiefer Ton), Geld (leiser Ton alle ~6 s bei Gewinn), Release- und Ziel-Jingles, Sieg-/Niederlage-Jingle.
- **Lautstärke:** Noten-Symbol oben rechts → zwei Regler (Musik, Effekte). Gespeichert in `user://settings.json`, getrennt vom Spielstand. Eigene Audio-Busse „Music“ und „SFX“.

## 12. Grafik-Update (23.11.2026)

- Renderer: Forward+ (Vulkan) mit automatischem Rückfall auf OpenGL. Himmel-Verlauf, SSAO, Glow, AgX-Tonemapping, weichere Schatten.
- Büro: steht auf einem Gelände (Garage = Einfahrt mit Auto, Tech-Tower = Dachterrasse, sonst Rasen mit Bäumen hinter den Wänden und Blumen davor). Boden im Schachbrett, warme Raumlichter, leuchtende Monitore.
- Leben: Mit Kaffeebar holen sich Leute regelmäßig Kaffee (laufen über den Gang und zurück).
- Welt: ~60 Bäume und Pflanzen, 12 Autos fahren rechts auf den Straßen.
- Deko-Update: Kleinkram auf Schreibtischen, Wandverkleidung und gerahmte Bilder, Garderobe, Regale, Kühlschrank, Serverecke mit Doppelboden und Racks mit LED-Matrix. Eine Belegungskarte (0,5-m-Raster) füllt freie Flächen automatisch mit Besprechungsecke, Lounge-Sesseln und Pflanzen. Tilt-Shift-Unschärfe (Miniatur-Look). Welt mit Park, Parkplatz und Skyline.

## 13. Auflösung & Layout (23.11.2026)

- 3D wird direkt im Hauptfenster gerendert (native Auflösung, z. B. 2560×1440) statt in einem 1600×900-Zwischenbild.
- Fenster startet maximiert, Seitenverhältnis frei (`stretch/aspect = expand`). UI skaliert mit, Schrift bleibt scharf.
- Tutorial oben links (kollidiert nicht mehr mit der Seitenleiste), lange Texte in der Seitenleiste brechen um. Bei offener Seitenleiste rückt die Kamera nach links.
- Grafik-Menü (Zahnrad oben rechts, gespeichert in `user://settings.json`): Kantenglättung bis 8×, Render-Auflösung 75–200 % (Supersampling), Schatten Mittel/Hoch/Ultra, Tilt-Shift an/aus, Vollbild (F11).
