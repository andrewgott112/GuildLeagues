extends Node
## Central game state & season/phase gating

# No Main Menu here — phases are just gameplay screens.
enum Phase { GUILD, DUNGEONS, PLAYOFFS, DRAFT }

signal phase_changed(new_phase: Phase)
signal season_changed(new_season: int)

var phase: Phase = Phase.GUILD
var season: int = 1
var gold: int = 20
var roster: Array = []

# -------------------------------------------------------------------
# Draft gate semantics:
#   Season 1: unlocked (draft_done_for_season = false)
#   When you ENTER Draft: set draft_done_for_season = true  (locks button)
#   After Playoffs (season roll): set draft_done_for_season = false (unlocks again)
# -------------------------------------------------------------------
var draft_done_for_season: bool = false
var playoffs_done_for_season: bool = false

# ───────────────────────────────────────────────────────────────────
# Phase helpers
# ───────────────────────────────────────────────────────────────────
func goto(p: Phase) -> void:
	phase = p
	emit_signal("phase_changed", p)

func phase_name() -> String:
	match phase:
		Phase.GUILD:     return "Guild"
		Phase.DUNGEONS:  return "Dungeons"
		Phase.PLAYOFFS:  return "Playoffs"
		Phase.DRAFT:     return "Draft"
		_:               return "~"

# ───────────────────────────────────────────────────────────────────
# Draft gating
# ───────────────────────────────────────────────────────────────────
func can_start_draft() -> bool:
	# Draft can only be started from Guild and only if the gate is open
	return phase == Phase.GUILD and not draft_done_for_season

## Preferred entry point from GuildScreen:
## Closes the gate *immediately* so when you come back to Guild the button is locked.
func start_draft_gate() -> bool:
	if not can_start_draft():
		return false
	draft_done_for_season = true        # close gate as soon as we enter Draft
	playoffs_done_for_season = false    # we're in a new cycle until playoffs finish
	goto(Phase.DRAFT)
	return true

## Back-compat alias (useful if your UI calls this name):
func start_new_draft_gate() -> bool:
	return start_draft_gate()

## Called by DraftScreen when "Finish Draft" is pressed.
## We *also* lock in start_draft_gate(), but keep this for safety/clarity.
func finish_draft() -> void:
	draft_done_for_season = true
	goto(Phase.GUILD)

# ───────────────────────────────────────────────────────────────────
# Season flow
# ───────────────────────────────────────────────────────────────────
func start_regular_season() -> bool:
	# If you want to force the player to draft before dungeons, keep this check.
	# Remove the draft_done_for_season check if you want to allow skipping.
	if phase != Phase.GUILD or not draft_done_for_season:
		return false
	goto(Phase.DUNGEONS)
	return true

func finish_regular_season() -> void:
	if phase == Phase.DUNGEONS:
		goto(Phase.PLAYOFFS)

## Call this when Playoffs end; it rolls the season and *reopens* the draft.
func finish_playoffs_and_roll_season() -> void:
	if phase != Phase.PLAYOFFS:
		return
	playoffs_done_for_season = true
	season += 1
	emit_signal("season_changed", season)

	# New season reset/unlock:
	draft_done_for_season = false
	playoffs_done_for_season = false
	goto(Phase.GUILD)

# ───────────────────────────────────────────────────────────────────
# New game
# ───────────────────────────────────────────────────────────────────
func start_new_game() -> void:
	season = 1
	gold = 20
	roster.clear()
	draft_done_for_season = false      # Season 1: unlocked
	playoffs_done_for_season = false
	goto(Phase.GUILD)
	emit_signal("season_changed", season)
