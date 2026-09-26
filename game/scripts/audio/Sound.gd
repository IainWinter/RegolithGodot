extends Node

# the Sound autoload, the port of the FMOD AudioManager and the PlaySoundEvent
# / StopSoundEvent bus of the original. sounds are named after the old event
# paths (event:/player_low_core -> player_low_core) and looked up in STREAMS,
# a small pool of AudioStreamPlayers plays effects, one more plays music.
# runs while the tree is paused so the dead song carries on under the death
# menu. files live in res://game/sounds, brought over from the old FMOD
# sources (Research/Regolith/game/assets/Sounds and IwEngine/_assets/audio)

const STREAMS := {
	# the alarm that loops while the player is a cloud, sound/player_low_core
	&"player_low_core": "res://game/sounds/player_low_core.wav",
	# the dead song, sound/music/level_fail, played on the death transition
	&"music_level_fail": "res://game/sounds/music_level_fail.ogg",
	# sound/item_pickup/health, played when a core rebuilds the cloud
	&"pickup_health": "res://game/sounds/pickup_health.wav",
	# sound/item_pickup/regolith
	&"pickup_regolith": "res://game/sounds/pickup_regolith.wav",
	# sound/guns/asteroids_laser and the minigun
	&"shoot_laser": "res://game/sounds/shoot_laser.wav",
	&"gun_minigun": "res://game/sounds/gun_minigun.wav",
	&"hit_laser": "res://game/sounds/hit_laser.wav",
	&"explosion": "res://game/sounds/explosion.wav",
	# sound/ui/click and sound/ui/hover, menus
	&"ui_click": "res://game/sounds/ui_click.wav",
	# the old ui/pause_menu_slide + pause_menu_thump exist only inside the
	# FMOD bank, no source file was found, the click stands in for now
	&"ui_pause": "res://game/sounds/ui_click.wav",
	&"ui_hover": "res://game/sounds/ui_hover.wav",
}

const POOL_SIZE := 8
# game sounds go through World, which the pause slide closes with a low pass
# (the underwater), menu sounds through Menu and stay clear. both feed Master
const WORLD_BUS := &"World"
const MENU_BUS := &"Menu"
const MENU_SOUNDS: Array[StringName] = [&"ui_click", &"ui_hover", &"ui_pause"]
# the low pass fully open, and fully under water
const CUTOFF_OPEN := 20500.0
const CUTOFF_UNDERWATER := 600.0
const UNDERWATER_VOLUME_DB := -6.0

# 0 = dry, 1 = fully under water: the World bus low pass cutoff and volume
var underwater := 0.0:
	set(value):
		underwater = clampf(value, 0.0, 1.0)
		apply_underwater()

var lowpass: AudioEffectLowPassFilter

var players: Array[AudioStreamPlayer] = []
var music_player: AudioStreamPlayer
var streams := {}

# what is on, for tests and for whoever wants to know without a handle
var music_name := &""
var last_played := &""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	make_buses()

	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = WORLD_BUS
		player.finished.connect(on_finished.bind(player))
		add_child(player)
		players.append(player)

	music_player = AudioStreamPlayer.new()
	music_player.bus = WORLD_BUS
	music_player.finished.connect(on_music_finished)
	add_child(music_player)

# the two buses under Master, made once per process
func make_buses() -> void:
	for bus_name in [WORLD_BUS, MENU_BUS]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var index := AudioServer.get_bus_count() - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, &"Master")

	var world := AudioServer.get_bus_index(WORLD_BUS)
	lowpass = null

	for i in AudioServer.get_bus_effect_count(world):
		if AudioServer.get_bus_effect(world, i) is AudioEffectLowPassFilter:
			lowpass = AudioServer.get_bus_effect(world, i)

	if lowpass == null:
		lowpass = AudioEffectLowPassFilter.new()
		lowpass.cutoff_hz = CUTOFF_OPEN
		AudioServer.add_bus_effect(world, lowpass)

	apply_underwater()

func apply_underwater() -> void:
	if lowpass == null:
		return

	lowpass.cutoff_hz = lerpf(CUTOFF_OPEN, CUTOFF_UNDERWATER, underwater)
	var world := AudioServer.get_bus_index(WORLD_BUS)

	if world != -1:
		AudioServer.set_bus_volume_db(world, lerpf(0.0, UNDERWATER_VOLUME_DB, underwater))

func bus_for(sound: StringName) -> StringName:
	return MENU_BUS if sound in MENU_SOUNDS else WORLD_BUS

func has(sound: StringName) -> bool:
	return STREAMS.has(sound)

func stream(sound: StringName) -> AudioStream:
	if streams.has(sound):
		return streams[sound]

	if not STREAMS.has(sound):
		push_warning("Sound: no stream named %s" % sound)
		return null

	var loaded: AudioStream = load(STREAMS[sound])

	if loaded == null:
		push_warning("Sound: could not load %s" % STREAMS[sound])

	streams[sound] = loaded
	return loaded

# plays an effect on a free pool player (the oldest one when all are busy)
# and returns it. loop keeps it going until stop(sound)
func play(sound: StringName, loop := false, volume_db := 0.0) -> AudioStreamPlayer:
	var loaded := stream(sound)

	if loaded == null:
		return null

	var player := free_player()
	player.bus = bus_for(sound)
	player.stream = loaded
	player.volume_db = volume_db
	player.set_meta(&"sound", sound)
	player.set_meta(&"loop", loop)
	player.play()
	last_played = sound
	return player

func stop(sound: StringName) -> void:
	for player in players:
		if player.get_meta(&"sound", &"") == sound:
			player.set_meta(&"loop", false)
			player.stop()
			player.set_meta(&"sound", &"")

func stop_all() -> void:
	for player in players:
		player.set_meta(&"loop", false)
		player.stop()
		player.set_meta(&"sound", &"")

	stop_music()

func is_playing(sound: StringName) -> bool:
	if music_name == sound and music_player.playing:
		return true

	for player in players:
		if player.playing and player.get_meta(&"sound", &"") == sound:
			return true

	return false

# one song at a time, replacing whatever was on
func music(sound: StringName, loop := true, volume_db := 0.0) -> void:
	var loaded := stream(sound)

	if loaded == null:
		return

	music_player.stream = loaded
	music_player.volume_db = volume_db
	music_player.set_meta(&"loop", loop)
	music_name = sound
	music_player.play()

func stop_music() -> void:
	music_player.set_meta(&"loop", false)
	music_player.stop()
	music_name = &""

func free_player() -> AudioStreamPlayer:
	for player in players:
		if not player.playing:
			return player

	# all busy: steal the one that has been going the longest
	var oldest := players[0]

	for player in players:
		if player.get_playback_position() > oldest.get_playback_position():
			oldest = player

	oldest.set_meta(&"loop", false)
	oldest.stop()
	return oldest

func on_finished(player: AudioStreamPlayer) -> void:
	if player.get_meta(&"loop", false):
		player.play()
	else:
		player.set_meta(&"sound", &"")

func on_music_finished() -> void:
	if music_player.get_meta(&"loop", false):
		music_player.play()
	else:
		music_name = &""
