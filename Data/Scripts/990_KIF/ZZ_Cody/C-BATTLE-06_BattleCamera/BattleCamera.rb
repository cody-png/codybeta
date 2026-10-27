#===============================================================================
# C-BATTLE-06 – Battle Camera (2026-10-27)
# PIF's battle screen (not EBDX's) "zoomed out" for double and triple battles:
# the Pokémon are drawn smaller and further apart so each one is fully
# visible. Single battles look as in PIF with every value.
#   PIF   - PIF's layout
#   Wide  - doubles: your side 2.5x, foes 2x (default)
#   Wider - doubles: both sides 2x
#   Wide and Wider - triples: both sides 2x, spread out
# Sprite files are 96 px art; PIF draws your side at 3x (288 px) and foes at
# 2x (192 px). 2x stays on the pixel grid; 2.5x is drawn nearest-pixel (sharp,
# pixel widths alternate 2 and 3), so players who mind it can pick Wider.
# The bitmap itself is scaled (as PIF scales front sprites), so the sprite's
# zoom stays 1: send-out, faint, catch and move animations work unchanged and
# aim at the moved spots. Metrics offsets shrink with the sprite.
# In the Graphical Changes module. Setting: Options > Graphics > Battle Camera,
# Wide by default (PIF for Classic KIF).
#===============================================================================
KIF::Options.define(:kif_battle_camera, 1, :global)

KIF::Options.add(:graphics, :global) {
  EnumOption.new(_INTL("Battle Camera"), [_INTL("PIF"), _INTL("Wide"), _INTL("Wider")],
                 proc { $PokemonSystem.kif_battle_camera },
                 proc { |value| $PokemonSystem.kif_battle_camera = value },
                 [_INTL("Double and triple battles look as in PIF"),
                  _INTL("Double and triple battles show your Pokémon a bit smaller and spaced out"),
                  _INTL("Double and triple battles show every Pokémon smaller, for the most room")])
}

module KIF
  module BattleCamera
    TRIPLES = { pos: [[56, 286], [462, 172], [140, 292], [370, 162], [222, 298], [282, 152]],
                scale: [2 / 3r, 1r] }
    # setting value => side size => [x, y] centre bottom of each battler index
    # (before metrics) and the scale on top of PIF's (your side, foes)
    LAYOUTS = {
      1 => { 2 => { pos: [[78, 302], [448, 170], [190, 312], [322, 156]], scale: [5 / 6r, 1r] },
             3 => TRIPLES },
      2 => { 2 => { pos: [[80, 290], [448, 170], [186, 298], [322, 156]], scale: [2 / 3r, 1r] },
             3 => TRIPLES }
    }
    @on = false
    class << self
      attr_accessor :on   # true while a battle in PIF's scene uses the camera

      def mode
        return $PokemonSystem ? $PokemonSystem.kif_battle_camera.to_i : 0
      end

      def for_scene?(scene)
        return false if defined?(PokeBattle_SceneEBDX) && scene.is_a?(PokeBattle_SceneEBDX)
        return LAYOUTS.has_key?(mode)
      end

      def layout(side_size)
        return nil unless @on && KIF::Modules.active?(:graphics)
        l = LAYOUTS[mode]
        return l && l[side_size]
      end

      def position(index, side_size)
        l = layout(side_size)
        return l && l[:pos][index] && l[:pos][index].dup
      end

      def scale(index, side_size)
        l = layout(side_size)
        return 1 unless l
        return l[:scale][index & 1]
      end

      # a new bitmap scaled by f (nearest pixel, as AnimatedBitmap#scale_bitmap)
      def scaled(bmp, f)
        w = (bmp.width * f).round
        h = (bmp.height * f).round
        ret = Bitmap.new(w, h)
        ret.stretch_blt(Rect.new(0, 0, w, h), bmp, Rect.new(0, 0, bmp.width, bmp.height))
        return ret
      end
    end
  end
end

module PokeBattle_SceneConstants
  class << self
    alias kif_cam_pbBattlerPosition pbBattlerPosition unless method_defined?(:kif_cam_pbBattlerPosition) || private_method_defined?(:kif_cam_pbBattlerPosition)
  end

  def self.pbBattlerPosition(index, sideSize = 1)
    return KIF::BattleCamera.position(index, sideSize) || kif_cam_pbBattlerPosition(index, sideSize)
  end
end

class PokeBattle_Scene
  alias kif_cam_pbStartBattle pbStartBattle unless method_defined?(:kif_cam_pbStartBattle) || private_method_defined?(:kif_cam_pbStartBattle)
  def pbStartBattle(battle)
    KIF::BattleCamera.on = KIF::BattleCamera.for_scene?(self)
    kif_cam_pbStartBattle(battle)
  end
end

class PokemonBattlerSprite
  alias kif_cam_setPokemonBitmap setPokemonBitmap unless method_defined?(:kif_cam_setPokemonBitmap) || private_method_defined?(:kif_cam_setPokemonBitmap)
  def setPokemonBitmap(pkmn, back = false, *rest)
    ret = kif_cam_setPokemonBitmap(pkmn, back, *rest)
    f = KIF::BattleCamera.scale(@index, @sideSize)
    if f != 1 && @_iconBitmap && @_iconBitmap.bitmap
      begin
        if @kif_frames   # an animated strip (C-BATTLE-04): every frame
          shown = @kif_frames.index { |b| b.equal?(@_iconBitmap.bitmap) } || 0
          @kif_frames = @kif_frames.map { |b| n = KIF::BattleCamera.scaled(b, f); b.dispose; n }
          @_iconBitmap.bitmap = @kif_frames[shown]
        else
          # not disposed: with no PIF scaling (your side) it can be the cached file
          @_iconBitmap.bitmap = KIF::BattleCamera.scaled(@_iconBitmap.bitmap, f)
        end
        self.bitmap = @_iconBitmap.bitmap
        pbSetPosition
      rescue StandardError => e
        KIF.log("Battle camera: sprite not scaled (#{e.class}: #{e.message})")
      end
    end
    return ret
  end

  alias kif_cam_pbSetPosition pbSetPosition unless method_defined?(:kif_cam_pbSetPosition) || private_method_defined?(:kif_cam_pbSetPosition)
  def pbSetPosition
    ret = kif_cam_pbSetPosition
    f = KIF::BattleCamera.scale(@index, @sideSize)
    if f != 1 && @_iconBitmap && !@ebdx_position_disabled
      p = PokeBattle_SceneConstants.pbBattlerPosition(@index, @sideSize)
      @spriteX = p[0] + ((@spriteX - p[0]) * f).round   # metrics offsets shrink with the sprite
      @spriteY = p[1] + ((@spriteY - p[1]) * f).round
    end
    return ret
  end
end
