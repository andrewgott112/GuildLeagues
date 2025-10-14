# scripts/systems/battle_system.gd
extends Node
class_name BattleSystem

signal battle_started()
signal phase_changed(combatant_name: String, phase: String)
signal action_completed(combatant_name: String, action: String, result: Dictionary)
signal battle_finished(result: Dictionary)
signal combatant_died(combatant_name: String)

enum BattlePhase {
	WAITING_TO_START,
	OBSERVE,
	DECIDE, 
	ACTION,
	BATTLE_FINISHED
}

enum ActionType {
	ATTACK,
	DEFEND,
	FLEE,
	WAIT
}

class Combatant:
	var name: String
	var is_player_controlled: bool
	var adventurer: AdventurerResource = null  # For player characters
	var monster: MonsterResource = null        # For enemies
	var current_phase: BattlePhase = BattlePhase.WAITING_TO_START
	var phase_timer: float = 0.0
	var current_action: ActionType = ActionType.WAIT
	var defending: bool = false
	var fled: bool = false
	
	# Track original HP for adventurers
	var original_hp: int = 0
	
	func _init(combatant_name: String, is_player: bool = true):
		name = combatant_name
		is_player_controlled = is_player
	
	func setup_adventurer(adv: AdventurerResource):
		adventurer = adv
		original_hp = adv.hp  # Store original HP
	
	func setup_monster(mon: MonsterResource):
		monster = mon
		monster.reset_for_battle()
	
	func get_current_hp() -> int:
		if adventurer:
			return adventurer.hp
		elif monster:
			return monster.current_hp
		return 0
	
	func get_max_hp() -> int:
		if adventurer:
			return original_hp  # Use the stored original HP
		elif monster:
			return monster.max_hp
		return 0
	
	func get_attack() -> int:
		if adventurer:
			return adventurer.attack
		elif monster:
			return monster.attack
		return 0
	
	func get_defense() -> int:
		if adventurer:
			return adventurer.defense
		elif monster:
			return monster.defense
		return 0
	
	func get_observe_time() -> float:
		if adventurer:
			return adventurer.get_observe_time()
		elif monster:
			return monster.get_observe_time()
		return 2.0
	
	func get_decide_time() -> float:
		if adventurer:
			return adventurer.get_decide_time()
		elif monster:
			return monster.get_decide_time()
		return 2.0
	
	func is_alive() -> bool:
		if adventurer:
			return adventurer.hp > 0
		elif monster:
			return monster.is_alive
		return false
	
	func take_damage(amount: int) -> int:
		var actual_damage = amount
		if adventurer:
			# REBALANCED: Slightly more damage reduction for adventurers 
			var reduced_damage = max(1, amount - (adventurer.defense / 12))  # Changed from /15 to /12 (more reduction)
			adventurer.hp = max(0, adventurer.hp - reduced_damage)
			actual_damage = reduced_damage
		elif monster:
			actual_damage = monster.take_damage(amount)
		return actual_damage

# Battle state
var combatants: Array[Combatant] = []
var battle_active: bool = false
var battle_log: Array[String] = []
var turn_count: int = 0
var rng: RandomNumberGenerator

func _init():
	rng = RandomNumberGenerator.new()
	rng.randomize()

func _ready():
	set_process(false)  # Only process when battle is active

func start_battle(player_party: Array, enemies: Array) -> bool:
	if battle_active:
		print("Battle already in progress!")
		return false
	
	# Clear previous battle state
	combatants.clear()
	battle_log.clear()
	turn_count = 0
	
	# Setup player combatants
	for adventurer in player_party:
		var combatant = Combatant.new(adventurer.name, true)
		combatant.setup_adventurer(adventurer)
		combatants.append(combatant)
	
	# Setup enemy combatants  
	for monster in enemies:
		var combatant = Combatant.new(monster.name, false)
		combatant.setup_monster(monster)
		combatants.append(combatant)
	
	if combatants.is_empty():
		print("No combatants available for battle!")
		return false
	
	battle_active = true
	set_process(true)
	
	# Start all combatants in observe phase
	for combatant in combatants:
		if combatant.is_alive():
			_start_observe_phase(combatant)
	
	_log_message("Battle begins!")
	battle_started.emit()
	return true

func _process(delta: float):
	if not battle_active:
		return
	
	# Process each living combatant's current phase
	for combatant in combatants:
		if not combatant.is_alive() or combatant.fled:
			continue
		
		combatant.phase_timer -= delta
		
		if combatant.phase_timer <= 0.0:
			_advance_combatant_phase(combatant)
	
	# Check for battle end conditions
	_check_battle_end()

func _start_observe_phase(combatant: Combatant):
	combatant.current_phase = BattlePhase.OBSERVE
	combatant.phase_timer = combatant.get_observe_time()
	combatant.defending = false  # Reset defending status
	phase_changed.emit(combatant.name, "observing")
	_log_message("%s is observing the battlefield..." % combatant.name)

func _advance_combatant_phase(combatant: Combatant):
	match combatant.current_phase:
		BattlePhase.OBSERVE:
			_start_decide_phase(combatant)
		BattlePhase.DECIDE:
			_start_action_phase(combatant)
		BattlePhase.ACTION:
			_complete_action(combatant)

func _start_decide_phase(combatant: Combatant):
	combatant.current_phase = BattlePhase.DECIDE
	combatant.phase_timer = combatant.get_decide_time()
	phase_changed.emit(combatant.name, "deciding")
	_log_message("%s is deciding their next move..." % combatant.name)

func _start_action_phase(combatant: Combatant):
	# Decide what action to take
	combatant.current_action = _choose_action(combatant)
	
	# Set action duration based on action type
	var action_duration = _get_action_duration(combatant.current_action)
	combatant.current_phase = BattlePhase.ACTION
	combatant.phase_timer = action_duration
	
	var action_name = _get_action_name(combatant.current_action)
	phase_changed.emit(combatant.name, "acting: " + action_name)
	_log_message("%s is performing: %s" % [combatant.name, action_name])

func _choose_action(combatant: Combatant) -> ActionType:
	if combatant.is_player_controlled:
		# For now, use simple AI for player characters too
		# Later this can be replaced with player input or more sophisticated AI
		return _choose_player_action(combatant)
	else:
		return _choose_monster_action(combatant)

func _choose_player_action(combatant: Combatant) -> ActionType:
	# Simple AI for player characters (can be enhanced later)
	var health_pct = float(combatant.get_current_hp()) / float(combatant.get_max_hp())
	var random_factor = rng.randf()
	
	# Low health - more likely to defend
	if health_pct < 0.3 and random_factor < 0.4:
		return ActionType.DEFEND
	
	# Default to attack most of the time
	if random_factor < 0.8:
		return ActionType.ATTACK
	else:
		return ActionType.DEFEND

func _choose_monster_action(combatant: Combatant) -> ActionType:
	if not combatant.monster:
		return ActionType.ATTACK
	
	var action_string = combatant.monster.choose_action({})
	match action_string:
		"attack":
			return ActionType.ATTACK
		"defend":
			return ActionType.DEFEND
		"flee":
			return ActionType.FLEE
		_:
			return ActionType.ATTACK

func _get_action_duration(action: ActionType) -> float:
	match action:
		ActionType.ATTACK:
			return 1.0 + rng.randf_range(-0.2, 0.3)  # 0.8-1.3 seconds
		ActionType.DEFEND:
			return 0.5 + rng.randf_range(-0.1, 0.2)  # 0.4-0.7 seconds
		ActionType.FLEE:
			return 0.8 + rng.randf_range(-0.1, 0.1)  # 0.7-0.9 seconds
		ActionType.WAIT:
			return 0.3
		_:
			return 1.0

func _get_action_name(action: ActionType) -> String:
	match action:
		ActionType.ATTACK:
			return "Attack"
		ActionType.DEFEND:
			return "Defend"
		ActionType.FLEE:
			return "Flee"
		ActionType.WAIT:
			return "Wait"
		_:
			return "Unknown"

func _complete_action(combatant: Combatant):
	var result = {}
	
	match combatant.current_action:
		ActionType.ATTACK:
			result = _execute_attack(combatant)
		ActionType.DEFEND:
			result = _execute_defend(combatant)
		ActionType.FLEE:
			result = _execute_flee(combatant)
		ActionType.WAIT:
			result = _execute_wait(combatant)
	
	action_completed.emit(combatant.name, _get_action_name(combatant.current_action), result)
	
	# Start next observe phase if still alive and didn't flee
	if combatant.is_alive() and not combatant.fled:
		_start_observe_phase(combatant)

func _execute_attack(attacker: Combatant) -> Dictionary:
	# Find a random living enemy
	var targets = []
	for combatant in combatants:
		if combatant != attacker and combatant.is_alive() and not combatant.fled:
			targets.append(combatant)
	
	if targets.is_empty():
		_log_message("%s attacks but finds no targets!" % attacker.name)
		return {"success": false, "message": "No valid targets"}
	
	var target = targets[rng.randi() % targets.size()]
	
	# REBALANCED: More reasonable damage calculation
	var attacker_attack = attacker.get_attack()
	var base_damage = max(1, attacker_attack / 12 + rng.randi_range(1, 4))  # Reduced from /10 to /12, dice from 1-6 to 1-4
	
	# Apply defense bonus if target is defending
	var final_damage = base_damage
	if target.defending:
		final_damage = max(1, base_damage / 2)  # 50% damage reduction when defending
	
	var actual_damage = target.take_damage(final_damage)
	
	_log_message("%s attacks %s for %d damage!" % [attacker.name, target.name, actual_damage])
	
	# Track combat stats for adventurers
	if attacker.adventurer:
		attacker.adventurer.add_battle_result(true)  # Count as participation
	
	if not target.is_alive():
		_log_message("%s has been defeated!" % target.name)
		combatant_died.emit(target.name)
		
		if attacker.adventurer:
			attacker.adventurer.add_monster_kill()
	
	return {
		"success": true,
		"target": target.name,
		"damage": actual_damage,
		"target_defeated": not target.is_alive()
	}

func _execute_defend(defender: Combatant) -> Dictionary:
	defender.defending = true
	_log_message("%s takes a defensive stance!" % defender.name)
	return {"success": true, "message": "Defending"}

func _execute_flee(fleer: Combatant) -> Dictionary:
	var flee_chance = 0.7  # 70% base chance to flee
	if rng.randf() < flee_chance:
		fleer.fled = true
		_log_message("%s successfully flees from combat!" % fleer.name)
		return {"success": true, "fled": true}
	else:
		_log_message("%s attempts to flee but fails!" % fleer.name)
		return {"success": false, "fled": false}

func _execute_wait(waiter: Combatant) -> Dictionary:
	_log_message("%s waits and watches..." % waiter.name)
	return {"success": true, "message": "Waiting"}

func _check_battle_end():
	var living_players = 0
	var living_enemies = 0
	
	for combatant in combatants:
		if not combatant.is_alive() or combatant.fled:
			continue
		
		if combatant.is_player_controlled:
			living_players += 1
		else:
			living_enemies += 1
	
	if living_players <= 0 or living_enemies <= 0:
		_end_battle()

func _end_battle():
	battle_active = false
	set_process(false)
	
	var living_players = 0
	var living_enemies = 0
	var fled_players = 0
	var fled_enemies = 0
	
	for combatant in combatants:
		if combatant.is_player_controlled:
			if combatant.fled:
				fled_players += 1
			elif combatant.is_alive():
				living_players += 1
		else:
			if combatant.fled:
				fled_enemies += 1
			elif combatant.is_alive():
				living_enemies += 1
	
	var result = {
		"victory": living_players > 0 and living_enemies <= 0,
		"living_players": living_players,
		"living_enemies": living_enemies,
		"fled_players": fled_players,
		"fled_enemies": fled_enemies,
		"turn_count": turn_count
	}
	
	var outcome_message = ""
	if result.victory:
		outcome_message = "Victory! All enemies have been defeated or fled!"
	elif living_players <= 0:
		outcome_message = "Defeat! All party members have been defeated or fled!"
	else:
		outcome_message = "Battle ended in a draw!"
	
	_log_message(outcome_message)
	
	# FIX: Restore original HP for all adventurers after battle
	# This ensures battles don't cause permanent HP loss
	for combatant in combatants:
		if combatant.adventurer and combatant.original_hp > 0:
			combatant.adventurer.hp = combatant.original_hp
			_log_message("%s's HP restored to %d" % [combatant.name, combatant.original_hp])
	
	# TODO: Consider adding a healing/recovery system here instead
	# For now, full restoration prevents permanent HP drain
	
	battle_finished.emit(result)

func _log_message(message: String):
	battle_log.append(message)
	print("[Battle] " + message)

func get_battle_log() -> Array[String]:
	return battle_log.duplicate()

func get_combatants() -> Array[Combatant]:
	return combatants.duplicate()

func is_battle_active() -> bool:
	return battle_active

func force_end_battle():
	if battle_active:
		_log_message("Battle forcefully ended!")
		_end_battle()
