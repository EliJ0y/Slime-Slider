extends Node2D

var slimes: Array
var controlled_slime
var pick_glow_interval = 4.0

func _ready() -> void:
	slimes = $"../Slimes".get_children()
	for slime in slimes:
		var slime_button = slime.get_node("Slime Button")
		slime_button.connect("pressed", on_slime_clicked)
		slime.connect("stopped_glowing", on_slime_stopped_glowing) #gets the signal from slime.gd
	glowing_slime_cycle()

func on_slime_clicked():
	var clicked_button = get_viewport().gui_get_focus_owner()
	#need to get the parent to be able to call on_slime_selected() as the script is on the parent node
	var clicked_slime = clicked_button.get_parent()
	print("clicked: ", clicked_slime.name, " glowing: ", clicked_slime.is_glowing)
	
	#checks if slime clicked on is glowing
	if clicked_slime.is_glowing:
		print("the slime clicked is glowing")
		#if there's already a slime being controlled
		if controlled_slime != null:
			#unselect that slime
			controlled_slime.unselect_slime() 
			#the new glowing slime clicked on is now controlled
		controlled_slime = clicked_slime 
		controlled_slime.on_slime_selected()

func pick_glowing_slimes():
	#filters out the already glowing slimes
	var not_glowing_slimes = slimes.filter(func(slime): return not slime.is_glowing)
	#will only pick slimes that arent already glowing
	var slime = not_glowing_slimes.pick_random()
	slime.slime_glowing()

func glowing_slime_cycle():
	#gets called in ready and runs during the level to continually pick new glowing slimes
	while true:
		await get_tree().create_timer(pick_glow_interval).timeout
		pick_glowing_slimes()

func on_slime_stopped_glowing(slime):
	#takes control away from the glowing slime if it was being controlled
	if slime == controlled_slime:
		controlled_slime.unselect_slime()
		controlled_slime = null
