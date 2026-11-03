#===============================================================================
# F-CORE-10 Mod API - the event table (KIF::API::EVENTS)
#
# One row per event: the name, the fields a handler sees, which of them it may
# change, whether it can cancel, and one sentence of what it means. This table
# is data: 040_Points.rb says WHERE in the game each event fires, and
# 090_Dev.rb writes this table into Logs/KIF_API_Reference.txt.
#
# Row keys: :since (API level), :p (0 = core, 1 = extra), :hot (runs many
# times a frame or battle: the ctx is reused, do not keep it), :ro (read-only
# fields), :rw ({ field => [kind, range] }: a handler may change it; a wrong
# kind or a number outside the range keeps the game's own value), :cancel
# (what ctx.cancel! does, or nil: the event can not be cancelled), :doc.
#
# Field objects (battle, battler, move, pokemon...) are the live game objects:
# use the game's own methods on them. File names in the docs are base game
# scripts under Data/Scripts.
# Reserved names with no code yet: net_connected net_disconnected
# coop_battle_begin coop_battle_end (KIF::API::RESERVED_EVENTS).
#===============================================================================
module KIF
  module API
    EVENTS = {} unless const_defined?(:EVENTS)
    EVENTS.clear

    def self.ev(name, doc, ro: [], rw: {}, cancel: nil, p: 0, hot: false)
      EVENTS[name] = { :since => 1, :p => p, :hot => hot, :ro => ro.freeze, :rw => rw.freeze,
                       :cancel => cancel, :doc => doc }.freeze
    end

    # --- loading -----------------------------------------------------------
    ev :mods_loading,  "Before the first mod loads. mods: the mod keys in load order.", ro: [:mods]
    ev :mod_loaded,    "After all mods loaded, once per mod. Read the mod's key with ctx[:mod] (ctx.mod is the mod whose handler runs).",
       ro: [:mod, :json_id, :name, :version, :ok, :error, :ms, :files]
    ev :mods_loaded,   "After every mod loaded. loaded / failed: lists of mod keys.", ro: [:loaded, :failed, :ms]
    ev :data_loaded,   "After GameData.load_all and KIF's data steps. reload is false the first time.", ro: [:reload]
    ev :game_new,      "A new game started (Game.start_new finished).", ro: [:new_game_plus]
    ev :game_loading,  "A save is about to load (Game.load). keys: the keys of the save.", ro: [:keys]
    ev :game_loaded,   "A save finished loading."
    ev :game_saving,   "The game is about to save (Game.save).", ro: [:path, :safe]
    ev :game_saved,    "The game saved. ok: false when the file could not be written.", ro: [:path, :ok]

    # --- time and the map --------------------------------------------------
    ev :frame,         "After every Graphics.update, in the map, battles and menus. HOT.", ro: [:scope, :frame_count], hot: true
    ev :tick,          "Once per logic step (40 a second), after Graphics.update. HOT.", ro: [:scope, :frame_count], hot: true
    ev :map_update,    "Every frame on the map (Events.onMapUpdate). HOT.", hot: true
    ev :map_changed,   "The player moved to another map (Events.onMapChange).", ro: [:old_map_id, :new_map_id]
    ev :step_taken,    "The player took a step (Events.onStepTaken). Can not veto: use :encounter_roll. HOT.",
       ro: [:event, :map_id, :x, :y], hot: true
    ev :interact_start, "An event is about to start (Game_Event#start).", ro: [:event, :map_id],
       cancel: "the event does not start"
    ev :interact_check, "The player pressed the action key (Game_Player#check_event_trigger_there).", ro: [:triggers],
       cancel: "no interaction happens"
    ev :encounter_roll, "Does a wild encounter happen now? (PokemonEncounters#encounter_triggered?)",
       ro: [:encounters, :enc_type, :repel_active, :by_step, :map_id], rw: { :result => [:bool, nil] }
    ev :encounter_choose, "Which wild Pokemon appears: [species, level] or nil (PokemonEncounters#choose_wild_pokemon).",
       ro: [:encounters, :enc_type, :chance_rolls, :map_id], rw: { :result => [:obj, nil] }

    # --- items and shops ---------------------------------------------------
    ev :item_stored,   "An item went into the bag (PokemonBag#pbStoreItem).", ro: [:bag, :item, :qty]
    ev :shop_stock,    "The list of items a city's Poke Mart sells (Array of item Symbols).", ro: [:city],
       rw: { :result => [:array, nil] }
    ev :item_found,    "An item is about to be given from the ground or a gift (pbItemBall).", ro: [:item_name], p: 1,
       rw: { :item => [:obj, nil], :quantity => [:int, 0..9999] }, cancel: "nothing is given"

    # --- battle ------------------------------------------------------------
    ev :battle_start,  "A battle is starting (PokeBattle_Battle#pbStartBattle).", ro: [:battle, :wild, :trainer, :double]
    ev :battle_loop,   "The intro and send-outs are done; the turns begin (pbBattleLoop).", ro: [:battle]
    ev :battle_end,    "The battle is about to end. decision: 1 win, 2 lose, 3 flee, 4 caught, 5 draw.",
       ro: [:battle, :decision, :can_lose]
    ev :battle_ended,  "The battle has ended (after pbEndOfBattle).", ro: [:battle, :decision]
    ev :turn_start,    "A new turn: the command phase starts (pbCommandPhase).", ro: [:battle, :turn]
    ev :attack_phase,  "The attack phase of a turn starts (pbAttackPhase).", ro: [:battle, :turn], p: 1
    ev :round_end,     "The end-of-round phase starts (pbEndOfRoundPhase).", ro: [:battle, :turn]
    ev :round_ended,   "The end-of-round phase is over.", ro: [:battle, :turn]
    ev :move_use,      "A battler is about to use a move (PokeBattle_Battler#pbUseMove).",
       ro: [:battler, :battle, :choice, :move, :special_usage], cancel: "the move is not used (no PP change)"
    ev :move_used,     "A battler used a move.", ro: [:battler, :battle, :choice, :move, :special_usage]
    ev :battler_faint, "A battler is about to faint (pbFaint).", ro: [:battler, :battle, :show_message]
    ev :battler_fainted, "A battler fainted.", ro: [:battler, :battle]
    ev :switch_in,     "A battler entered the field (pbEffectsOnSwitchIn).", ro: [:battler, :battle, :switch_in]
    ev :battler_init,  "A battler's effects were reset (pbInitEffects). baton_pass: true when a Baton Pass keeps some.",
       ro: [:battler, :battle, :baton_pass]
    ev :damage_multipliers, "The damage multipliers of one hit. Change multipliers[:base_damage_multiplier], [:attack_multiplier], [:defense_multiplier], [:final_damage_multiplier] (Float above 0, at most 16). HOT.",
       ro: [:move, :user, :target, :num_targets, :type, :base_damage], rw: { :multipliers => [:hash, nil] }, hot: true
    ev :type_effectiveness, "Effectiveness of one type against one type (pbCalcTypeModSingle). HOT.",
       ro: [:move, :move_type, :def_type, :user, :target], rw: { :result => [:int, 0..64] }, p: 1, hot: true
    ev :accuracy_check, "Does the move hit? (pbAccuracyCheck)", ro: [:move, :user, :target], rw: { :result => [:bool, nil] }, p: 1
    ev :crit_check,    "Is it a critical hit? (pbIsCritical?)", ro: [:move, :user, :target], rw: { :result => [:bool, nil] }, p: 1
    ev :hit_count,     "How many times a move hits (pbNumHits).", ro: [:move, :user, :targets], rw: { :result => [:int, 1..10] }, p: 1
    ev :exp_gain,      "Experience is about to be given after a battle (pbGainExp).", ro: [:battle]
    ev :exp_gained,    "Experience was given.", ro: [:battle]
    ev :money_gain,    "Prize money is about to be given (pbGainMoney).", ro: [:battle], p: 1
    ev :ai_score_move, "The AI's score for one move. PIF scores are absolute; a DemICE-style AI returns changes, so add to the score you get.",
       ro: [:ai, :move, :user, :target, :skill], rw: { :score => [:int, -100000..100000] }
    ev :ai_rough_damage, "The AI's guess of the damage a move does (pbRoughDamage).", ro: [:ai, :move, :user, :target, :skill],
       rw: { :result => [:int, 0..1_000_000] }, p: 1
    ev :ai_choose,     "The AI is about to choose a command for a battler.", ro: [:ai, :battler_index, :battle], p: 1,
       cancel: "your handler already registered a command; the AI does nothing"

    # --- Pokemon and fusion ------------------------------------------------
    ev :fusion_done,   "Two Pokemon were fused (pbFuse). result: the fusion.", ro: [:body, :head, :splicer, :result]
    ev :unfuse_done,   "A fusion was split (pbUnfuse).", ro: [:pokemon, :party_position, :pc_position, :result]
    ev :fusion_before, "A fusion is about to happen.", ro: [:body, :head, :splicer], p: 1, cancel: "no fusion"
    ev :pokemon_added, "A Pokemon was added to the party or the PC (pbAddPokemon).", ro: [:pokemon, :result], p: 1
    ev :level_changed, "A Pokemon changed level (pbChangeLevel).", ro: [:pokemon, :old_level, :new_level], p: 1
    ev :stats_calculated, "A Pokemon's stats were recalculated (Pokemon#calc_stats). Edit pokemon.stats on the live object.", ro: [:pokemon], p: 1
    ev :wild_battle_start, "A wild battle is about to start (pbWildBattle).", ro: [:can_run, :can_lose], p: 1,
       rw: { :species => [:obj, nil], :level => [:int, 1..100] }

    # --- screens -----------------------------------------------------------
    ev :sprite_update, "A map character sprite updated (Sprite_Character#update). HOT.", ro: [:sprite, :character], p: 1, hot: true
    ev :sprite_dispose, "A map character sprite is being disposed.", ro: [:sprite, :character], p: 1
    ev :pause_menu_build, "The pause menu's KIF rows are built. Change entries (an Array of KIF::PauseMenu::Entry) or use ctx.hide(id), ctx.relabel(id, text), ctx.move(id, order).",
       rw: { :entries => [:array, nil] }
    ev :summary_page_drawn, "A Summary page was drawn. Draw on overlay (a Bitmap).", ro: [:scene, :pokemon, :page, :overlay], p: 1
    ev :party_panel_drawn, "A party panel was drawn.", ro: [:panel, :pokemon, :bitmap], p: 1
    ev :databox_drawn, "A battle data box was drawn.", ro: [:databox, :battler, :bitmap], p: 1
    ev :storage_overlay_drawn, "The PC's information overlay was drawn.", ro: [:scene, :selection, :bitmap], p: 1
    ev :scene_open,    "The scene changed (seen in the frame hook).", ro: [:scene, :name], p: 1

    class << self; remove_method :ev; end   # a build helper, not API
  end
end
