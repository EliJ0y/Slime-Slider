extends Node2D

@export var level_settings: levels_resource
@onready var slimes_parent_node: Node = $"../Slimes"
var slime = preload("res://Scenes/slime.tscn")

var slimes: Array
var controlled_slime
var general_matches_made

func _ready() -> void:
	$"../CanvasLayer/Time Left Value".text = str(level_settings.level_time)
	spawn_slimes()
	slimes = $"../Slimes".get_children()
	for slime in slimes:
		var slime_button = slime.get_node("Slime Button")
		slime_button.connect("pressed", on_slime_clicked)
		slime.connect("stopped_glowing", on_slime_stopped_glowing) #gets the signal from slime.gd
		slime.glow_time = level_settings.glow_time

	await get_tree().create_timer(1.0).timeout
	pick_glowing_slimes()
	glowing_slime_cycle()

func _process(delta: float) -> void:
	if level_settings.level_time > 0:
		level_settings.level_time -= delta
		$"../CanvasLayer/Time Left Value".text = str(roundi(level_settings.level_time))
	win_or_lose()

func spawn_slimes():
	for x in range(160, 417, 64):
		for y in range(368, 689, 64):
			var spawned_slime = slime.instantiate()
			spawned_slime.position = Vector2(x, y)
			spawned_slime.slime_colour = randi_range(0, 2)
			slimes_parent_node.add_child(spawned_slime)

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

func pick_glowing_slimes():
	#filters out the already glowing slimes
	var not_glowing_slimes = slimes.filter(func(slime): return not slime.is_glowing)
	#will only pick slimes that arent already glowing
	var slime = not_glowing_slimes.pick_random()
	slime.slime_glowing()

func glowing_slime_cycle():
	#gets called in ready and runs during the level to continually pick new glowing slimes
	while level_settings.level_time > 4:
		await get_tree().create_timer(level_settings.pick_glow_interval).timeout
		pick_glowing_slimes()

func on_slime_stopped_glowing(slime):
	#takes control away from the glowing slime if it was being controlled
	if slime == controlled_slime:
		controlled_slime.unselect_slime()
		controlled_slime = null

func win_or_lose():
	if level_settings.level_time <= 0:
		#if general_matches_made >= level_settings.general_matches:
			$"../You Win Screen".visible = true
		#else:
			#$"../Game Over Screen".visible = true
