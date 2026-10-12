#===============================================================================
#  EBDX Battler Sprite Compatibility Shim
#===============================================================================
#  Adds EBDX-expected accessors to KIF's PokemonBattlerSprite so that
#  EBDX scene animation code can work with KIF's native sprites.
#  This reopens the class (Ruby allows this without modifying the original file).
#===============================================================================

module EBDXBattlerSpriteCompat
  attr_accessor :hidden, :fainted, :showshadow, :charged, :noshadow
  attr_accessor :status, :anim, :scale_y
  attr_accessor :loaded, :isSub, :pulse, :shadow

  def selected
    return @ebdx_selected || false
  end

  def selected=(val)
    @ebdx_selected = val
  end

  # Compatibility method for EBDX animation code
  def totalFrames
    return 1
  end

  def play
    # No-op - KIF sprites don't animate frame-by-frame like EBDX
  end

  def setFrame(frame)
    # No-op
  end

  # EBDX expects this on pokemon sprites
  def setPokemonBitmap(pokemon, back = false)
    if self.respond_to?(:setPokemonBitmapFiles)
      self.setPokemonBitmapFiles(pokemon, back)
    end
  end unless method_defined?(:setPokemonBitmap)

  # Shadow sprite stub (EBDX manages shadows on the sprite itself)
  def shadow
    return @ebdx_shadow
  end

  def shadow=(val)
    @ebdx_shadow = val
  end

  def shadowUpdate
    # No-op - KIF handles shadows separately
  end

  def chargedUpdate
    # No-op
  end

  def energyUpdate
    # No-op
  end

  # Substitute handling
  def setSubstitute(pokemon, back = false)
    @isSub = true
  end

  def removeSubstitute
    @isSub = false
  end
end

# Include the compat module into PokemonBattlerSprite
if defined?(PokemonBattlerSprite)
  PokemonBattlerSprite.send(:include, EBDXBattlerSpriteCompat)
end

#===============================================================================
#  PokeBattle_Battler additions for EBDX (toggle-guarded)
#===============================================================================
class PokeBattle_Battler
  # Low HP check used by EBDX's low HP BGM system
  def lowHP?
    return false if !self.pokemon
    return self.hp <= (self.totalhp * 0.25).floor
  end unless method_defined?(:lowHP?)

  # Multi-hit move tracking for EBDX animations
  alias pbProcessMoveHit_ebdx660 pbProcessMoveHit unless method_defined?(:pbProcessMoveHit_ebdx660)
  def pbProcessMoveHit(*args)
    @thisMoveHits = 0 if !@thisMoveHits
    @thisMoveHits += 1
    return pbProcessMoveHit_ebdx660(*args)
  end
  attr_accessor :thisMoveHits
end
