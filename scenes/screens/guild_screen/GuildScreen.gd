extends Control

@onready var season_label: Label = $Margin/Column/TopBar/SeasonLabel
@onready var lbl_gold: Label    = $Margin/Column/TopBar/GoldBox/GoldValue
@onready var roster_list: VBoxContainer = $Margin/Column/RosterPanel/MarginContainer/RosterPanelVBox/RosterScroll/RosterList

@onready var btn_to_draft: Button = $Margin/Column/BottomBar/ToDraft
@onready var btn_to_dungeons: Button = $Margin/Column/BottomBar/ToDungeon
@onready var btn_save: Button     = $Margin/Column/BottomBar/SaveBtn
@onready var btn_menu: Button     = $Margin/Column/BottomBar/ToMenu

func _ready() -> void:
	_wire_buttons()
	_refresh_header()
	_refresh_cta()
	_populate_roster()

	# Refresh when game state changes
	if Game.has_signal("phase_changed") and not Game.phase_changed.is_connected(_on_phase_or_season_changed):
		Game.phase_changed.connect(_on_phase_or_season_changed)
	if Game.has_signal("season_changed") and not Game.season_changed.is_connected(_on_phase_or_season_changed):
		Game.season_changed.connect(_on_phase_or_season_changed)

func _wire_buttons() -> void:
	btn_to_draft.pressed.connect(_on_to_draft)
	btn_to_dungeons.pressed.connect(_on_to_dungeons)
	btn_save.pressed.connect(_on_save_pressed)
	btn_menu.pressed.connect(_on_main_menu)

# ---------- Header + CTA ----------

func _refresh_header() -> void:
	season_label.text = "Season %d" % Game.season
	lbl_gold.text = str(Game.gold)
	_refresh_cta()

func _phase_text() -> String:
	if Game.has_method("season_progress_text"):
		return Game.season_progress_text()
	if Game.has_method("phase_name"):
		return Game.phase_name()

	if Game.phase == Game.Phase.DRAFT:
		return "Draft"
	elif Game.phase == Game.Phase.GUILD:
		return "Guild"
	elif Game.phase == Game.Phase.DUNGEONS:
		return "Dungeons"
	else:
		return "—"

func _refresh_cta() -> void:
	# Draft button logic
	var draft_unlocked: bool = Game.can_start_draft()
	btn_to_draft.disabled = not draft_unlocked
	btn_to_draft.tooltip_text = "Start the Draft" if draft_unlocked else "Complete the Playoffs to unlock the Draft."
	btn_to_draft.modulate = Color(1, 1, 1, 1.0) if draft_unlocked else Color(1, 1, 1, 0.6)
	
	# Dungeons button logic
	var dungeons_unlocked: bool = _can_access_dungeons()
	btn_to_dungeons.disabled = not dungeons_unlocked
	btn_to_dungeons.tooltip_text = "Explore Dungeons" if dungeons_unlocked else "Need at least one adventurer to explore dungeons."
	btn_to_dungeons.modulate = Color(1, 1, 1, 1.0) if dungeons_unlocked else Color(1, 1, 1, 0.6)

func _can_access_dungeons() -> bool:
	return Game.roster.size() > 0 and Game.phase != Game.Phase.DRAFT

func _can_start_draft() -> bool:
	if Game.has_method("can_start_draft"):
		return Game.can_start_draft()

	var playoffs_ok := true
	if "playoffs_done_for_season" in Game:
		playoffs_ok = Game.playoffs_done_for_season
	return Game.phase == Game.Phase.GUILD and playoffs_ok

func _on_phase_or_season_changed(_arg: Variant = null) -> void:
	_refresh_header()
	_refresh_cta()

# ---------- Roster UI ----------

func _populate_roster() -> void:
	# Clear old rows
	for c in roster_list.get_children():
		c.queue_free()

	if Game.roster.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No adventurers yet. Head to the draft!"
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		roster_list.add_child(empty_label)
		return

	# Create a simple header row
	roster_list.add_child(_make_header_row())

	# One row per adventurer
	for adv in Game.roster:
		roster_list.add_child(_make_roster_row(adv))

func _make_header_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_col_label("Name", true, 200))
	row.add_child(_col_label("Role", true, 120))
	row.add_child(_col_label("Wage", true, 80))
	row.add_child(_col_label("Details", true, 80))
	return row

func _make_roster_row(adv: Resource) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_col_label(adv.name, false, 200))
	row.add_child(_col_label(adv.role.display_name if adv.role else "—", false, 120))
	row.add_child(_col_label("%dg" % adv.wage, false, 80))
	
	# Add View Details button with fixed width
	var details_btn := Button.new()
	details_btn.text = "View"
	details_btn.custom_minimum_size = Vector2(70, 28)
	details_btn.size_flags_horizontal = 0  # Don't expand
	details_btn.pressed.connect(func():
		_show_character_details(adv)
	)
	
	var button_container := Control.new()
	button_container.custom_minimum_size.x = 80
	button_container.size_flags_horizontal = 0
	button_container.add_child(details_btn)
	details_btn.position.x = 5  # Small offset from left edge
	
	row.add_child(button_container)
	
	return row

func _col_label(text: String, is_header := false, width: int = 120) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = width
	l.size_flags_horizontal = 0  # Don't expand - use fixed width
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # Add ... if text too long
	if is_header:
		l.add_theme_color_override("font_color", Color(1,1,1))
		l.add_theme_constant_override("outline_size", 1)
	return l

# ---------- Buttons ----------

func _show_character_details(character) -> void:
	print("Attempting to show details for: %s" % character.name)
	
	# Load and show the character detail window
	var detail_scene_path = "res://scenes/ui/CharacterDetailWindow.tscn"
	
	if not ResourceLoader.exists(detail_scene_path):
		print("ERROR: Character detail window scene not found at: " + detail_scene_path)
		print("Please make sure you have created the scene file at that location")
		# Fallback: print to console
		print("=== CHARACTER DETAILS ===")
		print("Name: %s" % character.name)
		print("Role: %s" % (character.role.display_name if character.role else "None"))
		print("Attack: %d" % character.attack)
		print("Defense: %d" % character.defense)
		print("HP: %d" % character.hp)
		print("Role Stat: %d" % character.role_stat)
		print("Observe: %d" % character.observe_skill)
		print("Decide: %d" % character.decide_skill)
		print("Wage: %d" % character.wage)
		print("Monsters Killed: %d" % character.monsters_killed)
		print("Battles Won: %d" % character.battles_won)
		print("Battles Fought: %d" % character.battles_fought)
		print("========================")
		return
	
	print("Loading character detail window...")
	var detail_scene = load(detail_scene_path)
	var detail_window = detail_scene.instantiate()
	
	print("Adding window to scene tree...")
	add_child(detail_window)
	
	print("Calling show_character...")
	detail_window.show_character(character)
	
	# Auto-cleanup when the window is closed
	detail_window.visibility_changed.connect(func():
		if not detail_window.visible:
			detail_window.queue_free()
	)

func _on_to_draft() -> void:
	if Game.start_draft_gate():
		_switch_scene("res://scenes/screens/draft_screen/draft_screen.tscn")

func _on_to_dungeons() -> void:
	if _can_access_dungeons():
		Game.goto(Game.Phase.DUNGEONS)
		_switch_scene("res://scenes/screens/dungeon_screen/dungeon_screen.tscn")

func _on_save_pressed() -> void:
	print("Save not implemented yet.")

func _on_main_menu() -> void:
	_switch_scene("res://scenes/screens/main_menu/main_menu.tscn")

func _switch_scene(path: String) -> void:
	get_tree().change_scene_to_file(path)
