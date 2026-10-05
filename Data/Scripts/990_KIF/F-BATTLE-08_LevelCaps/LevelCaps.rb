#===============================================================================
# F-BATTLE-08 – Level Cap difficulty and Cap Behavior (Reïzod & HungryPickle)
# Source: KIF 0.20.7
#   049_Compatibility/Constants.rb:333-380   multipliers [1.1, 1.0, 0.9] + tables
#   049_Compatibility/MarinUtilities.rb:1126-1146 getkuraylevelcap
#   011_Battle/003_Battle/004_Battle_ExpAndMoveLearning.rb:237-285
#   014_Pokemon/001_Pokemon.rb:866-896      (level / calc_stats clamping)
#   013_Items/002_Item_Effects.rb:792       (Rare Candy blocked at the cap)
#   016_UI/015_UI_Options.rb:2180-2197      options (both default 0)
#
# "Level Cap": Off / Easy / Normal / Hard = the next gym leader's cap x1.1 /
#   x1.0 / x0.9 (rounded). Applies to the player's Pokémon (KIF
#   player_owned?). No cap once every badge is earned.
# "Cap Behavior":
#   Smart – Exp above the cap is banked, not lost. The Pokémon stays at the
#           cap and gets the banked Exp (levelling normally) at its next Exp
#           gain after the cap has risen.
#   Lock  – no Exp above the cap.
#   RC    – each level that would go past the cap becomes a Rare Candy.
#
# 6.8.2 adaptations (differences from KIF, see PORT_LOG):
#   * The cap comes from 6.8.2's getCurrentLevelCap (its badge table,
#     Hoenn support and hard-mode modifier) instead of KIF's switch table;
#     KIF's table had the same Kanto values.
#   * KIF clamped level/Exp inside Pokemon#level and calc_stats, which ran
#     calc_stats on every level read. Here the cap is applied where Exp is
#     gained (the pbGainExpOne copy in F-BATTLE-09) and for Rare Candies.
#     "Smart" in KIF let Exp grow past the cap while hiding the extra levels;
#     the banked Exp gives the same result without a level that disagrees
#     with the Exp.
#   * While the KIF cap is on, 6.8.2's own "Level caps" rule (no Exp, or
#     60% Exp past the cap) is skipped so the two don't stack.
#===============================================================================
KIF::Options.define(:kuraylevelcap, 0, :save)
KIF::Options.define(:levelcapbehavior, 0, :save)

KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("Level Cap"), [_INTL("Off"), _INTL("Easy"), _INTL("Normal"), _INTL("Hard")],
                 proc { $PokemonSystem.kuraylevelcap },
                 proc { |value| $PokemonSystem.kuraylevelcap = value },
                 [_INTL("No Forced Level Cap"),
                  _INTL("Easy Level Cap, for children"),
                  _INTL("Normal Level Cap, for normal people"),
                  _INTL("Hard Level Cap, for nerds")])
}
KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("Cap Behavior"), [_INTL("Smart"), _INTL("Lock"), _INTL("RC")],
                 proc { $PokemonSystem.levelcapbehavior },
                 proc { |value| $PokemonSystem.levelcapbehavior = value },
                 [_INTL("Exp past the cap is saved for when the cap rises."),
                  _INTL("The Pokemon can't earn exp."),
                  _INTL("Earn rare candies instead of going over the cap.")])
}

module KIF
  module LevelCap
    MULTIPLIERS = [1.1, 1.0, 0.9]   # Easy, Normal, Hard

    # KIF getkuraylevelcap; nil = no cap
    def self.cap
      mode = $PokemonSystem ? $PokemonSystem.kuraylevelcap.to_i : 0
      return nil if mode <= 0 || mode > MULTIPLIERS.length
      return nil unless $Trainer
      return nil if $Trainer.badge_count >= Settings::NB_BADGES
      base = getCurrentLevelCap
      return nil unless base
      max = GameData::GrowthRate.max_level
      ret = (base * MULTIPLIERS[mode - 1]).round
      return [[ret, 1].max, max].min
    end

    def self.applies_to?(pkmn)
      return false unless pkmn && !pkmn.egg? && !pkmn.shadowPokemon?
      return pkmn.kif_player_owned? if pkmn.respond_to?(:kif_player_owned?)
      return $Trainer && pkmn.owner && pkmn.owner.id == $Trainer.id
    end

    def self.cap_for(pkmn)
      return nil unless applies_to?(pkmn)
      return cap
    end

    def self.behavior
      return $PokemonSystem.levelcapbehavior.to_i
    end
  end
end

class Pokemon
  attr_accessor :kif_banked_exp
end

class PokeBattle_Battle
  def kif_level_cap_active?(pkmn)
    return !KIF::LevelCap.cap_for(pkmn).nil?
  end

  # Called by the pbGainExpOne copy with the Exp about to be gained.
  # Returns [exp to gain, rare candies to give].
  def kif_apply_level_cap(pkmn, exp, growth_rate)
    cap = KIF::LevelCap.cap_for(pkmn)
    return [exp, 0] unless cap
    behavior = KIF::LevelCap.behavior
    # Smart: release banked Exp once the cap is above the current level
    if behavior == 0 && pkmn.kif_banked_exp.to_i > 0 && pkmn.level < cap
      exp += pkmn.kif_banked_exp
      pkmn.kif_banked_exp = 0
    end
    limit = growth_rate.minimum_exp_for_level(cap)
    room = [limit - pkmn.exp, 0].max
    case behavior
    when 1 # Lock
      return [[exp, room].min, 0]
    when 2 # RC
      level = pkmn.level
      target = [level, cap].max
      bar_start = growth_rate.minimum_exp_for_level(target)
      total = growth_rate.add_exp(pkmn.exp, exp)
      candies = growth_rate.level_from_exp(total) - target
      if level < cap
        return [exp, 0] if candies <= 0
        return [bar_start - pkmn.exp, candies]
      end
      return [exp, 0] if candies <= 0 # still filling the bar of the cap level
      pkmn.exp = bar_start              # KIF: back to the start of the cap level
      return [0, candies]
    else # Smart
      return [exp, 0] if exp <= room
      pkmn.kif_banked_exp = pkmn.kif_banked_exp.to_i + (exp - room)
      return [room, 0]
    end
  end

  def kif_give_cap_candies(pkmn, candies)
    return if candies <= 0
    given = 0
    candies.times do
      break unless $PokemonBag.pbCanStore?(:RARECANDY, 1)
      $PokemonBag.pbStoreItem(:RARECANDY, 1)
      given += 1
    end
    return if given == 0
    if given == 1
      pbDisplayPaused(_INTL("Obtained a Rare Candy!"))
    else
      pbDisplayPaused(_INTL("Obtained {1} Rare Candies!", given))
    end
  end
end

# KIF 002_Item_Effects.rb:792 – no Rare Candy at or above the cap
alias kif_cap_can_use_rare_candy can_use_rare_candy unless defined?(kif_cap_can_use_rare_candy)

def can_use_rare_candy(pkmn)
  cap = KIF::LevelCap.cap_for(pkmn)
  return false if cap && pkmn.level >= cap
  return kif_cap_can_use_rare_candy(pkmn)
end
