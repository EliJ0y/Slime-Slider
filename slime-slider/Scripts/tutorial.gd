extends Node2D

@onready var tutorial_text: Label = $"CanvasLayer/Tutorial Text"
@onready var slime_5: CharacterBody2D = $Slimes/Slime5

var controlled_slime

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	slime_5.get_node("Slime Button").pressed.connect(on_slime_clicked)
	make_slime_glow()
	await get_tree().create_timer(1.5).timeout
	tutorial_text.visible = true
	tutorial_text.text = "Hey, look! A \n slime is glowing!"
	await get_tree().create_timer(2.0).timeout
	update_tutorial_text()

func update_tutorial_text():
	tutorial_text.text = "Click on it"
	await get_tree().create_timer(1.5).timeout
	tutorial_text.text = "Move the slime \n to make a match"

func make_slime_glow():
	await get_tree().create_timer(1.5).timeout
	slime_5.glow_time = 9999
	slime_5.slime_glowing()


func on_slime_clicked():
	var clicked_button = get_viewport().gui_get_focus_owner()
	#need to get the parent to be able to call on_slime_selected() as the script is on the parent node
	var clicked_slime = clicked_button.get_parent()
	
	#checks if slime clicked on is glowing
	if clicked_slime.is_glowing:
		#if there's already a slime being controlled
		if controlled_slime != null:
			#unselect that slime
			controlled_slime.unselect_slime() 
		#the new glowing slime clicked on is now controlled
		controlled_slime = clicked_slime 
		controlled_slime.on_slime_selected()
