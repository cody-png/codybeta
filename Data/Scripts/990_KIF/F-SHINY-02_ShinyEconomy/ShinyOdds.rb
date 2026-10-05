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
#     Applies to every newly generated Pokémon whose shininess is not fixed
#     yet. As in PIF, any shiny made while the odds differ from 16
#     (S_CHANCE_VALIDATOR) is flagged debug_shiny (different star icon).
#   Shiny Trainer Pokemon (shiny_trainer_pkmn):
#     0 Off      – each trainer Pokémon rolls shinyodds/65536 again
#     1 Ace      – same, then the ace (last Pokémon if its level >= the
#                  highest level, else the highest-level one) is made shiny
#     2 All      – the whole party is shiny
#     3 Disabled – nothing is done (normal PIF behaviour)
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
end

KIF.guard_base("014_Pokemon/001_Pokemon.rb", 212896005, "Pokemon#shiny?")

class Pokemon
  # Copy of PIF 6.8.2 Pokemon#shiny? using KIF's adjustable odds.
  def shiny?
    if @shiny.nil?
      a = @personalID ^ @owner.id
      b = a & 0xFFFF
      c = (a >> 16) & 0xFFFF
      d = b ^ c
      is_shiny = d < KIF.shiny_odds   # KIF (PIF: Settings::SHINY_POKEMON_CHANCE)
      if is_shiny
        @shiny = true
        @natural_shiny = true
      end
    end
    if @shiny && KIF.shiny_odds != S_CHANCE_VALIDATOR   # KIF
      @debug_shiny = true
      @natural_shiny = false
    end
    return @shiny
  end
end

# Trapstarr – trainer shinies. Event args: (sender, [trainer]).
Events.onTrainerPartyLoad += proc { |_sender, e|
  trainer = e.is_a?(Array) ? e[0] : e
  next if !trainer || !trainer.respond_to?(:party) || trainer.party.empty?
  mode = $PokemonSystem.shiny_trainer_pkmn
  if mode < 3
    trainer.party.each do |pokemon|
      pokemon.shiny = true if rand(65536) < $PokemonSystem.shinyodds
    end
  end
  if mode == 1
    last_pokemon = trainer.party.last
    ace_pokemon = trainer.party.max_by { |p| p.level }
    ace_pokemon = last_pokemon if last_pokemon.level >= ace_pokemon.level
    ace_pokemon.shiny = true
    ace_pokemon.debug_shiny = true
  elsif mode == 2
    trainer.party.each do |pokemon|
      pokemon.shiny = true
      pokemon.debug_shiny = true
    end
  end
}
