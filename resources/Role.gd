extends Resource
class_name RoleResource

@export var id: StringName
@export var display_name: String = ""
@export var base_attack: int = 5
@export var base_defense: int = 5
@export var base_hp: int = 15
@export var role_stat_name: StringName = &"navigation" # navigator/medicine/guard/hunt
@export var base_role_stat: int = 3
