extends "res://scripts/entity.gd"

signal flux_changed

export (int) var MAX_FLUX = 100
onready var flux = 0

const FLUX_PER_DELTA_TIME = 1 # Arbitrary, for now
const FLUX_GAIN_RATE = .2 # Arbitrary, for now

const MAX_THROWBACKS = 256
var throwback_positions = []
var throwback_i = 0
var throwback_count = 0

func _ready():
	throwback_positions.resize(MAX_THROWBACKS)

func move_entity(motion, dir):
	var remainder = .move_entity(motion, dir)

	# Only heal and cache throwback when we actually move,
	# and do so without collisions.
	if motion.length_squared() and not remainder.length_squared():
		heal_flux(motion.length_squared() * FLUX_GAIN_RATE)
		cache_throwback_position()
	
func heal_flux(amount):
	var previous_flux = flux
	flux = min(flux + amount, MAX_FLUX)

	if flux != previous_flux:
		emit_signal("flux_changed", flux_ratio())

func flux_ratio():
	return flux / MAX_FLUX

func can_throwback(delta):
	return (delta * FLUX_PER_DELTA_TIME) <= flux

# Caches the throwback position in the cyclic throwback array.
func cache_throwback_position():
	throwback_positions[throwback_i] = get_pos()
	throwback_i = (throwback_i + 1) % MAX_THROWBACKS
	throwback_count = min(throwback_count + 1, MAX_THROWBACKS)
	print(throwback_i)

func throwback(delta):
	assert(can_throwback(delta))
	flux -= delta * FLUX_PER_DELTA_TIME
	emit_signal("flux_changed", flux_ratio())
	# TODO: Actually perform the throwback.