extends CharacterBody2D

# Tune these in the Inspector
@export var speed: float = 300.0
@export var fire_rate: float = 0.15          # seconds between shots
@export var projectile_scene: PackedScene    # assign Projectile.tscn in the editor

var _shoot_cooldown: float = 0.0

func _ready() -> void:
	# Fallback: auto-load the projectile scene if not assigned in editor
	if projectile_scene == null:
		projectile_scene = load("res://scenes/Projectile.tscn")

func _physics_process(delta: float) -> void:
	_handle_movement()
	_handle_shooting(delta)

func _handle_movement() -> void:
	var direction := Vector2.ZERO

	if Input.is_action_pressed("move_up"):
		direction.y -= 1
	if Input.is_action_pressed("move_down"):
		direction.y += 1
	if Input.is_action_pressed("move_left"):
		direction.x -= 1
	if Input.is_action_pressed("move_right"):
		direction.x += 1

	# Normalize so diagonal movement isn't faster than cardinal
	if direction != Vector2.ZERO:
		direction = direction.normalized()

	velocity = direction * speed
	move_and_slide()

func _handle_shooting(delta: float) -> void:
	_shoot_cooldown -= delta

	if Input.is_action_pressed("shoot") and _shoot_cooldown <= 0.0:
		_fire()
		_shoot_cooldown = fire_rate

func _fire() -> void:
	if projectile_scene == null:
		push_warning("Player: projectile_scene is not set!")
		return

	var projectile = projectile_scene.instantiate()

	# Spawn at player's position
	projectile.global_position = global_position

	# Aim toward the mouse cursor in world space
	var mouse_pos := get_global_mouse_position()
	var dir := (mouse_pos - global_position).normalized()
	projectile.direction = dir

	# Add to the scene tree at the world level so it isn't
	# affected by the player's own transform
	get_tree().current_scene.add_child(projectile)
