#===============================================================================
# SCOPE-02 – shiny Pokémon evolve into a shiny sprite (2026-10-13)
# PIF 6.8.2's evolution scene (016_UI/001_Non-interactive UI/004_UI_Evolution.rb
# pbStartScreen) draws the evolved form with setPokemonBitmapPIFSprite, which
# loads the new species' sprite as it is: a shiny Kakuna turned into a normal
# Beedrill on the "Congratulations!" screen, and
# was shiny again everywhere after. EBDX's evolution scene uses the same call
# (F-BATTLE-12 EBDXCompat setPokemonBitmapSpecies).
# Here the evolved sprite gets the Pokémon's colours: KIF's shiny colours
# while the Shinies module is on and KIF colours this Pokémon, PIF's own shiny
# palette otherwise.
#===============================================================================
module KIF
  module EvolutionShiny
    module_function

    # The same sprite PIF's scene shows for the new species (pif_sprite), in
    # the Pokémon's shiny colours. nil when there is nothing to change.
    def bitmap(pokemon, newspecies, pif_sprite)
      return nil unless pokemon && pif_sprite && !pokemon.egg? && pokemon.shiny?
      species = GameData::Species.get(newspecies).species
      look = pokemon.clone   # the Pokémon as it will be: new species, same colours
      look.instance_variable_set(:@species, species)
      look.instance_variable_set(:@pif_sprite, pif_sprite)
      bm = BattleSpriteLoader.new.load_pif_sprite_directly(pif_sprite)
      return nil unless bm
      kif = defined?(KIF::Shiny) && (!defined?(KIF::Modules) || KIF::Modules.active?(:shinies)) &&
            KIF::Shiny.kif_render?(look)
      if kif
        KIF.ensure_fusion_shiny_parts(look) if defined?(KIF.ensure_fusion_shiny_parts)
        bm = KIF::Shiny.colorize!(bm, look, :sprite)
      else
        bm.shiftAllColors(look.id_number, look.body_shiny, look.head_shiny)
      end
      return bm
    end
  end
end

class PokemonSprite
  # setPokemonBitmapPIFSprite with an already loaded (coloured) bitmap
  def kif_set_animated_bitmap(animated)
    @_iconbitmap.dispose if @_iconbitmap
    @_iconbitmap = SpriteWrapper.new
    @_iconbitmap.bitmap = animated.bitmap if animated&.bitmap
    self.bitmap = @_iconbitmap.bitmap
    self.color = Color.new(0, 0, 0, 0)
    changeOrigin
  end
end

class PokemonEvolutionScene
  alias kif_evoshiny_pbStartScreen pbStartScreen unless method_defined?(:kif_evoshiny_pbStartScreen)

  def pbStartScreen(pokemon, newspecies, reversing = false)
    ret = kif_evoshiny_pbStartScreen(pokemon, newspecies, reversing)
    begin
      spr = @sprites && @sprites["rsprite2"]
      bm = spr ? KIF::EvolutionShiny.bitmap(pokemon, newspecies, pokemon.pif_sprite) : nil
      spr.kif_set_animated_bitmap(bm) if bm
    rescue => e
      KIF.log("Shiny evolution sprite failed (#{e.class}: #{e.message})") if defined?(KIF.log)
    end
    return ret
  end
end
