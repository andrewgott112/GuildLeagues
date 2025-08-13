# scenes/ui/character_detail_window/CharacterDetailWindow.gd
extends AcceptDialog

# UI References - using find_child with fallbacks
var character_name: Label
var role_info: Label
var attack_value: Label  
var defense_value: Label
var health_value: Label
var role_stat_value: Label
var role_stat_label: Label
var observe_value: Label
var decide_value: Label
var monsters_killed_value: Label
var battles_won_value: Label
var battles_fought_value: Label
var wage_value: Label
var experience_value: Label
var close_button: Button

var current_character = null

func _ready():
	print("CharacterDetailWindow _ready() called")
	
	# Try to find nodes with error handling
	_find_ui_nodes()
	
	# Connect close button if it exists
	if close_button:
		close_button.pressed.connect(_on_close_pressed)
	
	# Make sure the dialog closes when clicking the X or pressing Escape
	close_requested.connect(_on_close_pressed)
	
	print("CharacterDetailWindow setup complete")

func _find_ui_nodes():
	# Use find_child() to locate nodes by name, which is more flexible
	character_name = find_child("CharacterName")
	role_info = find_child("RoleInfo")
	attack_value = find_child("AttackValue")
	defense_value = find_child("DefenseValue") 
	health_value = find_child("HealthValue")
	role_stat_value = find_child("RoleStatValue")
	role_stat_label = find_child("RoleStatLabel")
	observe_value = find_child("ObserveValue")
	decide_value = find_child("DecideValue")
	monsters_killed_value = find_child("MonstersKilledValue")
	battles_won_value = find_child("BattlesWonValue")
	battles_fought_value = find_child("BattlesFoughtValue")
	wage_value = find_child("WageValue")
	experience_value = find_child("ExperienceValue")
	close_button = find_child("CloseButton")
	
	# Debug: Print which nodes were found
	print("Found nodes:")
	print("  character_name: ", character_name != null)
	print("  role_info: ", role_info != null)
	print("  attack_value: ", attack_value != null)
	print("  close_button: ", close_button != null)

func show_character(character):
	print("show_character called for: ", character.name if character else "null")
	current_character = character
	_populate_character_data()
	popup_centered()
	print("popup_centered() called")

func _populate_character_data():
	if not current_character:
		print("No character to populate")
		return
	
	var char = current_character
	print("Populating data for: ", char.name)
	
	# Header Information
	if character_name:
		character_name.text = char.name
	
	if role_info:
		if char.role:
			role_info.text = "%s - %s" % [char.role.display_name, _get_role_description(char.role)]
		else:
			role_info.text = "No Role Assigned"
	
	# Core Stats - access properties directly
	if attack_value:
		attack_value.text = str(char.attack)
		attack_value.add_theme_color_override("font_color", _get_stat_color(char.attack))
	
	if defense_value:
		defense_value.text = str(char.defense)
		defense_value.add_theme_color_override("font_color", _get_stat_color(char.defense))
	
	if health_value:
		health_value.text = str(char.hp)
		health_value.add_theme_color_override("font_color", _get_stat_color(char.hp))
	
	# Role stat
	if role_stat_label and char.role:
		role_stat_label.text = str(char.role.role_stat_name).capitalize() + ":"
	
	if role_stat_value:
		role_stat_value.text = str(char.role_stat)
		role_stat_value.add_theme_color_override("font_color", _get_stat_color(char.role_stat))
	
	# Battle Skills - access properties directly
	if observe_value:
		var observe_skill_val = char.observe_skill
		var observe_time_val = 2.0  # Default fallback
		
		# Try to call get_observe_time() safely
		if char.has_method("get_observe_time"):
			observe_time_val = char.get_observe_time()
		
		var observe_text = "%d (%s - %.1fs)" % [
			observe_skill_val, 
			_get_skill_rating(observe_skill_val), 
			observe_time_val
		]
		observe_value.text = observe_text
		observe_value.add_theme_color_override("font_color", _get_stat_color(observe_skill_val))
	
	if decide_value:
		var decide_skill_val = char.decide_skill
		var decide_time_val = 2.0  # Default fallback
		
		# Try to call get_decide_time() safely
		if char.has_method("get_decide_time"):
			decide_time_val = char.get_decide_time()
		
		var decide_text = "%d (%s - %.1fs)" % [
			decide_skill_val, 
			_get_skill_rating(decide_skill_val), 
			decide_time_val
		]
		decide_value.text = decide_text
		decide_value.add_theme_color_override("font_color", _get_stat_color(decide_skill_val))
	
	# Combat Record - access properties directly
	if monsters_killed_value:
		monsters_killed_value.text = str(char.monsters_killed)
	
	if battles_won_value:
		battles_won_value.text = str(char.battles_won)
	
	if battles_fought_value:
		battles_fought_value.text = str(char.battles_fought)
	
	# Economic Information
	if wage_value:
		wage_value.text = "%dg per mission" % char.wage
	
	if experience_value:
		experience_value.text = _get_experience_level(char)
	
	print("Data population complete")

func _get_stat_color(value: int) -> Color:
	if value >= 160:
		return Color.GOLD
	elif value >= 120:
		return Color.LIGHT_GREEN
	elif value >= 80:
		return Color.CYAN
	elif value >= 40:
		return Color.WHITE
	else:
		return Color.LIGHT_GRAY

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

func _get_role_description(role: RoleResource) -> String:
	match role.id:
		&"navigator":
			return "Specializes in exploration and pathfinding"
		&"healer":
			return "Expert in medical aid and support"
		&"tank":
			return "Focuses on defense and protection"
		&"damage":
			return "Excels in combat and offense"
		_:
			return "Versatile adventurer"

func _get_experience_level(char) -> String:
	var total_battles = char.battles_fought
	var monsters_killed = char.monsters_killed
	
	if total_battles == 0 and monsters_killed == 0:
		return "Rookie"
	elif total_battles >= 20 or monsters_killed >= 50:
		return "Veteran"
	elif total_battles >= 10 or monsters_killed >= 25:
		return "Experienced"
	elif total_battles >= 5 or monsters_killed >= 10:
		return "Seasoned"
	else:
		return "Novice"

func _on_close_pressed():
	print("Close button pressed")
	hide()
