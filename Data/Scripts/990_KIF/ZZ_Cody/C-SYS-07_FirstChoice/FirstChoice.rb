#===============================================================================
# C-SYS-07 – How do you want to play? (2026-10-12)
#   New players used to start with every module Off, so KIF played like
#   plain PIF until they found Options > Modules. The first time the load
#   screen shows (no module chosen yet), KIF asks once:
#     Classic KIF   - every module On, with the features KIF 0.20.7 never
#                     had (EBDX, Move Effectiveness, Fusion Screen) Off
#     PIF only      - every module Off (plays like Pokémon Infinite Fusion)
#     Let me choose - opens Options > Modules
#   Players who already have module choices (any save from before, or saves
#   copied from old KIF, which turn everything On) are never asked.
#   The answer is kept with the other global settings; like them it is
#   stored once a game is saved, so quitting before the first save asks again.
#===============================================================================
KIF::Options.define(:kif_first_choice, false, :global)

module KIF
  module FirstChoice
    module_function

    # true when this player has never picked how to play
    def needed?
      return false unless $PokemonSystem && $PokemonSystem.respond_to?(:kif_first_choice)
      return false if $PokemonSystem.kif_first_choice
      h = KIF::Modules.states
      unless h.nil? || h.empty?
        $PokemonSystem.kif_first_choice = true   # already has module choices
        return false
      end
      return true
    end

    def ask
      return false unless needed?
      pbMessage(_INTL("Welcome to KIF! KIF's features come in modules you can turn on or off at any time in Options > Modules."))
      cmd = pbMessage(_INTL("How do you want to play?"),
                      [_INTL("Classic KIF"), _INTL("PIF only"), _INTL("Let me choose")], 0)
      case cmd
      when 0
        KIF::Modules.all_on!
        classic_only!
        KIF::Modules.poll
        pbMessage(_INTL("KIF's classic features are on. Newer ones (EBDX battles, Move Effectiveness, Fusion Screen) can be turned on in Options > KIF Settings."))
      when 1
        KIF::Modules::MODULES.each_key { |id| KIF::Modules.set_state(id, KIF::Modules::OFF) }
        pbMessage(_INTL("KIF's features are off: the game plays like Pokémon Infinite Fusion."))
      else
        KIF::Modules::MODULES.each_key { |id| KIF::Modules.set_state(id, KIF::Modules::OFF) }
        open_modules
      end
      $PokemonSystem.kif_first_choice = true
      KIF.log("First launch: #{%w[Classic\ KIF PIF\ only Let\ me\ choose][cmd] || cmd} (#{KIF::Modules.states.select { |_k, v| v != KIF::Modules::OFF }.keys.join(', ')})") if defined?(KIF.log)
      return true
    rescue StandardError => e
      KIF.log("First launch question failed (#{e.class}: #{e.message})") if defined?(KIF.log)
      return false
    end

    # Classic KIF = KIF 0.20.7 as it was: features KIF never had, but that
    # default to On inside their module, are switched off
    NEW_ON_BY_DEFAULT = [:mp_ebdx_enabled, :cody_effectiveness, :cody_fusionscreen, :cody_battleinfo, :kif_mouse]

    def classic_only!
      NEW_ON_BY_DEFAULT.each do |key|
        $PokemonSystem.send("#{key}=", 0) if $PokemonSystem.respond_to?("#{key}=")
      end
    end

    # the settings screen, opened on its Modules section
    def open_modules
      pbFadeOutIn { KifSettingsScreen.new(true, :modules).main }
    end
  end
end

# At the load screen, after the update check (C-SYS-06), before the menu
alias kif_fc_find_newer_available_version find_newer_available_version unless defined?(kif_fc_find_newer_available_version)
def find_newer_available_version
  ret = kif_fc_find_newer_available_version
  KIF::FirstChoice.ask
  return ret
end

# Before that choice every module is Off, Quality of Life (C-SYS-02's Skip
# intro) included, so on a first start the opening movie played although
# Options showed Skip intro: On (26 Oct test). Until the player has chosen,
# the intro follows the Skip intro setting itself.
class Scene_Intro
  if method_defined?(:playIntroCinematic)
    alias kif_fc_playIntroCinematic playIntroCinematic unless method_defined?(:kif_fc_playIntroCinematic)

    def playIntroCinematic
      return if KIF::FirstChoice.needed? && defined?(KIF::SkipIntro) && KIF::SkipIntro.on?
      kif_fc_playIntroCinematic
    end
  end
end
