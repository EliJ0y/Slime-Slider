extends Node2D

#reusing code from game_manager.gd
@export var level_settings: levels_resource
@onready var slimes_parent_node: Node = $Slimes
var slime_prefab = preload("res://Scenes/slime.tscn")

@onready var tutorial_text: Label = $"CanvasLayer/Tutorial Text"
@onready var slime_7: CharacterBody2D = $Slimes/Slime7

var grid: Array = []
@onready var cell_size = level_settings.cell_size
@onready var start_spawn_x = level_settings.start_spawn_x
@onready var start_spawn_y = level_settings.start_spawn_y

var slimes: Array = []
var controlled_slime
var matches_made: int = 0

var base_fade_time = 0.75
var base_drop_time = 0.5
var base_move_time = 0.2
var fade_time = base_fade_time
var drop_time = base_drop_time

var slime_selected = false
var random_glow_started = false
var resolving_slimes = false
var input_locked = false
var tutorial_finished = false

var powerups: Dictionary = {"sameification": 0, "time_stop": 0, "slip_n_slide": 0}
var time_stopped = false
var time_stop_left = 0.0
var slip_n_slide = false
var speed_multiplier = 1.0

var sameification_used = false
var time_stop_used = false
var slip_n_slide_used = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	setup_grid()
	for slime in slimes_parent_node.get_children():
		register_slime(slime)
	rebuild_grid()
	
	$"CanvasLayer/Power-ups/Sameification".pressed.connect(use_sameification)
	$"CanvasLayer/Power-ups/Time Stop".pressed.connect(use_time_stop)
	$"CanvasLayer/Power-ups/Slip N' Slide".pressed.connect(use_slip_n_slide)
	update_powerups_ui()
	
	await get_tree().create_timer(1.0).timeout
	slime_7.glow_time = 9999
	slime_7.slime_glowing()
	
	tutorial_text.visible = true
	tutorial_text.text = "Now, let's try\nthe power-ups!"
	await get_tree().create_timer(1.5).timeout
	if !slime_selected:
		tutorial_text.text = "Click on the \nglowing slime"

func _unhandled_input(event: InputEvent) -> void:
	#writing the funcs for the effects of each powerup later
	if event.is_action_pressed("sameification"):
		use_sameification()
	elif event.is_action_pressed("time_stop"):
		use_time_stop()
	elif event.is_action_pressed("slip_n_slide"):
		use_slip_n_slide()

func update_powerups_ui():
	$"CanvasLayer/Power-ups/Sameification/Sameification Uses/Number of Uses".text = str(powerups["sameification"])
	$"CanvasLayer/Power-ups/Time Stop/Time Stop Uses/Number of Uses".text = str(powerups["time_stop"])
	$"CanvasLayer/Power-ups/Slip N' Slide/Slip N' Slide Uses/Number of Uses".text = str(powerups["slip_n_slide"])

func _process(delta: float) -> void:
	update_powerups_ui()
	
	if powerups["sameification"] == 1 and not sameification_used:
		tutorial_text.text = "You earned one use of\nSameification!"
		await get_tree().create_timer(1.5).timeout
		tutorial_text.text = "Control a slime then\npress the 'Q' key\nor the icon to try it!"
	if sameification_used:
		tutorial_text.text = "An easy match, right?\nOn to the next!"
	
	if powerups["time_stop"] == 1 and not time_stop_used:
		tutorial_text.text = "You got one use of\nTime Stop!"
		await get_tree().create_timer(1.0).timeout
		tutorial_text.text = "Press the 'E' key\nor the icon to try it!"
	if time_stop_used:
		tutorial_text.text = "Quite some extra time\nOn to the next!"
	
	if powerups["slip_n_slide"] == 1 and not slip_n_slide_used:
		tutorial_text.text = "You got one use of\nSlip N' Slide!"
		await get_tree().create_timer(1.0).timeout
		tutorial_text.text = "Press the 'R' key\nor the icon to try it!"
	if slip_n_slide_used:
		tutorial_text.text = "Gotta go fast!\nAll three power-ups done"
		await get_tree().create_timer(1.0).timeout
		tutorial_text.text = "Tutorials completed!\nOn to the game!"
		await get_tree().create_timer(1.0).timeout
		finish_tutorial()


func setup_grid():
	grid.clear()
	for column in range(level_settings.grid_columns):
		grid.append([])
		for row in range(level_settings.grid_rows):
			grid[column].append(null)

func cell_positions(column: int, row: int) -> Vector2:
	return Vector2(start_spawn_x + column * cell_size, start_spawn_y + row * cell_size)

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

	if matches_made >= 1 and !random_glow_started:
		random_glow_started = true
		pick_glowing_slime()
		glowing_slime_cycle()

func rebuild_grid():
	for column in grid.size():
		for row in grid[column].size():
			grid[column][row] = null
	for slime in slimes:
		var column = roundi((slime.position.x - level_settings.start_spawn_x) / level_settings.cell_size)
		var row = roundi((slime.position.y - level_settings.start_spawn_y) / level_settings.cell_size)
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
			tutorial_text.text = "Make a match of\nfour in a row"
		await get_tree().create_timer(2.0).timeout

func on_slime_stopped_glowing(slime):
	if slime == controlled_slime:
		controlled_slime.unselect_slime()
		controlled_slime = null

func pick_glowing_slime(only_when_none_glowing: bool = false):
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
		
		var earned_powerups: Array = []
		for group in matched_slimes_groups:
			earned_powerups.append_array(get_match_powerups(group))
		apply_powerups(earned_powerups, matched_slimes)
		
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
				matches_made += 1
				add_cells_to_clear(clear_lines(powerup["match"]), matched_slimes)
			"small_cross":
				matches_made += 2
				add_cells_to_clear(clear_crosses(powerup["centre"], 2), matched_slimes)
			"big_cross":
				matches_made += (maxi(level_settings.grid_columns, level_settings.grid_rows) - 1)
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
	if (powerups["sameification"] <= 0 or controlled_slime == null or resolving_slimes or tutorial_finished):
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
			sameification_used = true
			update_powerups_ui()
			await after_board_change()
			return

#time stop powerup
func use_time_stop():
	if powerups["time_stop"] <= 0 or time_stopped or resolving_slimes or tutorial_finished:
		return
	
	powerups["time_stop"] -= 1
	time_stop_used = true
	update_powerups_ui()
	time_stopped = true
	time_stop_left = 10.0
	$"CanvasLayer/Power-ups/Time Stop/Time Stop Panel".visible = true

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
		pick_glowing_slime(true)

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
	$"CanvasLayer/Power-ups/Time Stop/Time Stop Panel".visible = false
	await resolve_matches()

#slip n' slide powerup
func use_slip_n_slide():
	if powerups["slip_n_slide"] <= 0 or slip_n_slide or tutorial_finished:
		return
	
	powerups["slip_n_slide"] -= 1
	slip_n_slide_used = true
	update_powerups_ui()
	slip_n_slide = true
	set_speed(1.5)
	$"CanvasLayer/Power-ups/Slip N' Slide/Slip N' Slide Panel".visible = true
	await get_tree().create_timer(0.5).timeout
	$"CanvasLayer/Power-ups/Slip N' Slide/Slip N' Slide Panel".visible = false
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


func finish_tutorial():
	tutorial_finished = true
	input_locked = true
	
	if controlled_slime != null:
		controlled_slime.unselect_slime()
	
	await get_tree().create_timer(2.0).timeout
	$"Tutorial End Screen".visible = true

func _on_replay_button_pressed() -> void:
	get_tree().reload_current_scene()

func _on_next_level_button_pressed() -> void:
	get_tree().change_scene_to_file(level_settings.next_level_path)
