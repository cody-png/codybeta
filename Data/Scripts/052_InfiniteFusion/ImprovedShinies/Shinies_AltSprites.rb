# frozen_string_literal: true

class PokemonPokedexInfo_Scene

  alias pokedexAltSprites_PokedexSpritesPage_swap_main_sprite swap_main_sprite
  def swap_main_sprite
    pokedexAltSprites_PokedexSpritesPage_swap_main_sprite
    if @sprites["selectedSprite"] && @sprites["selectedSprite"].bitmap
      if @pokemon
        @sprites["selectedSprite"].bitmap.update_shiny_cache(@pokemon.id_number, "")
      elsif @idSpecies
        @sprites["selectedSprite"].bitmap.update_shiny_cache(@idSpecies, "")
      else
        @sprites["selectedSprite"].bitmap.update_shiny_cache(getDexNumberForSpecies(@species), "")
      end
    end
  end
end


