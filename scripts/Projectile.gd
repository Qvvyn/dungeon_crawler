extends Area2D

@export var speed: float = 600.0
@export var lifetime: float = 3.0    # auto-destroy after this many seconds

# Set by Player.gd immediately after instantiation
var direction: Vector2 = Vector2.RIGHT

func _ready() -> void:
	# Rotate the sprite/visual to face the travel direction
	rotation = direction.angle()

	# Connect collision signal — fires when this Area2D overlaps another body or area
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

	# Destroy after lifetime expires even if nothing is hit
	var timer := get_tree().create_timer(lifetime)
	timer.timeout.connect(queue_free)

func _process(delta: float) -> void:
	position += direction * speed * delta

func _on_body_entered(body: Node2D) -> void:
	# Ignore the player that fired this (they share the same scene tree level,
	# but the player is a CharacterBody2D, not an Area2D, so this still fires
	# if we collide with walls / other physics bodies)
	if body.is_in_group("player"):
		return
	queue_free()

func _on_area_entered(area: Area2D) -> void:
	# Ignore other projectiles hitting each other (optional — remove if you want
	# projectiles to cancel each other out)
	if area.is_in_group("projectile"):
		return
	queue_free()
