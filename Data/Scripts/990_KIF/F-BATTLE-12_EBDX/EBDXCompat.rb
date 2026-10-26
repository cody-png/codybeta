#===============================================================================
# F-BATTLE-12 – EBDX battle visuals
# Elite Battle DX (Luka S.J.) as it ships inside KIF Multiplayer 6.7.0 by
# Aleks, included in KIF since 0.21.27 (with Aleks's
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
          return false if defined?(KIF::Modules) && !KIF::Modules.active?("F-BATTLE-12_EBDX")
          return super
        end
      end
    end
  end
  ::EBDXToggle.singleton_class.prepend(KIF::EBDX::ToggleModule)
  KIF::Modules.no_gate(KIF::EBDX::ToggleModule) if defined?(KIF::Modules)
  KIF::Options.define(:mp_ebdx_enabled, 0, :global)

  # EBDX is opt-in: EBDX's own PokemonSystem#initialize
  # (660_EBDX/001, unchanged) sets it On for every new player, so a new
  # player's setting is put back to Off here. Saved settings keep their value.
  class ::PokemonSystem
    alias kif_ebdx_off_initialize initialize unless method_defined?(:kif_ebdx_off_initialize) || private_method_defined?(:kif_ebdx_off_initialize)
    def initialize
      kif_ebdx_off_initialize
      @mp_ebdx_enabled = 0
    end
  end
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
  # the evolved form's sprite as the scene showed it [species, pif sprite]:
  # the Pokémon keeps that one (a second pick can be another random sprite)
  class << KIF::EBDX; attr_accessor :evo_pif; end

  module KIF::EBDX::SpeciesBitmap
    def setPokemonBitmapSpecies(*args)
      if args[0].is_a?(Pokemon)
        pkmn, species, back = args
        pif = (BattleSpriteLoader.new.obtain_pif_sprite(species) rescue nil)
        KIF::EBDX.evo_pif = [species, pif] if pif && !back
        if pif && !back
          # a shiny Pokémon evolves into a shiny sprite (SCOPE-02 EvolutionShiny)
          bm = (KIF::EvolutionShiny.bitmap(pkmn, species, pif) rescue nil) if defined?(KIF::EvolutionShiny)
          return kif_set_animated_bitmap(bm) if bm
          return setPokemonBitmapPIFSprite(pif)
        end
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
        KIF::EBDX.evo_pif = nil
        ret = super
        if pokemon.respond_to?(:pif_sprite=)
          pokemon.preEvolved_pif_sprite = pokemon.pif_sprite if pokemon.respond_to?(:preEvolved_pif_sprite=)
          shown = KIF::EBDX.evo_pif
          pokemon.pif_sprite = (shown && shown[0] == newspecies) ? shown[1] :
                               (BattleSpriteLoader.new.obtain_pif_sprite(newspecies) rescue pokemon.pif_sprite)
        end
        ret
      end

      # PIF's scene takes (cancancel, reversing); EBDX's only cancancel, so
      # PIF's DNA Reverser crashed with EBDX on. Reversing: no "evolved"
      # after-effects (consumed item, Shedinja), as in PIF's scene.
      def pbEvolution(cancancel = true, reversing = false)
        define_singleton_method(:pbEvolutionMethodAfterEvolution) { } if reversing
        old = @pokemon.species
        ret = super(cancancel)
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

  # EBDX's party lineups (balls showing each side's team) never appeared:
  # 660/010's pbShowPartyLineup only set their toggle, so PartyLineupEBDX
  # was never refreshed (never loaded, never drawn), and its send-outs never
  # hid them. Now as in PIF's scene: both sides at a trainer battle's start,
  # one side when a Pokémon is switched in, each hidden at its send-out.
  if defined?(::PokeBattle_SceneEBDX) && defined?(::PartyLineupEBDX)
    class ::PokeBattle_SceneEBDX
      def pbShowPartyLineup(side, fullAnim = false)
        lineup = (side % 2 == 0) ? @playerLineUp : @opponentLineUp
        return if !lineup || lineup.disposed?
        lineup.refresh
        # this scene shows the player's battle box during the intro: the lineup
        # goes above it, not across it. Singles: between the foe trainer's feet
        # and the box (0.55 touches neither); doubles have no such gap (the
        # first box reaches the feet), so EBDX's follower spot (0.5) keeps the
        # balls off the box's name
        lineup.y = @viewport.height * (@battle.pbSideSize(0) == 1 ? 0.55 : 0.5) if side % 2 == 0
        # battle start: the intro messages run while it slides in (PIF's fullAnim)
        return if fullAnim || !@introdone
        kif_lineup_settle
      end

      # PIF lets the lineups finish sliding in before a send-out fades them
      # (inPartyAnimation?); skipping the intro message fast faded them
      # mid-slide. Bounded so a lineup that never arrives can't hang the battle.
      def kif_lineup_settle
        120.times do
          break unless [@playerLineUp, @opponentLineUp].any? { |l| l && !l.disposed? && l.toggle && l.animating? }
          self.wait(1, true)
        end
      end

      # the send-out animations wait without animateScene, which left a hiding
      # lineup half faded on screen until the next command menu
      alias kif_lineup_wait wait unless method_defined?(:kif_lineup_wait) || private_method_defined?(:kif_lineup_wait)
      def wait(frames = 1, align = false)
        return kif_lineup_wait(frames, align) if align   # animateScene moves them
        frames.times do
          [@playerLineUp, @opponentLineUp].each { |l| l.update if l && !l.disposed? }
          kif_lineup_wait(1, false)
        end
      end

      alias kif_lineup_pbSendOutBattlers pbSendOutBattlers unless method_defined?(:kif_lineup_pbSendOutBattlers) || private_method_defined?(:kif_lineup_pbSendOutBattlers)
      def pbSendOutBattlers(sendOuts, startBattle = false)
        kif_lineup_settle
        sendOuts.each do |pair|
          lineup = @battle.opposes?(pair[0]) ? @opponentLineUp : @playerLineUp
          lineup.toggle = false if lineup
        end
        kif_lineup_pbSendOutBattlers(sendOuts, startBattle)
      end
    end

    class ::PartyLineupEBDX
      # EBDX's own drew the whole side: a partner's team in the player's balls,
      # only the last of two foe trainers. PIF's classic mapping instead: the
      # player's own team, each foe trainer's in its share of the 6 balls.
      def party
        pty = @battle.pbParty(@side)
        map = ::LineupAppearAnimation.allocate
        map.instance_variable_set(:@side, @side % 2)
        map.instance_variable_set(:@partyStarts, @battle.respond_to?(:pbPartyStarts) ? @battle.pbPartyStarts(@side) : [0])
        (0...@num).map { |k| i = map.getPartyIndexFromBallIndex(k); i >= 0 ? pty[i] : nil }
      end

      # refresh gives the bar a clone and each ball a new bitmap without
      # disposing the ones they replace; free those (never the shared sheets)
      alias kif_lineup_refresh refresh unless method_defined?(:kif_lineup_refresh) || private_method_defined?(:kif_lineup_refresh)
      def refresh
        old = @kif_bitmaps || []
        kif_lineup_refresh
        ids = ["partyLine_#{@side}"] + (0...@num).map { |k| "partyLine_#{@side}_#{k}" }
        @kif_bitmaps = ids.map { |id| @sprites[id] && @sprites[id].bitmap }.compact - [@partyBar, @partyBalls]
        (old - @kif_bitmaps).each { |b| b.dispose if !b.disposed? }
      end

      # the scene disposes the sprites first (pbDisposeSprites), then this
      alias kif_lineup_dispose dispose unless method_defined?(:kif_lineup_dispose) || private_method_defined?(:kif_lineup_dispose)
      def dispose
        (@kif_bitmaps || []).each { |b| b.dispose if !b.disposed? } if !@disposed
        @kif_bitmaps = nil
        kif_lineup_dispose
      end
    end
  end

  # 661/003's Type Display for EBDX boxes loads KIF 0.20.7's icon sheets from
  # Graphics/Pictures/TypeIcons_*.png; KIF keeps them in
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

  KIF.verbose("EBDX found: battle visuals available (Options > Battles > EBDX Battles)") if KIF.respond_to?(:verbose)
end
