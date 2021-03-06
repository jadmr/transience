extends "res://scripts/entity.gd"

# Flux-based entity management. This contains a lot of the logic for the
# player character (perhaps the filename is a misnomer...).
# Expects the following child nodes (with the given name):
# - Tween

signal flux_changed

export (int) var MAX_FLUX = 100
onready var flux = 0

const FLUX_PER_THROWBACK_STEP = .4 # Multiplied with THROWBACK_STEPS
const FLUX_GAIN_RATE = .1 # Arbitrary, for now
const THROWBACK_STEPS = 32

onready var throwback_tween_node = get_node("ThrowbackTween")
const MAX_THROWBACKS = 512
var throwback_positions = []
var throwback_i = 0
var throwback_count = 0

const THROWBACK_TWEEN_TIME = 0.15
const THROWBACK_OPACITY = 0.2

const FLUX_PER_ATTACK = 5

onready var footprint_particles = get_node("FootprintParticles")
const FOOTPRINT_PARTICLE_OFFSET_Y = 11
const FOOTPRINT_PARTICLE_DISPLACEMENT_X = 2
const FOOTPRINT_PARTICLE_DISPLACEMENT_Y = 1
var footprint_swapped = false
var footprint_switch_threshold
var footprint_switch_delta = 0

const TIME_BEFORE_QUEUEING_NEW_ACTION = 0.2

func _ready():
	throwback_positions.resize(MAX_THROWBACKS)
	throwback_tween_node.connect("tween_completed", self, "on_throwback_complete")
	footprint_switch_threshold = footprint_particles.get_lifetime() / footprint_particles.get_amount()

func flux_physics_process(delta):
	# Footprint mechanics.
	footprint_particles.set_emitting(can_accept_input())
	footprint_switch_delta += delta
	if footprint_switch_delta > footprint_switch_threshold:
		footprint_swapped = not footprint_swapped
		footprint_switch_delta = fmod(footprint_switch_delta, footprint_switch_threshold)

	# Attack slide motion.
	if current_state == STATE_ATTACK:
		slide_in_dir(get_dir())

func move_entity(motion, dir, delta):
	var amount_moved = .move_entity(motion, dir, delta)
	var remainder = motion - amount_moved

	# Perform certain operations only when we actually move without collisions, or is "sliding".
	var is_sliding = remainder.x and remainder.y
	if (motion * delta).length_squared() and (not remainder.length_squared() or is_sliding):
		on_actual_move(motion, dir, delta)
	else:
		on_non_actual_move(motion, dir, delta)
	return amount_moved

func on_actual_move(motion, dir, delta):
	heal_flux((motion * delta).length_squared() * FLUX_GAIN_RATE)
	cache_throwback_position()

	# Update footprint particles.
	footprint_particles.set_emitting(true)
	var offset
	if dir == "right" or dir == "left":
		offset = Vector2(0, FOOTPRINT_PARTICLE_DISPLACEMENT_Y)
	else:
		offset = Vector2(FOOTPRINT_PARTICLE_DISPLACEMENT_X, 0)
	
	if footprint_swapped:
		offset *= -1

	footprint_particles.position = Vector2(0, FOOTPRINT_PARTICLE_OFFSET_Y) + offset

func on_non_actual_move(motion, dir, delta):
	footprint_particles.set_emitting(false)

func heal_flux(amount):
	var previous_flux = flux
	flux = min(flux + amount, MAX_FLUX)

	if flux != previous_flux:
		emit_signal("flux_changed", flux_ratio())

func use_flux(amount):
	assert(amount <= flux)
	flux -= amount
	emit_signal("flux_changed", flux_ratio())

func flux_ratio():
	return float(flux) / MAX_FLUX

func can_throwback(steps):
	var enough_flux = (steps * FLUX_PER_THROWBACK_STEP) <= flux
	var enough_throwback = steps <= throwback_count
	return enough_flux and enough_throwback

# Caches the throwback position in the cyclic throwback array.
func cache_throwback_position():
	throwback_positions[throwback_i] = position
	throwback_i = (throwback_i + 1) % MAX_THROWBACKS
	throwback_count = min(throwback_count + 1, MAX_THROWBACKS)

func throwback(steps):
	assert(can_throwback(steps))
	use_flux(steps * FLUX_PER_THROWBACK_STEP)
	
	# GDScript's modulo operator doesn't work on negatives, so "wrap" manually.
	throwback_i -= steps
	if throwback_i < 0:
		throwback_i += MAX_THROWBACKS
	throwback_count -= steps

	throwback_tween_node.interpolate_property(self, "position", position, throwback_positions[throwback_i], \
			THROWBACK_TWEEN_TIME, Tween.TRANS_QUAD, Tween.EASE_OUT)
	throwback_tween_node.start()
	on_throwback_start()

func on_throwback_start():
	# Disable collisions - e.g. enemy attacks, etc.
	set_collision_layer_bit(0, 0)
	set_collision_mask_bit(0, 0)
	sprite.modulate = Color(1, 1, 1, THROWBACK_OPACITY)
	change_state(STATE_THROWBACK)

func on_throwback_complete(object, key):
	# Re-enable collisions.
	set_collision_layer_bit(0, 1)
	set_collision_mask_bit(0, 1)
	sprite.modulate = Color(1, 1, 1, 1)
	change_state(STATE_IDLE)

func can_attack():
	return FLUX_PER_ATTACK <= flux

func attack():
	assert(can_attack())
	use_flux(FLUX_PER_ATTACK)
	.attack()

func on_attack_triggered():
	# TODO: Make this play earlier so that the sound syncs up.
	play_sample("slice")
	.on_attack_triggered()

func react_to_motion_controls(delta):
	if not can_accept_input():
		return

	var motion = Vector2()
	var dir = null
	
	if Input.is_action_pressed("ui_up"):
		motion.y -= 1
		dir = "up"
	if Input.is_action_pressed("ui_down"):
		motion.y += 1
		dir = "down"
	if Input.is_action_pressed("ui_left"):
		motion.x -= 1
		dir = "left"
	if Input.is_action_pressed("ui_right"):
		motion.x += 1
		dir = "right"

	motion = motion.normalized() * SPEED
	move_entity(motion, dir, delta)

func react_to_action_controls(event):
	var action = null
	if event.is_action_pressed("trans_accept"):
		action = "trans_accept"
	if event.is_action_pressed("trans_cancel"):
		action = "trans_cancel"

	if action:
		if can_accept_input():
			immediately_run_action(action)
			return
		
		# If we reach here, it means we're currently in an animation.
		# Check for the amount of time left before we can trigger a new action.
		var time_left = animation_player.current_animation_length - animation_player.current_animation_position
		if time_left < TIME_BEFORE_QUEUEING_NEW_ACTION:
			next_action = action

		# Otherwise, just drop the input.

func immediately_run_action(action):
	if action == "trans_accept":
		if can_throwback(THROWBACK_STEPS):
			throwback(THROWBACK_STEPS)
	if action == "trans_cancel":
		if can_attack():
			attack()

func handle_next_action(action):
	immediately_run_action(action)
	.handle_next_action(action)