# frozen_string_literal: true

class Game_Temp
  attr_accessor :water_plane
  attr_accessor :water_plane2

end

alias originalCausticsMethod addWaterCausticsEffect
def addWaterCausticsEffect(fog_name = "caustic1", opacity = 16)
  originalCausticsMethod(fog_name, 8)
  if Settings::GAME_ID == :IF_HOENN && $PokemonGlobal.diving
    if $game_temp.water_plane
      $game_temp.water_plane.bitmap.dispose if $game_temp.water_plane.bitmap
      $game_temp.water_plane.dispose
    end
    if $game_temp.water_plane2
      $game_temp.water_plane2.bitmap.dispose if $game_temp.water_plane2.bitmap
      $game_temp.water_plane2.dispose
    end


    $game_temp.water_plane = AnimatedPlane.new(Spriteset_Map.viewport)
    $game_temp.water_plane.bitmap = RPG::Cache.picture("Dive/ocean_dive")
    $game_temp.water_plane.z = -2
    $game_temp.water_plane.opacity = 230

    $game_temp.water_plane2 = AnimatedPlane.new(Spriteset_Map.viewport)
    $game_temp.water_plane2.bitmap = RPG::Cache.picture("Dive/dive_dark2")  # Different image if needed
    $game_temp.water_plane2.z = 2
    $game_temp.water_plane2.opacity = 210
  end
end




class Spriteset_Map
  alias pokemonEssentials_spritesetMap_update update
  def update
    pokemonEssentials_spritesetMap_update
    if Settings::GAME_ID == :IF_HOENN && $PokemonGlobal.diving
      @fog.z=-1 if @fog
      @fog2.z=-1 if @fog2

    end
  end
end



