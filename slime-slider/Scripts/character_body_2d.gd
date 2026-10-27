extends CharacterBody2D

const tile_size = 64
const move_time = 0.2

var is_moving = false
var is_controlled = false

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
	is_moving = true
	var offset = Vector2(direction * tile_size)
	var tween = create_tween()
	tween.tween_property(self, "global_position", global_position + offset, move_time)
	await tween.finished
	is_moving = false

func _physics_process(delta: float) -> void:
	get_input()
