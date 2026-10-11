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

# Battle AI dispatch (F-BATTLE-03 PowerfulAI). The switch itself lives here,
# outside every module, so the mod adapter (Alpha Encounters' own AI written
# for KIF 0.20.7) still gets its answers when the Battles module is Off.
module KIF
  def self.define_ai_dispatch(cls, m, pif, demi)
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

# Stats follow a rule change at once (Max IVs, No-EVs, fusion stat rules):
# every party and boxed Pokémon is recalculated. PIF only recalculates on a
# level up, so the Summary and battles would show the old numbers until then.
module KIF
  def self.recalc_all_stats
    return unless $Trainer
    begin
      $Trainer.party.each { |p| p.calc_stats if p && !p.egg? }
      if $PokemonStorage
        $PokemonStorage.boxes.each do |box|
          box.pokemon.each { |p| p.calc_stats if p && !p.egg? }
        end
      end
    rescue => e
      KIF.log("recalc_all_stats failed: #{e.class}: #{e.message}")
    end
  end
end

# KIF 0.20.7's hasActiveAbility? takes a third argument (mold_broken, from
# DemICE's AI); mods written for KIF pass it (GhostItem Splicers). The
# 3-argument form is always accepted, whatever the Battles module does.
class PokeBattle_Battler
  alias kif_core_hasActiveAbility? hasActiveAbility? unless method_defined?(:kif_core_hasActiveAbility?)
  def hasActiveAbility?(check_ability, ignore_fainted = false, mold_broken = false)
    return false if mold_broken
    return kif_core_hasActiveAbility?(check_ability, ignore_fainted)
  end
end
