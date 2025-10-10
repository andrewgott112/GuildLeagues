extends Resource
class_name RoleResource

@export var id: StringName
@export var display_name: String = ""
@export var base_attack: int = 5
@export var base_defense: int = 5
@export var base_hp: int = 15
@export var role_stat_name: StringName = &"navigation"
@export var base_role_stat: int = 3

# NEW: Role-specific stat tendencies (for new stats)
@export var speed_range: Vector2i = Vector2i(60, 140)       # min, max
@export var accuracy_range: Vector2i = Vector2i(60, 140)
@export var crit_range: Vector2i = Vector2i(60, 140)

# NEW: Role personality tendencies
@export var aggression_range: Vector2 = Vector2(0.3, 0.7)   # min, max
@export var caution_range: Vector2 = Vector2(0.3, 0.7)
@export var teamwork_range: Vector2 = Vector2(0.4, 0.8)
@export var ambition_range: Vector2 = Vector2(0.3, 0.7)

# NEW: Role characteristics
@export var peak_age_range: Vector2i = Vector2i(3, 8)
@export var injury_resistance_modifier: int = 0  # -20 to +20

# Description
@export_multiline var description: String = "A versatile adventurer"

func get_role_description() -> String:
	"""Get a description of the role's strengths"""
	return description

func generate_speed() -> int:
	return randi_range(speed_range.x, speed_range.y)

func generate_accuracy() -> int:
	return randi_range(accuracy_range.x, accuracy_range.y)

func generate_crit_chance() -> int:
	return randi_range(crit_range.x, crit_range.y)

func generate_aggression() -> float:
	return randf_range(aggression_range.x, aggression_range.y)

func generate_caution() -> float:
	return randf_range(caution_range.x, caution_range.y)

func generate_teamwork() -> float:
	return randf_range(teamwork_range.x, teamwork_range.y)

func generate_ambition() -> float:
	return randf_range(ambition_range.x, ambition_range.y)

func generate_peak_age() -> int:
	return randi_range(peak_age_range.x, peak_age_range.y)

func get_injury_resistance_base() -> int:
	return 100 + injury_resistance_modifier
