#===============================================================================
# C-RAND-01 – hooks into PIF's randomizer (025-Randomizer, 012_Overworld,
# 013_Trainer, 005_UI_Trading). No base file is copied; each wrapper calls
# PIF's own method.
#===============================================================================

#-------------------------------------------------------------------------------
# Seeded shuffles (+ spoiler log)
#-------------------------------------------------------------------------------
class << Kernel
  alias kif_rand_pbShuffleDex pbShuffleDex unless method_defined?(:kif_rand_pbShuffleDex)
  alias kif_rand_randomizeWildPokemonByRoute randomizeWildPokemonByRoute unless method_defined?(:kif_rand_randomizeWildPokemonByRoute)
  alias kif_rand_pbShuffleTrainers pbShuffleTrainers unless method_defined?(:kif_rand_pbShuffleTrainers)
  alias kif_rand_initRandomTypeArray initRandomTypeArray unless method_defined?(:kif_rand_initRandomTypeArray)

  # The range is always the Pokémon page's Strength range (Common Event 28
  # passes the default 50 when only the starters are random)
  def pbShuffleDex(range = 50, type = 0)
    range = $game_variables[VAR_RANDOMIZER_WILD_POKE_BST] if $game_variables
    ret = KIF::Rand.with_seed(:dex) { kif_rand_pbShuffleDex(range, type) }
    KIF::Rand.sanitize_tables
    KIF::Rand.progress_done
    KIF::Rand.data[:dex_ok] = true
    KIF::Rand.write_log
    return ret
  end

  def randomizeWildPokemonByRoute(*args)
    KIF::Rand.progress("Shuffling routes...", 0.5)
    ret = KIF::Rand.with_seed(:routes) { kif_rand_randomizeWildPokemonByRoute(*args) }
    KIF::Rand.progress_done
    KIF::Rand.mark_routes
    KIF::Rand.write_log
    return ret
  end

  def pbShuffleTrainers(*args)
    KIF::Rand.progress("Shuffling trainers...", 0.5)
    KIF::Rand.ensure_trainer_dex
    ret = KIF::Rand.with_seed(:trainers) {
      if KIF::Rand.trainer_features?
        KIF::Rand.shuffle_trainers(args[1] ? args[2] : nil)
      else
        kif_rand_pbShuffleTrainers(*args)
      end
    }
    KIF::Rand.progress_done
    KIF::Rand.write_log
    return ret
  end

  def initRandomTypeArray(*args)
    return KIF::Rand.with_seed(:gymtypes) { kif_rand_initRandomTypeArray(*args) }
  end
end

class Object
  alias kif_rand_pbShuffleItems pbShuffleItems unless method_defined?(:kif_rand_pbShuffleItems) || private_method_defined?(:kif_rand_pbShuffleItems)
  alias kif_rand_pbShuffleTMs pbShuffleTMs unless method_defined?(:kif_rand_pbShuffleTMs) || private_method_defined?(:kif_rand_pbShuffleTMs)
  alias kif_rand_show_shuffle_progress show_shuffle_progress unless method_defined?(:kif_rand_show_shuffle_progress) || private_method_defined?(:kif_rand_show_shuffle_progress)

  def pbShuffleItems(*args)
    ret = KIF::Rand.with_seed(:items) { KIF::Rand.shuffle_items }
    KIF::Rand.write_log
    return ret
  end

  def pbShuffleTMs(*args)
    ret = KIF::Rand.with_seed(:tms) { KIF::Rand.shuffle_tms }
    KIF::Rand.write_log
    return ret
  end

  # PIF's progress message updates the map (NPCs roll random steps), which
  # would change a seeded shuffle; the seeded one draws its own bar instead
  def show_shuffle_progress(i)
    return kif_rand_show_shuffle_progress(i) if KIF::Rand.seeded == 0
    KIF::Rand.progress(_INTL("Shuffling Pokémon..."), i.to_f / NB_POKEMON) if i % 25 == 0
  end
end

# Faster shuffles: while a seeded shuffle runs, the two lookups PIF makes for
# every candidate (base stat total, legendary check) are remembered per
# Pokémon (KIF::Rand.memo_*). Outside shuffles nothing changes.
class Object
  alias kif_rand_calcBaseStatsSum calcBaseStatsSum unless method_defined?(:kif_rand_calcBaseStatsSum) || private_method_defined?(:kif_rand_calcBaseStatsSum)
  alias kif_rand_is_legendary is_legendary unless method_defined?(:kif_rand_is_legendary) || private_method_defined?(:kif_rand_is_legendary)

  def calcBaseStatsSum(species)
    v = KIF::Rand.memo_bst(species)
    return v if v
    return KIF::Rand.memo_bst_set(species, kif_rand_calcBaseStatsSum(species))
  end

  def is_legendary(dex_num, printInfo = false)
    v = KIF::Rand.memo_legend(dex_num)
    return v unless v.nil?
    return KIF::Rand.memo_legend_set(dex_num, kif_rand_is_legendary(dex_num, printInfo))
  end
end

# Gym teams: the same team for the same seed (unless "Rerandomize each battle")
module GameData
  class Trainer
    alias kif_rand_replace_gym replace_species_to_randomized_gym unless method_defined?(:kif_rand_replace_gym)

    def replace_species_to_randomized_gym(species, trainerId, pokemonIndex)
      return kif_rand_replace_gym(species, trainerId, pokemonIndex) if $game_switches[SWITCH_GYM_RANDOM_EACH_BATTLE]
      return KIF::Rand.with_seed(:gym, trainerId.inspect, pokemonIndex, $game_variables[VAR_CURRENT_GYM_TYPE]) {
        kif_rand_replace_gym(species, trainerId, pokemonIndex)
      }
    end
  end
end

#-------------------------------------------------------------------------------
# Pokédex swap on demand, Dynamic encounters, trades
#-------------------------------------------------------------------------------
class Object
  alias kif_rand_getRegularEncounter getRegularEncounter unless method_defined?(:kif_rand_getRegularEncounter) || private_method_defined?(:kif_rand_getRegularEncounter)
  alias kif_rand_pbWildBattle pbWildBattle unless method_defined?(:kif_rand_pbWildBattle) || private_method_defined?(:kif_rand_pbWildBattle)
  alias kif_rand_tryRandomizeGiftPokemon tryRandomizeGiftPokemon unless method_defined?(:kif_rand_tryRandomizeGiftPokemon) || private_method_defined?(:kif_rand_tryRandomizeGiftPokemon)
  alias kif_rand_obtainRandomizedStarter obtainRandomizedStarter unless method_defined?(:kif_rand_obtainRandomizedStarter) || private_method_defined?(:kif_rand_obtainRandomizedStarter)
  alias kif_rand_pbStartTrade pbStartTrade unless method_defined?(:kif_rand_pbStartTrade) || private_method_defined?(:kif_rand_pbStartTrade)

  def getRegularEncounter(encounter_type)
    KIF::Rand.ensure_dex if $game_switches && $game_switches[SWITCH_WILD_RANDOM_GLOBAL]
    KIF::Rand.in_regular += 1
    begin
      encounter = kif_rand_getRegularEncounter(encounter_type)
    ensure
      KIF::Rand.in_regular -= 1
    end
    if encounter && KIF::Rand.dynamic?
      encounter[0] = KIF::Rand.dynamic_species(encounter[0])
    end
    return encounter
  end

  # PIF swaps the species in pbWildBattle when "Static encounters" is on, but
  # grass and fishing battles go through pbWildBattle too, so they were
  # swapped (again) by that option. Only event battles (the real static
  # encounters) are swapped now; grass/fishing follow "Wild encounters".
  def pbWildBattle(*args)
    statics = $game_switches && $game_switches[SWITCH_RANDOM_STATIC_ENCOUNTERS]
    return kif_rand_pbWildBattle(*args) unless statics
    if KIF::Rand.in_encounter > 0
      $game_switches[SWITCH_RANDOM_STATIC_ENCOUNTERS] = false
      begin
        return kif_rand_pbWildBattle(*args)
      ensure
        $game_switches[SWITCH_RANDOM_STATIC_ENCOUNTERS] = true
      end
    end
    KIF::Rand.ensure_dex
    return kif_rand_pbWildBattle(*args)
  end

  alias kif_rand_pbBattleOnStepTaken pbBattleOnStepTaken unless method_defined?(:kif_rand_pbBattleOnStepTaken) || private_method_defined?(:kif_rand_pbBattleOnStepTaken)
  alias kif_rand_pbEncounter pbEncounter unless method_defined?(:kif_rand_pbEncounter) || private_method_defined?(:kif_rand_pbEncounter)

  def pbBattleOnStepTaken(*args)
    KIF::Rand.in_encounter += 1
    begin
      return kif_rand_pbBattleOnStepTaken(*args)
    ensure
      KIF::Rand.in_encounter -= 1
    end
  end

  def pbEncounter(*args)
    KIF::Rand.in_encounter += 1
    begin
      return kif_rand_pbEncounter(*args)
    ensure
      KIF::Rand.in_encounter -= 1
    end
  end

  def tryRandomizeGiftPokemon(*args)
    KIF::Rand.ensure_dex if $game_switches && $game_switches[SWITCH_RANDOM_GIFT_POKEMON]
    return kif_rand_tryRandomizeGiftPokemon(*args)
  end

  def obtainRandomizedStarter(*args)
    KIF::Rand.ensure_dex
    return kif_rand_obtainRandomizedStarter(*args)
  end

  # Trades: Swap = the swap table (fusions part by part), Random = a roll
  # within the Strength range for that trade (009_RandRequests.rb)
  def pbStartTrade(pokemonIndex, newpoke, *args)
    if KIF::Rand.pokemon_parts_on? && KIF::Rand.get(:trades) > 0 && !$game_switches[SWITCH_DONT_RANDOMIZE]
      begin
        if newpoke.is_a?(Pokemon)
          to = KIF::Rand.trade_result(newpoke.species)
          newpoke.species = to if to
        else
          to = KIF::Rand.trade_result(newpoke)
          newpoke = to if to
        end
      rescue => e
        KIF.log("Randomized trade failed: #{e.message}")
      end
    end
    return kif_rand_pbStartTrade(pokemonIndex, newpoke, *args)
  end
end

# Route randomization made by another save's game is re-made for this one.
# PIF's double wild battles (and KIF's triples) pick the extra Pokémon with
# choose_wild_pokemon directly, so Swap / Dynamic never applied to them.
class PokemonEncounters
  alias kif_rand_choose_wild_pokemon choose_wild_pokemon unless method_defined?(:kif_rand_choose_wild_pokemon)

  def choose_wild_pokemon(*args)
    enc = kif_rand_choose_wild_pokemon(*args)
    return enc if !enc || KIF::Rand.in_regular > 0 || !KIF::Rand.pokemon_parts_on?
    begin
      if KIF::Rand.dynamic?
        enc[0] = KIF::Rand.dynamic_species(enc[0])
      elsif $game_switches[SWITCH_WILD_RANDOM_GLOBAL]
        KIF::Rand.ensure_dex
        to = KIF::Rand.dex_of(getRandomizedTo(enc[0]))
        enc[0] = GameData::Species.get(to).species if to > 0
      end
    rescue => e
      KIF.log("Extra wild Pokémon randomizing failed: #{e.message}")
    end
    return enc
  end

  alias kif_rand_setup setup unless method_defined?(:kif_rand_setup)

  def setup(map_ID)
    begin
      KIF::Rand.ensure_routes
    rescue => e
      KIF.log("Route randomizer check failed: #{e.message}")
    end
    return kif_rand_setup(map_ID)
  end
end

# Common Event 15 asks for the strength ranges with its own menus right after
# PIF's screen (during the intro); the new screen has the sliders, so those
# two menus (Common Events 56/57) are skipped right after it closes.
class Interpreter
  alias kif_rand_command_117 command_117 unless method_defined?(:kif_rand_command_117)

  def command_117
    if [56, 57].include?(@parameters[0]) && KIF::Rand.skip_bst_prompts?
      return true
    end
    return kif_rand_command_117
  end
end

module KIF
  module Rand
    @in_regular = 0
    @in_encounter = 0
    class << self
      attr_accessor :in_regular, :in_encounter
    end
    @screen_closed_at = nil
    def self.screen_closed!
      @screen_closed_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def self.skip_bst_prompts?
      return false unless @screen_closed_at && $game_switches && $game_switches[SWITCH_DURING_INTRO]
      return Process.clock_gettime(Process::CLOCK_MONOTONIC) - @screen_closed_at < 5
    end
  end
end
