#==============================================================================
# 003_EBDX_UIFixes.rb
# Miscellaneous EBDX battle UI fixes.
#==============================================================================

# Fix: CONFUSERAY animation leaves a purple overlay + particles stuck on screen
# if it crashes mid-animation (same issue Growl had before its rescue fix).
# Root causes:
#   - fp["bg"] and fp["0..35"] are Sprites that never get disposed on crash
#   - @sprites["battlebg"].defocus shifts z-values; focus() never restores them
#   - @targetSprite.tone may be left non-zero
# Solution: redefine the animation with fp initialized outside begin so
# ensure can always call pbDisposeSpriteHash(fp) regardless of crash point.
EliteBattle.defineMoveAnimation(:CONFUSERAY) do
  vector = @scene.getRealVector(@targetIndex, @targetIsPlayer)
  fp = {}; rndx = []; rndy = []
  begin
    fp["bg"] = Sprite.new(@viewport)
    fp["bg"].bitmap = Bitmap.new(@viewport.width, @viewport.height)
    fp["bg"].bitmap.fill_rect(0, 0, fp["bg"].bitmap.width, fp["bg"].bitmap.height, Color.new(68,41,85))
    fp["bg"].opacity = 0
    for i in 0...36
      fp["#{i}"] = Sprite.new(@viewport)
      fp["#{i}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/eb246_2")
      fp["#{i}"].src_rect.set(44*rand(4),0,44,44)
      fp["#{i}"].ox = fp["#{i}"].bitmap.width/8
      fp["#{i}"].oy = fp["#{i}"].bitmap.height/2
      fp["#{i}"].opacity = 0
      fp["#{i}"].z = (@targetIsPlayer ? 29 : 19)
      rndx.push(rand(8))
      rndy.push(rand(8))
    end
    pbSEPlay("Anim/Psych Up")
    @sprites["battlebg"].defocus
    for i in 0...128
      pbSEPlay("Anim/Psych Up", 75) if i%24==0 && i < 100
      cx, cy = @targetSprite.getCenter(true)
      ax, ay = @userSprite.getAnchor
      for j in 0...36
        if fp["#{j}"].opacity == 0 && fp["#{j}"].tone.gray == 0
          fp["#{j}"].zoom_x = @userSprite.zoom_x
          fp["#{j}"].zoom_y = @userSprite.zoom_y
          fp["#{j}"].x = ax
          fp["#{j}"].y = ay
        end
        next if j>(i/2)
        x2 = cx - 4*@targetSprite.zoom_x + rndx[j]*@targetSprite.zoom_x
        y2 = cy - 4*@targetSprite.zoom_y + rndy[j]*@targetSprite.zoom_y
        x0 = fp["#{j}"].x
        y0 = fp["#{j}"].y
        fp["#{j}"].x += (x2 - x0)*0.1
        fp["#{j}"].y += (y2 - y0)*0.1
        fp["#{j}"].zoom_x -= (fp["#{j}"].zoom_x - @targetSprite.zoom_x)*0.1
        fp["#{j}"].zoom_y -= (fp["#{j}"].zoom_y - @targetSprite.zoom_y)*0.1
        fp["#{j}"].angle += 2
        if (x2 - x0)*0.1 < 1 && (y2 - y0)*0.1 < 1
          fp["#{j}"].opacity -= 8
          fp["#{j}"].tone.gray += 8
          fp["#{j}"].angle += 2
        else
          fp["#{j}"].opacity += 12
        end
      end
      if i >= 96
        fp["bg"].opacity -= 10
      else
        fp["bg"].opacity += 5 if fp["bg"].opacity < 255*0.7
      end
      pbSEPlay("Anim/NightShade") if i == 90
      if i >= 72
        if i >= 96
          @targetSprite.tone.red -= 4.8/2
          @targetSprite.tone.green -= 4.8/2
          @targetSprite.tone.blue -= 4.8/2
        else
          @targetSprite.tone.red += 4.8 if @targetSprite.tone.red < 96
          @targetSprite.tone.green += 4.8 if @targetSprite.tone.green < 96
          @targetSprite.tone.blue += 4.8 if @targetSprite.tone.blue < 96
        end
        @targetSprite.still
      end
      @vector.set(vector) if i == 24
      @vector.inc = 0.1 if i == 24
      @scene.wait(1,true)
    end
    @sprites["battlebg"].focus
    @targetSprite.ox = @targetSprite.bitmap.width/2
    @targetSprite.tone = Tone.new(0,0,0,0)
    @vector.reset if !@multiHit
    @vector.inc = 0.2
    pbDisposeSpriteHash(fp)
  rescue => e
    EliteBattle.log.warn("\r\nCONFUSERAY rescue fix caught: #{e.message}\r\n")
  ensure
    pbDisposeSpriteHash(fp)
    @sprites["battlebg"].focus rescue nil
    @targetSprite.tone = Tone.new(0,0,0,0) rescue nil if @targetSprite && !pbDisposed?(@targetSprite)
    @vector.inc = 0.2 rescue nil
  end
end

# Fix: player-side databox overlaps the YES/NO command window that appears
# when the rival is about to send in a new Pokémon ("Will you switch?").
# The command window is anchored to the top-right of the screen, exactly
# where EBDX places the player's databox (index 0).
# We temporarily hide player-side databoxes for the duration of any
# pbDisplayConfirmMessage call and restore them afterward.
class PokeBattle_SceneEBDX
  alias _uifix_pbDisplayConfirmMessage pbDisplayConfirmMessage
  def pbDisplayConfirmMessage(msg)
    # Collect player-side databoxes that are currently visible
    hidden = []
    @battlers.each_with_index do |b, i|
      next if !b || i.odd?   # even indices = player side
      spr = @sprites["dataBox_#{i}"]
      next unless spr && !pbDisposed?(spr) && spr.visible
      spr.visible = false
      hidden << i
    end

    result = _uifix_pbDisplayConfirmMessage(msg)

    # Restore only the ones we hid
    hidden.each do |i|
      spr = @sprites["dataBox_#{i}"]
      spr.visible = true if spr && !pbDisposed?(spr)
    end

    result
  end
end

#==============================================================================
# EBDX DataBox: Type Display Support
# Mirrors the type display feature (Trapstarr's) from PokemonDataBox to EBDX.
# Only active when $PokemonSystem.typedisplay != 0 and for the enemy side.
#==============================================================================
if defined?(DataBoxEBDX)
  class DataBoxEBDX
    EBDX_TYPE_DISPLAY_BITMAPS = {
      1 => "Graphics/Pictures/TypeIcons_Lolpy1",
      2 => "Graphics/Pictures/TypeIcons_TCG",
      3 => "Graphics/Pictures/TypeIcons_Square",
      4 => "Graphics/Pictures/TypeIcons_FairyGodmother",
      5 => "Graphics/Pictures/types_display"
    }

    alias _td_setUp setUp
    def setUp
      # Dispose any existing type display resources before setUp clears @sprites
      @typeDisplayBitmap&.dispose
      @typeDisplayBitmap = nil
      @typeDisplaySprite&.dispose rescue nil
      @typeDisplaySprite = nil
      _td_setUp
      return if @playerpoke || $PokemonSystem.typedisplay.to_i == 0
      path = EBDX_TYPE_DISPLAY_BITMAPS[$PokemonSystem.typedisplay]
      return unless path
      @typeDisplayBitmap = AnimatedBitmap.new(path)
      # Keep this sprite OUTSIDE @sprites so EBDX's x=/y= setters (which call .ex/.ey)
      # never iterate over it — plain Sprite doesn't have those EBDX extension attributes.
      @typeDisplaySprite = Sprite.new(@viewport)
      @typeDisplaySprite.bitmap = Bitmap.new(Graphics.width, Graphics.height)
      @typeDisplaySprite.z = 10000
    end

    alias _td_dispose dispose
    def dispose
      @typeDisplayBitmap&.dispose
      @typeDisplayBitmap = nil
      @typeDisplaySprite&.dispose rescue nil
      @typeDisplaySprite = nil
      _td_dispose
    end

    alias _td_refresh refresh
    def refresh
      _td_refresh
      return if self.disposed?
      ebdx_refreshTypeDisplay if !@playerpoke && $PokemonSystem.typedisplay.to_i > 0
    end

    alias _td_update update
    def update
      _td_update
      return if self.disposed? || !@loaded
      ebdx_refreshTypeDisplay if !@playerpoke && $PokemonSystem.typedisplay.to_i > 0
    end

    def ebdx_refreshTypeDisplay
      spr = @typeDisplaySprite
      return unless spr && !spr.disposed? && @typeDisplayBitmap
      spr.bitmap.clear
      return unless @battler&.pokemon && !@battler.fainted?

      type1 = @battler.pokemon.type1
      type2 = @battler.pokemon.type2
      t1n = GameData::Type.get(type1).id_number
      t2n = GameData::Type.get(type2).id_number

      case $PokemonSystem.typedisplay
      when 1, 2, 3, 4
        t1rect = Rect.new(0, t1n * 20, 24, 20)
        t2rect = Rect.new(0, t2n * 20, 24, 20)
        scale = 1.0
        icon_gap = 3
      when 5
        t1rect = Rect.new(0, t1n * 28, 64, 28)
        t2rect = Rect.new(0, t2n * 28, 64, 28)
        scale = 0.65
        icon_gap = 0
      end

      sw  = (t1rect.width  * scale).to_i
      sh  = ($PokemonSystem.typedisplay == 5 ? t1rect.height * scale * 1.2 : t1rect.height * scale).to_i
      base = @sprites["base"]
      return unless base && !base.disposed?

      # Position inside the right edge of the enemy EBDX databox.
      # We use base.x (absolute screen position) so the icons follow the slide-in.
      type_x = base.x + base.bitmap.width - sw + 24
      type_y = base.y - 14

      spr.bitmap.stretch_blt(Rect.new(type_x, type_y, sw, sh), @typeDisplayBitmap.bitmap, t1rect)
      unless type1 == type2
        spr.bitmap.stretch_blt(Rect.new(type_x, type_y + sh + icon_gap, sw, sh), @typeDisplayBitmap.bitmap, t2rect)
      end
    end
  end
end
