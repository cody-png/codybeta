#===============================================================================
# C-RAND-01 – PIF's other randomizer menus open the Randomizer screen
# (Cody, 2026-10-07). Rolls follow the seed, so PIF's "reshuffle" buttons
# would give the same result again; changing things goes through the screen
# (new seed, settings, Randomize now) instead.
#   * Update Man → Advanced options → Randomizer options (Common Event 17,
#     PIF's own menu of reshuffles): the Randomizer screen. PIF's warning for
#     saves that aren't randomized yet still comes first.
#   * Oak's Lab "Re-randomize Pokémon?" / "Rerandomize starters?" (rerolling
#     the starters before picking one): Yes opens the Randomizer screen. The
#     strength prompt is skipped (the screen has it), and "The Pokédex was
#     re-shuffled." only shows when you did randomize.
# Nothing in the maps or common events is changed.
#===============================================================================
module KIF
  module Rand
    REROLL_TEXT = /\ARe-?randomize (Pokémon|starters)\?\z/
    REROLL_DONE_TEXT = /\A(The Pokédex was re-shuffled\.|Your wish is my command!)\z/

    @randomize_count = 0
    class << self
      attr_reader :randomize_count
      alias kif_reroll_randomize_now randomize_now unless method_defined?(:kif_reroll_randomize_now)

      def randomize_now
        @randomize_count += 1
        return kif_reroll_randomize_now
      end
    end

    # A command list of one of PIF's reroll events (cached per list)
    def self.reroll_event?(list)
      @reroll_lists ||= {}
      key = list.object_id
      return @reroll_lists[key] if @reroll_lists.key?(key)
      @reroll_lists.clear if @reroll_lists.length > 32
      asks = list.any? { |c| c.code == 101 && utf8(c.parameters[0].to_s).strip =~ REROLL_TEXT }
      shuffles = list.any? { |c| [355, 655].include?(c.code) && c.parameters[0].to_s.include?("pbShuffleDex") }
      @reroll_lists[key] = asks && shuffles
      return @reroll_lists[key]
    end

    def self.open_screen
      pbFadeOutIn { PokemonOptionScreen.new(RandomizerOptionsScene.new).pbStartScreen }
    end
  end
end

class Interpreter
  alias kif_reroll_command_117 command_117 unless method_defined?(:kif_reroll_command_117)
  alias kif_reroll_execute_command execute_command unless method_defined?(:kif_reroll_execute_command)
  alias kif_reroll_execute_script execute_script unless method_defined?(:kif_reroll_execute_script)

  def command_117
    if @parameters[0] == 17 && $game_switches && $PokemonGlobal && !$game_switches[SWITCH_DURING_INTRO]
      KIF::Rand.open_screen
      return true
    end
    return kif_reroll_command_117
  end

  def kif_reroll_list?
    return @list && $game_switches && $PokemonGlobal && KIF::Rand.available? &&
           !$game_switches[SWITCH_DURING_INTRO] && KIF::Rand.reroll_event?(@list)
  end

  def execute_command
    return kif_reroll_execute_command unless kif_reroll_list?
    @kif_reroll = nil if @index == 0   # a new run of the event
    cmd = @list[@index]
    if cmd
      # The strength prompt (the screen has its own)
      return true if cmd.code == 103 && cmd.parameters[0] == VAR_RANDOMIZER_WILD_POKE_BST
      # "Re-shuffled" only when the screen did randomize
      if cmd.code == 101 && KIF::Rand.utf8(cmd.parameters[0].to_s).strip =~ KIF::Rand::REROLL_DONE_TEXT && @kif_reroll &&
         KIF::Rand.randomize_count == @kif_reroll
        return true
      end
    end
    return kif_reroll_execute_command
  end

  def execute_script(script)
    if script.to_s.include?("pbShuffleDex") && kif_reroll_list?
      unless @kif_reroll
        @kif_reroll = KIF::Rand.randomize_count
        KIF::Rand.open_screen
      end
      return true
    end
    return kif_reroll_execute_script(script)
  end
end
