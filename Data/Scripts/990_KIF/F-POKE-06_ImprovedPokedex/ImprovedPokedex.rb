#===============================================================================
# F-POKE-06 – Improved Pokédex registration & Dex Sprite Select
# Source: KIF 0.20.7
#   015_Trainers and player/005_Player_Pokedex.rb:432-453 register_unfused_pkmn
#                                                    (Trapstarr & HungryPickle)
#   011_Battle/003_Battle/001_PokeBattle_BattleCommon.rb:74-76 (catch)
#   016_UI/001_Non-interactive UI/003_UI_EggHatching.rb:133-135 (hatch)
#   016_UI/001_Non-interactive UI/004_UI_Evolution.rb:646-649 (evolution)
#   016_UI/004_UI_Pokedex_Entry.rb:844 (dexspriteselect)
#   016_UI/015_UI_Options.rb:1865-1870, :2285-2290 (options, both default Off)
#
# Improved Pokedex: catching, hatching or evolving into a fusion also
#   registers its head and body as owned, with "{1}'s data was added to the
#   Pokédex" for each part that was new.
# Dex Sprite Select: whether a new species/fusion opens the alternate sprite
#   picker. KIF made it opt-in (default Off). 6.8.2 always opens it, so the
#   default here is On to keep 6.8.2's behaviour; turn it Off for KIF's.
#
# 6.8.2 adaptations: parts come from species_data.head_pokemon/body_pokemon
# (6.8.2 fusion ids are symbols); triple fusions are skipped like KIF.
#===============================================================================
KIF::Options.define(:improved_pokedex, 0, :save)
KIF::Options.define(:dexspriteselect, 1, :global)

KIF::Options.add(:battles, :save) {
  EnumOption.new(_INTL("Improved Pokedex"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.improved_pokedex },
                 proc { |value| $PokemonSystem.improved_pokedex = value },
                 [_INTL("Don't use the Improved Pokedex"),
                  _INTL("Registers a fusions base Pokemon to the Pokedex when catching/evolving")])
}
KIF::Options.add(:others, :global) {
  EnumOption.new(_INTL("Dex Sprite Select"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.dexspriteselect },
                 proc { |value| $PokemonSystem.dexspriteselect = value },
                 [_INTL("New species don't prompt a sprite selection"),
                  _INTL("Each new pokemon/fusion prompts a sprite selection")])
}

class Player < Trainer
  class Pokedex
    # KIF register_unfused_pkmn. Returns the species newly registered.
    def register_unfused_pkmn(pkmn)
      registered = []
      return registered unless $PokemonSystem && $PokemonSystem.improved_pokedex == 1
      return registered unless pkmn
      sp = pkmn.species_data
      return registered unless sp.is_a?(GameData::FusedSpecies)
      return registered if (pkmn.isTripleFusion? rescue false)
      [sp.head_pokemon, sp.body_pokemon].each do |part|
        next unless part
        species = part.species
        next if owned?(species) || registered.include?(species)
        set_owned(species)
        if $Trainer.has_pokedex
          register(species)
          registered << species
        end
      end
      return registered
    end
  end
end

module KIF
  def self.unfused_dex_names(pkmn)
    return [] unless $Trainer && $Trainer.pokedex.respond_to?(:register_unfused_pkmn)
    return $Trainer.pokedex.register_unfused_pkmn(pkmn).map { |s| GameData::Species.get(s).name }
  rescue => e
    KIF.log("Improved Pokedex failed: #{e.message}")
    return []
  end
end

#-------------------------------------------------------------------------------
# Catching (copy of 6.8.2 pbRecordAndStoreCaughtPokemon, 001_PokeBattle_
# BattleCommon.rb:60-85, with the KIF lines marked)
#-------------------------------------------------------------------------------
KIF.guard_base("011_Battle/003_Battle/001_PokeBattle_BattleCommon.rb", 563813507,
               "PokeBattle_Battle#pbRecordAndStoreCaughtPokemon")

module PokeBattle_BattleCommon
  def pbRecordAndStoreCaughtPokemon
    @caughtPokemon.each do |pkmn|
      pbPlayer.pokedex.register(pkmn) # In case the form changed upon leaving battle
      # Record the Pokémon's species as owned in the Pokédex
      if !pbPlayer.owned?(pkmn.species)
        pbPlayer.pokedex.set_owned(pkmn.species)
        if $Trainer.has_pokedex
          pbDisplayPaused(_INTL("{1}'s data was added to the Pokédex.", pkmn.name))
          pbPlayer.pokedex.register_last_seen(pkmn)
          @scene.pbShowPokedex(pkmn)
        end
      end
      KIF.unfused_dex_names(pkmn).each do |name|                         # KIF
        pbDisplayPaused(_INTL("{1}'s data was added to the Pokédex.", name)) # KIF
      end                                                                 # KIF
      # Record a Shadow Pokémon's species as having been caught
      pbPlayer.pokedex.set_shadow_pokemon_owned(pkmn.species) if pkmn.shadowPokemon?
      # Store caught Pokémon

      gave_away_pokemon = promptGiveToPartner(pkmn) if isPartneredWithAnyTrainer()

      promptCaughtPokemonAction(pkmn) if !gave_away_pokemon
      if $game_switches[AUTOSAVE_CATCH_SWITCH]
        Kernel.tryAutosave()
      end

    end
    @caughtPokemon.clear
  end
end

#-------------------------------------------------------------------------------
# Hatching
#-------------------------------------------------------------------------------
class PokemonEggHatch_Scene
  alias kif_dex_pbMain pbMain unless method_defined?(:kif_dex_pbMain)

  def pbMain
    ret = kif_dex_pbMain
    KIF.unfused_dex_names(@pokemon).each do |name|
      pbMessage(_INTL("{1}'s data was added to the Pokédex", name)) { update }
    end
    return ret
  end
end

#-------------------------------------------------------------------------------
# Evolution
#-------------------------------------------------------------------------------
class PokemonEvolutionScene
  alias kif_dex_pbEvolutionSuccess pbEvolutionSuccess unless method_defined?(:kif_dex_pbEvolutionSuccess)

  def pbEvolutionSuccess(*args)
    ret = kif_dex_pbEvolutionSuccess(*args)
    KIF.unfused_dex_names(@pokemon).each do |name|
      if @sprites && @sprites["msgwindow"] && !@sprites["msgwindow"].disposed?
        Kernel.pbMessageDisplay(@sprites["msgwindow"], _INTL("{1}'s data was added to the Pokédex", name))
      else
        pbMessage(_INTL("{1}'s data was added to the Pokédex", name))
      end
    end
    return ret
  end
end

#-------------------------------------------------------------------------------
# Dex Sprite Select (copy of 6.8.2 PokemonPokedexInfoScreen#pbDexEntry,
# 004_UI_Pokedex_Entry.rb:818-832)
#-------------------------------------------------------------------------------
KIF.guard_base("016_UI/Pokedex/004_UI_Pokedex_Entry.rb", 3919832689, "PokemonPokedexInfoScreen#pbDexEntry")

class PokemonPokedexInfoScreen
  def pbDexEntry(pokemon)
    species = pokemon.species

    # For use when capturing a new species
    nb_sprites_for_alts_page = isSpeciesFusion(species) ? 2 : 1
    alts_list = @scene.pbGetAvailableForms(species)
    if alts_list.length > nb_sprites_for_alts_page && $PokemonSystem.dexspriteselect != 0   # KIF
      @scene.pbStartSpritesSelectSceneBrief(species, alts_list, pokemon)
      @scene.pbSelectSpritesSceneBrief
      @scene.pbEndScene
    end
    @scene.pbStartSceneBrief(pokemon)
    @scene.pbSceneBrief
    @scene.pbEndScene
  end
end
