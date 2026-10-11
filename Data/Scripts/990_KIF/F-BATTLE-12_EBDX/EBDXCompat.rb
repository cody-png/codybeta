#===============================================================================
# F-BATTLE-12 – EBDX battle visuals (optional, not included in KIF)
# Elite Battle DX as it ships inside KIF Multiplayer 6.7.0 by Aleks
# (Data/Scripts/660_EBDX, 661_BossUIHooks/003_EBDX_UIFixes.rb; graphics in
# Graphics/EBDX, sounds in Audio/*/EBDX and Audio/SE/Anim). Cody has Aleks's
# permission to work with it (2026-10-10).
#
# When those scripts are installed without the rest of Multiplayer, this file
# supplies what they expect from Multiplayer, without changing them:
#   * the settings Multiplayer's options menu normally creates on
#     PokemonSystem (camera zoom, own trainer animation, stat stage icons);
#     a save made before EBDX was installed also gets EBDX's own on/off
#     setting (EBDX only sets it for brand-new games);
#   * rows in Options > KIF Settings > Battles instead of Multiplayer's menu.
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

  KIF.log("EBDX found: battle visuals available (Options > KIF Settings > Battles)") if KIF.respond_to?(:log)
end
