extends Resource
class_name AdventurerResource

# ═══════════════════════════════════════════════════════════════════
# BASIC INFO
# ═══════════════════════════════════════════════════════════════════
@export var name: String = "Rookie"
@export var role: RoleResource

# ═══════════════════════════════════════════════════════════════════
# CORE COMBAT STATS (1-200 range, visible)
# ═══════════════════════════════════════════════════════════════════
@export var attack: int = 100
@export var defense: int = 100
@export var hp: int = 100
@export var role_stat: int = 100

# NEW: Additional combat stats
@export var speed: int = 100        # Initiative/movement speed in combat
@export var accuracy: int = 100     # Hit chance modifier
@export var crit_chance: int = 100  # Critical hit chance (out of 200 = 100% base)

# ═══════════════════════════════════════════════════════════════════
# BATTLE SKILLS (1-200 range, visible after combat)
# ═══════════════════════════════════════════════════════════════════
@export var observe_skill: int = 100
@export var decide_skill: int = 100

# ═══════════════════════════════════════════════════════════════════
# HIDDEN ATTRIBUTES (not directly visible, affect growth/behavior)
# ═══════════════════════════════════════════════════════════════════
@export var potential: int = 100           # Growth rate multiplier (50-150)
@export var peak_age: int = 5              # Season when stats peak (3-8)
@export var injury_prone: int = 100        # Injury resistance (lower = more prone)
@export var mental_fortitude: int = 100    # Madness resistance
@export var loyalty_base: int = 50         # Base loyalty to current team (0-100)

# ═══════════════════════════════════════════════════════════════════
# PERSONALITY TRAITS (affect AI behavior and relationships)
# ═══════════════════════════════════════════════════════════════════
@export var aggression: float = 0.5        # 0.0 = defensive, 1.0 = very aggressive
@export var caution: float = 0.5           # 0.0 = reckless, 1.0 = very cautious
@export var teamwork: float = 0.5          # 0.0 = selfish, 1.0 = team player
@export var ambition: float = 0.5          # 0.0 = content, 1.0 = driven

# ═══════════════════════════════════════════════════════════════════
# STATUS & PROGRESSION
# ═══════════════════════════════════════════════════════════════════
@export var age: int = 1                   # Seasons played (starts at 1)
@export var seasons_played: int = 0        # Career length
@export var experience_points: int = 0     # For leveling up
@export var level: int = 1                 # Character level

# Status conditions
@export var madness_level: int = 0         # 0-100, go mad at 100
@export var injuries: Array = []           # Array of active injuries
@export var is_active: bool = true         # Can play this season?
@export var is_retired: bool = false       # Permanently out

# ═══════════════════════════════════════════════════════════════════
# ECONOMIC
# ═══════════════════════════════════════════════════════════════════
@export var wage: int = 5                  # Salary demand per season

# ═══════════════════════════════════════════════════════════════════
# COMBAT TRACKING (existing)
# ═══════════════════════════════════════════════════════════════════
@export var monsters_killed: int = 0
@export var battles_won: int = 0
@export var battles_fought: int = 0

# ═══════════════════════════════════════════════════════════════════
# RELATIONSHIPS (future: track bonds with teammates)
# ═══════════════════════════════════════════════════════════════════
@export var loyalty_current: int = 50      # Current loyalty (affected by events)
@export var teammate_bonds: Dictionary = {} # character_name -> bond_strength

# ═══════════════════════════════════════════════════════════════════
# INITIALIZATION
# ═══════════════════════════════════════════════════════════════════

func apply_role_defaults() -> void:
	"""Apply role-based stat defaults with variance"""
	if not role:
		return
	
	# Set base stats from role (scaled to 1-200 range)
	attack = _scale_to_200(role.base_attack, 1, 10)
	defense = _scale_to_200(role.base_defense, 1, 10)
	hp = _scale_to_200(role.base_hp, 5, 25)
	role_stat = _scale_to_200(role.base_role_stat, 1, 10)
	
	# Add variance to base stats (±20 points)
	attack = clampi(attack + randi_range(-20, 20), 1, 200)
	defense = clampi(defense + randi_range(-20, 20), 1, 200)
	hp = clampi(hp + randi_range(-20, 20), 1, 200)
	role_stat = clampi(role_stat + randi_range(-20, 20), 1, 200)
	
	# NEW: Generate combat stats from role
	speed = role.generate_speed()
	accuracy = role.generate_accuracy()
	crit_chance = role.generate_crit_chance()
	
	# Add individual variance (±15 points)
	speed = clampi(speed + randi_range(-15, 15), 20, 180)
	accuracy = clampi(accuracy + randi_range(-15, 15), 20, 180)
	crit_chance = clampi(crit_chance + randi_range(-15, 15), 20, 180)
	
	# Random battle skills (independent of role)
	observe_skill = randi_range(20, 180)
	decide_skill = randi_range(20, 180)
	
	# Initialize hidden attributes with role influence
	_generate_hidden_attributes()
	
	# Set personality based on role
	aggression = role.generate_aggression()
	caution = role.generate_caution()
	teamwork = role.generate_teamwork()
	ambition = role.generate_ambition()
	
	# Calculate initial wage based on visible stats
	wage = _calculate_wage()

func _scale_to_200(old_value: int, old_min: int, old_max: int) -> int:
	"""Scale old 1-10 range to 1-200 range"""
	var normalized = float(old_value - old_min) / float(old_max - old_min)
	return int(normalized * 179) + 21  # Maps to roughly 21-200 range

func _generate_hidden_attributes() -> void:
	"""Generate hidden attributes that affect growth and behavior"""
	# Potential: How much this character can grow (50-150)
	potential = _generate_biased_stat_custom(50, 150, 0.3)
	
	# Peak age: Use role's range
	peak_age = role.generate_peak_age() if role else randi_range(3, 8)
	
	# Injury prone: Use role's resistance modifier
	var injury_base = role.get_injury_resistance_base() if role else 100
	injury_prone = injury_base + randi_range(-30, 30)
	injury_prone = clampi(injury_prone, 50, 150)
	
	# Mental fortitude: Madness resistance (50-150)
	mental_fortitude = _generate_biased_stat_custom(50, 150, 0.25)
	
	# Loyalty base: Natural loyalty tendency (20-80)
	loyalty_base = randi_range(20, 80)
	loyalty_current = loyalty_base

func _generate_biased_stat_custom(min_val: int, max_val: int, extreme_chance: float) -> int:
	"""Generate a stat with most values in middle, some extremes"""
	var roll = randf()
	var range_size = max_val - min_val
	
	if roll < extreme_chance:
		return randi_range(min_val, min_val + range_size / 4)
	elif roll > (1.0 - extreme_chance):
		return randi_range(max_val - range_size / 4, max_val)
	else:
		var mid_min = min_val + range_size / 4
		var mid_max = max_val - range_size / 4
		return randi_range(mid_min, mid_max)

# Helper functions for role info
func get_role_name() -> String:
	"""Get the display name of this character's role"""
	return role.display_name if role else "Unknown"

func get_role_description() -> String:
	"""Get a description of the role's strengths"""
	return role.get_role_description() if role else "No role assigned"

func get_role_stat_name() -> String:
	"""Get the name of this role's special stat"""
	return str(role.role_stat_name).capitalize() if role else "Role Stat"

func get_character_summary() -> String:
	"""Get a brief summary of this character's role and strengths"""
	var summary = "%s - %s\n" % [name, get_role_name()]
	summary += get_role_description() + "\n"
	
	# Highlight strengths
	var strengths = []
	if attack > 130: strengths.append("Strong Attacker")
	if defense > 130: strengths.append("Tough Defender")
	if speed > 130: strengths.append("Lightning Fast")
	if crit_chance > 130: strengths.append("Critical Striker")
	
	if strengths.size() > 0:
		summary += "Strengths: " + ", ".join(strengths)
	
	return summary

# ═══════════════════════════════════════════════════════════════════
# STAT GROWTH & LEVELING
# ═══════════════════════════════════════════════════════════════════

func add_experience(amount: int) -> bool:
	"""Add experience and check for level up. Returns true if leveled up."""
	if is_retired:
		return false
	
	experience_points += amount
	var xp_needed = get_xp_for_next_level()
	
	if experience_points >= xp_needed:
		level_up()
		return true
	
	return false

func get_xp_for_next_level() -> int:
	"""Calculate XP needed for next level"""
	return 100 + (level * 50)  # 150, 200, 250, 300...

func level_up() -> void:
	"""Level up and increase stats based on potential"""
	level += 1
	experience_points = 0  # Reset XP for next level
	
	# Calculate growth multiplier based on age vs peak
	var age_factor = _calculate_age_growth_factor()
	
	# Calculate potential factor (50-150 potential -> 0.5x to 1.5x growth)
	var potential_factor = float(potential) / 100.0
	
	# Combined multiplier
	var growth_multiplier = age_factor * potential_factor
	
	# Grow stats (base growth: 3-8 points per level)
	var base_growth = randi_range(3, 8)
	var actual_growth = max(1, int(base_growth * growth_multiplier))
	
	# Distribute growth across stats (with some randomness)
	var stat_gains = _distribute_growth_points(actual_growth)
	
	attack = clampi(attack + stat_gains.attack, 1, 200)
	defense = clampi(defense + stat_gains.defense, 1, 200)
	hp = clampi(hp + stat_gains.hp, 1, 200)
	role_stat = clampi(role_stat + stat_gains.role_stat, 1, 200)
	speed = clampi(speed + stat_gains.speed, 1, 200)
	accuracy = clampi(accuracy + stat_gains.accuracy, 1, 200)
	crit_chance = clampi(crit_chance + stat_gains.crit_chance, 1, 200)
	
	# Skills grow slower
	observe_skill = clampi(observe_skill + randi_range(1, 3), 1, 200)
	decide_skill = clampi(decide_skill + randi_range(1, 3), 1, 200)
	
	print("%s leveled up to %d! (Growth: %dx)" % [name, level, growth_multiplier])

func _calculate_age_growth_factor() -> float:
	"""Calculate growth multiplier based on current age vs peak age"""
	if age < peak_age:
		# Growing toward peak (0.8x to 1.2x)
		var progress = float(age) / float(peak_age)
		return 0.8 + (progress * 0.4)
	elif age == peak_age:
		# At peak (1.2x growth)
		return 1.2
	else:
		# Past peak, declining growth (1.0x down to 0.3x)
		var years_past_peak = age - peak_age
		var decline_rate = 0.15  # Lose 15% per year past peak
		return max(0.3, 1.0 - (years_past_peak * decline_rate))

func _distribute_growth_points(total_points: int) -> Dictionary:
	"""Distribute growth points across stats based on role and personality"""
	var distribution = {
		"attack": 0,
		"defense": 0,
		"hp": 0,
		"role_stat": 0,
		"speed": 0,
		"accuracy": 0,
		"crit_chance": 0
	}
	
	# Distribute points randomly but weighted by role
	for i in total_points:
		var roll = randf()
		
		# Aggressive characters favor attack/speed
		if aggression > 0.7 and roll < 0.3:
			if randf() < 0.6:
				distribution.attack += 1
			else:
				distribution.speed += 1
		# Cautious characters favor defense/hp
		elif caution > 0.7 and roll < 0.3:
			if randf() < 0.6:
				distribution.defense += 1
			else:
				distribution.hp += 1
		# Otherwise distribute based on role focus
		else:
			var stat_roll = randf()
			if stat_roll < 0.25:
				distribution.attack += 1
			elif stat_roll < 0.5:
				distribution.defense += 1
			elif stat_roll < 0.65:
				distribution.hp += 1
			elif stat_roll < 0.75:
				distribution.role_stat += 1
			elif stat_roll < 0.85:
				distribution.speed += 1
			elif stat_roll < 0.92:
				distribution.accuracy += 1
			else:
				distribution.crit_chance += 1
	
	return distribution

func apply_aging() -> void:
	"""Called at end of season - age character and apply effects"""
	age += 1
	seasons_played += 1
	
	# Past peak age? Start declining
	if age > peak_age + 3:
		_apply_age_decline()

func _apply_age_decline() -> void:
	"""Apply stat losses due to aging"""
	var years_past_prime = age - (peak_age + 3)
	var decline_amount = years_past_prime  # Lose 1-3 points per stat per year
	
	if decline_amount > 0:
		attack = max(20, attack - decline_amount)
		defense = max(20, defense - decline_amount)
		speed = max(20, speed - decline_amount)
		accuracy = max(20, accuracy - decline_amount)
		
		print("%s is declining with age (-%d to stats)" % [name, decline_amount])

# ═══════════════════════════════════════════════════════════════════
# INJURY & MADNESS SYSTEM
# ═══════════════════════════════════════════════════════════════════

func add_injury(injury_data: Dictionary) -> void:
	"""Add an injury to this character"""
	injuries.append(injury_data)
	is_active = false  # Injured characters can't play
	print("%s suffered an injury: %s" % [name, injury_data.get("description", "Unknown")])

func heal_injury(injury_index: int) -> void:
	"""Remove an injury (fully healed)"""
	if injury_index >= 0 and injury_index < injuries.size():
		var injury = injuries[injury_index]
		injuries.remove_at(injury_index)
		
		# If no more injuries, can play again
		if injuries.is_empty():
			is_active = true
		
		print("%s recovered from: %s" % [name, injury.get("description", "injury")])

func process_injury_recovery() -> void:
	"""Process recovery for all active injuries (called each week/season)"""
	var healed_indices = []
	
	for i in range(injuries.size()):
		var injury = injuries[i]
		injury.recovery_time -= 1
		
		if injury.recovery_time <= 0:
			healed_indices.append(i)
	
	# Heal injuries that are ready (reverse order to avoid index issues)
	healed_indices.reverse()
	for idx in healed_indices:
		heal_injury(idx)

func increase_madness(amount: int) -> void:
	"""Increase madness level from dungeon exposure"""
	var resistance_factor = float(mental_fortitude) / 100.0
	var actual_increase = max(1, int(amount / resistance_factor))
	
	madness_level = min(100, madness_level + actual_increase)
	
	if madness_level >= 100:
		go_mad()
	elif madness_level >= 75:
		print("%s is teetering on the edge of madness! (%d/100)" % [name, madness_level])

func go_mad() -> void:
	"""Character goes permanently mad - forced retirement"""
	is_retired = true
	is_active = false
	print("%s has gone mad and must retire!" % name)

# ═══════════════════════════════════════════════════════════════════
# LOYALTY & RELATIONSHIPS
# ═══════════════════════════════════════════════════════════════════

func modify_loyalty(amount: int, reason: String = "") -> void:
	"""Change current loyalty level"""
	loyalty_current = clampi(loyalty_current + amount, 0, 100)
	
	if reason != "":
		print("%s loyalty %s by %d: %s" % [
			name,
			"increased" if amount > 0 else "decreased",
			abs(amount),
			reason
		])

func get_teammate_bond(teammate_name: String) -> int:
	"""Get bond strength with specific teammate (-100 to 100)"""
	return teammate_bonds.get(teammate_name, 0)

func modify_teammate_bond(teammate_name: String, amount: int) -> void:
	"""Change relationship with teammate"""
	var current = get_teammate_bond(teammate_name)
	teammate_bonds[teammate_name] = clampi(current + amount, -100, 100)

# ═══════════════════════════════════════════════════════════════════
# COMBAT TRACKING (existing methods, kept for compatibility)
# ═══════════════════════════════════════════════════════════════════

func add_monster_kill():
	monsters_killed += 1
	add_experience(10)  # NEW: Grant XP for kills

func add_battle_result(won: bool):
	battles_fought += 1
	if won:
		battles_won += 1
		add_experience(25)  # NEW: Grant XP for victories
	else:
		add_experience(5)   # Small XP even for losses

func get_win_rate() -> float:
	if battles_fought == 0:
		return 0.0
	return float(battles_won) / float(battles_fought)

# ═══════════════════════════════════════════════════════════════════
# BATTLE TIMING (existing, kept for compatibility)
# ═══════════════════════════════════════════════════════════════════

func get_observe_time() -> float:
	return max(0.5, 3.0 - (observe_skill * 2.5 / 200.0))

func get_decide_time() -> float:
	return max(0.5, 3.0 - (decide_skill * 2.5 / 200.0))

func get_observe_skill() -> int:
	return observe_skill

func get_decide_skill() -> int:
	return decide_skill

func get_observe_skill_text() -> String:
	return _get_skill_rating(observe_skill)

func get_decide_skill_text() -> String:
	return _get_skill_rating(decide_skill)

func _get_skill_rating(value: int) -> String:
	if value >= 160:
		return "Legendary"
	elif value >= 120:
		return "Excellent"
	elif value >= 80:
		return "Good"
	elif value >= 40:
		return "Average"
	else:
		return "Poor"

# ═══════════════════════════════════════════════════════════════════
# ECONOMIC
# ═══════════════════════════════════════════════════════════════════

func _calculate_wage() -> int:
	"""Calculate wage based on total power and potential"""
	var total_power = attack + defense + hp + role_stat + observe_skill + decide_skill
	var average_stat = total_power / 6.0
	
	# Base wage from stats (3g to 25g)
	var base_wage = 3 + int((average_stat - 1) * 22 / 199)
	
	# Potential modifier (high potential = higher wage)
	var potential_bonus = int((potential - 100) / 25)  # ±2g based on potential
	
	# Add randomness (±2g)
	var final_wage = base_wage + potential_bonus + randi_range(-2, 2)
	
	return clampi(final_wage, 3, 25)

# ═══════════════════════════════════════════════════════════════════
# STATIC GENERATION METHODS (for draft/free agents)
# ═══════════════════════════════════════════════════════════════════

static func generate_random_prospect(roles: Array[RoleResource]) -> AdventurerResource:
	"""Generate a completely random prospect for draft"""
	var prospect = AdventurerResource.new()
	
	# Assign random role
	if roles.size() > 0:
		prospect.role = roles.pick_random()
	
	# Generate stats based on role
	prospect.apply_role_defaults()
	
	# Generate name
	prospect.name = _generate_random_name()
	
	# Recalculate wage after all stats are set
	prospect.wage = prospect._calculate_wage()
	
	return prospect

static func _generate_biased_stat() -> int:
	"""Generate stat with bias toward middle values"""
	var roll = randf()
	
	if roll < 0.05:
		return randi_range(1, 30)
	elif roll < 0.15:
		return randi_range(31, 60)
	elif roll < 0.75:
		return randi_range(61, 140)
	elif roll < 0.95:
		return randi_range(141, 170)
	else:
		return randi_range(171, 200)

static func _generate_random_name() -> String:
	var first_names = [
		"Garruk", "Eryndra", "Milo", "Serah", "Tamsin", "Borin", "Nyx", "Quinn",
		"Lira", "Theron", "Kira", "Vex", "Zara", "Kai", "Nova", "Rex", "Luna",
		"Axel", "Vera", "Dante", "Iris", "Phoenix", "Sage", "Storm", "Vale"
	]
	
	var last_names = [
		"Stonefist", "Dawnstar", "Reed", "Voss", "Kestrel", "Blackwood", "Ashen",
		"Thorne", "Vale", "Swift", "Ward", "Kane", "Cross", "Steel", "Moon",
		"Fire", "Shadow", "Bright", "Wild", "Stone", "Wolf", "Hawk", "Star", "Blade"
	]
	
	return "%s %s" % [first_names.pick_random(), last_names.pick_random()]
