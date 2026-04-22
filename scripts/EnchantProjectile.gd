extends Area2D

# Matched to the regular enemy shooter projectile speed
@export var speed: float = 320.0
@export var lifetime: float = 3.0

const HEAL_AMOUNT   := 2
const BUFF_DURATION := 10.0

var direction: Vector2 = Vector2.RIGHT
# Set by EnemyEnchanter immediately after instantiation so the caster isn't
# hit by its own projectile (they share the same spawn position).
var source_entity: Node2D = null

func _ready() -> void:
	rotation = direction.angle()
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(queue_free)

func _process(delta: float) -> void:
	position += direction * speed * delta

func _on_body_entered(body: Node2D) -> void:
	if body == source_entity:
		return

	if body.is_in_group("enemy"):
		if body.has_method("heal"):
			body.heal(HEAL_AMOUNT)
		if body.has_method("apply_buff"):
			body.apply_buff(BUFF_DURATION)
		queue_free()
	elif body.is_in_group("player"):
		# Enchanter projectiles slow the player
		if body.has_method("apply_status"):
			body.apply_status("slow", 3.0)
		queue_free()
