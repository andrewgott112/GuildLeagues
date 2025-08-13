# resources/Monster.gd
extends Resource
class_name MonsterResource

@export var name: String = "Goblin"
@export var level: int = 1
@export var monster_type: String = "Beast"

# Core combat stats (similar to adventurers but simplified)
@export var attack: int = 50
@export var defense: int = 40  
@export var hp: int = 60
@export var max_hp: int = 60

# Battle skills (monsters are generally less skilled than adventurers)
@export var observe_skill: int = 30
@export var decide_skill: int = 25

# AI behavior tendencies (0.0 to 1.0)
@export var aggression: float = 0.7  # How likely to attack vs defend
@export var intelligence: float = 0.3  # How smart their decisions are
@export var survival_instinct: float = 0.4  # How likely to flee when low health

# Current battle state
var current_hp: int
var is_alive: bool = true
var last_action: String = ""

func _init():
	current_hp = hp
	max_hp = hp

func reset_for_battle():
	current_hp = hp
	is_alive = true
	last_action = ""

func take_damage(amount: int) -> int:
	var actual_damage = max(1, amount - (defense / 10))  # Basic damage reduction
	current_hp = max(0, current_hp - actual_damage)
	if current_hp <= 0:
		is_alive = false
	return actual_damage

func get_health_percentage() -> float:
	return float(current_hp) / float(max_hp) if max_hp > 0 else 0.0

# Battle timing functions (similar to adventurers)
func get_observe_time() -> float:
	return max(0.8, 4.0 - (observe_skill * 3.2 / 200.0))  # Slightly slower than adventurers

func get_decide_time() -> float:
	return max(0.8, 4.0 - (decide_skill * 3.2 / 200.0))

# AI decision making
func choose_action(battle_context: Dictionary) -> String:
	var health_pct = get_health_percentage()
	var random_factor = randf()
	
	# Flee logic (if health is very low and has survival instinct)
	if health_pct < 0.2 and survival_instinct > 0.5 and random_factor < survival_instinct:
		return "flee"
	
	# Defend logic (if health is low or not very aggressive)
	if health_pct < 0.4 and random_factor > aggression:
		return "defend"
	
	# Default to attack (modified by aggression)
	if random_factor < aggression + 0.3:  # Base 30% + aggression
		return "attack"
	else:
		return "defend"

# Generate random monsters for encounters
static func generate_random_monster(level: int = 1) -> MonsterResource:
	var monster = MonsterResource.new()
	
	var names = ["Goblin", "Orc", "Skeleton", "Wolf", "Spider", "Rat", "Slime", "Bandit"]
	var types = ["Beast", "Undead", "Humanoid", "Construct"]
	
	monster.name = names.pick_random()
	monster.monster_type = types.pick_random()
	monster.level = level
	
	# Scale stats by level with some randomness
	var base_multiplier = 1.0 + (level - 1) * 0.3
	var variance = 0.2  # ±20% variance
	
	monster.attack = int(_random_stat(45, base_multiplier, variance))
	monster.defense = int(_random_stat(35, base_multiplier, variance))
	monster.hp = int(_random_stat(50, base_multiplier, variance))
	monster.max_hp = monster.hp
	monster.current_hp = monster.hp
	
	# Battle skills (generally lower than adventurers)
	monster.observe_skill = int(_random_stat(25, base_multiplier, variance * 0.5))
	monster.decide_skill = int(_random_stat(20, base_multiplier, variance * 0.5))
	
	# Random AI personality
	monster.aggression = randf_range(0.4, 0.9)
	monster.intelligence = randf_range(0.1, 0.5)
	monster.survival_instinct = randf_range(0.2, 0.7)
	
	return monster

static func _random_stat(base: int, multiplier: float, variance: float) -> float:
	var scaled = base * multiplier
	var random_offset = scaled * randf_range(-variance, variance)
	return max(5.0, scaled + random_offset)  # Minimum 5 for any stat
