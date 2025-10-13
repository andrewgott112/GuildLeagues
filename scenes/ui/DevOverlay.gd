# ═══════════════════════════════════════════════════════════════════
# DEV INFO OVERLAY
# ═══════════════════════════════════════════════════════════════════
# Add this to any screen you want to show dev info on.
# 
# Usage in GuildScreen.gd (or any other screen):
# 
# @onready var dev_overlay = preload("res://scripts/ui/DevOverlay.gd").new()
# 
# func _ready():
#     add_child(dev_overlay)
#     dev_overlay.show_overlay()
# ═══════════════════════════════════════════════════════════════════

extends Control
class_name DevOverlay

var panel: PanelContainer
var info_label: Label
var update_timer: Timer
var visible_state: bool = false

func _ready():
	# Only create if dev tools are enabled
	if not DevTools.dev_mode_enabled:
		queue_free()
		return
	
	_create_overlay()
	
	# Update timer
	update_timer = Timer.new()
	update_timer.wait_time = 0.5
	update_timer.timeout.connect(_update_info)
	add_child(update_timer)
	
	# Listen for F10 to toggle
	set_process_input(true)

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F10:
			toggle_overlay()

func _create_overlay():
	# Create semi-transparent panel in top-left
	panel = PanelContainer.new()
	panel.position = Vector2(8, 8)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	
	# Style the panel
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.7)
	style.border_color = Color.YELLOW
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	panel.add_theme_stylebox_override("panel", style)
	
	# Add margin
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	
	# Info label
	info_label = Label.new()
	info_label.add_theme_font_size_override("font_size", 11)
	info_label.add_theme_color_override("font_color", Color.YELLOW)
	margin.add_child(info_label)
	
	add_child(panel)
	panel.hide()

func show_overlay():
	visible_state = true
	panel.show()
	update_timer.start()
	_update_info()

func hide_overlay():
	visible_state = false
	panel.hide()
	update_timer.stop()

func toggle_overlay():
	if visible_state:
		hide_overlay()
	else:
		show_overlay()

func _update_info():
	if not visible_state:
		return
	
	var text = "🛠️ DEV INFO (F10 hide, F12 tools)\n"
	text += "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
	text += "Season %d | %s | %dg\n" % [Game.season, Game.phase_name(), Game.gold]
	text += "Roster: %d | FA: %d\n" % [Game.roster.size(), Game.free_agent_pool.size()]
	text += "Contracts: %d / %d\n" % [Game.get_player_contracts().size(), Game.active_contracts.size()]
	text += "Salary: %d/%d (%d free)\n" % [
		Game.get_player_total_salary(),
		Game.salary_cap,
		Game.get_player_salary_space()
	]
	text += "Draft: %s | Playoffs: %s\n" % [
		"✓" if Game.draft_done_for_season else "✗",
		"✓" if Game.playoffs_done_for_season else "✗"
	]
	
	# Add character ages if roster exists
	if Game.roster.size() > 0:
		var ages = []
		for char in Game.roster:
			ages.append(char.age)
		var avg_age = ages.reduce(func(a, b): return a + b, 0) / float(ages.size())
		text += "Avg Age: %.1f | Range: %d-%d\n" % [avg_age, ages.min(), ages.max()]
	
	info_label.text = text
