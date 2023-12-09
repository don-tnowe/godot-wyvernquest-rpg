extends CombatActor

@export var available_moves : Array[CombatMove]
@export var available_weapons : Array[EquipmentItem]
@export var cam : Camera3D
@export var anim : AnimationPlayer

@export_group("Parameters")
@export var move_maxspeed := 8.0
@export var move_accel := 32.0
@export var move_brake := 64.0

var current_weapon : EquipmentItem
var last_input_direction := Vector3.FORWARD
var last_shoot_direction := Vector3.FORWARD


func _ready():
	stats.stat_changed.connect(_on_stat_changed)
	var starting_stats := stats.get_stats()
	for k in starting_stats:
		_on_stat_changed(k, starting_stats[k], 0.0)

	switch_weapon(0)


func _physics_process(delta):
	var input_vec := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_backwards")
	var velocity_h := Vector2(velocity.x, velocity.z)
	var speed_delta := move_brake
	if input_vec != Vector2.ZERO:
		# Changes speed at `move_brake` if pushing against velocity vec, `move_accel` if forwards or sideways
		speed_delta = -0.5 * (input_vec.dot(velocity_h.normalized()) - 1.0) * move_brake + move_accel
		last_input_direction = Vector3(input_vec.x, 0, input_vec.y).normalized()
		if anim.current_animation != &"run":
			anim.play(&"run")

	else:
		if anim.current_animation != &"idle":
			anim.play(&"idle")

	velocity_h = velocity_h.move_toward(input_vec * move_maxspeed, delta * speed_delta)
	velocity = Vector3(velocity_h.x, 0, velocity_h.y)
	if input_vec.x != 0:
		$"Visual/Flip/Sprite3D".flip_h = input_vec.x < 0

	move_and_slide()


func use_move(index : int):
	var move := available_moves[index]

	# First, apply the move's reactions and triggers.
	# This example only covers personal buffs.
	reactions.add_reactions(move.user_reactions)
	if move.user_stats != null:
		move.user_stats.apply(stats)

	var mouse_pos := get_viewport().get_mouse_position()
	var mouse_hit : Vector3 = get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(
			cam.project_ray_origin(mouse_pos),
			cam.project_ray_normal(mouse_pos) * 1000.0,
		)).get(&"position", position + last_shoot_direction)
	var shoot_direction := position.direction_to(Vector3(mouse_hit.x, position.y, mouse_hit.z))
	last_shoot_direction = shoot_direction
	for x in move.scenes:
		# Spawn the projectile.
		var scene_instance := x.instantiate()
		scene_instance.position = position
		add_sibling(scene_instance)
		if scene_instance.has_method(&"launch"):
			scene_instance.launch(
				stats.get_stat(&"weapon_damage"),
				move,
				shoot_direction * stats.get_stat(&"projectile_speed", 8.0),
				self
			)

		# Here's the trigger call! The ability_used method was generated by the database resource.
		# The database is accessible from the Inspector in any TriggerReaction resource.
		var result := reactions.ability_used(move, null, [scene_instance])
		for y in result.spawned_nodes:
			y.target_hit.connect(_on_target_hit)

	# Don't forget to remove reactions and stats without a timer! They'd stay permanently.
	if move.user_stats != null && move.user_stats.expires_in == 0:
		stats.clear(move.user_stats.at_path)

	for x in move.user_reactions:
		if x.expires_in == 0:
			reactions.remove_reaction(x.reaction_id, x.trigger_id)


func switch_weapon(index : int):
	if current_weapon != null:
		for x in current_weapon.reactions:
			reactions.remove_reaction(x.reaction_id, x.trigger_id)

		if current_weapon.stats != null:
			stats.clear(current_weapon.stats.at_path)

	# After removing old reactions and stats, add ones from the new item.
	var new_weapon = available_weapons[index]
	current_weapon = new_weapon
	reactions.add_reactions(new_weapon.reactions)
	if new_weapon.stats != null:
		new_weapon.stats.apply(stats)


func _unhandled_input(event):
	if event is InputEventMouseButton:
		if event.pressed:
			match event.button_index:
				MOUSE_BUTTON_LEFT: use_move(0)
				MOUSE_BUTTON_RIGHT: use_move(1)

	if event is InputEventKey:
		if event.pressed:
			if event.keycode >= KEY_1 && event.keycode < KEY_1 + available_moves.size() - 2:
				use_move(event.keycode - KEY_1 + 2)


func _on_target_hit(target, damage_result):
	var _result := reactions.hit_landed(target, damage_result.ability, damage_result.damage)
	# Do whatever with result


func _on_stat_changed(stat : StringName, new_value : float, _old_value : float):
	match stat:
		&"movement_speed":
			move_maxspeed = new_value
