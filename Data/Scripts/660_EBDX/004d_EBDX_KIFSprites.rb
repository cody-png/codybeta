#===============================================================================
#  KIF-Compatible Sprite Wrappers for EBDX
#  These provide the EBDX interface while using KIF's native sprite system
#===============================================================================

#===============================================================================
#  KIF Pokemon Sprite wrapper for EBDX scene
#  Wraps PokemonBattlerSprite with additional EBDX-expected methods
#===============================================================================
class KIFPokemonSprite < PokemonBattlerSprite
  attr_accessor :shadow, :showshadow, :hidden, :fainted, :isShadow, :charged, :noshadow
  attr_accessor :status, :anim, :dynamax, :scale_y, :legacy_anim
  attr_reader :loaded, :isSub, :pulse
  attr_reader :pokemon, :species, :form

  def initialize(viewport, sideSize, index, battleAnimations, battle = nil)
    super(viewport, sideSize, index, battleAnimations)
    @battle = battle
    @loaded = false
    @hidden = false
    @fainted = false
    @isShadow = false
    @charged = false
    @showshadow = true
    @noshadow = false
    @status = 0
    @dynamax = false
    @scale_y = 1
    @legacy_anim = false
    @isSub = false
    @pulse = 8.0
    @anim = false
    @pokemon = nil
    @species = nil
    @form = 0
    @spriteVisible = false
    # Create shadow sprite
    @shadow = PokemonBattlerShadowSprite.new(viewport, sideSize, index) rescue nil
  end

  # Override setPokemonBitmap to also set @loaded and @pokemon
  def setPokemonBitmap(pkmn, back = false, species = nil)
    @pokemon = pkmn
    @species = species || (pkmn.species rescue nil)
    @form = pkmn.form rescue 0
    @isShadow = pkmn.shadowPokemon? rescue false
    # Call parent's setPokemonBitmap
    super(pkmn, back)
    # Mark as loaded
    @loaded = true
    @fainted = false
    @hidden = false
    # Force sprite visible after bitmap is set
    @spriteVisible = true
    self.visible = true
    # Update shadow if present
    if @shadow
      @shadow.setPokemonBitmap(pkmn) rescue nil
    end
  end

  # Provide actualBitmap for compatibility
  def actualBitmap
    return @_iconBitmap
  end

  # Reset particles (no-op for KIF sprites)
  def resetParticles
    @isShadow = false
    @charged = false
    @dynamax = false
  end

  # Still animation (no-op for KIF)
  def still
    # KIF sprites don't have animation frames to stop
  end

  # Get sprite dimensions for animations
  def height
    return self.bitmap ? self.bitmap.height : 128
  end

  def width
    return self.bitmap ? self.bitmap.width : 128
  end

  # Get center position
  def getCenter(zoom = true)
    z = zoom ? self.zoom_y : 1
    bmp = self.bitmap
    return [self.x, self.y] if !bmp
    x = self.x
    y = self.y - bmp.height * z / 2
    return x, y
  end

  # Get anchor position
  def getAnchor(zoom = true)
    return getCenter(zoom)
  end

  # Dispose including shadow
  def dispose
    @shadow.dispose if @shadow && !@shadow.disposed?
    super
  end

  # Format shadow (update shadow position/visibility)
  def formatShadow
    return if !@shadow
    @shadow.visible = self.visible && @showshadow && !@noshadow && !@fainted && !@hidden
  end

  # Override pbSetPosition to position sprites correctly for EBDX scene
  def pbSetPosition
    return if !@_iconBitmap
    pbSetOrigin

    # Use vanilla positioning - EBDX coordinate system is too complex
    # and requires the camera/vector system to calculate properly
    if (@index % 2) == 0
      # Player side - higher z
      self.z = 100 + @index
    else
      # Opponent side - slightly lower z but still above backdrop
      self.z = 90 + @index
    end

    # Set position using vanilla constants
    p = PokeBattle_SceneConstants.pbBattlerPosition(@index, @sideSize)
    @spriteX = p[0]
    @spriteY = p[1]

    # Apply metrics if available
    if @pkmn && @pkmn.respond_to?(:species_data)
      @pkmn.species_data.apply_metrics_to_sprite(self, @index) rescue nil
    end
  end

  # Update method - delegates to parent with additional shadow handling
  def update(frameCounter = 0)
    # Call parent's update (handles bitmap, position, visibility)
    super(frameCounter)

    # Update shadow
    @shadow.update if @shadow && @shadow.respond_to?(:update)
    formatShadow
  end
end

#===============================================================================
#  KIF Trainer Sprite wrapper for EBDX scene
#===============================================================================
class KIFTrainerSprite < Sprite
  attr_accessor :index, :trainer, :hidden
  attr_reader :loaded

  def initialize(viewport, trainer = nil)
    super(viewport)
    @trainer = trainer
    @loaded = false
    @hidden = false
    @index = -1
  end

  def setTrainerBitmap(trainer = nil)
    trainer = @trainer if trainer.nil?
    return if trainer.nil?

    @trainer = trainer

    # Get trainer front sprite
    trfile = GameData::TrainerType.front_sprite_filename(trainer.trainer_type)
    if trfile && pbResolveBitmap(trfile)
      self.bitmap = AnimatedBitmap.new(trfile).bitmap
      self.ox = self.bitmap.width / 2
      self.oy = self.bitmap.height
      @loaded = true
    end
  end

  def actualBitmap
    return self.bitmap
  end

  def getCenter(zoom = true)
    z = zoom ? self.zoom_y : 1
    return [self.x, self.y - self.bitmap.height * z / 2] if self.bitmap
    return [self.x, self.y]
  end

  def getAnchor(zoom = true)
    return getCenter(zoom)
  end
end
