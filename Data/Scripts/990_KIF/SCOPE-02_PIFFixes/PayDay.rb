#===============================================================================
# SCOPE-02 – Pay Day with the Auto-Battler
# Source: KIF 0.20.7 011_Battle/002_Move/007_Move_Effects_100-17F.rb:141-142
#   (pbOwnedByPlayer? -> pbOwnedByPlayerSerious?)
#
# With the Auto-Battler on (F-BATTLE-02) pbOwnedByPlayer? answers false for
# the player's Pokémon, so Pay Day scattered no money for the player. KIF
# switched the check to pbOwnedByPlayerSerious? (000_Core/004_KIF_BattleHelpers).
# Copy of 6.8.2's PokeBattle_Move_109#pbEffectGeneral with that one change.
#===============================================================================
KIF.guard_base("011_Battle/002_Move/007_Move_Effects_100-17F.rb", 914265366,
               "PokeBattle_Move_109#pbEffectGeneral (Pay Day)")

class PokeBattle_Move_109 < PokeBattle_Move
  def pbEffectGeneral(user)
    if user.pbOwnedByPlayerSerious?
      @battle.field.effects[PBEffects::PayDay] += 5 * user.level
    end
    @battle.pbDisplay(_INTL("Coins were scattered everywhere!"))
  end
end

# Base PIF's pbGainMoney returns early on trainer rematches (SWITCH_IS_REMATCH)
# before reaching the Pay Day payout block, so coins scattered in a rematch were
# never collected. Keep prize money skipped on rematches, but still pay Pay Day.
# Prepended (not aliased) because KIF::EVAlloc::MoneyLine also prepends pbGainMoney.
module KIF
  module PayDayRematch
    def pbGainMoney(*args)
      ret = super
      if $game_switches[SWITCH_IS_REMATCH] && @internalBattle && @moneyGain &&
         @field.effects[PBEffects::PayDay] > 0
        @field.effects[PBEffects::PayDay] *= 2 if @field.effects[PBEffects::AmuletCoin]
        @field.effects[PBEffects::PayDay] *= 2 if @field.effects[PBEffects::HappyHour]
        oldMoney = pbPlayer.money
        pbPlayer.money += @field.effects[PBEffects::PayDay]
        @field.effects[PBEffects::PayDay] = 0
        moneyGained = pbPlayer.money - oldMoney
        if moneyGained > 0
          msg = _INTL("You picked up ${1}!", moneyGained.to_s_formatted)
          if @kif_coop
            @kif_coop.quietly { pbDisplayPaused(msg) }
          else
            pbDisplayPaused(msg)
          end
        end
      end
      return ret
    end
  end
end
PokeBattle_Battle.prepend(KIF::PayDayRematch) unless PokeBattle_Battle.ancestors.include?(KIF::PayDayRematch)
