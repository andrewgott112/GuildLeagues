extends RefCounted
class_name ScoutingUIHelper

# ═══════════════════════════════════════════════════════════════════
# COLOR CODING
# ═══════════════════════════════════════════════════════════════════

static func get_confidence_color(confidence: float) -> Color:
	"""Get color based on confidence level"""
	if confidence >= 0.95:
		return Color.GREEN  # Confirmed
	elif confidence >= 0.5:
		return Color.YELLOW  # Estimated
	else:
		return Color.GRAY  # Unknown

static func get_confidence_icon(confidence: float) -> String:
	"""Get icon based on confidence level"""
	if confidence >= 0.95:
		return "✓"  # Confirmed
	elif confidence >= 0.5:
		return "⚔️"  # Revealed through combat/play
	else:
		return "🔍"  # Scouted or unknown

# ═══════════════════════════════════════════════════════════════════
# STAT DISPLAY FORMATTING
# ═══════════════════════════════════════════════════════════════════

static func format_stat_with_confidence(
	stat_name: String, 
	character_name: String,
	show_confidence: bool = true
) -> Dictionary:
	"""
	Returns formatted stat information
	Returns: { "display": String, "color": Color, "tooltip": String }
	"""
	var info = Game.get_scouting_info(character_name)
	
	if not info or not info.stats_known.has(stat_name):
		return {
			"display": "???",
			"color": Color.GRAY,
			"tooltip": "No information available"
		}
	
	var stat = info.stats_known[stat_name]
	var display = stat.get_display_value()
	var color = get_confidence_color(stat.confidence)
	
	# Build tooltip
	var tooltip = "%s\n" % stat_name.capitalize()
	tooltip += "Confidence: %.0f%%\n" % (stat.confidence * 100)
	tooltip += stat.get_confidence_level()
	
	if stat.experiences > 0:
		tooltip += "\nObserved %d times" % stat.experiences
	
	if show_confidence:
		display += " " + get_confidence_icon(stat.confidence)
	
	return {
		"display": display,
		"color": color,
		"tooltip": tooltip
	}

# ═══════════════════════════════════════════════════════════════════
# CHARACTER SUMMARY
# ═══════════════════════════════════════════════════════════════════

static func get_character_knowledge_summary(character_name: String) -> String:
	"""Get a summary of what we know about a character"""
	var info = Game.get_scouting_info(character_name)
	
	if not info:
		return "Unknown prospect"
	
	var overall_confidence = info.get_overall_confidence()
	var summary = "Knowledge: %.0f%%\n" % (overall_confidence * 100)
	
	# Count known stats
	var known_combat_stats = 0
	var known_hidden_stats = 0
	
	var combat_stats = ["attack", "defense", "hp", "speed", "accuracy", "crit_chance"]
	var hidden_stats = ["potential", "injury_prone", "mental_fortitude", "loyalty_base"]
	
	for stat_name in combat_stats:
		if info.is_stat_known(stat_name, 0.5):
			known_combat_stats += 1
	
	for stat_name in hidden_stats:
		if info.is_stat_known(stat_name, 0.5):
			known_hidden_stats += 1
	
	summary += "Combat stats known: %d/%d\n" % [known_combat_stats, combat_stats.size()]
	summary += "Hidden traits known: %d/%d\n" % [known_hidden_stats, hidden_stats.size()]
	
	# Add experience summary
	if info.combat_experiences > 0:
		summary += "\nCombat experience: %d battles" % info.combat_experiences
	if info.training_sessions > 0:
		summary += "\nTraining sessions: %d" % info.training_sessions
	
	return summary

# ═══════════════════════════════════════════════════════════════════
# STAT BAR VISUALIZATION
# ═══════════════════════════════════════════════════════════════════

static func create_confidence_bar(
	stat_name: String,
	character_name: String,
	bar_width: int = 200
) -> Dictionary:
	"""
	Create data for a confidence bar visualization
	Returns: { "filled_width": int, "color": Color, "display_text": String }
	"""
	var info = Game.get_scouting_info(character_name)
	
	if not info or not info.stats_known.has(stat_name):
		return {
			"filled_width": 0,
			"color": Color.GRAY,
			"display_text": "???"
		}
	
	var stat = info.stats_known[stat_name]
	var character = Game.get_character_by_name(character_name)
	
	if not character:
		return {
			"filled_width": 0,
			"color": Color.GRAY,
			"display_text": "???"
		}
	
	# Get the actual value for bar fill
	var true_value = character.get(stat_name)
	var filled_width = int((true_value / 200.0) * bar_width)
	
	# Color based on confidence
	var color = get_confidence_color(stat.confidence)
	
	# If low confidence, make bar semi-transparent/foggy
	if stat.confidence < 0.5:
		color.a = 0.3  # Very foggy
	elif stat.confidence < 0.75:
		color.a = 0.6  # Somewhat foggy
	else:
		color.a = 1.0  # Clear
	
	return {
		"filled_width": filled_width,
		"color": color,
		"display_text": stat.get_display_value()
	}

# ═══════════════════════════════════════════════════════════════════
# PROSPECT CARD TEXT
# ═══════════════════════════════════════════════════════════════════

static func get_prospect_card_text(character: AdventurerResource) -> String:
	"""Get formatted text for a prospect card in draft"""
	var text = "[b]%s[/b]\n" % character.name
	text += "[i]%s[/i]\n\n" % character.get_role_name()
	
	# Combat stats
	text += "[color=cyan]Combat Stats:[/color]\n"
	var combat_stats = [
		["Attack", "attack"],
		["Defense", "defense"],
		["HP", "hp"],
		["Speed", "speed"],
		["Accuracy", "accuracy"],
		["Crit", "crit_chance"]
	]
	
	for stat_pair in combat_stats:
		var stat_label = stat_pair[0]
		var stat_name = stat_pair[1]
		var stat_data = format_stat_with_confidence(stat_name, character.name, true)
		text += "%s: [color=#%s]%s[/color]\n" % [
			stat_label,
			stat_data.color.to_html(false),
			stat_data.display
		]
	
	# Overall knowledge
	text += "\n[color=gray]%s[/color]" % get_character_knowledge_summary(character.name)
	
	return text

# ═══════════════════════════════════════════════════════════════════
# REVELATION LOG (for debugging/player feedback)
# ═══════════════════════════════════════════════════════════════════

static func get_revelation_message(
	character_name: String,
	stat_name: String,
	context: String
) -> String:
	"""Get a message about a stat revelation"""
	var messages = {
		"attack": "You learned more about %s's offensive capability through %s",
		"defense": "You learned more about %s's defensive prowess through %s",
		"hp": "You learned more about %s's durability through %s",
		"speed": "You learned more about %s's speed through %s",
		"accuracy": "You learned more about %s's accuracy through %s",
		"crit_chance": "You learned more about %s's critical strike ability through %s",
		"potential": "You learned more about %s's growth potential through %s",
		"injury_prone": "You learned more about %s's injury risk through %s",
		"mental_fortitude": "You learned more about %s's mental strength through %s",
		"loyalty_base": "You learned more about %s's loyalty through %s",
	}
	
	var template = messages.get(stat_name, "You learned more about %s through %s")
	return template % [character_name, context]
