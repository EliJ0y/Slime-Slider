extends Node2D

@export var level_settings: levels_resource
@onready var slimes_parent_node: Node = $"../Slimes"
var slime_prefab = preload("res://Scenes/slime.tscn")

var slimes: Array
var controlled_slime
var general_matches_made: int

var fade_time = 1.0
var drop_time = 0.5
var resolving_slimes = false

var grid: Array = []
@onready var tile_size = level_settings.tile_size
@onready var start_spawn_x = level_settings.start_spawn_x
@onready var start_spawn_y = level_settings.start_spawn_y

func _ready() -> void:
	$"../CanvasLayer/Time Left Value".text = str(level_settings.level_time)
	$"../CanvasLayer/Objective Label".text = str(level_settings.general_matches) + " Matches Left!"
	spawn_slimes()
	await resolve_matches()
	
	await get_tree().create_timer(1.0).timeout
	pick_glowing_slimes()
	glowing_slime_cycle()

func _process(delta: float) -> void:
	if level_settings.level_time > 0:
		level_settings.level_time -= delta
		$"../CanvasLayer/Time Left Value".text = str(roundi(level_settings.level_time))
		$"../CanvasLayer/Objective Label".text = str(level_settings.general_matches - general_matches_made) + " Matches Left!"
	win_or_lose()


func create_slime(column: int, row: int):
	var new_slime = slime_prefab.instantiate()
	new_slime.position = cell_positions(column, row) 
	new_slime.slime_colour = randi_range(0, new_slime.slime_colours.size() - 1)
	slimes_parent_node.add_child(new_slime)
	new_slime.get_node("Slime Button").connect("pressed", on_slime_clicked)
	new_slime.connect("move_slime_finished", on_slime_moved)
	new_slime.connect("stopped_glowing", on_slime_stopped_glowing)
	new_slime.glow_time = level_settings.glow_time
	slimes.append(new_slime)
	return new_slime

func spawn_slimes():
	for column in range(level_settings.grid_columns):
		#adds an empty array to the end of the grid
		grid.append([])
		for row in range(level_settings.grid_rows):
			grid[column].append(create_slime(column, row))

func cell_positions(column: int, row: int) -> Vector2:
	#e.g. first slime is 160 + 0 * 64, 368 + 0 *64 for (160, 368)
	return Vector2(start_spawn_x + column * tile_size, start_spawn_y + row * tile_size)

func on_slime_moved():
	rebuild_grid()
	await resolve_matches()

func rebuild_grid():
	for column in grid.size():
		for row in grid[column].size():
			#resets every slime's position
			grid[column][row] = null
	for slime in slimes:
		#e.g. (224 - 160) / 64 = 1. so slime is in the column of index 1
		var column = roundi((slime.position.x - start_spawn_x) / tile_size)
		var row = roundi((slime.position.y - start_spawn_y) / tile_size)
		#ensures its within the bounds of the grid
		if (column >= 0 and column < grid.size()) and (row >= 0 and row < grid[column].size()):
			grid[column][row] = slime


func on_slime_clicked():
	if resolving_slimes:
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

func pick_glowing_slimes():
	#filters out the already glowing slimes
	var not_glowing_slimes = slimes.filter(func(slime): return not slime.is_glowing)
	#will only pick slimes that arent already glowing
	if not_glowing_slimes.is_empty():
		return
	not_glowing_slimes.pick_random().slime_glowing()

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
		general_matches_made += matched_slimes_groups.size()
		
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


func win_or_lose():
	if level_settings.level_time <= 0:
		if general_matches_made >= level_settings.general_matches:
			$"../You Win Screen".visible = true
		else:
			$"../Game Over Screen".visible = true
