#===============================================================================
# C-BATTLE-04 – Animated sprites play in battle (2026-10-18)
# Some sprite files are animation strips: frames side by side, each as wide as
# it is tall (191.208 is 48 frames of 288). Outside battle they show their
# first frame (C-SYS-04 first_frame). In battle the whole strip is loaded,
# scaled and recoloured once (shiny colours, as for any sprite), then cut into
# frames that PokemonBattlerSprite#update steps through.
# Always on (a base feature, in no module): only a handful of sprites are strips.
# Not animated: shinies coloured by PIF's Improved Shinies palettes (PIF saves
# that result per Pokédex number, so a strip there would replace the normal
# sprite everywhere).
# shortcut: one speed for every strip (10 frames a second), first 48 frames;
# a per-sprite speed would need data the sprite files don't carry.
#===============================================================================
module KIF
  module AnimatedSprites
    FPS = 10

    # PIF's palette shinies are saved per Pokédex number: never as a strip
    def self.allowed?(pkmn)
      return false unless pkmn && !pkmn.egg?
      return true unless pkmn.shiny?
      return false unless defined?(KIF::Shiny) && KIF::Shiny.kif_render?(pkmn)
      return !KIF::Shiny.decide(pkmn)[0]
    end

    # a strip bitmap -> its frames (the strip is disposed); nil if not a strip
    def self.cut(bmp)
      return nil unless bmp && !bmp.disposed?
      h = bmp.height
      return nil unless h > 0 && bmp.width > h && bmp.width % h == 0
      frames = Array.new(bmp.width / h) do |i|
        f = Bitmap.new(h, h)
        f.blt(0, 0, bmp, Rect.new(i * h, 0, h, h))
        f
      end
      bmp.dispose
      return frames
    end

    # the hat as PIF's add_hat_to_bitmap draws it (LayeredClothes.rb), made
    # once for every frame: add_hat_to_bitmap loads and scales the file on
    # each call (48 frames = 48 loads per send-out)
    def self.draw_hat(frames, pkmn, scale)
      file = getTrainerSpriteHatFilename(pkmn.hat)
      return unless pbResolveBitmap(file)
      s = 1.5 * scale
      hat = AnimatedBitmap.new(file, 0)
      hat.scale_bitmap(s)
      hat.mirror_horizontally if pkmn.hat_mirrored_horizontal
      hat.mirror_vertically if pkmn.hat_mirrored_vertical
      frames.each { |f| f.blt(pkmn.hat_x * s, pkmn.hat_y * s, hat.bitmap, hat.bitmap.rect) }
    ensure
      hat.dispose if hat
    end
  end
end

class PokemonBattlerSprite
  alias kif_anim_setPokemonBitmap setPokemonBitmap unless method_defined?(:kif_anim_setPokemonBitmap)
  alias kif_anim_update update unless method_defined?(:kif_anim_update)
  alias kif_anim_dispose dispose unless method_defined?(:kif_anim_dispose)

  def setPokemonBitmap(pkmn, back = false, *rest)
    kif_anim_drop_frames
    unless KIF::AnimatedSprites.allowed?(pkmn)
      return kif_anim_setPokemonBitmap(pkmn, back, *rest)
    end
    ret = KIF::SpriteImport.keep_strips { kif_anim_setPokemonBitmap(pkmn, back, *rest) }
    begin
      frames = KIF::AnimatedSprites.cut(@_iconBitmap && @_iconBitmap.bitmap)
      if frames
        @kif_frames = frames
        @kif_frame_t0 = Graphics.frame_count
        @_iconBitmap.bitmap = frames[0]
        self.bitmap = frames[0]
        if pkmn.respond_to?(:hat) && pkmn.hat   # the hat was drawn on the strip's first frame only
          scale = back ? Settings::BACKRPSPRITE_SCALE : Settings::FRONTSPRITE_SCALE
          KIF::AnimatedSprites.draw_hat(frames[1..-1], pkmn, scale)
        end
        pbSetPosition
      end
    rescue => e
      KIF.log("Animated sprite failed (#{e.class}: #{e.message})")
    end
    return ret
  end

  def update(*args)
    if @kif_frames && @_iconBitmap && !@_iconBitmap.disposed?
      i = ((Graphics.frame_count - @kif_frame_t0) * KIF::AnimatedSprites::FPS / Graphics.frame_rate) % @kif_frames.length
      @_iconBitmap.bitmap = @kif_frames[i]
    end
    return kif_anim_update(*args)
  end

  def dispose
    kif_anim_drop_frames
    return kif_anim_dispose
  end

  # the shown frame goes with @_iconBitmap (the base disposes it)
  def kif_anim_drop_frames
    return unless @kif_frames
    shown = @_iconBitmap && (@_iconBitmap.bitmap rescue nil)
    @kif_frames.each { |f| f.dispose unless f.disposed? || f.equal?(shown) }
    @kif_frames = nil
  end
end
