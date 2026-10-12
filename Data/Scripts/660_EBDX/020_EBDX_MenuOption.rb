#===============================================================================
#  EBDX Menu Option - Adds toggle to Multiplayer Options menu
#===============================================================================
#  Reopens MultiplayerOptScene to add "EBDX Battle Visuals" option.
#  This does NOT modify the original file.
#===============================================================================

if defined?(MultiplayerOptScene)
  class MultiplayerOptScene
    alias ebdx_original_pbGetOptions pbGetOptions unless method_defined?(:ebdx_original_pbGetOptions)
    def pbGetOptions(inloadscreen = false)
      options = ebdx_original_pbGetOptions(inloadscreen)

      # Add EBDX toggle option
      options << EnumOption.new(_INTL("EBDX Visuals"),
        [_INTL("Off"), _INTL("On")],
        proc { $PokemonSystem.mp_ebdx_enabled || 0 },
        proc { |value|
          $PokemonSystem.mp_ebdx_enabled = value
        },
        ["Use standard KIF battle visuals",
         "Use Elite Battle DX enhanced visuals (local only)"]
      )

      return options
    end
  end
end
