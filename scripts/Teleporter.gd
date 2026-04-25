extends Area2D

var _partner: Node2D = null
var _cooldown: float = 0.0
var _lbl: Label = null

func setup(pos: Vector2) -> void:
	position = pos
	add_to_group("teleporter")
	collision_layer = 0
	collision_mask  = 1

	var cshape := CollisionShape2D.new()
	var circ := CircleShape2D.new()
	circ.radius = 12.0
	cshape.shape = circ
	add_child(cshape)

	_lbl = Label.new()
	_lbl.text = "O"
	_lbl.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
	_lbl.add_theme_font_size_override("font_size", 14)
	_lbl.position = Vector2(-5.0, -10.0)
	add_child(_lbl)

	_start_pulse()
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta

func _start_pulse() -> void:
	var tw := create_tween()
	tw.set_loops()
	tw.tween_property(_lbl, "modulate:a", 0.3, 0.7)
	tw.tween_property(_lbl, "modulate:a", 1.0, 0.7)

func link(other: Node2D) -> void:
	_partner = other

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if _cooldown > 0.0:
		return
	if _partner == null or not is_instance_valid(_partner):
		return
	_cooldown = 1.5
	_partner._cooldown = 1.5
	if SoundManager:
		SoundManager.play("teleport")
	# Autoplay: remember both endpoints so future paths route around them
	if body.get("_autoplay") == true and body.has_method("_autoplay_blacklist_pos"):
		body.call("_autoplay_blacklist_pos", global_position)
		body.call("_autoplay_blacklist_pos", _partner.global_position)
	body.global_position = _partner.global_position
