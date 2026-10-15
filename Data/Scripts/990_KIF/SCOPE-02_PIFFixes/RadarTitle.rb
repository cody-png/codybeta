#===============================================================================
# SCOPE-02 – PIF fix: the Poké Radar's row of Pokémon stayed on the title
# screen (Monto, 2026-10-15)
# The radar's banner (PokeRadar_UI: the Pokémon of the area along the top) is
# only removed by pbPokeRadarCancel. Going back to the title screen with a
# radar chain running left it drawn over the title, and $PokemonTemp (which
# holds the chain) lives on until the game closes, so the next save loaded
# could even carry the old chain. When the title screen starts, the banner
# is removed and the chain dropped (without pbPokeRadarCancel, which would
# also reset the Repel of the save being left).
#===============================================================================
module KIF
  module RadarTitle
    def self.clear
      return unless $PokemonTemp
      ui = $PokemonTemp.respond_to?(:pokeradar_ui) ? $PokemonTemp.pokeradar_ui : nil
      if ui
        ui.dispose rescue nil
        $PokemonTemp.pokeradar_ui = nil
      end
      $PokemonTemp.pokeradar = nil if $PokemonTemp.respond_to?(:pokeradar=)
    rescue StandardError => e
      KIF.log("Radar banner cleanup failed (#{e.class}: #{e.message})") if defined?(KIF.log)
    end
  end
end

class Scene_Intro
  alias kif_radartitle_main main unless method_defined?(:kif_radartitle_main)

  def main
    KIF::RadarTitle.clear
    return kif_radartitle_main
  end
end
