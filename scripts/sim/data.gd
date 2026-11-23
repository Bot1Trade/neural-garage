extends RefCounted
## Statische Spieldaten. Balance-Werte hier ändern, nicht in lab.gd.

const START_YEAR := 2016
const END_YEAR := 2032
const AGI_Q := 185.0
## Marktniveau (erwartete Modellqualität) am 1. Januar jedes Jahres ab 2016. Kalibriert am Balance-Bot.
const EXPECTED_BY_YEAR := [12.0, 18.0, 38.0, 62.0, 78.0, 88.0, 100.0, 115.0, 140.0, 150.0, 158.0, 165.0, 172.0, 180.0, 188.0, 196.0, 205.0, 215.0]

const MONTH_NAMES := ["Jan.", "Feb.", "März", "Apr.", "Mai", "Juni", "Juli", "Aug.", "Sep.", "Okt.", "Nov.", "Dez."]
const MONTH_DAYS_CUM := [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]

const ROLE_ORDER := ["research", "engineer", "safety", "sales"]
const ROLES := {
	"research": {"name": "Forschung", "color": Color(0.35, 0.65, 1.0), "desc": "Erzeugt Forschungspunkte und hebt die Modellqualität."},
	"engineer": {"name": "Engineering", "color": Color(1.0, 0.7, 0.25), "desc": "Macht das Training schneller (mehr Rechenleistung pro GPU)."},
	"safety": {"name": "Safety", "color": Color(0.4, 0.9, 0.5), "desc": "Senkt das Risiko neuer Modelle. Ohne Safety-Team siehst du das Risiko nicht."},
	"sales": {"name": "Vertrieb", "color": Color(0.9, 0.45, 0.85), "desc": "Mehr Umsatz aus deinen API-Produkten."},
}

const OFFICES := [
	{"name": "Garage", "staff": 4, "gpus": 8, "cost": 0.0, "desc": "Wo alles anfängt. Das WLAN reicht bis zur Hälfte."},
	{"name": "Hinterhof-Büro", "staff": 7, "gpus": 24, "cost": 120000.0, "desc": "Zwei Räume, ein Drucker, viel Hoffnung."},
	{"name": "Loft", "staff": 12, "gpus": 64, "cost": 350000.0, "desc": "Backsteinwände und ein Tischkicker. Investoren lieben es."},
	{"name": "Tech-Tower-Etage", "staff": 20, "gpus": 256, "cost": 2000000.0, "desc": "Eine ganze Etage mit Blick über die Stadt."},
	{"name": "Campus", "staff": 35, "gpus": 1024, "cost": 8000000.0, "desc": "Eigene Gebäude, eigene Kantine, eigener Ruf."},
	{"name": "Mega-Campus", "staff": 60, "gpus": 4096, "cost": 120000000.0, "desc": "Eine kleine Stadt nur für dein Labor."},
]

## Büro-Upgrades: einmal kaufen, gelten dauerhaft (auch nach Umzug)
const OFFICE_UPGRADES := [
	{"id": "coffee", "name": "Kaffeebar", "cost": 25000.0, "min_office": 1, "desc": "+10 % Forschungspunkte. Koffein ist auch eine Architektur."},
	{"id": "meeting", "name": "Konferenzräume", "cost": 200000.0, "min_office": 2, "desc": "+0,04 Modellqualität-Faktor durch bessere Abstimmung."},
	{"id": "gym", "name": "Fitness & Ruheraum", "cost": 900000.0, "min_office": 3, "desc": "Gehälter steigen halb so schnell, Abwerben wird seltener."},
	{"id": "hwlab", "name": "Hardware-Labor", "cost": 3000000.0, "min_office": 3, "desc": "+10 % Trainingsleistung auf alle GPUs."},
	{"id": "daycare", "name": "Kita", "cost": 6000000.0, "min_office": 4, "desc": "Bewerbungen sind im Schnitt eine Stufe besser."},
]

## Eigene Rechenzentren: Hardware kaufen statt mieten → nur Strom zahlen
const BUY_DAYS := 250.0          # Kaufpreis = so viele Tage Miete
const UPKEEP_SHARE := 0.12       # Strom/Wartung pro Tag = Anteil der Tagesmiete
const DATACENTERS := [
	{"id": "colo", "name": "Server-Raum (Colocation)", "slots": 512, "cost": 1500000.0, "base": 1500.0, "year": 2018, "desc": "Ein gemieteter Käfig in einem fremden Rechenzentrum."},
	{"id": "dc", "name": "Rechenzentrum", "slots": 8192, "cost": 40000000.0, "base": 25000.0, "year": 2020, "desc": "Dein eigenes Gebäude voller Server."},
	{"id": "hyper", "name": "Hyperscale-Campus", "slots": 131072, "cost": 900000000.0, "base": 350000.0, "year": 2023, "desc": "Strombedarf einer Kleinstadt. Eigener Netzanschluss."},
]
const LOCATIONS := [
	{"id": "fra", "name": "Frankfurt", "power": 1.3, "build": 1.0, "desc": "Teurer Strom, aber nah dran."},
	{"id": "tex", "name": "Texas", "power": 0.85, "build": 0.9, "desc": "Billiger Strom und Land. Heiß – Kühlung lohnt sich."},
	{"id": "isl", "name": "Island", "power": 0.55, "build": 1.3, "desc": "Geothermie und kalte Luft. Bau teurer, Betrieb sehr günstig."},
]
const DC_UPGRADES := [
	{"id": "cooling", "name": "Flüssigkühlung", "cost": 0.25, "power": 0.7, "desc": "Strom −30 %"},
	{"id": "solar", "name": "Solarpark", "cost": 0.4, "power": 0.6, "rep": 3.0, "desc": "Strom −40 %, +3 Reputation"},
	{"id": "network", "name": "Hochgeschwindigkeits-Netz", "cost": 0.3, "perf": 1.15, "desc": "+15 % Leistung in diesem Rechenzentrum"},
	{"id": "expand", "name": "Erweiterung", "cost": 0.6, "slots": 1.5, "desc": "+50 % Stellplätze"},
]

## Eigene Chips
const CHIP_BASE_COST := 15000000.0   # erstes Chip-Projekt, jedes weitere ×1,6
const CHIP_DAYS := 300.0             # Entwicklungsdauer (Engineering beschleunigt)
const CHIP_POWER := 2.2              # Leistung relativ zur Markt-GPU bei Fertigstellung (schlägt auch die nächste Generation)
const CHIP_PRICE := 0.6              # Preis relativ zur Markt-GPU (mit Fabrik: ×0,5 zusätzlich)
const FAB_COST := 1500000000.0

const FOCUS_KEYS := ["help", "code", "creative", "safety"]
## Fokus-Punkte pro Modell. Mehr in einen Bereich = weniger in die anderen. Ungenutzte Punkte kosten Qualität.
const FOCUS_BUDGET := 10
const FOCUS_NAMES := {"help": "Hilfsbereitschaft", "code": "Coding", "creative": "Kreativität", "safety": "Sicherheit"}

## Was der Markt gerade will. Der Spieler sieht nur Name + Hinweis und lernt den Rest aus den Kritiken.
const ERAS := [
	{"from": 2016, "name": "Forschungs-Ära", "ideal": {"help": 2, "code": 1, "creative": 5, "safety": 1}, "hint": "Fachleute staunen vor allem über Modelle, die überraschende Texte schreiben."},
	{"from": 2019, "name": "Text-Boom", "ideal": {"help": 4, "code": 2, "creative": 4, "safety": 1}, "hint": "Erste Firmen wollen Modelle, die wirklich bei Aufgaben helfen."},
	{"from": 2022, "name": "Chat-Ära", "ideal": {"help": 6, "code": 2, "creative": 2, "safety": 3}, "hint": "Millionen Menschen chatten mit KI. Sie wollen Hilfe – und keine Skandale."},
	{"from": 2024, "name": "Coding-Ära", "ideal": {"help": 3, "code": 6, "creative": 1, "safety": 2}, "hint": "Entwickler sind die zahlungskräftigste Kundschaft."},
	{"from": 2026, "name": "Agenten-Ära", "ideal": {"help": 3, "code": 4, "creative": 1, "safety": 5}, "hint": "Modelle handeln selbstständig. Vertrauen wird zum wichtigsten Verkaufsargument."},
]

## Modellgröße in Milliarden Parametern
const SIZES := [0.01, 0.03, 0.1, 0.3, 1.0, 3.0, 7.0, 13.0, 30.0, 70.0, 175.0, 400.0, 1000.0]

const DATA := {
	"web": {"name": "Web-Crawl", "quality": 0.0, "cost": 0.0, "risk": 1.25, "year": 2016, "desc": "Riesig und gratis – aber voller Müll und Toxizität (+Risiko)."},
	"code": {"name": "Open-Source-Code", "quality": 0.05, "cost": 0.0, "risk": 1.0, "year": 2016, "desc": "Kleiner Qualitätsbonus, stärker je höher dein Coding-Fokus."},
	"books": {"name": "Lizenzierte Bücher", "quality": 0.15, "cost": 6000.0, "risk": 0.9, "year": 2016, "desc": "Sauber und hochwertig. Kostet Lizenzgebühren."},
	"curated": {"name": "Kuratierte Daten", "quality": 0.2, "cost": 30000.0, "risk": 0.7, "year": 2019, "desc": "Von Menschen geprüft. Teuer, aber senkt das Risiko deutlich."},
	"synthetic": {"name": "Synthetische Daten", "quality": 0.15, "cost": 0.0, "risk": 1.0, "year": 2023, "needs_rating": 7.0, "desc": "Dein bestes Modell erzeugt Trainingsdaten. Braucht ein Modell mit Bewertung 7+."},
	"gray": {"name": "Graue Daten", "quality": 0.3, "cost": 0.0, "risk": 1.3, "year": 2016, "legal": true, "desc": "Raubkopierte Bücher und gescrapte Privatdaten. Stark – und illegal."},
}

const TECHS := [
	{"id": "rnn", "kind": "arch", "name": "RNN", "quality": 0.6, "eff": 1.0, "rp": 0, "year": 2016, "req": "", "desc": "Alte Schule. Vergisst nach ein paar Sätzen, worum es ging."},
	{"id": "transformer", "kind": "arch", "name": "Transformer", "quality": 1.0, "eff": 1.0, "rp": 40, "year": 2017, "req": "rnn", "desc": "Attention ist alles, was du brauchst. Großer Qualitätssprung."},
	{"id": "scaling", "kind": "arch", "name": "Skaliertes Pretraining", "quality": 1.15, "eff": 1.25, "rp": 200, "year": 2018, "req": "transformer", "desc": "Mehr Daten, mehr Parameter, effizienteres Training."},
	{"id": "interp", "kind": "safety", "name": "Interpretierbarkeit", "risk": 0.7, "rp": 200, "year": 2018, "req": "transformer", "desc": "Du verstehst, was im Modell passiert. Risiko neuer Modelle −30 %."},
	{"id": "rlhf", "kind": "arch", "name": "RLHF-Chat", "quality": 1.25, "eff": 1.25, "rp": 600, "year": 2020, "req": "scaling", "desc": "Menschliches Feedback macht Modelle hilfreich und gesprächig."},
	{"id": "moe", "kind": "arch", "name": "Mixture of Experts", "quality": 1.35, "eff": 2.0, "rp": 1400, "year": 2021, "req": "rlhf", "desc": "Nur ein Teil des Modells rechnet pro Wort. Training doppelt so effizient."},
	{"id": "constitution", "kind": "safety", "name": "Verfassungs-Training", "risk": 0.6, "rp": 1000, "year": 2021, "req": "rlhf", "desc": "Das Modell lernt Regeln statt nur Beispiele. Risiko neuer Modelle −40 %."},
	{"id": "reasoning", "kind": "arch", "name": "Reasoning", "quality": 1.55, "eff": 1.6, "rp": 3000, "year": 2023, "req": "moe", "desc": "Das Modell denkt nach, bevor es antwortet."},
	{"id": "evals", "kind": "safety", "name": "Automatische Evals", "risk": 0.7, "rp": 2000, "year": 2023, "req": "constitution", "desc": "Tausende Tests pro Nacht. Risiko neuer Modelle −30 %."},
	{"id": "chipdesign", "kind": "infra", "name": "Eigenes Chip-Design", "rp": 1500, "year": 2021, "req": "scaling", "desc": "Schaltet Chip-Projekte frei: eigene KI-Beschleuniger, stärker und günstiger als Markt-GPUs."},
	{"id": "fab", "kind": "infra", "name": "Chip-Fertigung", "rp": 4000, "year": 2024, "req": "chipdesign", "desc": "Erlaubt den Bau einer eigenen Chipfabrik: Chips noch billiger, keine Lieferengpässe."},
	{"id": "agents", "kind": "arch", "name": "Agenten", "quality": 1.75, "eff": 1.5, "rp": 6000, "year": 2025, "req": "reasoning", "desc": "Modelle planen und handeln selbst. Der Weg zur AGI."},
]

## Investoren-Runden: Reputation nötig, Geld gegen Anteile
const INVESTORS := [
	{"name": "Angel-Investorin", "rep": 0.0, "year": 2016, "money": 150000.0, "equity": 8.0},
	{"name": "Seed-Runde", "rep": 12.0, "year": 2017, "money": 700000.0, "equity": 10.0},
	{"name": "Series A", "rep": 28.0, "year": 2018, "money": 4000000.0, "equity": 15.0},
	{"name": "Series B", "rep": 45.0, "year": 2020, "money": 30000000.0, "equity": 15.0},
	{"name": "Series C", "rep": 62.0, "year": 2022, "money": 250000000.0, "equity": 12.0},
	{"name": "Series D", "rep": 78.0, "year": 2024, "money": 1500000000.0, "equity": 10.0},
]

## Gewichtung, wenn mehrere API-Modelle parallel laufen (sie kannibalisieren sich)
const STACK_WEIGHTS := [1.0, 0.35, 0.12, 0.05]

const GOALS := [
	{"id": "train1", "text": "Trainiere dein erstes Modell"},
	{"id": "release1", "text": "Veröffentliche ein Modell"},
	{"id": "staff3", "text": "Hab 3 Leute im Team"},
	{"id": "transformer", "text": "Erforsche den Transformer"},
	{"id": "rating7", "text": "Erreiche eine Bewertung von 7+"},
	{"id": "loft", "text": "Zieh in den Loft um"},
	{"id": "rev1m", "text": "Mach insgesamt 1 Mio. $ Umsatz"},
	{"id": "beat_rival", "text": "Übertriff das beste Modell von Helix Dynamics"},
	{"id": "rlhf", "text": "Erforsche RLHF-Chat"},
	{"id": "campus", "text": "Zieh auf den Campus"},
	{"id": "datacenter", "text": "Baue dein erstes eigenes Rechenzentrum"},
	{"id": "rating9", "text": "Erreiche eine Bewertung von 9+"},
	{"id": "reasoning", "text": "Erforsche Reasoning"},
	{"id": "chip", "text": "Entwickle deinen ersten eigenen Chip"},
	{"id": "agents", "text": "Erforsche Agenten"},
	{"id": "agi", "text": "Veröffentliche eine AGI (Agenten, Qualität 185+) – und zwar sicher"},
]

const OUTLETS := ["TechBlick", "Byte-Rundschau", "Der Prompt", "Netzpuls", "Silicon Sentinel", "Code & Kultur"]
const QUOTES := [
	["Ein teurer Zufallsgenerator.", "Wir haben es dreimal getestet. Es wurde nicht besser.", "Die Demo stürzte ab. Vielleicht war das gnädig."],
	["Bemüht, aber klar hinter der Konkurrenz.", "Hat Momente – sehr kurze Momente.", "Für Bastler okay, für alle anderen nicht."],
	["Solide Arbeit ohne Überraschungen.", "Macht, was es soll. Meistens.", "Kein Durchbruch, aber ein ehrlicher Schritt."],
	["Beeindruckend! Das Labor sollte man im Auge behalten.", "Wir haben die Abgabe verpasst, weil wir damit gespielt haben.", "Ein echter Konkurrent für die Großen."],
	["Ein Meilenstein. Die Branche wird darüber reden.", "So fühlt sich die Zukunft an.", "Wir mussten unsere Benchmark-Tabelle neu skalieren."],
]

const FIRST_NAMES := ["Mia", "Jonas", "Aylin", "Mateo", "Priya", "Kenji", "Lena", "Omar", "Sofia", "Lukas", "Zara", "Elif", "Noah", "Amara", "Felix", "Yuki", "Ines", "Tariq", "Nora", "Emil", "Leila", "Hugo", "Mei", "Darius", "Ronja", "Kofi", "Ana", "Viktor"]
const LAST_NAMES := ["Berg", "Okafor", "Nakamura", "Petrov", "Silva", "Kaya", "Novak", "Haddad", "Lindqvist", "Mensah", "Rossi", "Schmidt", "Chen", "Duarte", "Varga", "Ito", "Bauer", "Adeyemi", "Moreau", "Kowalski", "Ivanova", "Sato"]
