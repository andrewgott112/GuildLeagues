extends Resource
class_name AdventurerResource

@export var name: String = "Rookie"
@export var role: RoleResource   # <-- now recognized

@export var attack: int
@export var defense: int
@export var hp: int
@export var role_stat: int
@export var wage: int = 5

func apply_role_defaults() -> void:
	if role:
		attack = role.base_attack
		defense = role.base_defense
		hp = role.base_hp
		role_stat = role.base_role_stat
