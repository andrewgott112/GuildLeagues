extends Resource
class_name AdventurerResource

@export var name: String = "Rookie"
@export var role: RoleResource

# Core stats (1-200 range)
@export var attack: int
@export var defense: int
@export var hp: int
@export var role_stat: int
@export var wage: int = 5

# Battle skills (1-200 range, random for all)
@export var observe_skill: int = 50
@export var decide_skill: int = 50

# NEW: Combat tracking
@export var monsters_killed: int = 0
@export var battles_won: int = 0
@export var battles_fought: int = 0

func apply_role_defaults() -> void:
	if role:
		# Set stats to role defaults but in 1-200 range
		attack = _scale_to_200(role.base_attack, 1, 10)
		defense = _scale_to_200(role.base_defense, 1, 10) 
		hp = _scale_to_200(role.base_hp, 5, 25)
		role_stat = _scale_to_200(role.base_role_stat, 1, 10)
		
		# Add variance to stats (±20 points)
		attack = clampi(attack + randi_range(-20, 20), 1, 200)
		defense = clampi(defense + randi_range(-20, 20), 1, 200)
		hp = clampi(hp + randi_range(-20, 20), 1, 200)
		role_stat = clampi(role_stat + randi_range(-20, 20), 1, 200)
		
		# Random battle skills (completely independent of role)
		observe_skill = randi_range(20, 180)
		decide_skill = randi_range(20, 180)

# Helper to scale old 1-10 range to 1-200 range
func _scale_to_200(old_value: int, old_min: int, old_max: int) -> int:
	var normalized = float(old_value - old_min) / float(old_max - old_min)
	return int(normalized * 179) + 21  # Maps to roughly 21-200 range

# Battle timing functions (now based on 1-200 scale)
func get_observe_time() -> float:
	# 200 skill = 0.5s, 1 skill = 3.0s
	return max(0.5, 3.0 - (observe_skill * 2.5 / 200.0))

func get_decide_time() -> float:
	# 200 skill = 0.5s, 1 skill = 3.0s  
	return max(0.5, 3.0 - (decide_skill * 2.5 / 200.0))

# Get skill values for external use
func get_observe_skill() -> int:
	return observe_skill

func get_decide_skill() -> int:
	return decide_skill

# Get skill descriptions for UI (now based on 1-200 scale)
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

# Combat tracking methods
func add_monster_kill():
	monsters_killed += 1

func add_battle_result(won: bool):
	battles_fought += 1
	if won:
		battles_won += 1

func get_win_rate() -> float:
	if battles_fought == 0:
		return 0.0
	return float(battles_won) / float(battles_fought)

# Generate a completely random prospect (for draft)
static func generate_random_prospect(roles: Array[RoleResource]) -> AdventurerResource:
	var prospect = AdventurerResource.new()
	
	# Assign random role
	if roles.size() > 0:
		prospect.role = roles.pick_random()
	
	# Generate random stats in 1-200 range
	# Bias toward middle ranges (40-160) with occasional extremes
	prospect.attack = _generate_biased_stat()
	prospect.defense = _generate_biased_stat()
	prospect.hp = _generate_biased_stat()
	prospect.role_stat = _generate_biased_stat()
	
	# Random battle skills
	prospect.observe_skill = _generate_biased_stat()
	prospect.decide_skill = _generate_biased_stat()
	
	# Generate name and calculate wage
	prospect.name = _generate_random_name()
	prospect.wage = prospect._calculate_wage()
	
	return prospect

# Biased random generation - more likely to get middle values
static func _generate_biased_stat() -> int:
	var roll = randf()
	
	if roll < 0.05:  # 5% chance for very low (1-30)
		return randi_range(1, 30)
	elif roll < 0.15:  # 10% chance for low (31-60)
		return randi_range(31, 60)
	elif roll < 0.75:  # 60% chance for average (61-140)
		return randi_range(61, 140)
	elif roll < 0.95:  # 20% chance for high (141-170)
		return randi_range(141, 170)
	else:  # 5% chance for very high (171-200)
		return randi_range(171, 200)

func _calculate_wage() -> int:
	# Calculate wage based on total power (all stats matter)
	var total_power = attack + defense + hp + role_stat + observe_skill + decide_skill
	var average_stat = total_power / 6.0
	
	# Scale wage from 3g to 25g based on average stat
	var base_wage = 3 + int((average_stat - 1) * 22 / 199)
	
	# Add some randomness (±2g)
	return clampi(base_wage + randi_range(-2, 2), 3, 25)

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
