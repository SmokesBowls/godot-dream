# staging_activity_probe.gd
# Test-only probe: an invalid staged room must never enter the live tree.
extends Node

static var ready_count := 0

func _ready() -> void:
	ready_count += 1
