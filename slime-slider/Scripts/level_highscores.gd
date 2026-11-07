extends Node

const save_path = "user://highscores.cfg"
var level_highscores: Dictionary = {}

func _ready() -> void:
	load_highscores()

func get_highscores(level: String) -> int:
	#get the highscore for a specific level
	return level_highscores.get(level, 0)

func increase_highscore(level: String, extra_matches: int) -> bool:
	if extra_matches > get_highscores(level):
		level_highscores[level] = extra_matches
		save_highscores()
		return true
	else:
		return false

func save_highscores():
	var config_file = ConfigFile.new()
	for level in level_highscores:
		config_file.set_value("level_highscores", level, level_highscores[level])
	config_file.save(save_path)

func load_highscores():
	var config_file = ConfigFile.new()
	if config_file.load(save_path) != OK:
		return
	for level in config_file.get_section_keys("level_highscores"):
		level_highscores[level] = config_file.get_value("level_highscores", level)
