extends Node2D

@onready var win_lose_text: Label = $"Win_Lose Text"
@onready var retry_button: Button = $"Retry Button"
@onready var next_level_button: Button = $"Next Level Button"
@onready var highscore_text: Label = $Highscore


var next_level_path: String

func _ready() -> void:
	visible = false
	var game_manager = $"../Game Manager"
	game_manager.connect("level_won", level_won)
	game_manager.connect("level_lost", level_lost)

func level_won(path: String, extra_matches: int, highscore: int, new_highscore: bool):
	visible = true
	win_lose_text.text = "YOU WIN!"
	var level = get_tree().current_scene.scene_file_path.get_file().get_basename()
	
	if new_highscore:
		highscore_text.text = "NEW HIGHSCORE!\nHighscore: " + str(LevelHighscores.get_highscores(level))
	else:
		highscore_text.text = "Highscore: " + str(LevelHighscores.get_highscores(level))
		
	next_level_path = path
	if not path.is_empty():
		next_level_button.visible = true

func level_lost():
	visible = true
	win_lose_text.text = "GAME OVER!"
	next_level_button.visible = false

func _on_retry_button_pressed() -> void:
	get_tree().reload_current_scene()

func _on_next_level_button_pressed() -> void:
	if next_level_path.is_empty():
		return
	else: 
		get_tree().change_scene_to_file(next_level_path) 
