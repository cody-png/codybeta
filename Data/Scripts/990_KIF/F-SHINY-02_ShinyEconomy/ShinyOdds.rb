#===============================================================================
# F-SHINY-02 (part) – Wild Shiny Odds & Shiny Trainer Pokémon
# Source: KIF 0.20.7
#   014_Pokemon/001_Pokemon.rb:1356-1376 (Pokemon#shiny? uses shinyodds)
#   012_Overworld/002_Battle triggering/004_Overworld_EncounterModifiers.rb:8-48
#     (Trapstarr, onTrainerPartyLoad)
#
#   Wild Shiny Odds (shinyodds, per-save, 0-65536, default
#     Settings::SHINY_POKEMON_CHANCE = 16): a Pokémon is shiny when
#     ((pid ^ ownerId) low16 XOR high16) < shinyodds, i.e. shinyodds / 65536.
#     Each Pokémon keeps the odds that were set when it was generated
#     (@kif_odds): changing the setting only affects Pokémon met afterwards,
#     never ones already caught. Pokémon from before the
#     port, or from 0.21.21 and earlier (@kif_new_odds only), use PIF's
#     16/65536. As in PIF, any shiny made with odds other than 16
#     (S_CHANCE_VALIDATOR) is flagged debug_shiny (different star icon).
#   Shiny Trainer Pokemon (shiny_trainer_pkmn):
#     0 Normal   – each trainer Pokémon rolls shinyodds/65536 (PIF's
#                  trainer Pokémon are never shiny unless the trainer file
#                  says so, so this roll is what gives Wild Odds shinies)
#     1 Ace      – same, then the ace (last Pokémon if its level >= the
#                  highest level, else the highest-level one) is made shiny
#     2 All      – the whole party is shiny
#     3 Off      – never shiny, not even ones the trainer file marks shiny
#   Until 2026-10-27, 0 was shown as "Off" and 3 as "Normal" (no roll, i.e.
#   as PIF), so the two looked the same (Cody's settings review). The stored
#   values keep their behaviour and only swap places on screen: saves that
#   had "Off" now show Normal and play the same; saves that had "Normal"
#   show Off (only trainer-file shinies, which PIF has very few of, change).
#   Opposing trainers only: partner trainers and the player's own Pokémon
#   (e.g. passed into customTrainerBattle) are never touched.
#   Shiny fusions always get head/body shiny parts so their colours change.
#   The slider step follows "Increment Slider by" in KIF Settings.
#
# The Poké Radar chain formula using shinyodds is in F-ITEM-04. Not ported
# yet: K-Egg odds (F-ITEM-02).
# Shiny gamble odds: ShinyGamble.rb. Shiny Fuse Dye: F-SHINY-01 003_ShinyHooks.
#===============================================================================
KIF::Options.define(:shinyodds, Settings::SHINY_POKEMON_CHANCE || 16, :save)
KIF::Options.define(:shiny_trainer_pkmn, 0, :save)

KIF::Options.add(:shinies, :save) {
  SliderOption.new(_INTL("Wild Shiny Odds"), 0, 65536, KIF::Options.slider_step,
                   proc { $PokemonSystem.shinyodds },
                   proc { |value|
                     $PokemonSystem.shinyodds = value
                     $PokemonSystem.shinyodds = 1 if $PokemonSystem.shinyodds < 1
                   }, _INTL("<x> out of 65536 | Choose the Shiny Odds"))
}
KIF::Options.add(:shinies, :save) {
  EnumOption.new(_INTL("Shiny Trainer Pokemon"), [_INTL("Off"), _INTL("Ace"), _INTL("All"), _INTL("Normal")],
                 # on screen Off is first and Normal last; stored 3 = Off, 0 = Normal
                 proc { KIF.shiny_trainer_swap($PokemonSystem.shiny_trainer_pkmn) },
                 proc { |value| $PokemonSystem.shiny_trainer_pkmn = KIF.shiny_trainer_swap(value) },
                 [_INTL("Trainer Pokemon are never shiny"),
                  _INTL("Draws the opposing trainers ace pokemon as shiny"),
                  _INTL("All trainers pokemon in their party will be shiny"),
                  _INTL("Trainer Pokemon use the same shiny odds as your Wild Shiny Odds slider")])
}

module KIF
  def self.shiny_trainer_swap(v)
    v = v.to_i
    return v == 0 ? 3 : (v == 3 ? 0 : v)
  end

  def self.shiny_odds
    return Settings::SHINY_POKEMON_CHANCE unless $PokemonSystem
    return $PokemonSystem.shinyodds
  end

  # A shiny fusion only shows shiny colours if head_shiny and/or body_shiny is
  # set (6.8.2 Shinies_AnimatedBitmap#shiftAllColors returns early otherwise).
  # PIF only sets them when two Pokémon are fused, so a fusion made shiny any
  # other way (odds, trainer shinies, debug) showed the star but normal
  # colours. Pick head, body or both (1/3 each).
  def self.ensure_fusion_shiny_parts(pkmn)
    return unless pkmn && pkmn.shiny?
    return unless (pkmn.isFusion? rescue false)
    return if pkmn.head_shiny || pkmn.body_shiny
    case rand(3)
    when 0 then pkmn.head_shiny = true
    when 1 then pkmn.body_shiny = true
    else
      pkmn.head_shiny = true
      pkmn.body_shiny = true
    end
  end

  def self.make_shiny(pkmn)
    pkmn.shiny = true
    pkmn.debug_shiny = true
    ensure_fusion_shiny_parts(pkmn)
  end
end

KIF.guard_base("014_Pokemon/001_Pokemon.rb", 212896005, "Pokemon#shiny?")

class Pokemon
  # Each Pokémon remembers the odds set when it was generated. A non-shiny
  # Pokémon's shininess is worked out again on every shiny? call (@shiny
  # stays nil, as in PIF), so with the current setting instead, raising the
  # odds later turned caught Pokémon shiny (bug found 2026-10-04 for old
  # saves, 2026-10-10 for Pokémon caught under KIF).
  alias kif_odds_initialize initialize unless method_defined?(:kif_odds_initialize) || private_method_defined?(:kif_odds_initialize)

  def initialize(*args)
    kif_odds_initialize(*args)
    @kif_odds = KIF.shiny_odds
  end

  # Copy of PIF 6.8.2 Pokemon#shiny? using KIF's adjustable odds for new
  # Pokémon, plus fusion shiny parts.
  def shiny?
    odds = @kif_odds || Settings::SHINY_POKEMON_CHANCE   # KIF
    if @shiny.nil?
      a = @personalID ^ @owner.id
      b = a & 0xFFFF
      c = (a >> 16) & 0xFFFF
      d = b ^ c
      is_shiny = d < odds   # KIF (PIF: Settings::SHINY_POKEMON_CHANCE)
      if is_shiny
        @shiny = true
        @natural_shiny = true
        KIF.ensure_fusion_shiny_parts(self)   # KIF
      end
    end
    if @shiny && odds != S_CHANCE_VALIDATOR   # KIF
      @debug_shiny = true
      @natural_shiny = false
    end
    return @shiny
  end
end

# Any wild shiny (odds, Shiny Charm rerolls, PIF's shiny switch) that is a
# fusion gets its shiny parts.
Events.onWildPokemonCreate += proc { |_sender, e|
  KIF.ensure_fusion_shiny_parts(e[0]) if e.is_a?(Array)
}

# Partner trainers (pbRegisterPartner) also fire onTrainerPartyLoad; the
# setting is meant for opposing trainers only, so they are skipped.
module KIF
  @loading_partner = false
  class << self
    attr_accessor :loading_partner
  end
end

alias kif_pbRegisterPartner pbRegisterPartner unless defined?(kif_pbRegisterPartner)

def pbRegisterPartner(*args)
  KIF.loading_partner = true
  begin
    return kif_pbRegisterPartner(*args)
  ensure
    KIF.loading_partner = false
  end
end

# Trapstarr – trainer shinies. Event args: (sender, [trainer]).
Events.onTrainerPartyLoad += proc { |_sender, e|
  trainer = e.is_a?(Array) ? e[0] : e
  next if KIF.loading_partner
  next if !trainer || !trainer.respond_to?(:party) || trainer.party.empty?
  next if $Trainer && trainer.equal?($Trainer)
  mode = $PokemonSystem.shiny_trainer_pkmn.to_i
  if mode == 3   # Off
    trainer.party.each do |pokemon|
      next if $Trainer && $Trainer.party.any? { |p| p.equal?(pokemon) }
      pokemon.shiny = false
      pokemon.head_shiny = pokemon.body_shiny = false
    end
  elsif mode < 3
    trainer.party.each do |pokemon|
      next if $Trainer && $Trainer.party.any? { |p| p.equal?(pokemon) }
      if rand(65536) < $PokemonSystem.shinyodds
        pokemon.shiny = true
        KIF.ensure_fusion_shiny_parts(pokemon)
      end
    end
  end
  if mode == 1
    last_pokemon = trainer.party.last
    ace_pokemon = trainer.party.max_by { |p| p.level }
    ace_pokemon = last_pokemon if last_pokemon.level >= ace_pokemon.level
    KIF.make_shiny(ace_pokemon) unless $Trainer && $Trainer.party.any? { |p| p.equal?(ace_pokemon) }
  elsif mode == 2
    trainer.party.each do |pokemon|
      next if $Trainer && $Trainer.party.any? { |p| p.equal?(pokemon) }
      KIF.make_shiny(pokemon)
    end
  end
}
