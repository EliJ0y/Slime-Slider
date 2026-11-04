extends Node2D

#reusing code from game_manager.gd
@export var level_settings: levels_resource
@onready var slimes_parent_node: Node = $Slimes
var slime_prefab = preload("res://Scenes/slime.tscn")

@onready var tutorial_text: Label = $"CanvasLayer/Tutorial Text"
@onready var slime_5: CharacterBody2D = $Slimes/Slime5

var grid: Array = []
@onready var tile_size = level_settings.tile_size
@onready var start_spawn_x = level_settings.start_spawn_x
@onready var start_spawn_y = level_settings.start_spawn_y

var slimes: Array = []
var controlled_slime
var matches_made: int = 0

var fade_time = 1.0
var drop_time = 0.5

var slime_selected = false
var random_glow_started = false
var resolving_slimes = false
var input_locked = false
var tutorial_finished = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	setup_grid()
	for slime in slimes_parent_node.get_children():
		register_slime(slime)
	rebuild_grid()
	
	await get_tree().create_timer(1.0).timeout
	slime_5.glow_time = 9999
	slime_5.slime_glowing()
	
	tutorial_text.visible = true
	tutorial_text.text = "Hey, look! A \n slime is glowing!"
	await get_tree().create_timer(2.0).timeout
	if !slime_selected:
		tutorial_text.text = "Click on it"

func _process(delta: float) -> void:
	if matches_made == 1:
		tutorial_text.text = "Nice one! \n Make two more"
	if matches_made == 2:
		tutorial_text.text = "Just one \n more to go!"


func setup_grid():
	grid.clear()
	for column in range(level_settings.grid_columns):
		grid.append([])
		for row in range(level_settings.grid_rows):
			grid[column].append(null)

func cell_positions(column: int, row: int) -> Vector2:
	return Vector2(start_spawn_x + column * tile_size, start_spawn_y + row * tile_size)

func register_slime(slime):
	slime.get_node("Slime Button").pressed.connect(on_slime_clicked)
	slime.move_slime_finished.connect(on_slime_moved)
	slime.stopped_glowing.connect(on_slime_stopped_glowing)
	slime.glow_time = level_settings.glow_time
	slimes.append(slime)

func create_slime(column: int, row: int):
	var new_slime = slime_prefab.instantiate()
	new_slime.position = cell_positions(column, row)
	new_slime.slime_colour = randi_range(0, new_slime.slime_colours.size() - 1)
	slimes_parent_node.add_child(new_slime)
	register_slime(new_slime)
	return new_slime


func on_slime_moved():
	rebuild_grid()
	await resolve_matches()

	if matches_made >= 3:
		tutorial_text.text = "Great job! \n On to level 1!"
		finish_tutorial()
	elif matches_made >= 1 and !random_glow_started:
		random_glow_started = true
		pick_glowing_slime()
		glowing_slime_cycle()

func rebuild_grid():
	for column in grid.size():
		for row in grid[column].size():
			grid[column][row] = null
	for slime in slimes:
		var column = roundi((slime.position.x - level_settings.start_spawn_x) / level_settings.tile_size)
		var row = roundi((slime.position.y - level_settings.start_spawn_y) / level_settings.tile_size)
		if column >= 0 and column < grid.size() and row >= 0 and row < grid[column].size():
			grid[column][row] = slime


func on_slime_clicked():
	if resolving_slimes or input_locked:
		return
	
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
		
		if !slime_selected:
			slime_selected = true
			tutorial_text.text = "Use WASD or arrow \n keys to move it"
		await get_tree().create_timer(2.0).timeout
		if matches_made == 0:
			tutorial_text.text = "Make a match!"

func on_slime_stopped_glowing(slime):
	if slime == controlled_slime:
		controlled_slime.unselect_slime()
		controlled_slime = null

func pick_glowing_slime():
	if resolving_slimes:
		return
	var not_glowing_slimes = slimes.filter(func(slime): return not slime.is_glowing)
	if not_glowing_slimes.is_empty():
		return
	not_glowing_slimes.pick_random().slime_glowing()

func glowing_slime_cycle():
	while not tutorial_finished:
		await get_tree().create_timer(level_settings.pick_glow_interval).timeout
		pick_glowing_slime()


func find_matches() -> Array:
	var matched_slimes_groups: Array = []
	
	#checks the slimes in every column
	for column in grid.size():
		var colours_adjacent: Array = []
		for row in grid[column].size():
			#check each slime in the column to see if they r viable to become a match
			colours_adjacent = scan_slimes(grid[column][row], colours_adjacent, matched_slimes_groups)
		#calls the function to check if any matches in the column have been made
		save_colours_adjacent(colours_adjacent, matched_slimes_groups)
	
	#checks the slimes in every row
	for row in grid[0].size():
		var colours_adjacent: Array = []
		for column in grid.size():
			colours_adjacent = scan_slimes(grid[column][row], colours_adjacent, matched_slimes_groups)
		#calls the function to check if any matches in the row have been made
		save_colours_adjacent(colours_adjacent, matched_slimes_groups)
	
	return matched_slimes_groups

func scan_slimes(slime, colours_adjacent: Array, matched_slimes_groups: Array) -> Array:
	#checks if theres nothing or if the colours match
	if colours_adjacent.is_empty() or slime.slime_colour == colours_adjacent[0].slime_colour:
		colours_adjacent.append(slime)
		return colours_adjacent
	
	#calls the function to check if any matches have been made since the colour has changed
	save_colours_adjacent(colours_adjacent, matched_slimes_groups)
	#starts a new array with the current slime after colour changed
	return [slime]

func save_colours_adjacent(colours_adjacent: Array, matched_slimes_groups: Array):
	if colours_adjacent.size() < 3:
		return
	
	#an array to merge two matches if they share a slime
	#duplicate() so it doesnt mess up the actual array
	var merged_slime_group: Array = colours_adjacent.duplicate()
	
	for group in matched_slimes_groups.duplicate():
		var shares_a_slime = false
		for slime in group:
			if colours_adjacent.has(slime):
				shares_a_slime = true
				break
		
		if shares_a_slime:
			#merges the slimes from previous match (except dupes) with current match
			for slime in group:
				if not merged_slime_group.has(slime):
					merged_slime_group.append(slime)
			#remove the previous match so it doesnt count twice for the matches
			matched_slimes_groups.erase(group)
	
	matched_slimes_groups.append(merged_slime_group)


func resolve_matches():
	if resolving_slimes:
		return
	resolving_slimes = true
	if controlled_slime != null:
		#pause keyboard input while removing slimes
		controlled_slime.unselect_slime()
	
	var matched_slimes_groups = find_matches()
	while not matched_slimes_groups.is_empty():
		#adds a point for each unique match
		matches_made += matched_slimes_groups.size()
		
		var matched_slimes: Array = []
		for group in matched_slimes_groups:
			#makes sure each slime is appended individually and not in a lump group
			matched_slimes.append_array(group)
		
		await fade_out_slimes(matched_slimes)
		drop_slimes()
		await get_tree().create_timer(drop_time).timeout
		respawn_slimes()
		await get_tree().create_timer(fade_time).timeout
		matched_slimes_groups = find_matches()
	
	#give control back since the grid is done changing
	if controlled_slime != null:
		controlled_slime.on_slime_selected()
	resolving_slimes = false

func fade_out_slimes(matched_slimes: Array):
	for slime in matched_slimes:
		var fade_tween = create_tween()
		#fade the slimes out into transparency
		fade_tween.tween_property(slime, "modulate:a", 0.0, fade_time)
	#wait for the fade to finish then remove the slimes
	await get_tree().create_timer(fade_time).timeout
	for slime in matched_slimes:
		remove_slimes(slime)

func remove_slimes(slime):
	for column in grid.size():
		#finds slime's index (row) in the column
		var row = grid[column].find(slime)
		if row != -1:
			#make the position empty after removing slime
			grid[column][row] = null
	
	slimes.erase(slime)
	if slime == controlled_slime:
		controlled_slime = null
	slime.queue_free()

func drop_slimes():
	for column in grid.size():
		#start from the bottom-most row
		var lowest_row = grid[column].size() - 1
		#from bottom-most row, goes up a row each time, stops before index -1 which doesnt exist
		for row in range((grid[column].size() - 1), -1, -1):
			var slime = grid[column][row]
			if slime == null:
				continue
			if row != lowest_row:
				#update the slime's new position after dropping
				grid[column][lowest_row] = slime
				#its previous position is now empty
				grid[column][row] = null
				slime.move_animation(cell_positions(column, lowest_row))
			#goes to the next row one above
			lowest_row -= 1

func respawn_slimes():
	for column in grid.size():
		for row in grid[column].size():
			#checks if the position is empty
			if grid[column][row] == null:
				#then creates a new slime for that position
				var new_slime = create_slime(column, row)
				grid[column][row] = new_slime
				new_slime.modulate.a = 0.0
				create_tween().tween_property(new_slime, "modulate:a", 1.0, fade_time)


func finish_tutorial():
	tutorial_finished = true
	input_locked = true
	
	if controlled_slime != null:
		controlled_slime.unselect_slime()
	
	await get_tree().create_timer(2.0).timeout
	$"Tutorial End Screen".visible = true

func _on_replay_button_pressed() -> void:
	get_tree().reload_current_scene()

func _on_level_1_button_pressed() -> void:
	get_tree().change_scene_to_file(level_settings.next_level_path)
