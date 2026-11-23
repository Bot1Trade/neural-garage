extends RefCounted
## Gemeinsame Einstellungsdatei (Audio + Grafik). Jeder Teil schreibt nur seine Schlüssel.

const PATH := "user://settings.json"


static func load_all() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return d if typeof(d) == TYPE_DICTIONARY else {}


static func save_keys(values: Dictionary) -> void:
	var d := load_all()
	d.merge(values, true)
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d, "\t"))
