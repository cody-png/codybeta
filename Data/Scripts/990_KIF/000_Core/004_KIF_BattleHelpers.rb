#===============================================================================
# Battle helpers shared by several KIF features
#===============================================================================
class PokeBattle_Battle
  # KIF 002_PokeBattle_Battle.rb:293. "Really the player's Pokémon", even when
  # Auto-Battle (F-BATTLE-02) makes pbOwnedByPlayer? lie.
  def pbOwnedByPlayerSerious?(idxBattler)
    return false if opposes?(idxBattler)
    return pbGetOwnerIndexFromBattlerIndex(idxBattler) == 0
  end
end

class PokeBattle_Battler
  def pbOwnedByPlayerSerious?
    return @battle.pbOwnedByPlayerSerious?(@index)
  end
end

module KIF
  # DemICE's Endgame Challenge (switch 850). Redefined by F-BATTLE-04
  # (002_EndgameChallenge.rb); false only if that folder is removed.
  def self.endgame_challenge_active?
    return false
  end
end
