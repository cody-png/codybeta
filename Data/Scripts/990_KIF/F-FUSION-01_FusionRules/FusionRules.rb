#===============================================================================
# F-FUSION-01 – Fusion stat & type rules
# Source: KIF 0.20.7
#   014_Pokemon/001_Pokemon.rb:912-958   self-fusion stat boost (Reïzod/DemICE)
#   014_Pokemon/001_Pokemon.rb:2108-2120 baseStats with custom fusion BST
#   014_Pokemon/001_Pokemon.rb:1107-1145 type1/type2 dominant overrides
#   048_Fusion/FusedSpecies.rb:136-173   dominant fusion types (DemICE)
#   048_Fusion/FusedSpecies.rb:195-214, :451-454 custom BST (HungryPickle)
#   019_Utilities/001_Utilities.rb:607   pbDominantFusionTypes?
#   016_UI/015_UI_Options.rb:2198-2283   options (all default Off; sliders
#                                         HP 65 / Atk 35 / Def 35 / SpA 65 /
#                                         SpD 65 / Spe 35)
#
# Self-Fusion Stat Boost: a self-fusion's base stats are multiplied by a
#   factor that grows as its base stat total shrinks (x1.02 at 800+ ... x2.8
#   under 100). Disabled during DemICE's endgame challenge.
# Fusion BaseStats (player) / NPC Fusion BaseStats: Head = each slider is the %
#   of that stat taken from the head; Better = the % taken from whichever of
#   head/body has the higher value. Player = Pokémon whose OT is the player,
#   or that were traded / fateful (KIF player_owned?); wild Pokémon count as
#   the player's, like KIF.
# Dominant Fusion Types: pre-6.0 typing, e.g. a Bulbasaur body always gives
#   Grass, Dewgong is Ice/Water.
#
# 6.8.2 adaptations (no copies of base methods):
#   * The boost is applied through baseStats while calc_stats runs, so the
#     Summary keeps showing the real base stats (same as KIF).
#   * FusedSpecies caches its types when created, so KIF's change to
#     calculate_type1/2 only took effect for fusions created after toggling.
#     Here FusedSpecies#type1/type2 apply the rule when read.
#   * Pokemon#types (6.8.2) reads the species directly; it now follows the
#     dominant types too, so type1/type2 and types never disagree.
#===============================================================================
KIF::Options.define(:self_fusion_boost, 0, :save)
KIF::Options.define(:dominant_fusion_types, 0, :save)
KIF::Options.define(:custom_bst, 0, :save)
KIF::Options.define(:custom_bst_npc, 0, :save)
KIF::Options.define(:custom_bst_sliders, { :HP => 65, :ATTACK => 35, :DEFENSE => 35,
                                           :SPECIAL_ATTACK => 65, :SPECIAL_DEFENSE => 65, :SPEED => 35 }, :save)
KIF::Options.define(:custom_bst_sliders_npc, { :HP => 65, :ATTACK => 35, :DEFENSE => 35,
                                               :SPECIAL_ATTACK => 65, :SPECIAL_DEFENSE => 65, :SPEED => 35 }, :save)

module KIF
  module FusionRules
    STATS = [[:HP, "HP"], [:ATTACK, "Attack"], [:DEFENSE, "Defense"],
             [:SPECIAL_ATTACK, "Special Attack"], [:SPECIAL_DEFENSE, "Special Defense"], [:SPEED, "Speed"]]
    DEFAULT_SLIDERS = { :HP => 65, :ATTACK => 35, :DEFENSE => 35,
                        :SPECIAL_ATTACK => 65, :SPECIAL_DEFENSE => 65, :SPEED => 35 }

    # KIF 001_Pokemon.rb:921-940
    def self.self_fusion_factor(total)
      return 1.02 if total >= 800
      return 1.04 if total >= 700
      return 1.06 if total >= 600
      return 1.09 if total >= 500
      return 1.13 if total >= 400
      return 1.19 if total >= 300
      return 1.47 if total >= 200
      return 1.81 if total >= 100
      return 2.8
    end

    def self.sliders(key)
      s = $PokemonSystem.send(key)
      s = DEFAULT_SLIDERS.dup unless s.is_a?(Hash)
      DEFAULT_SLIDERS.each { |k, v| s[k] = v if s[k].nil? }
      return s
    end

    def self.dominant?
      return true if $PokemonSystem && $PokemonSystem.dominant_fusion_types == 1
      return KIF.endgame_challenge_active?
    end

    # Pokémon whose stats are being calculated with the self-fusion boost
    @boosting = nil
    @boost = 1.0
    class << self
      attr_accessor :boosting, :boost
    end
  end
end

def pbDominantFusionTypes?
  return KIF::FusionRules.dominant?
end unless defined?(pbDominantFusionTypes?)

#-------------------------------------------------------------------------------
# Options (KIF lists these in the "Battles & Pokemons" settings)
#-------------------------------------------------------------------------------
KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("Self-Fusion Stat Boost"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.self_fusion_boost },
                 proc { |value| $PokemonSystem.self_fusion_boost = value },
                 [_INTL("Stat boost for self-fusions is disabled."),
                  _INTL("Stat boost for self-fusions is enabled.")])
}

[[:custom_bst, :custom_bst_sliders, "Fusion BaseStats", "Default fusion base stats."],
 [:custom_bst_npc, :custom_bst_sliders_npc, "NPC Fusion BaseStats", "Default NPC fusion base stats."]].each do |key, skey, title, offtext|
  KIF::Options.add(:battles, :save) {
    EnumOption.new(_INTL(title), [_INTL("Off"), _INTL("Head"), _INTL("Better")],
                   proc { $PokemonSystem.send(key) },
                   proc { |value| $PokemonSystem.send("#{key}=", value) },
                   [_INTL(offtext),
                    _INTL("Sliders determine what % of each stat comes from the head pokemon."),
                    _INTL("Sliders determine what % of each stat comes from the better base stat.")])
  }
  KIF::FusionRules::STATS.each do |stat, name|
    KIF::Options.add(:battles, :save) {
      SliderOption.new(_INTL("    {1}", name), 0, 100, 5,
                       proc { KIF::FusionRules.sliders(skey)[stat] },
                       proc { |value|
                         s = KIF::FusionRules.sliders(skey)
                         s[stat] = value
                         $PokemonSystem.send("#{skey}=", s)
                       },
                       _INTL("Percentage of base {1} contributed.", name))
    }
  end
end

KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("Dominant Fusion Types"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.dominant_fusion_types },
                 proc { |value| $PokemonSystem.dominant_fusion_types = value },
                 [_INTL("Brings back the dominant/inverse fusion types from pre-v6."),
                  _INTL("Brings back the dominant/inverse fusion types from pre-v6.")])
}

#-------------------------------------------------------------------------------
# Custom fusion base stats and dominant types on the fused species
#-------------------------------------------------------------------------------
KIF.guard_base("052_InfiniteFusion/Fusion/Data/FusedSpecies.rb", 1199575393, "FusedSpecies type/base stat calculation")

module GameData
  class FusedSpecies
    # KIF FusedSpecies.rb:195-214
    def calculate_base_stats_custom(bst_option, bst_sliders)
      head_stats = @head_pokemon.base_stats
      body_stats = @body_pokemon.base_stats
      return base_stats unless bst_option == 1 || bst_option == 2
      fused = {}
      head_stats.each do |stat, head_value|
        body_value = body_stats[stat]
        slider = bst_sliders[stat] || KIF::FusionRules::DEFAULT_SLIDERS[stat] || 50
        if bst_option == 1 || head_value > body_value
          fused[stat] = calculate_fused_stats_custom(head_value, body_value, slider)
        else
          fused[stat] = calculate_fused_stats_custom(body_value, head_value, slider)
        end
      end
      return fused
    end

    # KIF FusedSpecies.rb:451-454
    def calculate_fused_stats_custom(dominantStat, otherStat, slider)
      ratio = slider / 100.to_f
      return ((dominantStat * ratio) + (otherStat * (1 - ratio))).floor
    end

    # KIF FusedSpecies.rb:136-146 (calculate_type1 with dominant types)
    def kif_dominant_type1
      head = @head_pokemon.species
      return :ICE if head == :DEWGONG
      return :WATER if [:OMANYTE, :OMASTAR].include?(head)
      return :STEEL if [:SCIZOR, :MAGNEZONE, :EMPOLEON, :FERROTHORN].include?(head)
      return :GRASS if head == :CELEBI
      return :GROUND if head == :GASTRODON
      return @head_pokemon.type2 if @head_pokemon.type1 == :NORMAL && @head_pokemon.type2 == :FLYING
      return @head_pokemon.type1
    end

    # KIF FusedSpecies.rb:148-173 (calculate_type2 with dominant types)
    def kif_dominant_type2
      body = @body_pokemon.species
      # Dominant types
      return :GRASS if [:BULBASAUR, :IVYSAUR, :VENUSAUR].include?(body)
      return :FIRE if [:CHARMANDER, :CHARMELEON, :CHARIZARD, :MOLTRES].include?(body)
      return :WATER if [:SQUIRTLE, :WARTORTLE, :BLASTOISE, :GYARADOS].include?(body)
      return :GHOST if [:GASTLY, :HAUNTER, :GENGAR].include?(body)
      return :ROCK if [:GEODUDE, :GRAVELER, :GOLEM, :ONIX].include?(body)
      return :STEEL if body == :STEELIX
      return :BUG if body == :SCYTHER
      return :ELECTRIC if body == :ZAPDOS
      return :ICE if body == :ARTICUNO
      return :DRAGON if body == :DRAGONITE
      # Inverse types
      return :WATER if body == :DEWGONG
      return :ROCK if [:OMANYTE, :OMASTAR].include?(body)
      return :BUG if body == :SCIZOR
      return :ELECTRIC if body == :MAGNEZONE
      return :WATER if body == :EMPOLEON
      return :GRASS if body == :FERROTHORN
      return :PSYCHIC if body == :CELEBI
      return :WATER if body == :GASTRODON
      return @body_pokemon.type1 if @body_pokemon.type2 == kif_dominant_type1
      return @body_pokemon.type2
    end

    alias kif_rules_type1 type1 unless method_defined?(:kif_rules_type1)
    alias kif_rules_type2 type2 unless method_defined?(:kif_rules_type2)

    def type1
      return kif_dominant_type1 if KIF::FusionRules.dominant? && @head_pokemon && @body_pokemon
      return kif_rules_type1
    end

    def type2
      return kif_dominant_type2 if KIF::FusionRules.dominant? && @head_pokemon && @body_pokemon
      return kif_rules_type2
    end

    # Species#types reads @type1/@type2 directly
    alias kif_rules_types types unless method_defined?(:kif_rules_types)

    def types
      return kif_rules_types unless KIF::FusionRules.dominant? && @head_pokemon && @body_pokemon
      t1 = type1
      t2 = type2
      ret = [t1]
      ret << t2 if t2 && t2 != t1
      return ret
    end
  end
end

#-------------------------------------------------------------------------------
# Pokémon: base stats, self-fusion boost, unfused dominant/inverse types
#-------------------------------------------------------------------------------
class Pokemon
  KIF_DOMINANT_TYPES = {   # KIF 001_Pokemon.rb:1114-1141
    :DEWGONG   => [:ICE, :WATER],
    :OMANYTE   => [:WATER, :ROCK],
    :OMASTAR   => [:WATER, :ROCK],
    :SCIZOR    => [:STEEL, :BUG],
    :MAGNEZONE => [:STEEL, :ELECTRIC],
    :EMPOLEON  => [:STEEL, :WATER],
    :FERROTHORN => [:STEEL, :GRASS],
    :CELEBI    => [:GRASS, :PSYCHIC],
    :GASTRODON => [:GROUND, :WATER]
  }

  # KIF player_owned? (001_Pokemon.rb:1848)
  def kif_player_owned?
    return true if $Trainer && @owner && @owner.id == $Trainer.id
    return true if @obtain_method == 2 || @obtain_method == 4
    return true if respond_to?(:imported?) && imported?
    return false
  end

  alias kif_rules_baseStats baseStats unless method_defined?(:kif_rules_baseStats)

  def baseStats
    ret = kif_rules_baseStats
    sp = species_data
    if sp.is_a?(GameData::FusedSpecies) && !getBaseStatsFormException
      if kif_player_owned?
        opt, skey = $PokemonSystem.custom_bst, :custom_bst_sliders
      else
        opt, skey = $PokemonSystem.custom_bst_npc, :custom_bst_sliders_npc
      end
      if opt && opt > 0
        custom = sp.calculate_base_stats_custom(opt, KIF::FusionRules.sliders(skey))
        GameData::Stat.each_main { |s| ret[s.id] = custom[s.id] }
      end
    end
    if KIF::FusionRules.boosting.equal?(self)
      boost = KIF::FusionRules.boost
      ret.each_key { |k| ret[k] = (ret[k] * boost).round }
    end
    return ret
  end

  alias kif_rules_calc_stats calc_stats unless method_defined?(:kif_rules_calc_stats)

  def calc_stats(*args)
    return kif_rules_calc_stats(*args) unless $PokemonSystem && $PokemonSystem.self_fusion_boost == 1
    return kif_rules_calc_stats(*args) if KIF.endgame_challenge_active?
    return kif_rules_calc_stats(*args) unless (isSelfFusion? rescue false)
    total = 0
    baseStats.each_value { |v| total += v }
    prev = [KIF::FusionRules.boosting, KIF::FusionRules.boost]
    KIF::FusionRules.boosting = self
    KIF::FusionRules.boost = KIF::FusionRules.self_fusion_factor(total)
    begin
      return kif_rules_calc_stats(*args)
    ensure
      KIF::FusionRules.boosting, KIF::FusionRules.boost = prev
    end
  end

  alias kif_rules_type1 type1 unless method_defined?(:kif_rules_type1)
  alias kif_rules_type2 type2 unless method_defined?(:kif_rules_type2)
  alias kif_rules_types types unless method_defined?(:kif_rules_types)

  def kif_dominant_pair
    return nil unless KIF::FusionRules.dominant?
    return KIF_DOMINANT_TYPES[self.species]
  end

  def type1
    return kif_rules_type1 if @ability == :MULTITYPE && species_data.type1 == :NORMAL
    pair = kif_dominant_pair
    return pair[0] if pair
    return kif_rules_type1
  end

  def type2
    return kif_rules_type2 if @ability == :MULTITYPE && species_data.type2 == :NORMAL
    pair = kif_dominant_pair
    return pair[1] if pair
    return kif_rules_type2
  end

  def types
    pair = kif_dominant_pair
    return pair.uniq.clone if pair
    return kif_rules_types
  end
end
