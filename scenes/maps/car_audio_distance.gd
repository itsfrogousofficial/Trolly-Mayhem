
extends AudioStreamPlayer3D

# Maximum distance at which the sound can be heard.
@export var max_hearing_distance: float = 50.0

func _ready() -> void:
	# Use distance-based 3D audio attenuation.
	attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	max_distance = max_hearing_distance

	# Start playing automatically if a sound is assigned.
	if stream != null:
		play()
