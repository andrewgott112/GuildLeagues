# Guild Leagues - Development Roadmap

**Last Updated:** 10/10/2025 
**Current Phase:** Pre-Alpha - Foundation Work  
**Timeline:** Open-ended, quality over speed  

---

## Roadmap Philosophy

### Build Strategy: Vertical Slices
Rather than building all systems to 10% completion, we build one complete flow at a time:
1. Get ONE complete season cycle working
2. Expand with more activities and depth
3. Polish and balance
4. Add meta-progression

### Success Metrics
- Can complete full season without bugs
- Battles feel fair and readable 
- Character attachment develops naturally
- Decisions feel meaningful
- Each season feels different

---

## Phase Overview

```
PHASE 1: Foundation (4-6 weeks)
└─ Character stats, contracts, persistence

PHASE 2: Combat Rebuild (6-8 weeks)  
└─ Autobattle system, battlefields, replays

PHASE 3: Draft Overhaul (3-4 weeks)
└─ Hidden stats, negotiation, staff

PHASE 4: Season Activities (4-6 weeks)
└─ Training, minor fights, dungeon fixes

PHASE 5: Integration (4-6 weeks)
└─ Free agency, injuries, loyalty

PHASE 6: Alpha Polish (3-4 weeks)
└─ Balance, UI, testing

════════════════════════════════════
ALPHA COMPLETE: ~24-34 weeks (6-8 months)
```

---

## PHASE 1: Foundation Systems

**Goal:** Expand core data structures to support full vision without breaking existing game.

### 1.1 Character Stats Expansion
**Priority:** Critical (blocks everything)  
**Estimated Time:** 1-2 weeks  

**Tasks:**
- [X] Expand AdventurerResource.gd with new stats (speed, accuracy, crit_chance)
- [ ] Add hidden attributes (potential, peak_age, injury_prone, mental_fort, loyalty_base)
- [ ] Add personality traits (aggression, caution)
- [ ] Add status effects (injuries array, madness_level, seasons_played, age)
- [ ] Create migration script to update existing adventurers
- [ ] Update character detail window to show new stats
- [ ] Add stat growth system (level up logic)
- [ ] Test: Create character, level them up, verify stats increase correctly

**Deliverable:** Expanded character system that won't need changes later

---

### 1.2 Contract System
**Priority:** Critical (blocks free agency, staff, persistence)  
**Estimated Time:** 2 weeks

**Tasks:**
- [ ] Create Contract class in Game.gd (character, seasons_remaining, salary_per_season, team, signed_date)
- [ ] Add contract tracking to Game.gd (active_contracts array, sign_contract function, process_contract_expirations function)
- [ ] Update AITeamResource to track contracts (signed_contracts array, salary_cap, get_total_salary function)
- [ ] Add simple salary cap enforcement
- [ ] Add contract expiration logic
- [ ] Test: Sign contract, advance season, verify it expires

**Deliverable:** Working contract system that tracks ownership and expirations

---

### 1.3 Roster Persistence
**Priority:** Critical (required for persistent world)  
**Estimated Time:** 1 week

**Tasks:**
- [ ] Remove roster reset in Game.finish_playoffs_and_roll_season()
- [ ] Add aging logic instead (seasons_played += 1, age += 1 for all characters)
- [ ] Create free agent pool (free_agent_pool array in Game.gd)
- [ ] Test: Complete season, verify rosters persist, AI teams keep players

**Deliverable:** Characters persist across seasons, no more roster resets

---

### 1.4 Hidden Information System
**Priority:** High (needed for draft)  
**Estimated Time:** 1-2 weeks

**Tasks:**
- [ ] Create ScoutingInfo class (character ref, reveal_level 0-4, stats_known dict, confidence dict)
- [ ] Add scouting data to Game.gd (scouting_database dict, get_scouting_info function, reveal_stat function)
- [ ] Create stat revelation through gameplay (reveal_combat_stats function after battles)
- [ ] Test: Create unknown character, play battles, verify stats reveal over time

**Deliverable:** System for tracking what player knows about each character

---

### 1.5 Phase 1 Integration Test
**Tasks:**
- [ ] Create test scenario: Draft 3 characters with hidden stats
- [ ] Sign them to contracts (2-3 seasons)
- [ ] Play through season
- [ ] Advance season, verify contracts decrement
- [ ] Verify roster persists
- [ ] Verify stats revealed through play

**Checkpoint:** Foundation is solid and ready to build on

---

## PHASE 2: Combat System Rebuild

**Goal:** Replace turn-based combat with real-time autobattle + replay system.

### 2.1 Battlefield Scene Setup
**Priority:** Critical (foundation for autobattle)  
**Estimated Time:** 1-2 weeks

**Tasks:**
- [ ] Create BattlefieldScene.tscn base template (TileMap, SpawnPoints, Camera2D, BattleUI)
- [ ] Create 3 battlefield templates: dungeon_ruins.tscn, minor_guild_grounds.tscn, playoff_arena.tscn
- [ ] Add simple placeholder art (ColorRect tiles, basic shapes for obstacles, spawn point markers)
- [ ] Create BattlefieldManager.gd (battlefield_type export, ally_spawns array, enemy_spawns array, get_spawn_position function)
- [ ] Test: Load battlefield, verify spawns work, camera can pan

**Deliverable:** 3 working battlefield scenes ready for combat

---

### 2.2 Combat Character Controller
**Priority:** Critical (how characters move/act)  
**Estimated Time:** 2-3 weeks

**Tasks:**
- [ ] Create BattleCharacter.gd extends CharacterBody2D
- [ ] Add phase system (OBSERVE, DECIDE, ACTION with timers)
- [ ] Implement advance_phase function
- [ ] Implement start_observe_phase and assess_battlefield functions
- [ ] Implement start_decide_phase and choose_action functions
- [ ] Implement start_action_phase and execute_chosen_action functions
- [ ] Implement basic AI decision making (attack nearest, defend if low HP, move toward target)
- [ ] Add movement to targets (pathfinding)
- [ ] Add attack animations (simple tween to target)
- [ ] Add health bars above characters
- [ ] Test: Spawn 2 characters, verify they move and attack each other

**Deliverable:** Characters autonomously fight on battlefield

---

### 2.3 Battle Manager & Victory Conditions
**Priority:** Critical (managing battle flow)  
**Estimated Time:** 1 week

**Tasks:**
- [ ] Create BattleManager.gd with signals (battle_started, battle_finished, character_died)
- [ ] Add ally_characters and enemy_characters arrays
- [ ] Implement start_battle function (spawn characters, start timer)
- [ ] Implement check_victory_conditions in _process
- [ ] Implement end_battle function
- [ ] Add battle UI overlay (time, alive counts)
- [ ] Add speed controls (1x, 2x, 4x buttons)
- [ ] Add pause button
- [ ] Test: Full battle from start to victory/defeat

**Deliverable:** Complete battles with win/loss detection

---

### 2.4 Combat Moment Tracking (Simple)
**Priority:** Medium (for replay, but can iterate)  
**Estimated Time:** 1-2 weeks

**Tasks:**
- [ ] Create CombatMoment class (timestamp, type, impact_score, description, characters_involved)
- [ ] Add tracked_moments array to BattleManager
- [ ] Implement track_damage_spike function (damage > 40 threshold)
- [ ] Implement track_clutch_save function (heal when ally < 10% HP)
- [ ] Implement select highest-impact moment after battle
- [ ] Test: Fight battle, verify moments are tracked

**Deliverable:** System identifies key battle moments

---

### 2.5 Basic Replay System
**Priority:** Medium (can be simple for Alpha)  
**Estimated Time:** 1-2 weeks

**Tasks:**
- [ ] Record character positions during battle (replay_data array of snapshots)
- [ ] Implement record_frame function
- [ ] Create replay playback function (play_replay with start/end time)
- [ ] Add post-battle screen with replay button
- [ ] Test: Win battle, watch 5-second replay of key moment

**Deliverable:** Simple replay system showing key moment

---

### 2.6 Integrate Autobattle with Existing Game
**Priority:** Critical (connect new combat to old systems)  
**Estimated Time:** 1 week

**Tasks:**
- [ ] Replace BattleWindow.tscn calls with new autobattle in DungeonScreen.gd
- [ ] Update playoff matches to use autobattle
- [ ] Remove old turn-based combat code (BattleWindow.tscn, old BattleSystem.gd logic)
- [ ] Test: Full game loop with new combat in all contexts

**Deliverable:** Autobattle working in dungeons and playoffs

---

### 2.7 Phase 2 Integration Test
**Tasks:**
- [ ] Draft team, explore dungeon, fight monster, watch autobattle
- [ ] Complete dungeon run
- [ ] Enter playoffs, watch playoff match, see replay
- [ ] Verify combat feels balanced (~60 sec battles)
- [ ] Verify replays show cool moments

**Checkpoint:** New combat system fully integrated and working

---

## PHASE 3: Draft System Overhaul

**Goal:** Add hidden stats, contracts, and staff to draft.

### 3.1 Hidden Stat UI
**Priority:** High (core to discovery gameplay)  
**Estimated Time:** 2 weeks

**Tasks:**
- [ ] Design stat display for unknown prospects (Level 0: "???", Level 1: "40-70", Level 2: "50-60", Level 3: "55")
- [ ] Create ProspectCard.gd component with display_stat function
- [ ] Add stat reveal visualization (fog clearing effect)
- [ ] Update draft screen to use new card display
- [ ] Test: View draft prospects with varying scouting levels

**Deliverable:** Draft shows hidden/partial information based on scouting

---

### 3.2 Contract Negotiation UI
**Priority:** High (required for contracts)  
**Estimated Time:** 1-2 weeks

**Tasks:**
- [ ] Create ContractNegotiationWindow.tscn (character info, demand display, offer sliders, salary cap info, buttons)
- [ ] Implement simple negotiation logic (evaluate_offer function)
- [ ] Add to draft flow: Pick, Negotiate, Sign or Release
- [ ] Test: Draft character, negotiate, sign contract

**Deliverable:** Working contract negotiation in draft

---

### 3.3 Staff Drafting
**Priority:** High (needed for scouting/training)  
**Estimated Time:** 1-2 weeks

**Tasks:**
- [ ] Expand draft prospect generation (15 fighters, 5 staff prospects)
- [ ] Add generate_staff_prospect function with hidden staff potentials
- [ ] Add staff role assignment UI (Fighter/Scout/Trainer/Medic buttons)
- [ ] Create StaffMember class/wrapper (character, role, effectiveness)
- [ ] Add staff roster tracking in Game.gd (staff_roster array)
- [ ] Test: Draft staff, assign to role, verify they appear in staff roster

**Deliverable:** Can draft and assign staff in draft

---

### 3.4 Scouting System Integration
**Priority:** High (affects draft info)  
**Estimated Time:** 1 week

**Tasks:**
- [ ] Calculate scouting level based on staff (get_scouting_level function)
- [ ] Apply scouting level to draft prospect display
- [ ] Test: Draft with no scout (everything ???), draft with scout (more info)

**Deliverable:** Scouting level affects draft information

---

### 3.5 Phase 3 Integration Test
**Tasks:**
- [ ] Season 1: Draft with no scout (blind picks)
- [ ] Assign one pick as scout
- [ ] Season 2: Draft with scout (better info)
- [ ] Sign contracts with varying lengths
- [ ] Verify salary cap enforced
- [ ] Verify staff affects gameplay (scout reveals info)

**Checkpoint:** Draft is fully functional with hidden stats, contracts, staff

---

## PHASE 4: Season Activity Expansion

**Goal:** Add Training and Minor Guild Fights as alternatives to dungeons.

### 4.1 Training Activity System
**Priority:** High (key regular season activity)  
**Estimated Time:** 2-3 weeks

**Tasks:**
- [ ] Create TrainingScreen.tscn (character selection, stat focus, duration slider, cost display, trainer bonus, start button)
- [ ] Implement training mechanics (train_character function with base_gain, multipliers, stat increase)
- [ ] Add training to Guild screen as button
- [ ] Show training results screen
- [ ] Test: Train character, verify stats increase, gold decreases

**Deliverable:** Working training system as alternative to dungeons

---

### 4.2 Minor Guild Fights System
**Priority:** Medium (adds variety)  
**Estimated Time:** 2-3 weeks

**Tasks:**
- [ ] Generate minor guilds (generate_minor_guilds function creating 10 weak AI teams)
- [ ] Create MinorGuildScreen.tscn (list of guilds, difficulty/reward info, challenge buttons)
- [ ] Implement minor guild fight flow (challenge_minor_guild function using autobattle)
- [ ] Add rewards (gold based on difficulty)
- [ ] Test: Fight minor guild, win, earn gold, verify stat revelation

**Deliverable:** Minor guild fights as third regular season activity

---

### 4.3 Dungeon System Improvements
**Priority:** Medium (make dungeons better)  
**Estimated Time:** 2-3 weeks

**Tasks:**
- [ ] Fix pathfinding oscillation issues (better stuck detection, cleaner exit logic, improved target selection)
- [ ] Add more dungeon templates (at least 5 different layouts)
- [ ] Better difficulty scaling (start low, gradual increase, consider player strength)
- [ ] Improve completion feedback (summary screen, compare to previous runs, highlight improvements)
- [ ] Test: Run 10 dungeons, verify no stuck/crash issues

**Deliverable:** Dungeons feel better and more varied

---

### 4.4 Phase 4 Integration Test
**Tasks:**
- [ ] Season loop: Choose between 3 activities each week
- [ ] Training: Train 2 characters, verify stat growth
- [ ] Minor fights: Challenge 3 guilds, earn gold
- [ ] Dungeons: Explore 2 dungeons, find loot
- [ ] Verify all activities reveal hidden stats appropriately
- [ ] Proceed to playoffs

**Checkpoint:** Full regular season with meaningful activity choices

---

## PHASE 5: Persistence & Consequences

**Goal:** Add free agency, injuries, loyalty, and offseason phase.

### 5.1 Offseason/Free Agency System
**Priority:** Critical (makes world persistent)  
**Estimated Time:** 2-3 weeks

**Tasks:**
- [ ] Create offseason phase in season cycle (add OFFSEASON to Phase enum)
- [ ] Implement contract expiration (process_offseason function)
- [ ] Create FreeAgencyScreen.tscn (free agents list, sorting, salary cap space, make offer buttons)
- [ ] Implement free agent decision logic (evaluate_free_agent_offers function)
- [ ] Test: Expire contracts, make offers, lose player to rival, sign new player

**Deliverable:** Working free agency where characters change teams

---

### 5.2 Injury System
**Priority:** High (adds risk/consequence)  
**Estimated Time:** 1-2 weeks

**Tasks:**
- [ ] Create Injury class (type, affected_stat, stat_penalty, recovery_time, description)
- [ ] Add injury chance to combat/dungeons (check_injury_after_combat function)
- [ ] Implement injury effects (apply_injury_penalties function)
- [ ] Add injury recovery (process_injury_recovery function)
- [ ] Show injury notifications in UI
- [ ] Test: Character gets injured, stats reduced, heals over time

**Deliverable:** Injury system with combat risk and recovery

---

### 5.3 Death & Madness System
**Priority:** Medium (adds drama but needs balance)  
**Estimated Time:** 1-2 weeks

**Tasks:**
- [ ] Implement permadeath (check_death_in_combat with 5% chance when knocked out)
- [ ] Handle death consequences (process_character_death function removes from roster, breaks contracts, shows notification)
- [ ] Add madness mechanic (increase_madness function, go_mad when > 100)
- [ ] Balance: Death should be RARE but impactful
- [ ] Test: Trigger death (cheat for testing), verify character removed

**Deliverable:** Permadeath and madness add stakes

---

### 5.4 Loyalty & Relationship System
**Priority:** Medium (affects free agency)  
**Estimated Time:** 2 weeks

**Tasks:**
- [ ] Track loyalty per character (loyalty_to_player int, teammate_bonds dict in AdventurerResource)
- [ ] Implement loyalty changes (modify_loyalty function with reasons)
- [ ] Use loyalty in free agency (will_re_sign function with loyalty discount)
- [ ] Add teammate chemistry (calculate_combat_bonus function for friends)
- [ ] Test: Build loyalty, verify player takes less in free agency

**Deliverable:** Loyalty system affects contracts and performance

---

### 5.5 Phase 5 Integration Test
**Tasks:**
- [ ] Complete full season
- [ ] Player gets injured, sits out battles
- [ ] Contract expires, player becomes free agent
- [ ] Rival guild signs your former player
- [ ] Sign new player in free agency
- [ ] Verify loyalty affects negotiations
- [ ] Advance to next season

**Checkpoint:** Persistent world with consequences working

---

## PHASE 6: Alpha Polish & Balance

**Goal:** Make it feel good and test with real players.

### 6.1 Balance Pass
**Priority:** Critical (game must feel fair)  
**Estimated Time:** 2 weeks

**Tasks:**
- [ ] Combat balance: Average battle 45-75 seconds, ~70% win rate for appropriate level, adjust damage/defense formulas
- [ ] Economy balance: Can afford 3-4 good players + depth, training costs vs dungeon rewards, salary cap flexibility
- [ ] Progression balance: Season 1-3 accessible, smooth difficulty curve, recover from bad draft
- [ ] Playtest extensively with different strategies

**Deliverable:** Game feels balanced and fair

---

### 6.2 UI/UX Polish
**Priority:** High (must be usable)  
**Estimated Time:** 2 weeks

**Tasks:**
- [ ] Consistent visual language (color coding, icons for stats, readable fonts)
- [ ] Add tooltips everywhere (hover any stat, hover any button)
- [ ] Improve screen transitions (fade in/out, loading indicators, breadcrumbs)
- [ ] Add feedback for all actions (gold spent animation, stat increase popup, character signed celebration)
- [ ] Polish all existing screens (alignment, spacing, clarity)

**Deliverable:** UI is clear and pleasant to use

---

### 6.3 Tutorial/Onboarding
**Priority:** High (friends need to understand game)  
**Estimated Time:** 1-2 weeks

**Tasks:**
- [ ] Create tutorial mode (guided first draft, explains hidden stats, shows scouting, walks through first season)
- [ ] Add contextual tooltips (first time seeing each screen gets popup explanation)
- [ ] Create reference screen (list all stats, explain each activity, season cycle diagram)
- [ ] Test with someone who hasn't played before

**Deliverable:** New players can learn without asking questions

---

### 6.4 Bug Fixing & Stability
**Priority:** Critical (must not crash)  
**Estimated Time:** 1-2 weeks

**Tasks:**
- [ ] Test every screen transition
- [ ] Test every button
- [ ] Test edge cases (empty roster, out of gold, all contracts expire)
- [ ] Fix all known bugs
- [ ] Add error handling everywhere
- [ ] Add save corruption prevention

**Deliverable:** Game runs without crashes

---

### 6.5 Alpha Testing Period
**Priority:** Critical (real feedback)  
**Estimated Time:** 2-3 weeks

**Tasks:**
- [ ] Recruit 3-5 friends/family for testing
- [ ] Watch them play (don't help unless stuck)
- [ ] Take notes on confusion, unfun moments, enjoyment, desires
- [ ] Gather feedback via survey
- [ ] Prioritize feedback into must fix vs nice to have
- [ ] Implement critical fixes
- [ ] Iterate based on feedback

**Deliverable:** Tested, polished Alpha ready for next phase

---

## ALPHA COMPLETE

**At this point you have:**
- Full season cycle: Draft → Regular Season → Playoffs → Offseason
- Autobattle combat with replays
- Hidden stats + scouting system
- Contracts + free agency
- Staff system (scout, trainer, medic)
- 3 regular season activities (dungeons, training, minor fights)
- Character persistence across seasons
- Injuries, death, loyalty
- Balanced and tested gameplay
- Usable UI with tutorial

**What's missing for Beta:**
- More content (roles, dungeons, events)
- More polish (sound, music, animations)
- Save/load system
- Advanced features (detailed injuries, complex contracts, more staff roles)
- Meta-progression (unlocks, achievements)

---

## Timeline Summary

**Conservative Estimate:**
- Phase 1: 6 weeks
- Phase 2: 8 weeks
- Phase 3: 4 weeks
- Phase 4: 6 weeks
- Phase 5: 6 weeks
- Phase 6: 4 weeks
**Total: 34 weeks (~8 months)**

**Optimistic Estimate:**
- Phase 1: 4 weeks
- Phase 2: 6 weeks
- Phase 3: 3 weeks
- Phase 4: 4 weeks
- Phase 5: 4 weeks
- Phase 6: 3 weeks
**Total: 24 weeks (~6 months)**

**Reality Check:**
You're working on this part-time with no deadline. Expect 6-8 months to Alpha if you maintain consistent progress (5-10 hours/week).

---

## Weekly Workflow Suggestion

**Each Week:**
1. Pick ONE task from current phase
2. Work on it until complete (don't context switch)
3. Update this document with [x] when done
4. Test what you built
5. Commit to git with reference to roadmap

**Example Weekly Entry:**
```markdown
## Week of [Date]
**Phase:** 1 - Foundation
**Task:** 1.1 Character Stats Expansion
**Progress:** 
- [x] Added new combat stats
- [x] Added hidden attributes
- [x] Created migration script
- [ ] Updated character detail window (moved to next week)
**Blockers:** None
**Notes:** Stat system is getting complex, might need refactor later
**Next Week:** Finish character detail window, start contracts
```

---

## How to Use This Roadmap

**Weekly:**
- Check off completed tasks
- Update "Current Focus" section
- Note any blockers or questions

**Monthly:**
- Review phase progress
- Adjust estimates if needed
- Celebrate completed phases!

**As Needed:**
- Add tasks you discover along the way
- Reorganize if priorities change
- Reference vision doc when making decisions

---

## Current Status

**Current Phase:** [Update this]  
**Current Task:** [Update this]  
**Blockers:** [Update this]  
**Recent Completions:** [Update this]

---

*Remember: This is ambitious but achievable. One task at a time, one week at a time. The journey is part of the fun!*
