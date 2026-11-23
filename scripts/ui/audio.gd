extends Node
## Musik-Playlist + Soundeffekte. Lautstärke/Stumm in user://settings.json (getrennt vom Spielstand).
## Musik: OpenGameArt (CC0), Effekte: Kenney Interface Sounds, Digital Audio, Music Jingles (CC0).

const SETTINGS_PATH := "user://settings.json"
const MUSIC := ["res://assets/music/lofi_loop.ogg", "res://assets/music/chill_lofi.ogg", "res://assets/music/electronic_loop.ogg"]
const S := "res://assets/kenney/sounds/"
## Name → [Datei, Lautstärke in dB]
const SFX := {
	"click": ["click_002", -8.0],
	"open": ["open_001", -6.0],
	"close": ["close_001", -6.0],
	"confirm": ["confirmation_002", -4.0],
	"error": ["error_004", -4.0],
	"speed": ["switch_002", -6.0],
	"hire": ["select_003", -3.0],
	"event": ["question_001", -3.0],
	"research": ["powerUp3", -6.0],
	"build": ["powerUp7", -6.0],
	"train": ["phaserUp2", -8.0],
	"incident": ["lowDown", -2.0],
	"money": ["threeTone1", -14.0],
	"release": ["jingles_PIZZI03", -2.0],
	"goal": ["jingles_STEEL02", -4.0],
	"win": ["jingles_SAX05", -2.0],
	"lose": ["jingles_SAX09", -2.0],
}

var music_volume := 0.5
var sfx_volume := 0.8
var music_on := true
var sfx_on := true
var music_player: AudioStreamPlayer
var sfx_players: Array = []
var track := 0
var last_play := {}     # Name → Zeit, damit nichts im selben Moment doppelt spielt


func _ready() -> void:
	_ensure_bus("Music")
	_ensure_bus("SFX")
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Music"
	music_player.finished.connect(_next_track)
	add_child(music_player)
	for i in range(6):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		sfx_players.append(p)
	_load_settings()
	_apply()
	track = randi() % MUSIC.size()
	if DisplayServer.get_name() != "headless":
		_play_track()


func _exit_tree() -> void:
	music_player.stop()
	music_player.stream = null
	for p in sfx_players:
		p.stop()
		p.stream = null


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) == -1:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus_name)
		AudioServer.set_bus_send(i, "Master")


func play(sfx_name: String) -> void:
	if not sfx_on or not SFX.has(sfx_name):
		return
	var now := Time.get_ticks_msec()
	if now - int(last_play.get(sfx_name, -1000)) < 120:
		return
	last_play[sfx_name] = now
	for p in sfx_players:
		if not p.playing:
			p.stream = load(S + SFX[sfx_name][0] + ".ogg")
			p.volume_db = SFX[sfx_name][1]
			p.play()
			return


func _play_track() -> void:
	music_player.stream = load(MUSIC[track])
	music_player.volume_db = -30.0
	music_player.play()
	create_tween().tween_property(music_player, "volume_db", 0.0, 3.0)


func _next_track() -> void:
	track = (track + 1) % MUSIC.size()
	_play_track()


# ---------------------------------------------------------------- Einstellungen

func set_music(on: bool, volume: float) -> void:
	music_on = on
	music_volume = clampf(volume, 0.0, 1.0)
	_apply()
	_save_settings()


func set_sfx(on: bool, volume: float) -> void:
	sfx_on = on
	sfx_volume = clampf(volume, 0.0, 1.0)
	_apply()
	_save_settings()


func _apply() -> void:
	var mi := AudioServer.get_bus_index("Music")
	var si := AudioServer.get_bus_index("SFX")
	AudioServer.set_bus_volume_db(mi, linear_to_db(maxf(music_volume, 0.001)))
	AudioServer.set_bus_mute(mi, not music_on or music_volume <= 0.0)
	AudioServer.set_bus_volume_db(si, linear_to_db(maxf(sfx_volume, 0.001)))
	AudioServer.set_bus_mute(si, not sfx_on or sfx_volume <= 0.0)


func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	if typeof(d) != TYPE_DICTIONARY:
		return
	music_volume = float(d.get("music_volume", music_volume))
	sfx_volume = float(d.get("sfx_volume", sfx_volume))
	music_on = bool(d.get("music_on", music_on))
	sfx_on = bool(d.get("sfx_on", sfx_on))


func _save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"music_volume": music_volume, "sfx_volume": sfx_volume, "music_on": music_on, "sfx_on": sfx_on}))
