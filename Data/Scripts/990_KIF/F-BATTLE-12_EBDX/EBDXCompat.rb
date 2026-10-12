#===============================================================================
# F-BATTLE-12 – EBDX battle visuals
# Elite Battle DX (Luka S.J.) as it ships inside KIF Multiplayer 6.7.0 by
# Aleks, included in KIF Beta since 0.21.27 (Cody, 2026-10-11, with Aleks's
# permission): Data/Scripts/660_EBDX and 661_BossUIHooks/003_EBDX_UIFixes.rb
# copied as they are, graphics in Graphics/EBDX, sounds in Audio/*/EBDX and
# the Audio/SE/Anim files PIF lacked. The two files are never edited here.
#
# Those scripts expect the rest of Multiplayer; this file supplies what they
# need from it, without changing them:
#   * the settings Multiplayer's options menu normally creates on
#     PokemonSystem (camera zoom, own trainer animation, stat stage icons);
#     a save made before EBDX was installed also gets EBDX's own on/off
#     setting (EBDX only sets it for brand-new games);
#   * rows in Options > Modules > Graphical Changes settings instead of
#     Multiplayer's menu;
#   * EBDX battles only while the Graphical Changes module is on.
# Nothing here runs when EBDX isn't installed.
# Not usable without Multiplayer: 661_BossUIHooks/001-002 (boss battles call
# Pokemon#is_boss?, a Multiplayer method) - leave those two files out.
#===============================================================================
module KIF
  module EBDX
    def self.installed?
      return defined?(::EBDXToggle) ? true : false
    end
  end
end

if KIF::EBDX.installed?
  # EBDX battles follow the Graphical Changes module (Off = PIF's battles)
  module KIF
    module EBDX
      module ToggleModule
        def enabled?
          return false if defined?(KIF::Modules) && !KIF::Modules.active?(:graphics)
          return super
        end
      end
    end
  end
  ::EBDXToggle.singleton_class.prepend(KIF::EBDX::ToggleModule)
  KIF::Modules.no_gate(KIF::EBDX::ToggleModule) if defined?(KIF::Modules)
  KIF::Options.define(:mp_ebdx_enabled, 1, :global)
  KIF::Options.define(:mp_ebdx_zoom_disabled, 1, :global)
  KIF::Options.define(:mp_skip_trainer_anim, 0, :global)
  KIF::Options.define(:mp_stat_stage_overlay, 1, :global)

  KIF::Options.add(:battles, :global) {
    EnumOption.new(_INTL("EBDX Battles"), [_INTL("Off"), _INTL("On")],
                   proc { $PokemonSystem.mp_ebdx_enabled },
                   proc { |value| $PokemonSystem.mp_ebdx_enabled = value },
                   [_INTL("Battles look like PIF's own"),
                    _INTL("Battles use Elite Battle DX visuals and animations")])
  }
  KIF::Options.add(:battles, :global) {
    EnumOption.new(_INTL("EBDX Camera Zoom"), [_INTL("Off"), _INTL("On")],
                   proc { 1 - $PokemonSystem.mp_ebdx_zoom_disabled.to_i },
                   proc { |value| $PokemonSystem.mp_ebdx_zoom_disabled = 1 - value },
                   [_INTL("The camera stays still during attacks"),
                    _INTL("The camera zooms in on attacks")])
  }
  KIF::Options.add(:battles, :global) {
    EnumOption.new(_INTL("EBDX Stat Stage Icons"), [_INTL("Off"), _INTL("On")],
                   proc { $PokemonSystem.mp_stat_stage_overlay },
                   proc { |value| $PokemonSystem.mp_stat_stage_overlay = value },
                   [_INTL("No stat stage icons on the battle boxes"),
                    _INTL("Raised and lowered stats show on the battle boxes")])
  }
  KIF::Options.add(:battles, :global) {
    EnumOption.new(_INTL("EBDX Own Trainer Animation"), [_INTL("Show"), _INTL("Skip")],
                   proc { $PokemonSystem.mp_skip_trainer_anim },
                   proc { |value| $PokemonSystem.mp_skip_trainer_anim = value },
                   [_INTL("Your trainer throws the ball at the start of a battle"),
                    _INTL("Your Pokémon comes straight out")])
  }
  # EBDX's evolution scene (014_EBDX_Evolution.rb) draws the evolved form with
  # KIF 0.20.7's setPokemonBitmapSpecies(pokemon, species, back); PIF 6.8.2's
  # takes (species, back) and crashed with "wrong number of arguments".
  # With a Pokémon first, the evolved form is drawn the way 6.8.2's own
  # evolution scene does (the chosen sprite for the new species).
  module KIF::EBDX::SpeciesBitmap
    def setPokemonBitmapSpecies(*args)
      if args[0].is_a?(Pokemon)
        _pkmn, species, back = args
        pif = (BattleSpriteLoader.new.obtain_pif_sprite(species) rescue nil)
        return setPokemonBitmapPIFSprite(pif) if pif && !back
        return super(species, back || false)
      end
      super(*args)
    end
  end
  PokemonSprite.prepend(KIF::EBDX::SpeciesBitmap)

  # 6.8.2's evolution scene also remembers which sprite the evolved Pokémon
  # uses (pif_sprite, put back if the evolution is cancelled) and whether it
  # can still evolve from the party menu. EBDX's scene predates that; this
  # does the same around it.
  if defined?(::PokemonEvolutionSceneEBDX)
    module KIF::EBDX::EvolutionSprites
      def pbStartScreen(pokemon, newspecies, *rest)
        ret = super
        if pokemon.respond_to?(:pif_sprite=)
          pokemon.preEvolved_pif_sprite = pokemon.pif_sprite if pokemon.respond_to?(:preEvolved_pif_sprite=)
          pokemon.pif_sprite = (BattleSpriteLoader.new.obtain_pif_sprite(newspecies) rescue pokemon.pif_sprite)
        end
        ret
      end

      def pbEvolution(*args)
        old = @pokemon.species
        ret = super
        evolved = (@pokemon.species != old)
        if !evolved && @pokemon.respond_to?(:pif_sprite=)
          pre = (@pokemon.preEvolved_pif_sprite rescue nil)
          @pokemon.pif_sprite = pre || (BattleSpriteLoader.new.obtain_pif_sprite(@pokemon.species) rescue nil)
          @pokemon.preEvolved_pif_sprite = nil if @pokemon.respond_to?(:preEvolved_pif_sprite=)
        end
        @pokemon.evolve_from_party = !evolved if @pokemon.respond_to?(:evolve_from_party=)
        ret
      end
    end
    PokemonEvolutionSceneEBDX.prepend(KIF::EBDX::EvolutionSprites)
  end

  # 661/003's Type Display for EBDX boxes loads KIF 0.20.7's icon sheets from
  # Graphics/Pictures/TypeIcons_*.png; KIF Beta keeps them in
  # Graphics/Pictures/KIF/TypeIcons (F-BATTLE-07), and "Txt" (5) has no sheet
  # here, so PIF's own 64x28 type strip stands in for it (the 661 code draws
  # 5 at 64x28 anyway). Without this, Type Display 1-4 + EBDX crashed at the
  # first battle (missing file).
  if defined?(::DataBoxEBDX) && ::DataBoxEBDX.const_defined?(:EBDX_TYPE_DISPLAY_BITMAPS)
    sheets = {}
    if defined?(KIF::BattleUI::TYPE_SHEETS)
      KIF::BattleUI::TYPE_SHEETS.each_with_index { |path, i| sheets[i] = path if path }
    end
    sheets[5] = "Graphics/Pictures/types"
    ::DataBoxEBDX.send(:remove_const, :EBDX_TYPE_DISPLAY_BITMAPS)
    ::DataBoxEBDX.const_set(:EBDX_TYPE_DISPLAY_BITMAPS, sheets)
  end

  KIF.log("EBDX found: battle visuals available (Options > Modules > Graphical Changes)") if KIF.respond_to?(:log)
end
