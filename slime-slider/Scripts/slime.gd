extends CharacterBody2D

var green_slime = preload("res://Assets/green-slime.png")
var blue_slime = preload("res://Assets/blue-slime.png")
var yellow_slime = preload("res://Assets/yellow-slime.png")

var slime_colours: Array = [green_slime, blue_slime, yellow_slime]
@export var slime_colour: int

const tile_size = 64
const move_time = 0.2

var is_moving = false

func _ready() -> void:
	$"Slime Sprite".texture = slime_colours[slime_colour]
	set_physics_process(false)

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

func move_one_tile(direction: Vector2i):
	var offset = Vector2(direction * tile_size)
	#checks for collisions by taking object's position and how far it will move
	if test_move(global_transform, offset):
		return
	
	is_moving = true
	var tween = create_tween()
	tween.tween_property(self, "global_position", global_position + offset, move_time)
	await tween.finished
	is_moving = false

func on_slime_selected():
	set_physics_process(true)

func unselect_slime():
	set_physics_process(false)

func _physics_process(delta: float) -> void:
	get_input()
