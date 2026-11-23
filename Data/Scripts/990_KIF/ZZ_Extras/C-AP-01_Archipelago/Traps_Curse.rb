#===============================================================================
# C-AP-01 – Archipelago Disobedience Curse (2026-10-23)
#   "TRAP_CURSE" (a quiet moment on the map, as every trap, Traps.rb): until
#   the next Pokemon Center nurse heal (the nurse detection of the Party Lock,
#   Traps_PartyLock.rb nurse_page?), each move the player's own Pokemon are
#   told to use is disobeyed curse_disobey_percent % of the time (slot option,
#   5-75, default 25). A second curse while cursed just keeps it on.
#   The disobedience is PIF's own pbDisobey, called with the Pokemon's own
#   level as the badge level, so only its harmless half can happen: half the
#   time "ignored orders!" and another usable move (or nothing), else "won't
#   obey!" / "turned away!" / "is loafing around!" / "pretended not to
#   notice!" (asleep with Snore / Sleep Talk: "kept sleeping"). It never naps
#   and never hurts itself (the level-minus-badge-level chances are 0), so no
#   HP is lost (Nuzlocke). Only the player's Pokemon (not a partner's or the
#   foe's), only for moves (switching, items, running are untouched), never
#   a multi-turn move already going, never on Pinkan Island, only in
#   internal battles (as PIF's check). Wild, trainer, double battles, KIF
#   Auto-Battle and EBDX all go through pbTryUseMove's obedience check.
#   Kept in the save (kif_ap[:curse]); "The curse is lifted." is said at the
#   next quiet moment after the nurse.
#===============================================================================
module KIF
  module AP
    module Traps
      module_function

      def cursed?
        return KIF::AP.on? && KIF::AP.data[:curse] == true
      end

      def run_curse(who)
        d = KIF::AP.data
        d[:curse] = true
        d[:curse_lifted] = false
        pbMessage(_INTL("A Disobedience Curse from {1}! Your Pokémon won't always listen until your next Pokémon Center visit.", who))
      end

      # the nurse's Recover All (Interpreter#command_314, Traps_PartyLock.rb)
      def lift_curse
        return unless cursed?
        d = KIF::AP.data
        d[:curse] = false
        d[:curse_lifted] = true
      end

      def tell_curse_lifted
        d = KIF::AP.on? ? KIF::AP.data : nil
        return unless d && d[:curse_lifted]
        d[:curse_lifted] = false
        pbMessage(_INTL("The curse is lifted."))
      end

      def curse_disobeys?(battler, choice)
        return false unless cursed? && choice[0] == :UseMove
        return false if battler.usingMultiTurnAttack? || KIF::Rand.pinkan?
        b = battler.battle
        return false unless b.internalBattle && b.pbOwnedByPlayer?(battler.index)
        return b.pbRandom(100) < KIF::AP.opt("curse_disobey_percent").to_i.clamp(5, 75)
      rescue StandardError => e
        KIF.log("Archipelago: curse check failed (#{e.class}: #{e.message})")
        return false
      end
    end
  end
end

class PokeBattle_Battler
  alias kif_ap_pbObedienceCheck? pbObedienceCheck? unless method_defined?(:kif_ap_pbObedienceCheck?)

  def pbObedienceCheck?(choice)
    return false unless kif_ap_pbObedienceCheck?(choice)
    return true unless KIF::AP::Traps.curse_disobeys?(self, choice)
    PBDebug.log("[Archipelago] #{pbThis} disobeyed (Disobedience Curse)")
    return pbDisobey(choice, @level)   # badge level = level: no nap, no self-hit
  end
end
