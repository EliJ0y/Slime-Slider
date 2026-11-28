extends Node2D

signal level_won(next_level_path, extra_matches, highscore, new_highscore)
signal level_lost()

@export var level_settings: levels_resource
@onready var slimes_parent_node: Node = $"../Slimes"
var slime_prefab = preload("res://Scenes/slime.tscn")

var grid: Array = []
@onready var cell_size = level_settings.cell_size
@onready var start_spawn_x = level_settings.start_spawn_x
@onready var start_spawn_y = level_settings.start_spawn_y

@onready var tile_map_layer: TileMapLayer = $"../TileMapLayer"
var tiles_data: Dictionary = {
	"rock" = Vector2i(19, 23),
	"water" = Vector2i(22,  7)
}
var grid_gaps: Dictionary

var slimes: Array
var controlled_slime
var general_matches_made: int

#need to make a var instead of using level_settings.level_time so that the time can reset properly when you retry
var time_left: float
var level_ended = false

var base_fade_time = 0.75
var base_drop_time = 0.5
var base_move_time = 0.2
var fade_time = base_fade_time
var drop_time = base_drop_time
var resolving_slimes = false

#powerups need to be reset every level
var powerups: Dictionary = {"sameification": 0, "time_stop": 0, "slip_n_slide": 0}
var time_stopped = false
var time_stop_left = 0.0
var slip_n_slide = false
var speed_multiplier = 1.0

var level: String


func _ready() -> void:
	level = get_tree().current_scene.scene_file_path.get_file().get_basename()
	time_left = level_settings.level_time
	$"../CanvasLayer/Time Left Value".text = str(time_left)
	$"../CanvasLayer/Objective Label".text = str(level_settings.general_matches) + " Matches Left!"
	$"../CanvasLayer/Highscore".text = "Extra Matches Highscore: " + str(LevelHighscores.get_highscores(level))
	
	$"../CanvasLayer/Power-ups/Sameification".pressed.connect(use_sameification)
	$"../CanvasLayer/Power-ups/Time Stop".pressed.connect(use_time_stop)
	$"../CanvasLayer/Power-ups/Slip N' Slide".pressed.connect(use_slip_n_slide)
	update_powerups_ui()
	
	find_grid_gaps()
	spawn_slimes()
	await resolve_matches()
	
	await get_tree().create_timer(1.0).timeout
	pick_glowing_slimes()
	glowing_slime_cycle()

func _unhandled_input(event: InputEvent) -> void:
	#writing the funcs for the effects of each powerup later
	if event.is_action_pressed("sameification"):
		use_sameification()
	elif event.is_action_pressed("time_stop"):
		use_time_stop()
	elif event.is_action_pressed("slip_n_slide"):
		use_slip_n_slide()

func update_powerups_ui():
	$"../CanvasLayer/Power-ups/Sameification/Sameification Uses/Number of Uses".text = str(powerups["sameification"])
	$"../CanvasLayer/Power-ups/Time Stop/Time Stop Uses/Number of Uses".text = str(powerups["time_stop"])
	$"../CanvasLayer/Power-ups/Slip N' Slide/Slip N' Slide Uses/Number of Uses".text = str(powerups["slip_n_slide"])

func _process(delta: float) -> void:
	if level_ended: 
		return
	
	if time_stopped:
		time_stop_left -= delta
		$"../CanvasLayer/Time Left Value".text = "STOPPED: " + str(roundi(time_stop_left))
		if time_stop_left <= 0:
			end_time_stop()
		return
	
	if time_left > 0:
		time_left -= delta
		if not general_matches_made >= level_settings.general_matches:
			$"../CanvasLayer/Time Left Value".text = str(roundi(time_left))
			$"../CanvasLayer/Objective Label".text = str(level_settings.general_matches - general_matches_made) + " Matches Left!"
		else:
			$"../CanvasLayer/Time Left Value".text = str(roundi(time_left))
			$"../CanvasLayer/Objective Label".text = str(general_matches_made - level_settings.general_matches) + " Extra Matches\nWell done!"
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
	new_slime.move_time = base_move_time / speed_multiplier
	slimes.append(new_slime)
	return new_slime

func spawn_slimes():
	for column in range(level_settings.grid_columns):
		#adds an empty array to the end of the grid
		grid.append([])
		for row in range(level_settings.grid_rows):
			if is_cell_gap(column, row):
				grid[column].append(null)
			else:
				grid[column].append(create_slime(column, row))

func cell_positions(column: int, row: int) -> Vector2:
	#e.g. first slime is 160 + 0 * 64, 368 + 0 *64 for (160, 368)
	return Vector2(start_spawn_x + column * cell_size, start_spawn_y + row * cell_size)

func on_slime_moved():
	rebuild_grid()
	await after_board_change()

func rebuild_grid():
	for column in grid.size():
		for row in grid[column].size():
			#resets every slime's position
			grid[column][row] = null
	for slime in slimes:
		#e.g. (224 - 160) / 64 = 1. so slime is in the column of index 1
		var column = roundi((slime.position.x - start_spawn_x) / cell_size)
		var row = roundi((slime.position.y - start_spawn_y) / cell_size)
		#ensures its within the bounds of the grid
		if (column >= 0 and column < grid.size()) and (row >= 0 and row < grid[column].size()):
			grid[column][row] = slime


func is_cell_gap(column: int, row: int) -> bool:
	return grid_gaps.has(Vector2i(column, row))

func find_grid_gaps():
	grid_gaps.clear()
	#one 64px cell has 16 tiles, 4 per line
	var tiles_per_line = roundi(cell_size / tile_map_layer.tile_set.tile_size.x)
	
	for column in range(level_settings.grid_columns):
		for row in range(level_settings.grid_rows):
			#go to the corner of the 64px cell instead of the centre
			var corner = cell_positions(column, row) - (Vector2(cell_size, cell_size) / 2)
			
			#ensure its inside the tile and not on the edge
			#converts the world coords into coords local to the tile map
			#converts the local coords into tile coords like (1, 10 
			var first_tile = tile_map_layer.local_to_map(tile_map_layer.to_local(corner + Vector2(1, 1)))
			
			for x in tiles_per_line:
				for y in tiles_per_line:
					#gets coords from tileset for each tile in the line by increasing by Vector2i(x, y)
					var atlas_coords  = tile_map_layer.get_cell_atlas_coords(first_tile + Vector2i(x, y))
					if atlas_coords in tiles_data.values():
						grid_gaps[Vector2i(column, row)] = true


func on_slime_clicked():
	if resolving_slimes or level_ended:
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

func pick_glowing_slimes(only_when_none_glowing: bool = false):
	#wait for the board to go back to normal then glow to reduce waiting time
	while resolving_slimes:
		await get_tree().process_frame
	if level_ended:
		return
	#only_when_none_glowing is set to true at places where glows would have stopped
	if only_when_none_glowing and slimes.any(func(slime): return slime.is_glowing):
		return
	#filters out the already glowing slimes
	var not_glowing_slimes = slimes.filter(func(slime): return not slime.is_glowing and not slime.is_locked)
	#will only pick slimes that arent already glowing
	if not_glowing_slimes.is_empty():
		return
	not_glowing_slimes.pick_random().slime_glowing()

func glowing_slime_cycle():
	#gets called in ready and runs during the level to continually pick new glowing slimes
	while time_left > 2.5:
		await get_tree().create_timer(level_settings.pick_glow_interval).timeout
		#no regular glow cycle during time_stop
		if time_stopped:
			continue
		await pick_glowing_slimes()

func on_slime_stopped_glowing(slime):
	#takes control away from the glowing slime if it was being controlled
	if slime == controlled_slime:
		controlled_slime.unselect_slime()
		controlled_slime = null
	#in time_stop, pick a new slime to glow immediately after the old glow expires
	if time_stopped and not slime.is_locked:
		pick_glowing_slimes(true)


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
	if slime == null:
		save_colours_adjacent(colours_adjacent, matched_slimes_groups)
		return []
	
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


func resolve_matches(award_powerups: bool = true):
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
		
		if award_powerups:
			var earned_powerups: Array = []
			for group in matched_slimes_groups:
				earned_powerups.append_array(get_match_powerups(group))
			apply_powerups(earned_powerups, matched_slimes)
		
		#moved here as some powerups/effects provide bonus matches
		update_highscore_label()
		
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

func update_highscore_label():
	var extra_matches = general_matches_made - level_settings.general_matches
	#comapre whether old highscore or current extra matches is higher
	var highscore = maxi(LevelHighscores.get_highscores(level), extra_matches)
	$"../CanvasLayer/Highscore".text = "Extra Matches Highscore: " + str(highscore)

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
			if is_cell_gap(column, row):
				lowest_row = row - 1
				continue
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
			#checks if the position is empty and not a gap
			if grid[column][row] == null and !is_cell_gap(column, row):
				#then creates a new slime for that position
				var new_slime = create_slime(column, row)
				grid[column][row] = new_slime
				new_slime.modulate.a = 0.0
				create_tween().tween_property(new_slime, "modulate:a", 1.0, fade_time)


#Power-ups code
#gets the column and row of the slime
func cell_of(slime) -> Vector2i:
	return Vector2i(
		roundi((slime.position.x - start_spawn_x) / cell_size),
		roundi((slime.position.y - start_spawn_y) / cell_size))

#gets the slime in a specific cell
func slime_at(cell: Vector2i):
	if (cell.x < 0 or cell.x >= grid.size()) or (cell.y < 0 or cell.y >= grid[0].size()):
		return null
	return grid[cell.x][cell.y]

#Power-up: matches of >3 in a line
func get_matches(cells: Dictionary) -> Array:
	var matches: Array = []
	for cell in cells:
		#(horizontal) start at the first slime in the match from left
		if not cells.has(cell + Vector2i.LEFT):
			var matched_cells: Array = [cell]
			#while there are still more slimes to the right
			while cells.has(matched_cells.back() + Vector2i.RIGHT):
				matched_cells.append(matched_cells.back() + Vector2i.RIGHT)
			if matched_cells.size() >= 3:
				matches.append({"cells": matched_cells, "horizontal": true})
			
		#(vertical) start at the first slime in the match from top
		if not cells.has(cell + Vector2i.UP):
			var matched_cells: Array = [cell]
			#while there are still more slimes to the bottom
			while cells.has(matched_cells.back() + Vector2i.DOWN):
				matched_cells.append(matched_cells.back() + Vector2i.DOWN)
			if matched_cells.size() >= 3:
				matches.append({"cells": matched_cells, "horizontal": false})
	return matches

#check if the slime is at one of the ends or centre or neither
func position_in_match(matched_cells: Array, cell: Vector2i) -> String:
	var index = matched_cells.find(cell)
	if index == 0 or index == matched_cells.size() - 1:
		return "end"
	if abs(index * 2 - (matched_cells.size() - 1)) <= 1:
		return "centre"
	return "other"

func get_powerups(cells: Dictionary) -> Array:
	var matches = get_matches(cells)
	var earned_powerups: Array = []
	
	#powerups for straight line matches of 4 and 5
	for a_match in matches:
		if a_match.cells.size() == 4:
			earned_powerups.append({"type": "sameification", "match": a_match})
		if a_match.cells.size() >= 5:
			earned_powerups.append({"type": "clear_lines", "match": a_match})
	
	#checking the shapes of matches to assign powerups
	for h in matches:
		if not h.horizontal:
			continue
		for v in matches:
			if v.horizontal:
				continue
			for cell in h.cells:
				#if no overlapping matches and the match is just in one direction
				if not v.cells.has(cell):
					continue
				var h_pos = position_in_match(h.cells, cell)
				var v_pos = position_in_match(v.cells, cell)
				
				if h_pos == "centre" and v_pos == "centre":
					#small cross: match of 3 through each direction
					if h.cells.size() == 3 and v.cells.size() == 3:
						earned_powerups.append({"type": "small_cross", "centre": cell})
					else:
						#big cross: anything more than a match of 3
						earned_powerups.append({"type": "big_cross", "centre": cell})
				#'T' match: the second match's end overlapping at centre of the first
				elif (h_pos == "centre" and v_pos == "end") or (h_pos == "end" and v_pos == "centre"):
					earned_powerups.append({"type": "time_stop"})
				#arrow tip match: both matches overlap at their ends
				elif h_pos == "end" and v_pos == "end":
					earned_powerups.append({"type": "slip_n_slide"})
	
	#big cross clears entire grid so stop it from earning bonus matches the lines of 5+ get
	if earned_powerups.any(func(e): return e["type"] == "big_cross"):
		#give only the effects of big_cross and no clear_lines
		earned_powerups = earned_powerups.filter(func(e): return e["type"] != "clear_lines")
	
	return earned_powerups

func get_match_powerups(matched_cells: Array) -> Array:
	var cells: Dictionary = {}
	for slime in matched_cells:
		cells[cell_of(slime)] = true
	return get_powerups(cells)

#checks which and then adds uses to the powerup earned 
func apply_powerups(earned_powerups: Array, matched_slimes: Array):
	for powerup in earned_powerups:
		match powerup["type"]:
			"sameification", "time_stop", "slip_n_slide":
				powerups[powerup["type"]] += 1
			"clear_lines":
				general_matches_made += 1
				add_cells_to_clear(clear_lines(powerup["match"]), matched_slimes)
			"small_cross":
				general_matches_made += 2
				add_cells_to_clear(clear_crosses(powerup["centre"], 2), matched_slimes)
			"big_cross":
				general_matches_made += (maxi(level_settings.grid_columns, level_settings.grid_rows) - 1)
				add_cells_to_clear(get_all_cells(), matched_slimes)
	update_powerups_ui()

#adds slimes that were part of special matches to be cleared
func add_cells_to_clear(cells: Array, matched_slimes: Array):
	for cell in cells:
		var slime = slime_at(cell)
		if slime != null and not matched_slimes.has(slime):
			matched_slimes.append(slime)

func get_all_cells():
	var cells: Array = []
	for column in grid.size():
		for row in grid[column].size():
			cells.append(Vector2i(column, row))
	return cells


#sameification powerup
func use_sameification():
	if (powerups["sameification"] <= 0 or controlled_slime == null or resolving_slimes or level_ended):
		return
	
	var cell = cell_of(controlled_slime)
	#try left and right, then above and below
	for pair in [[Vector2i.LEFT, Vector2i.RIGHT], [Vector2i.UP, Vector2i.DOWN]]:
		var a_slime = slime_at(cell + pair[0])
		var b_slime = slime_at(cell + pair[1])
		if (a_slime != null and b_slime != null) and (not a_slime.is_locked and not b_slime.is_locked):
			a_slime.set_colours_same(controlled_slime.slime_colour)
			b_slime.set_colours_same(controlled_slime.slime_colour)
			powerups["sameification"] -= 1
			update_powerups_ui()
			await after_board_change()
			return

#time stop powerup
func use_time_stop():
	if powerups["time_stop"] <= 0 or time_stopped or resolving_slimes or level_ended:
		return
	
	powerups["time_stop"] -= 1
	update_powerups_ui()
	time_stopped = true
	time_stop_left = 10.0
	$"../CanvasLayer/Power-ups/Time Stop/Time Stop Panel".visible = true

func after_board_change():
	if time_stopped:
		handle_time_stopped_moves()
	else:
		await resolve_matches()

#matches dont resolve yet in time stop, resolve all at once when it ends
func handle_time_stopped_moves():
	var newly_matched = 0
	for group in find_matches():
		for slime in group:
			if not slime.is_locked:
				lock_slime(slime)
				newly_matched += 1
	if newly_matched > 0:
		pick_glowing_slimes(true)

#so slimes locked into matches will not glow
func lock_slime(slime):
	slime.is_locked = true
	slime.modulate = Color(0.6, 0.6, 0.6)
	if slime.is_glowing:
		slime.slime_stop_glowing()

func end_time_stop():
	time_stopped = false
	for slime in slimes:
		slime.is_locked = false
		slime.modulate = Color.WHITE
	$"../CanvasLayer/Power-ups/Time Stop/Time Stop Panel".visible = false
	await resolve_matches()

#slip n' slide powerup
func use_slip_n_slide():
	if powerups["slip_n_slide"] <= 0 or slip_n_slide or level_ended:
		return
	
	powerups["slip_n_slide"] -= 1
	update_powerups_ui()
	slip_n_slide = true
	set_speed(1.5)
	$"../CanvasLayer/Power-ups/Slip N' Slide/Slip N' Slide Panel".visible = true
	await get_tree().create_timer(0.5).timeout
	$"../CanvasLayer/Power-ups/Slip N' Slide/Slip N' Slide Panel".visible = false
	await get_tree().create_timer(15.0).timeout
	set_speed(1.0)
	slip_n_slide = false

func set_speed(multiplier: float):
	speed_multiplier = multiplier
	fade_time = base_fade_time / multiplier
	drop_time = base_drop_time / multiplier
	for slime in slimes:
		slime.move_time = base_move_time / multiplier

#lines of 5+ line clear effect
func clear_lines(a_match: Dictionary) -> Array:
	var matched_cells: Array = a_match["cells"]
	var size = matched_cells.size()
	
	var centre_index = (size - 1) / 2
	#pick one at random if the line match is of an even no. of slimes
	if size % 2 == 0 and randi() % 2 == 0:
		centre_index += 1
	var centre: Vector2i = matched_cells[centre_index]
	
	var cells: Array = []
	for column in grid.size():
		cells.append(Vector2i(column, centre.y))
	for row in grid[0].size():
		cells.append(Vector2i(centre.x, row))
	return cells

#cross matches clear effect
func clear_crosses(centre: Vector2i, radius: int) -> Array:
	var cells: Array = []
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			cells.append(centre + Vector2i(x, y))
	return cells


func win_or_lose():
	if time_left <= 0:
		$"../CanvasLayer/Time Left label".visible = false
		$"../CanvasLayer/Time Left Value".visible = false
		$"../CanvasLayer/Objective Label".visible = false
		$"../CanvasLayer/Highscore". visible = false
		$"../CanvasLayer/Power-ups/Sameification".visible = false
		$"../CanvasLayer/Power-ups/Time Stop".visible = false
		$"../CanvasLayer/Power-ups/Slip N' Slide".visible = false
		
		level_ended = true
		if general_matches_made >= level_settings.general_matches:
			var extra_matches = general_matches_made - level_settings.general_matches
			var new_highscore = LevelHighscores.increase_highscore(level, extra_matches)
			level_won.emit(level_settings.next_level_path, extra_matches, LevelHighscores.get_highscores(level), new_highscore)
		else:
			level_lost.emit()
