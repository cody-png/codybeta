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
KIF.guard_base("011_Battle/002_Move/007_Move_Effects_100-17F.rb", 3403102880,
               "PokeBattle_Move_109#pbEffectGeneral (Pay Day)")

class PokeBattle_Move_109 < PokeBattle_Move
  def pbEffectGeneral(user)
    if user.pbOwnedByPlayerSerious?
      @battle.field.effects[PBEffects::PayDay] += 5 * user.level
    end
    @battle.pbDisplay(_INTL("Coins were scattered everywhere!"))
  end
end
