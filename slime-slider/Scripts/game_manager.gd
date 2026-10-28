extends Node2D

var slimes: Array
var controlled_slime

func _ready() -> void:
	slimes = $"../Slimes".get_children()
	for slime in slimes:
		var slime_button = slime.get_node("Slime Button")
		slime_button.connect("pressed", on_slime_clicked)

func on_slime_clicked():
	if controlled_slime != null:
		controlled_slime.unselect_slime()
	var controlled_button = get_viewport().gui_get_focus_owner()
	#need to get the parent to be able to call on_slime_selected() as the script is on the parent node
	controlled_slime = controlled_button.get_parent()
	controlled_slime.on_slime_selected()
