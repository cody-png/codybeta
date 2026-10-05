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
#     Applies only to Pokémon generated after the port started (flag
#     @kif_new_odds); older Pokémon keep PIF's 16/65536 check. As in PIF, any shiny made while the odds differ from 16
#     (S_CHANCE_VALIDATOR) is flagged debug_shiny (different star icon).
#   Shiny Trainer Pokemon (shiny_trainer_pkmn):
#     0 Off      – each trainer Pokémon rolls shinyodds/65536 again
#     1 Ace      – same, then the ace (last Pokémon if its level >= the
#                  highest level, else the highest-level one) is made shiny
#     2 All      – the whole party is shiny
#     3 Disabled – nothing is done (normal PIF behaviour)
#   Opposing trainers only: partner trainers and the player's own Pokémon
#   (e.g. passed into customTrainerBattle) are never touched.
#   Shiny fusions always get head/body shiny parts so their colours change.
#   The slider step follows "Increment Slider by" in KIF Settings.
#
# Not ported yet: the Poké Radar chain formula using shinyodds (KIF
# 005_Item_PokeRadar.rb:185, see F-ITEM-04), K-Egg odds (F-ITEM-02), shiny
# gamble odds and Shiny Fuse Dye (need the PC "Kuray Actions" menu, F-PC-01).
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
  EnumOption.new(_INTL("Shiny Trainer Pokemon"), [_INTL("Off"), _INTL("Ace"), _INTL("All"), _INTL("Disabled")],
                 proc { $PokemonSystem.shiny_trainer_pkmn },
                 proc { |value| $PokemonSystem.shiny_trainer_pkmn = value },
                 [_INTL("Trainer pokemon will have their normal shiny rates"),
                  _INTL("Draws the opposing trainers ace pokemon as shiny"),
                  _INTL("All trainers pokemon in their party will be shiny"),
                  _INTL("Trainer pokemon will never be shiny")])
}

module KIF
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
  # Marks Pokémon generated while this overlay runs. Only these use the KIF
  # odds: Pokémon that already existed (in any save) keep PIF's 16/65536
  # check. Without this, a Pokémon whose shininess hadn't been evaluated yet
  # (@shiny nil – e.g. never displayed) was re-rolled at the new odds, which
  # turned most of a test save shiny at 65536/65536 (bug found 2026-10-04).
  alias kif_odds_initialize initialize unless method_defined?(:kif_odds_initialize)

  def initialize(*args)
    kif_odds_initialize(*args)
    @kif_new_odds = true
  end

  # Copy of PIF 6.8.2 Pokemon#shiny? using KIF's adjustable odds for new
  # Pokémon, plus fusion shiny parts.
  def shiny?
    odds = @kif_new_odds ? KIF.shiny_odds : Settings::SHINY_POKEMON_CHANCE   # KIF
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
  mode = $PokemonSystem.shiny_trainer_pkmn
  if mode < 3
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
