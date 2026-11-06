extends CharacterBody2D

signal move_slime_finished
signal stopped_glowing(slime)

var green_slime = preload("res://Assets/green-slime.png")
var blue_slime = preload("res://Assets/blue-slime.png")
var yellow_slime = preload("res://Assets/yellow-slime.png")
var red_slime = preload("res://Assets/red-slime.png")
var purple_slime = preload("res://Assets/purple-slime.png")

var slime_colours: Array = [green_slime, blue_slime, yellow_slime, red_slime, purple_slime]
@export var slime_colour: int

const cell_size = 64
const move_time = 0.2

var is_moving = false
var is_glowing = false
var glow_time = 2.0

var slime_selected = false
var swipe_total_distance := Vector2.ZERO
var swipe_min_distance = 30.0
var finished_swiping = false

func _ready() -> void:
	$"Slime Sprite".texture = slime_colours[slime_colour]
	set_physics_process(false)
	$"White Border".visible = false

func get_input():
	if is_moving:
		return
	var direction = Vector2i.ZERO
	
	if Input.is_action_pressed("up"):
		direction = Vector2i.UP
	elif Input.is_action_pressed("down"):
		direction = Vector2i.DOWN
	elif Input.is_action_pressed("left"):
		direction = Vector2i.LEFT
	elif Input.is_action_pressed("right"):
		direction = Vector2i.RIGHT
	
	if direction != Vector2i.ZERO:
		move_one_tile(direction)

#checks for the direction across the whole swipe to reduce wrong movement
func _input(event) -> void:
	if is_moving or !slime_selected:
		return
	
	#checks for a new screen touch
	if event is InputEventScreenTouch and event.pressed:
		swipe_total_distance = Vector2.ZERO
		finished_swiping = false
	
	elif event is InputEventScreenDrag and !finished_swiping:
		#adds movement since the last swipe
		swipe_total_distance += event.relative
		if swipe_total_distance.length() >= swipe_min_distance:
			finished_swiping = true
			var direction = Vector2i.ZERO
			#checks if the absolute horizontal movement was more than absolute vertical movement
			if abs(swipe_total_distance.x) > abs(swipe_total_distance.y):
				if swipe_total_distance.x < 0:
					direction = Vector2i.LEFT
				else:
					direction = Vector2i.RIGHT
			else:
				if swipe_total_distance.y < 0:
					direction = Vector2i.UP
				else:
					direction = Vector2i.DOWN
			
			if !is_moving:
				finished_swiping = true
				move_one_tile(direction)

func move_one_tile(direction: Vector2i):
	#e.g. Vector2i.UP is (0, -1) so this will be (0, -64) and only moves in the one direction i want
	var offset = Vector2(direction * cell_size)
	var collision = KinematicCollision2D.new()
	
	#checks for collisions by taking object's position and how far it will move
	if test_move(global_transform, offset, collision):
		var collided_object = collision.get_collider()
		if collided_object is CharacterBody2D:
			#move other slime first so controlled slime's global position hasnt updated yet
			collided_object.move_animation(global_position)
			#then move the controlled slime like normal
			await move_animation(global_position + offset)
			move_slime_finished.emit()
			return
		else:
			return
	#if no collision, move controlled slime like normal
	await move_animation(global_position + offset)
	move_slime_finished.emit()

func move_animation(target_position: Vector2):
	is_moving = true
	var tween = create_tween()
	tween.tween_property(self, "global_position", target_position, move_time)
	await tween.finished
	is_moving = false

func on_slime_selected():
	slime_selected = true
	set_physics_process(true)

func unselect_slime():
	slime_selected = false
	set_physics_process(false)

func _physics_process(delta: float) -> void:
	get_input()

func slime_glowing():
	if !is_glowing:
		is_glowing = true
		$"White Border".visible = true
		await get_tree().create_timer(glow_time).timeout
		slime_stop_glowing()

func slime_stop_glowing():
	is_glowing = false
	$"White Border".visible = false
	#sends signal to game_manager.gd when a slime stops glowing
	stopped_glowing.emit(self) 
