#===============================================================================
# F-BATTLE-03 – DemICE's Powerful AI
# Source: KIF 0.20.7 Data/Scripts/100_DemICE's AI/ (AI Move.rb, AI Move
#   EffectScores.rb, AI Switch.rb), copied here as 001-003 with small changes
#   marked "# KIF port". KIF's options only had a "Powerful AI" label
#   (016_UI/015_UI_Options.rb:2149); the AI itself was always on.
#
# Option Battles > "Battle AI" PIF / DemICE (per save, default DemICE) – port
#   addition (Cody, 2026-10-05). Named as a choice between two AIs rather
#   than "harder" (Cody, play test 6). With $DEBUG on (KIF Debug option) and
#   the console open, DemICE's AI prints its move/switch scores ("Switch
#   score for: ...") – a way to see it is the one deciding.
#
# How the switch works: this file saves PIF's versions of the methods DemICE
# replaces (as kif_pif_<name>) before 001-003 load; 999_Dispatch.rb then saves
# DemICE's versions (kif_demice_<name>) and puts back a method that calls one
# or the other. DemICE's new helper methods are simply added.
#
# Changes to DemICE's code:
#   * $game_switches[850] (KIF's Endgame Challenge switch) ->
#     KIF.endgame_challenge_active? (switch 850 means something else in 6.8.2).
#   * pbCommandPhaseLoop keeps 6.8.2's addition: after switching from the
#     party menu the command cursor goes back to Fight.
#   * DemICE kept two of its own overrides that apply either way, as they
#     behave like PIF's unless DemICE's code uses them:
#     PokeBattle_Battler#hasActiveAbility? (extra mold_broken argument) and
#     pbBattleTypeWeakingBerry (no berry animation while $aiberrycheck).
#   * DemICE's AI has no Drowsy/Frostbite awareness (F-BATTLE-06); KIF's own
#     Drowsy/Frostbite AI edits were in base AI methods DemICE replaces.
#
# 6.8.2 differences lost while On (DemICE replaces these methods whole):
#   6.8.2's reworked trainer item choice (pbEnemyItemToUse – Full Restore and
#   low-stock rules). Move-effect scores DemICE doesn't handle still come from
#   6.8.2 (stupidity_pbGetMoveScoreFunctionCode).
#===============================================================================
KIF::Options.define(:powerfulai, 1, :save)

KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("Battle AI"), [_INTL("PIF"), _INTL("DemICE")],
                 proc { $PokemonSystem.powerfulai },
                 proc { |value| $PokemonSystem.powerfulai = value },
                 [_INTL("Opponents use PIF 6.8.2's own AI"),
                  _INTL("Opponents use DemICE's AI (from the community hard-mode mods)")])
}

module KIF
  module PowerfulAI
    # class name => methods DemICE replaces
    REPLACED = {
      "PokeBattle_AI"     => [:pbDefaultChooseEnemyCommand, :pbChooseMoves,
                              :pbRegisterMoveTrainer, :pbGetMoveScore,
                              :pbGetMoveScoreDamage, :pbRoughDamage,
                              :pbMoveBaseDamage, :pbCheckMoveImmunity,
                              :pbEnemyItemToUse, :pbGetMoveScoreFunctionCode,
                              :pbEnemyShouldWithdrawEx?, :pbChooseBestNewEnemy],
      "PokeBattle_Battle" => [:pbCommandPhaseLoop]
    }

    def self.on?
      return true unless $PokemonSystem && $PokemonSystem.respond_to?(:powerfulai)
      return $PokemonSystem.powerfulai.to_i != 0
    end

    def self.alias_name(prefix, m)
      return "#{prefix}_#{m.to_s.sub('?', '_q')}".to_sym
    end

    # Before DemICE's files: keep PIF's versions
    def self.save_pif
      REPLACED.each do |cls_name, methods|
        cls = Object.const_get(cls_name)
        methods.each do |m|
          pif = alias_name("kif_pif", m)
          next if cls.method_defined?(pif) || !cls.method_defined?(m)
          cls.send(:alias_method, pif, m)
        end
      end
    end

    # After DemICE's files: switch between the two
    def self.install_switch
      REPLACED.each do |cls_name, methods|
        cls = Object.const_get(cls_name)
        methods.each do |m|
          pif  = alias_name("kif_pif", m)
          demi = alias_name("kif_demice", m)
          next unless cls.method_defined?(pif)
          next if cls.method_defined?(demi)
          cls.send(:alias_method, demi, m)
          cls.send(:define_method, m) do |*args, &block|
            if KIF::PowerfulAI.on?
              send(demi, *args, &block)
            elsif Thread.current[:kif_mod_ai]
              KIF::PowerfulAI.mod_adapt(self, m, pif, args, block)
            else
              send(pif, *args, &block)
            end
          end
        end
      end
    end

    # A mod's own pbChooseMoves written for KIF 0.20.7 (Alpha Encounters)
    # expects DemICE's answers: move choices as [index, score, target, name]
    # and pbEnemyItemToUse as [[item, score], target]. With Battle AI = PIF,
    # PIF's answers are adapted while that mod code runs (ModCompat sets
    # Thread.current[:kif_mod_ai]). PIF's own item choice already ran this
    # turn before pbChooseMoves, so no second item answer is given.
    def self.mod_adapt(ai, m, pif, args, block)
      case m
      when :pbRegisterMoveTrainer
        user, _idx, choices = args
        n = choices.length
        ret = ai.send(pif, *args, &block)
        choices[n..-1].each do |c|
          next unless c.is_a?(Array) && c.length == 3
          c[3] = (user.moves[c[0]].name rescue "")
        end
        return ret
      when :pbEnemyItemToUse
        return nil
      end
      return ai.send(pif, *args, &block)
    end
  end
end

KIF::PowerfulAI.save_pif
