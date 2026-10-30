extends Node2D

@export var level_settings: levels_resource
@onready var slimes_parent_node: Node = $"../Slimes"
var slime_prefab = preload("res://Scenes/slime.tscn")

var slimes: Array
var controlled_slime
var general_matches_made

var grid: Array = []
@onready var cell_size = level_settings.tile_size
@onready var start_spawn_x = level_settings.start_spawn_x
@onready var start_spawn_y = level_settings.start_spawn_y

func _ready() -> void:
	$"../CanvasLayer/Time Left Value".text = str(level_settings.level_time)
	spawn_slimes()
	find_matches()
	
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
	for column in range(level_settings.grid_columns):
		#adds an empty array to the end of the grid
		grid.append([])
		for row in range(level_settings.grid_rows):
			#get the instantiated slime before spawning at position
			var spawned_slime = slime_prefab.instantiate()
			spawned_slime.position = cell_positions(column, row) 
			spawned_slime.slime_colour = randi_range(0, spawned_slime.slime_colours.size() - 1)
			slimes_parent_node.add_child(spawned_slime)
			#puts the spawned slime into the empty array from earlier
			#goes through each available position in the row before going back to columns loop
			grid[column].append(spawned_slime)

func cell_positions(column: int, row: int) -> Vector2:
	#e.g. first slime is 160 + 0 * 64, 368 + 0 *64 for (160, 368)
	return Vector2(start_spawn_x + column * cell_size, start_spawn_y + row * cell_size)

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

func find_matches():
	var matched_slimes: Array = []
	var colours_adjacent: Array = []
	for column in grid.size():
		for slime in grid[column]:
			if colours_adjacent.is_empty() or slime.slime_colour == colours_adjacent[0].slime_colour:
				colours_adjacent.append(slime)
			else:
				if colours_adjacent.size() >= 3:
					#adds a match of 3 or more same colour slimes to to array
					matched_slimes.append(colours_adjacent)
				#starts anew from the slime after the match
				colours_adjacent = [slime]
		#checks at the end so matches completing with last slime in the column still count
		if colours_adjacent.size() >= 3:
			matched_slimes.append(colours_adjacent)
		colours_adjacent.clear()
		print(matched_slimes.size())

func win_or_lose():
	if level_settings.level_time <= 0:
		if general_matches_made >= level_settings.general_matches:
			$"../You Win Screen".visible = true
		else:
			$"../Game Over Screen".visible = true
