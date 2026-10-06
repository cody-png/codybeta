class PokemonBoxArrow < SpriteWrapper
  attr_accessor :cursormode

  alias _multiSelect_PokemonBoxArrow_initialize initialize

  def initialize(*args)
    _multiSelect_PokemonBoxArrow_initialize(*args)
    @cursormode = "default"
    @handsprite.addBitmap("point1m", "Graphics/Pictures/Storage/cursor_point_1_m")
    @handsprite.addBitmap("point2m", "Graphics/Pictures/Storage/cursor_point_2_m")
    @handsprite.addBitmap("grabm", "Graphics/Pictures/Storage/cursor_grab_m")
    @handsprite.addBitmap("fistm", "Graphics/Pictures/Storage/cursor_fist_m")
    @multiheldpkmn = []
  end

  alias _multiSelect_PokemonBoxArrow_dispose dispose

  def dispose
    _multiSelect_PokemonBoxArrow_dispose
    @multiheldpkmn.each { |pkmn| pkmn.dispose }
  end

  alias _multiSelect_PokemonBoxArrow_visible_eq visible=

  def visible=(value)
    _multiSelect_PokemonBoxArrow_visible_eq(value)
    multiHeldPokemon.each { |pkmn| pkmn.visible = value }
  end

  alias _multiSelect_PokemonBoxArrow_color_eq color=

  def color=(value)
    _multiSelect_PokemonBoxArrow_color_eq(value)
    multiHeldPokemon.each { |pkmn| pkmn.color = value }
  end

  alias _multiSelect_PokemonBoxArrow_x_eq x=

  def x=(value)
    _multiSelect_PokemonBoxArrow_x_eq(value)
    multiHeldPokemon.each { |pkmn| pkmn.x = self.x + (pkmn.heldox * 48) } if holdingMulti?
  end

  alias _multiSelect_PokemonBoxArrow_y_eq y=

  def y=(value)
    _multiSelect_PokemonBoxArrow_y_eq(value)
    multiHeldPokemon.each { |pkmn| pkmn.y = self.y + 16 + (pkmn.heldoy * 48) } if holdingMulti?
  end

  def setSprite(sprite)
    if holdingSingle?
      @heldpkmn = sprite
      @heldpkmn.viewport = self.viewport if @heldpkmn
      @heldpkmn.z = 1 if @heldpkmn
      @holding = false if !@heldpkmn && @multiheldpkmn.length == 0
      self.z = 2
    end
  end

  def setSprites(sprites)
    if holdingMulti?
      @multiheldpkmn = sprites
      for pkmn in @multiheldpkmn
        pkmn.viewport = self.viewport
        pkmn.z = 1
      end
      @holding = false if !@heldpkmn && @multiheldpkmn.length == 0
      self.z = 2
    end
  end

  alias _multiSelect_PokemonBoxArrow_deleteSprite deleteSprite

  def deleteSprite
    _multiSelect_PokemonBoxArrow_deleteSprite
    @multiheldpkmn.each { |pkmn| pkmn.dispose }
    @multiheldpkmn = []
  end

  def grabImmediate(sprite)
    @grabbingState = 0
    @holding = true
    @heldpkmn = sprite
    @heldpkmn.viewport = self.viewport
    @heldpkmn.z = 1
    self.z = 2

    self.x = @spriteX
    self.y = @spriteY
  end

  def holdingMulti?
    return @multiheldpkmn.length > 0 && @holding
  end

  def heldPokemon
    @heldpkmn = nil if @heldpkmn && @heldpkmn.disposed?
    @holding = false if !@heldpkmn && @multiheldpkmn.length == 0
    return @heldpkmn
  end

  def getModeSprites
    case @cursormode
    when "quickswap"
      return ["point1q", "point2q", "grabq", "fistq"]
    when "multiselect"
      return ["point1m", "point2m", "grabm", "fistm"]
    else
      return ["point1", "point2", "grab", "fist"]
    end
  end

  def update
    @updating = true
    super
    heldpkmn = heldPokemon
    heldpkmn.update if heldpkmn
    multiheldpkmn = multiHeldPokemon
    multiheldpkmn.each { |pkmn| pkmn.update }
    modeSprites = getModeSprites
    @handsprite.update
    @holding = false if !heldpkmn && multiheldpkmn.length == 0
    if @grabbingState > 0
      if @grabbingState <= 4 * Graphics.frame_rate / 20
        @handsprite.changeBitmap(modeSprites[2]) # grab
        self.y = @spriteY + 4.0 * @grabbingState * 20 / Graphics.frame_rate
        @grabbingState += 1
      elsif @grabbingState <= 8 * Graphics.frame_rate / 20
        @holding = true
        @handsprite.changeBitmap(modeSprites[3]) # fist
        self.y = @spriteY + 4 * (8 * Graphics.frame_rate / 20 - @grabbingState) * 20 / Graphics.frame_rate
        @grabbingState += 1
      else
        @grabbingState = 0
      end
    elsif @placingState > 0
      if @placingState <= 4 * Graphics.frame_rate / 20
        @handsprite.changeBitmap(modeSprites[3]) # fist
        self.y = @spriteY + 4.0 * @placingState * 20 / Graphics.frame_rate
        @placingState += 1
      elsif @placingState <= 8 * Graphics.frame_rate / 20
        @holding = false
        @heldpkmn = nil
        @multiheldpkmn = []
        @handsprite.changeBitmap(modeSprites[2]) # grab
        self.y = @spriteY + 4 * (8 * Graphics.frame_rate / 20 - @placingState) * 20 / Graphics.frame_rate
        @placingState += 1
      else
        @placingState = 0
      end
    elsif holdingSingle? || holdingMulti?
      @handsprite.changeBitmap(modeSprites[3]) # fist
    else
      self.x = @spriteX
      self.y = @spriteY
      if @frame < Graphics.frame_rate / 2
        @handsprite.changeBitmap(modeSprites[0]) # point1
      else
        @handsprite.changeBitmap(modeSprites[1]) # point2
      end
    end
    @handsprite.changeBitmap(getSplicerIcon) if @fusing

    @frame += 1
    @frame = 0 if @frame >= Graphics.frame_rate
    @updating = false
  end

  def multiHeldPokemon
    @multiheldpkmn.delete_if { |pkmn| pkmn.disposed? }
    @holding = false if !@heldpkmn && @multiheldpkmn.length == 0
    return @multiheldpkmn
  end

  def holdingSingle?
    return self.heldPokemon && @holding
  end

  def grabMulti(sprites)
    @grabbingState = 1
    @multiheldpkmn = sprites
    for pkmn in @multiheldpkmn
      pkmn.viewport = self.viewport
      pkmn.z = 1
    end
    self.z = 2
  end

end