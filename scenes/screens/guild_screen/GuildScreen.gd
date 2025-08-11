extends Control

@onready var season_label: Label = $Margin/Column/TopBar/SeasonLabel
@onready var lbl_gold: Label    = $Margin/Column/TopBar/GoldBox/GoldValue
@onready var roster_list: VBoxContainer = $Margin/Column/RosterPanel/MarginContainer/RosterPanelVBox/RosterScroll/RosterList

@onready var btn_to_draft: Button = $Margin/Column/BottomBar/ToDraft
@onready var btn_save: Button     = $Margin/Column/BottomBar/SaveBtn
@onready var btn_menu: Button     = $Margin/Column/BottomBar/ToMenu

func _ready() -> void:
	_wire_buttons()
	_refresh_header()
	_refresh_cta()
	_populate_roster()

	# Refresh when game state changes (if your Game.gd emits these)
	if Game.has_signal("phase_changed") and not Game.phase_changed.is_connected(_on_phase_or_season_changed):
		Game.phase_changed.connect(_on_phase_or_season_changed)
	if Game.has_signal("season_changed") and not Game.season_changed.is_connected(_on_phase_or_season_changed):
		Game.season_changed.connect(_on_phase_or_season_changed)

func _wire_buttons() -> void:
	btn_to_draft.pressed.connect(_on_to_draft)
	btn_save.pressed.connect(_on_save_pressed)
	btn_menu.pressed.connect(_on_main_menu)

# ---------- Header + CTA ----------

func _refresh_header() -> void:
	season_label.text = "Season %d" % Game.season
	lbl_gold.text = str(Game.gold)
	_refresh_cta()

# Replace your _phase_text() with this minimal-safe version
func _phase_text() -> String:
	# Prefer helpers if you added them
	if Game.has_method("season_progress_text"):
		return Game.season_progress_text()
	if Game.has_method("phase_name"):
		# Many helpers accept the phase value
		return Game.phase_name()

	# Fallbacks using only phases that exist today
	if Game.phase == Game.Phase.DRAFT:
		return "Draft"
	elif Game.phase == Game.Phase.GUILD:
		return "Guild"
	else:
		return "—"


func _refresh_cta() -> void:
	var unlocked: bool = Game.can_start_draft()
	btn_to_draft.disabled = not unlocked
	btn_to_draft.tooltip_text = "Start the Draft" if unlocked else "Complete the Playoffs to unlock the Draft."
	btn_to_draft.modulate = Color(1, 1, 1, 1.0) if unlocked else Color(1, 1, 1, 0.6)

func _can_start_draft() -> bool:
	# Prefer Game.can_start_draft() if present.
	if Game.has_method("can_start_draft"):
		return Game.can_start_draft()

	# Otherwise: only from Guild, and require playoffs flag if present.
	var playoffs_ok := true
	if "playoffs_done_for_season" in Game:
		playoffs_ok = Game.playoffs_done_for_season
	return Game.phase == Game.Phase.GUILD and playoffs_ok

# Replace the handler signature so "null" is allowed
func _on_phase_or_season_changed(_arg: Variant = null) -> void:
	_refresh_header()
	_refresh_cta()
	# If your roster changes when phases change, you can also refresh it:
	# _populate_roster()


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
	row.add_child(_col_label("Name", true))
	row.add_child(_col_label("Role", true))
	row.add_child(_col_label("ATK", true))
	row.add_child(_col_label("DEF", true))
	row.add_child(_col_label("HP", true))
	row.add_child(_col_label("Role Stat", true))
	row.add_child(_col_label("Wage", true))
	return row

func _make_roster_row(adv: Resource) -> Control:
	var row := HBoxContainer.new()
	row.add_child(_col_label(adv.name))
	row.add_child(_col_label(adv.role.display_name if adv.role else "—"))
	row.add_child(_col_label(str(adv.attack)))
	row.add_child(_col_label(str(adv.defense)))
	row.add_child(_col_label(str(adv.hp)))

	var role_stat_name: StringName = adv.role.role_stat_name if adv.role else &"stat"
	row.add_child(_col_label("%s: %s" % [str(role_stat_name), str(adv.role_stat)]))
	row.add_child(_col_label("%dg" % adv.wage))
	return row

func _col_label(text: String, is_header := false) -> Label:
	var l := Label.new()
	l.text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	if is_header:
		l.add_theme_color_override("font_color", Color(1,1,1))
		l.add_theme_constant_override("outline_size", 1)
	return l

# ---------- Buttons ----------

func _on_to_draft() -> void:
	if Game.start_draft_gate():
		_switch_scene("res://scenes/screens/draft_screen/draft_screen.tscn")

	# Close the gate so Draft can’t be re-entered until next playoffs.
	if Game.has_method("start_new_draft_gate"):
		Game.start_new_draft_gate()

	Game.goto(Game.Phase.DRAFT)
	_switch_scene("res://scenes/screens/draft_screen/draft_screen.tscn")

func _on_save_pressed() -> void:
	print("Save not implemented yet.")

func _on_main_menu() -> void:
	
	_switch_scene("res://scenes/screens/main_menu/main_menu.tscn")

func _switch_scene(path: String) -> void:
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		push_error("Scene not found or not a PackedScene: " + path)
		return
	var inst: Node = packed.instantiate()
	get_tree().root.add_child(inst)
	queue_free()
