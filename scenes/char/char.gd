extends "res://scripts/flux_entity.gd"

const PERCENT_DAMAGE_HEALED = 0.2

func _ready():
	add_to_group("player")
	
	play_animation("down_idle")

func _physics_process(delta):
	flux_physics_process(delta)
	react_to_motion_controls(delta)

func _input(event):
	react_to_action_controls(event)

func on_attack_triggered():
	var total_damage = detect_directional_area_attack_collisions("enemies")
	heal(total_damage * PERCENT_DAMAGE_HEALED)
	.on_attack_triggered()

func on_die_finished():
	# *Don't* queue_free the main player, unlike how we handle other entities.
	.on_die_finished(false)