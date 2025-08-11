@tool
extends EditorScript

func _run():
	var RoleResource = load("res://resources/Role.gd")
	if RoleResource == null:
		push_error("Role.gd not found at res://resources/Role.gd")
		return

	# Ensure folder exists
	DirAccess.make_dir_recursive_absolute("res://data/roles")

	var defs = [
		{"path":"res://data/roles/navigator_role.tres", "id":"navigator", "display":"Navigator",
		 "atk":5, "def":8, "hp":14, "stat_name":&"navigation", "stat":4},
		{"path":"res://data/roles/healer_role.tres", "id":"healer", "display":"Healer",
		 "atk":3, "def":6, "hp":15, "stat_name":&"medicine", "stat":4},
		{"path":"res://data/roles/tank_role.tres", "id":"tank", "display":"Tank",
		 "atk":4, "def":9, "hp":20, "stat_name":&"guard", "stat":3},
		{"path":"res://data/roles/damage_role.tres", "id":"damage", "display":"Damage",
		 "atk":9, "def":5, "hp":12, "stat_name":&"hunt", "stat":3},
	]

	for d in defs:
		var res = RoleResource.new()
		res.id = d["id"]
		res.display_name = d["display"]
		res.base_attack = d["atk"]
		res.base_defense = d["def"]
		res.base_hp = d["hp"]
		res.role_stat_name = d["stat_name"]
		res.base_role_stat = d["stat"]
		var err = ResourceSaver.save(res, d["path"])
		if err != OK:
			push_error("Failed to save: %s (err %s)" % [d["path"], str(err)])
		else:
			print("Saved ", d["path"])
