#===============================================================================
#  KIF-adapted EBDX UI Widgets File
#  Combined from Elite Battle DX Battle UI scripts
#  Contains all standalone UI widget classes for EBDX battle system
#===============================================================================

#===============================================================================
#  Command Menu (Next Generation)
#  UI ovarhaul
#===============================================================================
class CommandWindowEBDX
  attr_accessor :index
  attr_accessor :overlay
  attr_accessor :backdrop
  attr_accessor :coolDown
  attr_reader :indexes
  #-----------------------------------------------------------------------------
  #  class inspector
  #-----------------------------------------------------------------------------
  def inspect
    str = self.to_s.chop
    str << format(' index: %s>', @index)
    return str
  end
  #-----------------------------------------------------------------------------
  #  constructor
  #-----------------------------------------------------------------------------
  def initialize(viewport = nil, battle = nil, scene = nil, safari = false)
    @viewport = viewport
    @battle = battle
    @scene = scene
    @safaribattle = safari
    @index = 0
    @oldindex = 0
    @coolDown = 0
    @over = false
    @path = "Graphics/EBDX/Pictures/UI/"
    @sprites = {}
    @indexes = []

    self.applyMetrics

    @btnCmd = pbBitmap(@path+@cmdImg)
    @btnEmp = pbBitmap(@path+@empImg)

    @sprites["sel"] = SpriteSheet.new(@viewport,4)
    @sprites["sel"].setBitmap(pbSelBitmap(@path+@selImg,Rect.new(0,0,92,38)))
    @sprites["sel"].speed = 4
    @sprites["sel"].ox = @sprites["sel"].src_rect.width/2
    @sprites["sel"].oy = @sprites["sel"].src_rect.height/2
    @sprites["sel"].z = 99
    @sprites["sel"].visible = false

    @sprites["bg"] = Sprite.new(@viewport)
    @sprites["bg"].create_rect(@viewport.width,40,Color.new(0,0,0,150))
    @sprites["bg"].bitmap = pbBitmap(@path+@barImg) if !@barImg.nil?
    @sprites["bg"].y = @viewport.height
    self.update
  end
  #-----------------------------------------------------------------------------
  #  PBS data
  #-----------------------------------------------------------------------------
  def applyMetrics
    # sets default values
    @cmdImg = "btnCmd"
    @empImg = "btnEmpty"
    @selImg = "cmdSel"
    @parImg = "partyLine"
    @barImg = nil
    # looks up next cached metrics first
    d1 = EliteBattle.get(:nextUI)
    d1 = d1[:COMMANDMENU] if !d1.nil? && d1.has_key?(:COMMANDMENU)
    # looks up globally defined settings
    d2 = EliteBattle.get_data(:COMMANDMENU, :Metrics, :METRICS)
    # looks up globally defined settings
    d7 = EliteBattle.get_map_data(:COMMANDMENU_METRICS)
    # look up trainer specific metrics
    d6 = @battle.opponent ? EliteBattle.get_trainer_data(@battle.opponent[0].trainer_type, :COMMANDMENU_METRICS, @battle.opponent[0]) : nil
    # looks up species specific metrics
    d5 = !@battle.opponent ? EliteBattle.get_data(@battle.battlers[1].species, :Species, :COMMANDMENU_METRICS, (@battle.battlers[1].form rescue 0)) : nil
    # proceeds with parameter definition if available
    for data in [d2, d7, d6, d5, d1]
      if !data.nil?
        # applies a set of predefined keys
        @cmdImg = data[:BUTTONGRAPHIC] if data.has_key?(:BUTTONGRAPHIC) && data[:BUTTONGRAPHIC].is_a?(String)
        @selImg = data[:SELECTORGRAPHIC] if data.has_key?(:SELECTORGRAPHIC) && data[:SELECTORGRAPHIC].is_a?(String)
        @barImg = data[:BARGRAPHIC] if data.has_key?(:BARGRAPHIC) && data[:BARGRAPHIC].is_a?(String)
        @parImg = data[:PARTYLINEGRAPHIC] if data.has_key?(:PARTYLINEGRAPHIC) && data[:PARTYLINEGRAPHIC].is_a?(String)
      end
    end
  end
  #-----------------------------------------------------------------------------
  #  re-draw command menu
  #-----------------------------------------------------------------------------
  def refreshCommands(index)
    poke = @battle.battlers[index]
    cmds = self.compileCommands(index)
    h = @btnCmd.height/5
    w = @btnCmd.width/2
    for i in 0...cmds.length
      @sprites["b#{i}"] = Sprite.new(@viewport)
      @sprites["b#{i}"].bitmap = Bitmap.new(@btnEmp.width*2,@btnEmp.height)
      @sprites["b#{i}"].src_rect.width /= 2
      @sprites["b#{i}"].ox = @sprites["b#{i}"].src_rect.width/2
      @sprites["b#{i}"].oy = @sprites["b#{i}"].src_rect.height/2
      pbSetSmallFont(@sprites["b#{i}"].bitmap)
      x = (@safaribattle || (poke.shadowPokemon? && poke.inHyperMode?) || i > 3) ? w : 0
      for j in 0...2
        @sprites["b#{i}"].bitmap.blt(j*@btnEmp.width,0,@btnEmp,@btnEmp.rect)
        @sprites["b#{i}"].bitmap.blt(j*@btnEmp.width+2,0,@btnCmd,Rect.new(x,h*i,w,h)) if j > 0
        c = (j > 0) ? @btnCmd.get_pixel(x+8,h*i+8).darken(0.6) : Color.new(51,51,51)
        pbDrawOutlineText(@sprites["b#{i}"].bitmap,@btnEmp.width*j,11,@btnEmp.width,h,cmds[i],Color.white,c,1)
      end
      @sprites["b#{i}"].x = (@viewport.width/(cmds.length + 1))*(i+1)
      @sprites["b#{i}"].y = @viewport.height - 36 + 80
    end
    @sprites["bg"].y = @viewport.height + 40
  end
  #-----------------------------------------------------------------------------
  #  compile command menu
  #-----------------------------------------------------------------------------
  def compileCommands(index)
    cmd = []
    @indexes = []
    poke = @battle.battlers[index]
    # returns indexes and commands for Safari Battles
    if @safaribattle
      @indexes = [0,1,2,3]
      return [_INTL("BALL"), _INTL("BAIT"), _INTL("ROCK"), _INTL("RUN")]
    end
    # looks up cached metrics
    d1 = EliteBattle.get(:nextUI)
    d1 = d1.has_key?(:BATTLE_COMMANDS) ? d1[:BATTLE_COMMANDS] : nil if !d1.nil?
    # looks up globally defined settings
    d1 = EliteBattle.get_data(:BATTLE_COMMANDS, :Metrics, :METRICS) if d1.nil?
    # array containing the default commands
    default = [_INTL("FIGHT"), _INTL("BAG"), _INTL("PARTY"), _INTL("RUN")]
    default.push(_INTL("DEBUG")) if $DEBUG && default.length == 4 && EliteBattle::SHOW_DEBUG_FEATURES
    for i in 0...default.length
      val = default[i]; val = _INTL("CALL") if default[i] == _INTL("RUN") && (poke.shadowPokemon? && poke.inHyperMode?)
      if !d1.nil?
        if d1.include?(default[i])
          @indexes.push(i); cmd.push(val)
        end
        next
      end
      cmd.push(val); @indexes.push(i)
    end
    return cmd
  end
  #-----------------------------------------------------------------------------
  #  visibility functions
  #-----------------------------------------------------------------------------
  def visible; end; def visible=(val); end
  def disposed?; end
  def dispose
    @btnCmd.dispose
    @btnEmp.dispose
    pbDisposeSpriteHash(@sprites)
  end
  def color; end; def color=(val); end
  def shiftMode=(val); end
  #-----------------------------------------------------------------------------
  #  show command menu animation
  #-----------------------------------------------------------------------------
  def show
    @sprites["sel"].visible = false
    @sprites["bg"].y -= @sprites["bg"].bitmap.height/4
    for i in 0...@indexes.length
      next if !@sprites["b#{i}"]
      @sprites["b#{i}"].y -= 10
    end
  end
  def showPlay
    8.times do
      self.show; @scene.wait(1, true)
    end
  end
  #-----------------------------------------------------------------------------
  #  hide command menu animation
  #-----------------------------------------------------------------------------
  def hide(skip = false)
    return if skip
    @sprites["sel"].visible = false
    @sprites["bg"].y += @sprites["bg"].bitmap.height/4
    for i in 0...@indexes.length
      next if !@sprites["b#{i}"]
      @sprites["b#{i}"].y += 10
    end
  end
  def hidePlay
    8.times do
      self.hide; @scene.wait(1, true)
    end
  end
  #-----------------------------------------------------------------------------
  #  update command menu
  #-----------------------------------------------------------------------------
  def update
    # animation for when the index changes
    for i in 0...@indexes.length
      next if !@sprites["b#{i}"]
      if i == @index
        @sprites["b#{i}"].src_rect.y = -4 if @sprites["b#{i}"].src_rect.x == 0
        @sprites["b#{i}"].src_rect.x = @sprites["b#{i}"].src_rect.width
      else
        @sprites["b#{i}"].src_rect.x = 0
      end
      @sprites["b#{i}"].src_rect.y += 1 if @sprites["b#{i}"].src_rect.y < 0
    end
    return if !@sprites["b#{@index}"]
    @sprites["sel"].visible = true
    @sprites["sel"].x = @sprites["b#{@index}"].x
    @sprites["sel"].y = @sprites["b#{@index}"].y - 2
    @sprites["sel"].update
  end
  #-----------------------------------------------------------------------------
end

#===============================================================================
#  Fight Menu (Next Generation)
#  UI ovarhaul
#===============================================================================
class FightWindowEBDX
  attr_accessor :index
  attr_accessor :battler
  attr_accessor :refreshpos
  attr_reader :nummoves
  #-----------------------------------------------------------------------------
  #  class inspector
  #-----------------------------------------------------------------------------
  def inspect
    str = self.to_s.chop
    str << format(' index: %s>', @index)
    return str
  end
  #-----------------------------------------------------------------------------
  #  constructor
  #-----------------------------------------------------------------------------
  def initialize(viewport = nil, battle = nil, scene = nil)
    @viewport = viewport
    @battle = battle
    @scene = scene
    @index = 0
    @oldindex = -1
    @over = false
    @refreshpos = false
    @battler = nil
    @nummoves = 0

    @opponent = nil
    @player = nil
    @opponent = @battle.battlers[1] if !@battle.doublebattle?
    @player = @battle.battlers[0] if !@battle.doublebattle?

    @path = "Graphics/EBDX/Pictures/UI/"
    self.applyMetrics

    @buttonBitmap = pbBitmap(@path + @cmdImg)
    @typeBitmap = pbBitmap(@path + @typImg)
    @catBitmap = pbBitmap(@path + @catImg)

    @background = Sprite.new(@viewport)
    @background.create_rect(@viewport.width,64,Color.new(0,0,0,150))
    @background.bitmap = pbBitmap(@path + @barImg) if !@barImg.nil?
    @background.y = Graphics.height - @background.bitmap.height
    @background.z = 100

    @megaButton = Sprite.new(@viewport)
    @megaButton.bitmap = pbBitmap(@path + @megaImg)
    @megaButton.z = 101
    @megaButton.src_rect.width /= 2
    @megaButton.center!
    @megaButton.x = 30
    @megaButton.y = @viewport.height - @background.bitmap.height/2 + 100

    @sel = SpriteSheet.new(@viewport,4)
    @sel.setBitmap(pbSelBitmap(@path + @selImg,Rect.new(0,0,192,68)))
    @sel.speed = 4
    @sel.ox = @sel.src_rect.width/2
    @sel.oy = @sel.src_rect.height/2
    @sel.z = 199
    @sel.visible = false

    @button = {}
    @moved = false
    @showMega = false
    @megaActive = false

    eff = [_INTL("Normal damage"),_INTL("Not very effective"),_INTL("Super effective"),_INTL("No effect")]
    @typeInd = Sprite.new(@viewport)
    @typeInd.bitmap = Bitmap.new(192,24*4)
    pbSetSmallFont(@typeInd.bitmap)
    for i in 0...4
      pbDrawOutlineText(@typeInd.bitmap,0,24*i + 5,192,24,eff[i],Color.white,Color.black,1)
    end
    @typeInd.src_rect.set(0,0,192,24)
    @typeInd.ox = 192/2
    @typeInd.oy = 16
    @typeInd.z = 103
    @typeInd.visible = false

  end
  #-----------------------------------------------------------------------------
  #  PBS metadata
  #-----------------------------------------------------------------------------
  def applyMetrics
    # sets default values
    @cmdImg = "moveSelButtons"
    @selImg = "cmdSel"
    @typImg = "types"
    @catImg = "category"
    @megaImg = "megaButton"
    @barImg = nil
    @showTypeAdvantage = false
    # looks up next cached metrics first
    d1 = EliteBattle.get(:nextUI)
    d1 = d1[:FIGHTMENU] if !d1.nil? && d1.has_key?(:FIGHTMENU)
    # looks up globally defined settings
    d2 = EliteBattle.get_data(:FIGHTMENU, :Metrics, :METRICS)
    # looks up globally defined settings
    d7 = EliteBattle.get_map_data(:FIGHTMENU_METRICS)
    # look up trainer specific metrics
    d6 = @battle.opponent ? EliteBattle.get_trainer_data(@battle.opponent[0].trainer_type, :FIGHTMENU_METRICS, @battle.opponent[0]) : nil
    # looks up species specific metrics
    d5 = !@battle.opponent ? EliteBattle.get_data(@battle.battlers[1].species, :Species, :FIGHTMENU_METRICS, (@battle.battlers[1].form rescue 0)) : nil
    # proceeds with parameter definition if available
    for data in [d2, d7, d6, d5, d1]
      if !data.nil?
        # applies a set of predefined keys
        @megaImg = data[:MEGABUTTONGRAPHIC] if data.has_key?(:MEGABUTTONGRAPHIC) && data[:MEGABUTTONGRAPHIC].is_a?(String)
        @cmdImg = data[:BUTTONGRAPHIC] if data.has_key?(:BUTTONGRAPHIC) && data[:BUTTONGRAPHIC].is_a?(String)
        @selImg = data[:SELECTORGRAPHIC] if data.has_key?(:SELECTORGRAPHIC) && data[:SELECTORGRAPHIC].is_a?(String)
        @barImg = data[:BARGRAPHIC] if data.has_key?(:BARGRAPHIC) && data[:BARGRAPHIC].is_a?(String)
        @typImg = data[:TYPEGRAPHIC] if data.has_key?(:TYPEGRAPHIC) && data[:TYPEGRAPHIC].is_a?(String)
        @catImg = data[:CATEGORYGRAPHIC] if data.has_key?(:CATEGORYGRAPHIC) && data[:CATEGORYGRAPHIC].is_a?(String)
        @showTypeAdvantage = data[:SHOWTYPEADVANTAGE] if data.has_key?(:SHOWTYPEADVANTAGE)
      end
    end
  end
  #-----------------------------------------------------------------------------
  #  render move info buttons
  #-----------------------------------------------------------------------------
  def generateButtons
    @moves = @battler.moves
    @nummoves = 0
    @oldindex = -1
    @x = []; @y = []
    for i in 0...4
      @button["#{i}"].dispose if @button["#{i}"]
      @nummoves += 1 if @moves[i] && @moves[i].id
      @x.push(@viewport.width/2 + (i%2==0 ? -1 : 1)*(@viewport.width/2 + 99))
      @y.push(@viewport.height - 90 + (i/2)*44)
    end
    for i in 0...4
      @y[i] += 22 if @nummoves < 3
    end
    @button = {}
    for i in 0...@nummoves
      # get numeric values of required variables
      movedata = GameData::Move.get(@moves[i].id)
      category = movedata.physical? ? 0 : (movedata.special? ? 1 : 2)
      type = GameData::Type.get(movedata.type).id_number
      # create sprite
      @button["#{i}"] = Sprite.new(@viewport)
      @button["#{i}"].param = category
      @button["#{i}"].z = 102
      @button["#{i}"].bitmap = Bitmap.new(198*2, 74)
      @button["#{i}"].bitmap.blt(0, 0, @buttonBitmap, Rect.new(0, type*74, 198, 74))
      @button["#{i}"].bitmap.blt(198, 0, @buttonBitmap, Rect.new(198, type*74, 198, 74))
      @button["#{i}"].bitmap.blt(65, 46, @catBitmap, Rect.new(0, category*22, 38, 22))
      @button["#{i}"].bitmap.blt(3, 46, @typeBitmap, Rect.new(0, type*22, 72, 22))
      baseColor = @buttonBitmap.get_pixel(5, 32 + (type*74)).darken(0.4)
      pbSetSmallFont(@button["#{i}"].bitmap)
      pbDrawOutlineText(@button["#{i}"].bitmap, 198, 10, 196, 42,"#{movedata.real_name}", Color.white, baseColor, 1)
      pp = "#{@moves[i].pp}/#{@moves[i].total_pp}"
      pbDrawOutlineText(@button["#{i}"].bitmap, 0, 48, 191, 26, pp, Color.white, baseColor, 2)
      pbSetSystemFont(@button["#{i}"].bitmap)
      text = [[movedata.real_name, 99, 4, 2, baseColor, Color.new(0, 0, 0, 24)]]
      pbDrawTextPositions(@button["#{i}"].bitmap, text)
      @button["#{i}"].src_rect.set(198, 0, 198, 74)
      @button["#{i}"].ox = @button["#{i}"].src_rect.width/2
      @button["#{i}"].x = @x[i]
      @button["#{i}"].y = @y[i]
    end
  end
  #-----------------------------------------------------------------------------
  #  unused
  #-----------------------------------------------------------------------------
  def formatBackdrop; end
  def shiftMode=(val); end
  #-----------------------------------------------------------------------------
  #  show fight menu animation
  #-----------------------------------------------------------------------------
  def show
    @sel.visible = false
    @typeInd.visible = false
    @background.y -= (@background.bitmap.height/8)
    for i in 0...@nummoves
      @button["#{i}"].x += ((i%2 == 0 ? 1 : -1)*@viewport.width/16)
    end
  end
  def showPlay
    @megaButton.src_rect.x = 0
    @megaActive = false
    @megaButton.tone = Tone.new(0, 0, 0)
    @megaButton.zoom_x = 1.0
    @megaButton.zoom_y = 1.0
    @background.y = @viewport.height
    # Reset button positions to their initial off-screen positions (@x values)
    # The show() animation will move them toward center
    for i in 0...@nummoves
      next unless @button["#{i}"] && @x && @x[i]
      @button["#{i}"].x = @x[i]
    end
    8.times do
      self.show; @scene.wait(1, true)
    end
  end
  #-----------------------------------------------------------------------------
  #  hide fight menu animation
  #-----------------------------------------------------------------------------
  def hide
    @sel.visible = false
    @typeInd.visible = false
    @background.y += (@background.bitmap.height/8)
    @megaButton.y += 12
    for i in 0...@nummoves
      @button["#{i}"].x -= ((i%2 == 0 ? 1 : -1)*@viewport.width/16)
    end
    @showMega = false
    @megaActive = false
    @megaButton.src_rect.x = 0
    @megaButton.tone = Tone.new(0, 0, 0)
    @megaButton.zoom_x = 1.0
    @megaButton.zoom_y = 1.0
  end
  def hidePlay
    8.times do
      self.hide; @scene.wait(1, true)
    end
    @megaButton.y = @viewport.height - @background.bitmap.height/2 + 100
  end
  #-----------------------------------------------------------------------------
  #  toggle mega button visibility
  #-----------------------------------------------------------------------------
  def megaButton
    @showMega = true
  end
  #-----------------------------------------------------------------------------
  #  trigger mega button
  #-----------------------------------------------------------------------------
  def megaButtonTrigger
    @megaButton.src_rect.x += @megaButton.src_rect.width
    @megaButton.src_rect.x = 0 if @megaButton.src_rect.x > @megaButton.src_rect.width
    @megaButton.src_rect.y = -4
    @megaActive = !@megaActive
    if @megaActive
      @megaButton.tone = Tone.new(60, 40, 80)   # bright pink-purple glow
      @megaButton.zoom_x = 1.15
      @megaButton.zoom_y = 1.15
    else
      @megaButton.tone = Tone.new(0, 0, 0)
      @megaButton.zoom_x = 1.0
      @megaButton.zoom_y = 1.0
    end
  end
  #-----------------------------------------------------------------------------
  #  update fight menu
  #-----------------------------------------------------------------------------
  def update
    @sel.visible = true
    if @showMega
      @megaButton.y -= 10 if @megaButton.y > @viewport.height - @background.bitmap.height/2
      @megaButton.src_rect.y += 1 if @megaButton.src_rect.y < 0
    end
    # Safety check - return early if buttons haven't been generated yet
    return if @button.nil? || @button.empty? || @button["#{@index}"].nil?
    if @oldindex != @index
      @button["#{@index}"].src_rect.y = -4 if @button["#{@index}"]
      if @showTypeAdvantage && !(@battle.doublebattle? || @battle.triplebattle?)
        move = @battler.moves[@index]
        @modifier = move.pbCalcTypeMod(move.type, @player, @opponent) if move
      end
      @oldindex = @index
    end
    for i in 0...@nummoves
      next unless @button["#{i}"]
      @button["#{i}"].src_rect.x = 198*(@index == i ? 0 : 1)
      @button["#{i}"].y = @y[i] if @y && @y[i]
      @button["#{i}"].src_rect.y += 1 if @button["#{i}"].src_rect.y < 0
      next if i != @index
      # Shift selected button up slightly for visual feedback
      # Simplified from EBDX's "column lift" effect to prevent buttons going out of bounds
      shiftAmount = (@nummoves < 3) ? 14 : 20
      @button["#{i}"].y = @y[i] - shiftAmount if @y && @y[i]
    end
    return unless @button["#{@index}"]
    @sel.x = @button["#{@index}"].x
    @sel.y = @button["#{@index}"].y + @button["#{@index}"].src_rect.height/2 - 1
    @sel.update
    if @showTypeAdvantage && !(@battle.doublebattle? || @battle.triplebattle?)
      @typeInd.visible = true
      @typeInd.y = @button["#{@index}"].y
      @typeInd.x = @button["#{@index}"].x
      eff = 0
      if @button["#{@index}"].param == 2 # status move
        eff = 4
      elsif @modifier == 0 # No effect
        eff = 3
      elsif @modifier < 8
        eff = 1   # "Not very effective"
      elsif @modifier > 8
        eff = 2   # "Super effective"
      end
      @typeInd.src_rect.y = 24 * eff
    end
  end
  #-----------------------------------------------------------------------------
  #  visibility functions
  #-----------------------------------------------------------------------------
  def dispose
    @buttonBitmap.dispose
    @catBitmap.dispose
    @typeBitmap.dispose
    @background.dispose
    @megaButton.dispose
    @typeInd.dispose
    pbDisposeSpriteHash(@button)
  end
  #-----------------------------------------------------------------------------
end

#===============================================================================
#  Battle Bag interface
#  UI ovarhaul
#===============================================================================
def pbIsMedicine?(item)
  return [1, 2, 6, 7].include?(GameData::Item.get(item).battle_use) && !GameData::Item.get(item).is_berry?
end

def pbIsBattleItem?(item)
  return [3, 5, 8, 9, 10].include?(GameData::Item.get(item).battle_use)
end
#===============================================================================
#  Main UI class
#===============================================================================
class BagWindowEBDX
  attr_reader :index, :ret, :finished
  attr_accessor :sprites
  #-----------------------------------------------------------------------------
  #  class inspector
  #-----------------------------------------------------------------------------
  def inspect
    str = self.to_s.chop
    str << format(' pocket: %s,', @index)
    str << format(' page: %s,', @page)
    str << format(' item: %s>', @item)
    return str
  end
  #-----------------------------------------------------------------------------
  #  hide bag UI and display scene message
  #-----------------------------------------------------------------------------
  def pbDisplayMessage(msg)
    self.visible = false
    @scene.pbDisplayMessage(msg)
    @scene.clearMessageWindow
    self.visible = true
  end
  def pbDisplay(msg); self.pbDisplayMessage(msg); end
  #-----------------------------------------------------------------------------
  #  configure PBS data for graphics
  #-----------------------------------------------------------------------------
  def applyMetrics
    # sets default values
    @cmdImg = "itemContainer"
    @lastImg = "last"
    @backImg = "back"
    @frameImg = "itemFrame"
    @selImg = "cmdSel"
    @shadeImg = "shade"
    @nameImg = "itemName"
    @confirmImg = "itemConfirm"
    @cancelImg = "itemCancel"
    @iconsImg = "pocketIcons"
    # looks up next cached metrics first
    d1 = EliteBattle.get(:nextUI)
    d1 = d1[:BAGMENU] if !d1.nil? && d1.has_key?(:BAGMENU)
    # looks up globally defined settings
    d2 = EliteBattle.get_data(:BAGMENU, :Metrics, :METRICS)
    # looks up globally defined settings
    d7 = EliteBattle.get_map_data(:BAGMENU_METRICS)
    # look up trainer specific metrics
    d6 = @battle.opponent ? EliteBattle.get_trainer_data(@battle.opponent[0].trainer_type, :BAGMENU_METRICS, @battle.opponent[0]) : nil
    # looks up species specific metrics
    d5 = !@battle.opponent ? EliteBattle.get_data(@battle.battlers[1].species, :Species, :BAGMENU_METRICS, (@battle.battlers[1].form rescue 0)) : nil
    # proceeds with parameter definition if available
    for data in [d2, d7, d6, d5, d1]
      if !data.nil?
        # applies a set of predefined keys
        @cmdImg = data[:POCKETBUTTONS] if data.has_key?(:POCKETBUTTONS) && data[:POCKETBUTTONS].is_a?(String)
        @lastImg = data[:LASTITEM] if data.has_key?(:LASTITEM) && data[:LASTITEM].is_a?(String)
        @backImg = data[:BACKBUTTON] if data.has_key?(:BACKBUTTON) && data[:BACKBUTTON].is_a?(String)
        @frameImg = data[:ITEMFRAME] if data.has_key?(:ITEMFRAME) && data[:ITEMFRAME].is_a?(String)
        @nameImg = data[:POCKETNAME] if data.has_key?(:POCKETNAME) && data[:POCKETNAME].is_a?(String)
        @confirmImg = data[:ITEMCONFIRM] if data.has_key?(:ITEMCONFIRM) && data[:ITEMCONFIRM].is_a?(String)
        @cancelImg = data[:ITEMCANCEL] if data.has_key?(:ITEMCANCEL) && data[:ITEMCANCEL].is_a?(String)
        @selImg = data[:SELECTORGRAPHIC] if data.has_key?(:SELECTORGRAPHIC) && data[:SELECTORGRAPHIC].is_a?(String)
        @shadeImg = data[:SHADE] if data.has_key?(:SHADE) && data[:SHADE].is_a?(String)
        @iconsImg = data[:POCKETICONS] if data.has_key?(:POCKETICONS) && data[:POCKETICONS].is_a?(String)
      end
    end
  end
  #-----------------------------------------------------------------------------
  #  construct Bag UI
  #-----------------------------------------------------------------------------
  def initialize(scene, viewport)
    # set up variables
    @scene = scene
    @battle = scene.battle
    $lastUsed = 0 if $lastUsed.nil?; @lastUsed = $lastUsed
    @index = 0; @oldindex = -1; @item = 0; @olditem = -1
    @finished = false
    @disposed = true
    @page = -1; @selPocket = 0
    @ret = nil; @path = "Graphics/EBDX/Pictures/Bag/"
    @baseColor = Color.new(96, 96, 96)
    @shadowColor = nil
    # configure viewport
    @viewport = Viewport.new(0, 0, viewport.width, viewport.height)
    @viewport.z = viewport.z + 5
    # load bitmaps for use
    self.applyMetrics
    # configure initial sprites
    @sprites = {}
    @items = {}
    @sprites["back"] = Sprite.new(viewport)
    @sprites["back"].stretch_screen(@path + @shadeImg)
    @sprites["back"].opacity = 0
    @sprites["back"].z = 99998
    # set up selector sprite
    @sprites["sel"] = SelectorSprite.new(@viewport, 4)
    @sprites["sel"].filename = @path + @selImg
    @sprites["sel"].z = 99999
    # item name sprite
    bmp = pbBitmap(@path + @nameImg)
    @sprites["name"] = Sprite.new(@viewport)
    @sprites["name"].bitmap = Bitmap.new(bmp.width*1.2, bmp.height)
    pbSetSystemFont(@sprites["name"].bitmap)
    @sprites["name"].x = -@sprites["name"].width - @sprites["name"].width%10
    @sprites["name"].y = @viewport.height - 56
    bmp.dispose
    # pocket bitmap
    pbmp = pbBitmap(@path + @cmdImg)
    ibmp = pbBitmap(@path + @iconsImg)
    # item pocket buttons
    for i in 0...4
      @sprites["pocket#{i}"] = Sprite.new(@viewport)
      @sprites["pocket#{i}"].bitmap = Bitmap.new(pbmp.width, pbmp.height/4)
      @sprites["pocket#{i}"].bitmap.blt(0, 0, pbmp, Rect.new(0, (pbmp.height/4)*i, pbmp.width, pbmp.height/4))
      @sprites["pocket#{i}"].bitmap.blt((pbmp.width - ibmp.width)/2, (pbmp.height/4 - ibmp.height/4)/2, ibmp, Rect.new(0, (ibmp.height/4)*i, ibmp.width, ibmp.height/4))
      @sprites["pocket#{i}"].center!
      @sprites["pocket#{i}"].x = ((i%2)*2 + 1)*@viewport.width/4 + ((i%2 == 0) ? -1 : 1)*(@viewport.width/2 - 8)
      @sprites["pocket#{i}"].y = ((i/2)*2 + 2)*@viewport.height/8 + (i%2)*42
    end
    pbmp.dispose
    ibmp.dispose
    # last used item sprite
    @sprites["pocket4"] = Sprite.new(@viewport)
    bmp = pbBitmap(@path + @lastImg)
    @sprites["pocket4"].bitmap = Bitmap.new(bmp.width, bmp.height/2)
    pbSetSystemFont(@sprites["pocket4"].bitmap)
    @sprites["pocket4"].x = 24
    @sprites["pocket4"].ey = @viewport.height - 62
    @sprites["pocket4"].y = @sprites["pocket4"].ey + 80
    bmp.dispose
    self.refresh(true)
    # back button sprite
    @sprites["pocket5"] = Sprite.new(@viewport)
    @sprites["pocket5"].bitmap = pbBitmap(@path + @backImg)
    @sprites["pocket5"].x = @viewport.width - @sprites["pocket5"].width - 16
    @sprites["pocket5"].ey = @viewport.height - 60
    @sprites["pocket5"].y = @sprites["pocket4"].ey + 80
    @sprites["pocket5"].z = 5
    # confirmation buttons
    @sprites["confirm"] = Sprite.new(@viewport)
    bmp = pbBitmap(@path + @confirmImg)
    @sprites["confirm"].bitmap = Bitmap.new(bmp.width, bmp.height)
    pbSetSmallFont(@sprites["confirm"].bitmap); bmp.dispose
    @sprites["confirm"].center!
    @sprites["confirm"].x = @viewport.width/2 - @viewport.width + @viewport.width%8
    @sprites["cancel"] = Sprite.new(@viewport)
    @sprites["cancel"].bitmap = pbBitmap(@path + @cancelImg)
    @sprites["cancel"].center!
    @sprites["cancel"].x = @viewport.width/2 - @viewport.width + @viewport.width%8
    # calculate y values for the confirm/cancel buttons
    maxh = @sprites["confirm"].height + @sprites["cancel"].height + 8
    @sprites["confirm"].y = (@viewport.height - maxh)/2 + @sprites["confirm"].oy
    @sprites["cancel"].y = (@viewport.height - maxh)/2 + maxh - @sprites["cancel"].oy
    # initial target
    @sprites["sel"].target(@sprites["pocket#{@oldindex}"])
  end
  #-----------------------------------------------------------------------------
  #  dispose of the current UI
  #-----------------------------------------------------------------------------
  def dispose
    keys = ["back", "sel", "name", "confirm", "cancel"]
    for i in 0..5
      keys.push("pocket#{i}")
    end
    for key in keys
      @sprites[key].dispose
    end
    pbDisposeSpriteHash(@items)
    @disposed = true
  end
  def disposed?; return @disposed; end
  #-----------------------------------------------------------------------------
  #  merge required pockets
  #-----------------------------------------------------------------------------
  def checkPockets
    @mergedPockets = []
    for i in 0...$PokemonBag.pockets.length
      @mergedPockets += $PokemonBag.pockets[i]
    end
  end
  #-----------------------------------------------------------------------------
  #  draw content of selected pocket
  #-----------------------------------------------------------------------------
  def drawPocket(pocket, index)
    @pocket = []
    @pgtrigger = false
    # get a list of all the items
    self.checkPockets
    for item in @mergedPockets
      next if item.nil?
      next if !(ItemHandlers.hasUseInBattle(item[0]) || ItemHandlers.hasBattleUseOnPokemon(item[0]) || ItemHandlers.hasBattleUseOnBattler(item[0]))
      case index
      when 0 # Medicine
        @pocket.push([item[0], item[1]]) if pbIsMedicine?(item[0])
      when 1 # Pokeballs
        @pocket.push([item[0], item[1]]) if GameData::Item.get(item[0]).is_poke_ball?
      when 2 # Berries
        @pocket.push([item[0], item[1]]) if GameData::Item.get(item[0]).is_berry?
      when 3 # Battle Items
        @pocket.push([item[0], item[1]]) if pbIsBattleItem?(item[0])
      end
    end
    # show message if pocket is empty
    if @pocket.length < 1
      pbDisplayMessage(_INTL("You have no usable items in this pocket."))
      return
    end
    # configure variables
    @xpos = []
    @pages = @pocket.length/6
    @pages += 1 if @pocket.length%6 > 0
    @page = 0; @item = 0; @olditem = 0
    @back = false
    @selPocket = pocket
    # dispose sprites if already existing
    pbDisposeSpriteHash(@items)
    @pname = Settings.bag_pocket_names[pocket]
    x = 0; y = 0
    # pocket bitmap
    pbmp = pbBitmap(@path + @cmdImg)
    ibmp = pbBitmap(@path + @frameImg)
    for i in 0...@pocket.length
      @items["#{i}"] = Sprite.new(@viewport)
      # create bitmap and draw all the required contents on it
      @items["#{i}"].bitmap = Bitmap.new(pbmp.width, pbmp.height/4)
      @items["#{i}"].bitmap.blt(0, 0, pbmp, Rect.new(0, (pbmp.height/4)*@index, pbmp.width, pbmp.height/4))
      @items["#{i}"].bitmap.blt((pbmp.width - ibmp.width)/2, (pbmp.height/4 - ibmp.height)/2, ibmp, ibmp.rect)
      pbSetSystemFont(@items["#{i}"].bitmap)
      icon = pbBitmap(GameData::Item.icon_filename(@pocket[i][0]))
      @items["#{i}"].bitmap.blt(pbmp.width - icon.width - (pbmp.width - ibmp.width)/2 - 4, (pbmp.height/4 - icon.height)/2, icon, icon.rect, 164); icon.dispose
      # draw texxt
      text = [
        ["#{GameData::Item.get(@pocket[i][0]).real_name}", pbmp.width/2 - 15, 2*pbmp.height/64 - 8, 2, @baseColor, Color.new(0, 0, 0, 32)],
        ["x#{@pocket[i][1]}", pbmp.width/2 - 12, 8*pbmp.height/64 - 14, 2, @baseColor, Color.new(0, 0, 0, 32)],
      ]
      pbDrawTextPositions(@items["#{i}"].bitmap, text)
      # center sprite
      @items["#{i}"].center!
      # position items
      @items["#{i}"].x = @viewport.width + (x%2 == 0 ? 1 : -1)*8 + (x*2 + 1)*@viewport.width/4 + (i/6)*@viewport.width
      @xpos.push(@items["#{i}"].x - @viewport.width)
      @items["#{i}"].y = (y + 1)*@viewport.height/5 + (y*12)
      @items["#{i}"].opacity = 255
      # increment the position count
      x += 1; y += 1 if x > 1
      x = 0 if x > 1
      y = 0 if y > 2
    end
    pbmp.dispose; ibmp.dispose
    self.name
    @sprites["name"].x = -@sprites["name"].width - @sprites["name"].width%10
  end
  #-----------------------------------------------------------------------------
  #  refresh bitmap contents of item name
  #-----------------------------------------------------------------------------
  def name
    @page = @item/6
    # clean bitmap
    bmp = pbBitmap(@path + @nameImg)
    bitmap = @sprites["name"].bitmap
    bitmap.clear
    bitmap.blt(0, 0, bmp, Rect.new(0,0,320,44))
    # draw text
    text = [
      [@pname, bmp.width/2, -5, 2, Color.white, nil],
      ["#{@page+1}/#{@pages}", bmp.width, -5, 0, Color.white, nil]
    ]
    pbDrawTextPositions(bitmap, text)
    bmp.dispose
  end
  #-----------------------------------------------------------------------------
  #  update item selection menu
  #-----------------------------------------------------------------------------
  def updatePocket
    @page = @item/6
    # animate position of item sprites
    for i in 0...@pocket.length
      @items["#{i}"].x -= (@items["#{i}"].x - (@xpos[i] - @page*@viewport.width))*0.2
      @items["#{i}"].src_rect.y += 1 if @items["#{i}"].src_rect.y < 0
    end
    @sprites["name"].x += @sprites["name"].width/10 if @sprites["name"].x < -24
    @sprites["pocket5"].src_rect.y += 1 if @sprites["pocket5"].src_rect.y < 0
    # process item selection
    if Input.trigger?(Input::LEFT) && !@back
      if ![0, 2, 4].include?(@item)
        @item -= (@item%2 == 0) ? 5 : 1
      else
        @item -= 1 if @item < 0
      end
      @item = 0 if @item < 0
    elsif Input.trigger?(Input::RIGHT) && !@back
      if @page < (@pocket.length)/6
        @item += (@item%2 == 1) ? 5 : 1
      else
        @item += 1 if @item < @pocket.length - 1
      end
      @item = @pocket.length - 1 if @item > @pocket.length - 1
    elsif Input.trigger?(Input::UP)
      if @back
        @item += 4 if (@item%6) < 2
        @back = false
      else
        @item -= 2
        if (@item%6) > 3
          @item += 6
          @back = true
        end
      end
      @item = 0 if @item < 0
      @item = @pocket.length-1 if @item > @pocket.length-1
      @sprites["pocket5"].src_rect.y -= 6 if @back
    elsif Input.trigger?(Input::DOWN)
      if @back
        @item -= 4 if (@item%6) > 3
        @back = false
      else
        @item += 2
        if (@item%6) < 2
          @item -= 6
          @back = true
        end
        @back = true if @item > @pocket.length - 1
      end
      @item = @pocket.length - 1 if @item > @pocket.length - 1
      @item = 0 if @item < 0
      @sprites["pocket5"].src_rect.y -= 6 if @back
    end
    # confirm or cancel input
    if (@back && Input.trigger?(Input::C)) || Input.trigger?(Input::B)
      pbSEPlay("EBDX/SE_Select3")
      @selPocket = 0
      @page = -1; @oldindex = -1
      @back = false; @doubleback = true
    end
    # refresh selected values if index has changed
    if @item != @olditem
      @olditem = @item
      pbSEPlay("EBDX/SE_Select1")
      @sprites["sel"].target(@back ? @sprites["pocket5"] : @items["#{@item}"])
      @items["#{@item}"].src_rect.y -= 6 if !@back
      self.name
    end
  end
  #-----------------------------------------------------------------------------
  #  close current UI level
  #-----------------------------------------------------------------------------
  def closeCurrent
    @selPocket = 0
    @page = -1
    @back = false
    @ret = nil
    self.refresh
  end
  #-----------------------------------------------------------------------------
  #  show bag UI
  #-----------------------------------------------------------------------------
  def show
    @ret = nil
    self.refresh
    for i in 0...6
      @sprites["pocket#{i}"].opacity = 255
    end
    @sprites["pocket4"].y = @sprites["pocket4"].ey + 80
    @sprites["pocket5"].y = @sprites["pocket5"].ey + 80
    pbSEPlay("EBDX/SE_Zoom4", 60)
    8.times do
      for i in 0...4
        @sprites["pocket#{i}"].x += ((i%2 == 0) ? 1 : -1)*@viewport.width/16
      end
      for i in 4...6
        @sprites["pocket#{i}"].y -= 10
      end
      @sprites["back"].opacity += 32
      @sprites["sel"]
      @scene.wait(1, true)
    end
  end
  #-----------------------------------------------------------------------------
  #  hide bag UI
  #-----------------------------------------------------------------------------
  def hide
    8.times do
      for i in 0...4
        @sprites["pocket#{i}"].x -= ((i%2 == 0) ? 1 : -1)*@viewport.width/16
      end
      for i in 4...6
        @sprites["pocket#{i}"].y += 10
      end
      if @pocket
        for i in 0...@pocket.length
          @items["#{i}"].opacity -= 25.5
        end
      end
      @sprites["name"].x -= 48 if @sprites["name"].x > -380
      @sprites["back"].opacity -= 32
      @sprites["sel"].update
      @scene.wait(1, true)
    end
  end
  #-----------------------------------------------------------------------------
  #  dig into menu to use item
  #-----------------------------------------------------------------------------
  def useItem?
    # to make sure duplicates are not registered at the beginning
    Input.update
    # render bitmap for item use confirmation
    bitmap = @sprites["confirm"].bitmap
    bitmap.clear; bmp = pbBitmap(@path + @confirmImg)
    bitmap.blt(0, 0, bmp, bmp.rect)
    icon = pbBitmap(GameData::Item.icon_filename(@ret))
    bitmap.blt(20, 30, icon, icon.rect)
    # draw text
    drawTextEx(bitmap, 80, 12, 364, 3, GameData::Item.get(@ret).description, @baseColor, Color.new(0, 0, 0, 32))
    # select confirm message as target
    @sprites["sel"].target(@sprites["confirm"])
    # animate in
    8.times do
      # slide panels into screen
      @sprites["confirm"].x += @viewport.width/8
      @sprites["cancel"].x += @viewport.width/8
      if @pocket
        # fade out panels
        for i in 0...@pocket.length
          @items["#{i}"].opacity -= 32
        end
      end
      for i in 0...4
        @sprites["pocket#{i}"].opacity -= 64 if @sprites["pocket#{i}"].opacity > 0
      end
      # animate bottom items moving off screen
      @sprites["pocket4"].y += 10 if @sprites["pocket4"].y < @sprites["pocket4"].ey + 80
      @sprites["pocket5"].y += 10 if @sprites["pocket5"].y < @sprites["pocket5"].ey + 80
      @sprites["name"].x -= @sprites["name"].width/8
      @sprites["sel"].update
      @scene.animateScene
      @scene.pbGraphicsUpdate
    end
    # ensure pocket name is off screen
    @sprites["name"].x = -@sprites["name"].width
    index = 0; oldindex = 0
    choice = (index == 0) ? "confirm" : "cancel"
    # start the main input loop
    loop do
      @sprites["#{choice}"].src_rect.y += 1 if @sprites["#{choice}"].src_rect.y < 0
      # process directional input
      if Input.trigger?(Input::UP)
        index -= 1
        index = 1 if index < 0
        choice = (index == 0) ? "confirm" : "cancel"
      elsif Input.trigger?(Input::DOWN)
        index += 1
        index = 0 if index > 1
        choice = (index == 0) ? "confirm" : "cancel"
      end
      # process change in index
      if index != oldindex
        oldindex = index
        pbSEPlay("EBDX/SE_Select1")
        @sprites["#{choice}"].src_rect.y -= 6
        @sprites["sel"].target(@sprites["#{choice}"])
      end
      # confirmation and cancellation input
      if Input.trigger?(Input::C)
        pbSEPlay("EBDX/SE_Select2")
        break
      elsif Input.trigger?(Input::B)
        @scene.pbPlayCancelSE()
        index = 1
        break
      end
      Input.update
      @sprites["sel"].update
      @scene.animateScene
      @scene.pbGraphicsUpdate
    end
    # animate exit
    8.times do
      @sprites["confirm"].x -= @viewport.width/8
      @sprites["cancel"].x -= @viewport.width/8
      @sprites["pocket5"].y -= 10 if index > 0
      @sprites["sel"].update
      @scene.animateScene
      @scene.pbGraphicsUpdate
    end
    # refresh old UI (swap cursor to target)
    self.refresh
    # return output
    if index > 0
      @ret = nil
      return false
    else
      @index = 0 if @index == 4 && (@lastUsed == 0 || GameData::Item.get(@lastUsed).id_number == 0)
      return true
    end
  end
  #-----------------------------------------------------------------------------
  #  refresh last item use
  #-----------------------------------------------------------------------------
  def refresh(skip = false)
    last = @lastUsed != 0 ? GameData::Item.get(@lastUsed).id_number : 0
    # format text
    i = last > 0 ? 1 : 0
    name = last > 0 ? GameData::Item.get(@lastUsed).real_name : ""
    text = ["", "#{name}"]
    # clean bitmap
    bmp = pbBitmap(@path + @lastImg)
    icon = pbBitmap(GameData::Item.icon_filename(last))
    bitmap = @sprites["pocket4"].bitmap
    bitmap.clear
    bitmap.blt(0, 0, bmp, Rect.new(0, i*bmp.height/2, bmp.width, bmp.height/2))
    bitmap.blt(28, (bmp.height/2 - icon.height)/2 - 2, icon, icon.rect) if last > 0
    icon.dispose
    # draw text
    dtext = [[text[i], bmp.width/2, 0, 2, @baseColor, Color.new(0, 0, 0, 32)]]
    pbDrawTextPositions(bitmap, dtext); bmp.dispose
    @sprites["sel"].target(@sprites["pocket#{@index}"]) unless skip
  end
  #-----------------------------------------------------------------------------
  #  main update function across all levels
  #-----------------------------------------------------------------------------
  def update
    # pocket selection page
    if @selPocket == 0
      self.updateMain
      for i in 0...4
        @sprites["pocket#{i}"].opacity += 51 if @sprites["pocket#{i}"].opacity < 255
      end
      @sprites["back"].opacity += 51 if @sprites["back"].opacity < 255
      @sprites["pocket4"].y -= 8 if @sprites["pocket4"].y > @sprites["pocket4"].ey
      @sprites["pocket5"].y -= 8 if @sprites["pocket5"].y > @sprites["pocket5"].ey
      if @pocket
        for i in 0...@pocket.length
          @items["#{i}"].opacity -= 51 if @items["#{i}"] && @items["#{i}"].opacity > 0
        end
      end
      @sprites["name"].x -= @sprites["name"].width/10 if @sprites["name"].x > -@sprites["name"].width
    # item selection page
    else
      if Input.trigger?(Input::C) && !@back
        self.intoPocket
      end
      self.updatePocket
      for i in 0...4
        @sprites["pocket#{i}"].opacity -= 51 if @sprites["pocket#{i}"].opacity > 0
      end
      @sprites["pocket4"].y += 8 if @sprites["pocket4"].y < (@sprites["pocket4"].ey + 80)
      for i in 0...@pocket.length
        @items["#{i}"].opacity += 51 if @items["#{i}"] && @items["#{i}"].opacity < 255
      end
    end
    # update selection sprite
    @sprites["sel"].update
  end
  #-----------------------------------------------------------------------------
  #  update function during item pocket selection
  #-----------------------------------------------------------------------------
  def updateMain
    last = @lastUsed != 0 ? GameData::Item.get(@lastUsed).id_number : 0
    # move the index around
    if Input.trigger?(Input::LEFT)
      @index -= 1
      @index += 2 if @index%2 == 1
      @index = 3 if @index == 4 && !(last > 0)
    elsif Input.trigger?(Input::RIGHT)
      @index += 1
      @index -= 2 if @index%2 == 0
      @index = 2 if @index == 4 && !(last > 0)
    elsif Input.trigger?(Input::UP)
      @index -= 2
      @index += 6 if @index < 0
      @index = 5 if @index == 4 && !(last > 0)
    elsif Input.trigger?(Input::DOWN)
      @index += 2
      @index -= 6 if @index > 5
      @index = 5 if @index == 4 && !(last > 0)
    end
    # play effects on index change
    if @oldindex != @index
      @oldindex = @index
      @sprites["sel"].target(@sprites["pocket#{@index}"])
      @sprites["pocket#{@index}"].src_rect.y -= 6
      pbSEPlay("EBDX/SE_Select1")
    end
    # slide buttons into original position after selector shift
    for i in 0...6
      @sprites["pocket#{i}"].src_rect.y += 1 if @sprites["pocket#{i}"].src_rect.y < 0
    end
    # set variables
    @doubleback = false
    @finished = false
    # check if confirm or cancel inputs are pressed
    if Input.trigger?(Input::C) && !@doubleback && @index < 5
      self.confirm
    elsif (Input.trigger?(Input::B) || (Input.trigger?(Input::C) && @index==5)) && @selPocket == 0 && !@doubleback
      self.finish
    end
  end
  #-----------------------------------------------------------------------------
  #  finish current bag processing
  #-----------------------------------------------------------------------------
  def finish
    pbSEPlay("EBDX/SE_Select3")
    @finished = true
    Input.update
  end
  #-----------------------------------------------------------------------------
  #  confirm current selection
  #-----------------------------------------------------------------------------
  def confirm
    pbSEPlay("EBDX/SE_Select2")
    if @index < 4
      cmd = [2, 3, 5, 7]
      cmd = [2, 1, 4, 5] if Settings.bag_pocket_names.length == 6
      self.drawPocket(cmd[@index], @index)
      @sprites["sel"].target(@back ? @sprites["pocket5"] : @items["#{@item}"])
    else
      @selPocket = 0
      @page = -1
      @ret = @lastUsed
      @lastUsed = 0 if !($PokemonBag.pbQuantity(@lastUsed) > 1)
    end
  end
  #-----------------------------------------------------------------------------
  #  open selected pocket
  #-----------------------------------------------------------------------------
  def intoPocket
    pbSEPlay("EBDX/SE_Select2")
    @selPocket = 0
    @page = -1
    @lastUsed = 0
    @lastUsed = @pocket[@item][0] if @pocket[@item][1] > 1
    $lastUsed = @lastUsed
    @ret = @pocket[@item][0]
  end
  #-----------------------------------------------------------------------------
  #  set visibility of UI
  #-----------------------------------------------------------------------------
  def visible=(val)
    for key in @sprites.keys
      next if key == "back"
      @sprites[key].visible = val
    end
  end
  #-----------------------------------------------------------------------------
  #  clear sel sprite
  #-----------------------------------------------------------------------------
  def clearSel
    @sprites["sel"].bitmap = Bitmap.new(2, 2)
  end
  #-----------------------------------------------------------------------------
end

#===============================================================================
#  Pokemon data battle boxes (Next Generation)
#  UI overhaul
#===============================================================================
class DataBoxEBDX  <  SpriteWrapper
  attr_reader :battler, :animatingHP, :animatingEXP, :expBarWidth, :hpBarWidth
  attr_accessor :selected, :appearing, :inposition
  #-----------------------------------------------------------------------------
  #  constructor
  #-----------------------------------------------------------------------------
  def initialize(battler, viewport = nil, player = nil, scene = nil)
    @viewport = viewport
    @scene = scene
    @battle = scene.battle
    @player = player
    @battler = battler
    @pokemon = @battler.displayPokemon
    @trainer = @battle.opponent ? @battle.opponent[0] : nil
    @doublebattle = @battle.doublebattle?
    @playerpoke = (@battler.index%2) == 0
    @sprites = {}
    @path = "Graphics/EBDX/Pictures/UI/"
    @showexp = @playerpoke && !@doublebattle
    @explevel = 0
    @selected = false
    @appearing = false
    @animatingHP = false
    @starthp = 0.0
    @currenthp = 0.0
    @endhp = 0.0
    @frame = 0
    @loaded = false
    @showing = false
    @hidden = false
    @inposition = false
    @temphide = false
  end
  #-----------------------------------------------------------------------------
  #  PBS metadata
  #-----------------------------------------------------------------------------
  def applyMetrics
    # default variable states
    @showhp = @playerpoke && !@doublebattle
    @expBarWidth = 100
    @hpBarWidth = 168
    @baseBitmap = "dataBox"
    @colors = "barColors"
    @containerBmp = "containers"
    @expandDouble = false
    @hpBarX = 4
    @hpBarY = 2
    @expBarX = 4
    @expBarY = 16
    # calc width in advance
    tbmp = pbBitmap(@path + @baseBitmap)
    # set XY positions
    @defX = @playerpoke ? @viewport.width - tbmp.width : 0
    @defY = @playerpoke ? @viewport.height - 130 : 52
    tbmp.dispose
    # compiles default positioning data for databox
    @data = {
      "status" => {:x => @playerpoke ? -26 : 202, :y => 16, :z => 1},
      "mega" => {:x => @playerpoke ? -10 : 206, :y => -18, :z => 1},
      "container" => {:x => @playerpoke ? 20 : 24, :y => 6, :z => 1},
      "name" => {:x => @playerpoke ? 22 : 26, :y => -24, :z => 9},
      "hp" => {:x => @playerpoke ? 22 : 20, :y => 9, :z => 9}
    }
    # determines which constant to search for
    const = @playerpoke ? :PLAYERDATABOX : :ENEMYDATABOX
    # looks up next cached metrics first
    d1 = EliteBattle.get(:nextUI)
    d2 = d1[const] if !d1.nil? && d1.has_key?(const)
    d3 = d1[:ALLDATABOX] if !d1.nil? && d1.has_key?(:ALLDATABOX)
    # looks up globally defined settings
    d4 = EliteBattle.get_data(const, :Metrics, :METRICS)
    d7 = EliteBattle.get_map_data(:DATABOX_METRICS)
    # look up trainer specific metrics
    d6 = @battle.opponent ? EliteBattle.get_trainer_data(@trainer.trainer_type, :DATABOX_METRICS, @trainer) : nil
    # looks up species specific metrics
    d5 = EliteBattle.get_data(@battler.species, :Species, :DATABOX_METRICS, (@battler.form rescue 0))
    # proceeds with parameter definition if available
    for data in [d4, d2, d3, d7, d6, d5, d1]
      if !data.nil?
        # applies a set of predefined keys
        @defX = data[:X] if data.has_key?(:X) && data[:X].is_a?(Numeric)
        @defY = data[:Y] if data.has_key?(:Y) && data[:Y].is_a?(Numeric)
        @showhp = data[:SHOWHP] if (!@doublebattle || (@doublebattle && !@playerpoke && @battle.pbParty(1).length < 2)) && data.has_key?(:SHOWHP)
        @expBarWidth = data[:EXPBARWIDTH] if data.has_key?(:EXPBARWIDTH) && data[:EXPBARWIDTH].is_a?(Numeric)
        @expBarX = data[:EXPBARX] if data.has_key?(:EXPBARX) && data[:EXPBARX].is_a?(Numeric)
        @expBarY = data[:EXPBARY] if data.has_key?(:EXPBARY) && data[:EXPBARY].is_a?(Numeric)
        @hpBarWidth = data[:HPBARWIDTH] if data.has_key?(:HPBARWIDTH) && data[:HPBARWIDTH].is_a?(Numeric)
        @hpBarX = data[:HPBARX] if data.has_key?(:HPBARX) && data[:HPBARX].is_a?(Numeric)
        @hpBarY = data[:HPBARY] if data.has_key?(:HPBARY) && data[:HPBARY].is_a?(Numeric)
        @baseBitmap = data[:BITMAP] if data.has_key?(:BITMAP) && data[:BITMAP].is_a?(String)
        @colors = data[:HPCOLORS] if data.has_key?(:HPCOLORS) && data[:HPCOLORS].is_a?(String)
        @containerBmp = data[:CONTAINER] if data.has_key?(:CONTAINER) && data[:CONTAINER].is_a?(String)
        # expand databox even in doubles
        @expandDouble = data[:EXPANDINDOUBLES] == true ? true : false if data.has_key?(:EXPANDINDOUBLES)
        @showexp = true if @expandDouble && @playerpoke && @battler.pbOwnedByPlayer?
        @showhp = true if @expandDouble && @playerpoke
        # applies a set of possible modifier keys
        for key in data.keys
          next if !key.is_a?(String) || !@data.has_key?(key) || !data[key].is_a?(Hash)
          for m in data[key].keys
            next if !@data[key].has_key?(m)
            @data[key][m] = data[key][m]
          end
        end
      end
    end
  end
  #-----------------------------------------------------------------------------
  #  get specific metric
  #-----------------------------------------------------------------------------
  def getMetric(key,value)
    return (@data.has_key?(key) && @data[key].has_key?(value)) ? @data[key][value] : 0
  end
  #-----------------------------------------------------------------------------
  #  check if databox is disposed
  #-----------------------------------------------------------------------------
  def disposed?
    return @sprites["base"].disposed? if @sprites["base"]
    return true
  end
  #-----------------------------------------------------------------------------
  #  dispose databox
  #-----------------------------------------------------------------------------
  def dispose
    pbDisposeSpriteHash(@sprites)
  end
  #-----------------------------------------------------------------------------
  #  refresh EXP amount
  #-----------------------------------------------------------------------------
  def refreshExpLevel
    if !@battler.pokemon
      @explevel = 0
    else
      growthrate = @battler.pokemon.growth_rate
      startexp = GameData::GrowthRate.get(growthrate).minimum_exp_for_level(@battler.pokemon.level)
      endexp = GameData::GrowthRate.get(growthrate).minimum_exp_for_level(@battler.pokemon.level + 1)
      if startexp == endexp
        @explevel = 0
      else
        @explevel = (@battler.pokemon.exp-startexp)*@expBarWidth/(endexp-startexp)
      end
    end
  end
  #-----------------------------------------------------------------------------
  #  get current EXP
  #-----------------------------------------------------------------------------
  def exp
    return @animatingEXP ? @currentexp : @explevel
  end
  #-----------------------------------------------------------------------------
  #  get current HP
  #-----------------------------------------------------------------------------
  def hp
    return @animatingHP ? @currenthp : @battler.hp
  end
  #-----------------------------------------------------------------------------
  #  animate HP
  #-----------------------------------------------------------------------------
  def animateHP(oldhp, newhp)
    @starthp = oldhp.to_f
    @currenthp = oldhp.to_f
    @endhp = newhp.to_f
    @animatingHP = true
  end
  #-----------------------------------------------------------------------------
  #  animate EXP
  #-----------------------------------------------------------------------------
  def animateEXP(oldexp, newexp)
    @currentexp = oldexp
    @endexp = newexp
    @animatingEXP = true
  end
  #-----------------------------------------------------------------------------
  #  check if databox is showing
  #-----------------------------------------------------------------------------
  def show; @showing = false; end
  #-----------------------------------------------------------------------------
  #  apply damage tint
  #-----------------------------------------------------------------------------
  def damage
    @sprites["base"].color = Color.new(221, 82, 71)
  end
  #-----------------------------------------------------------------------------
  #  draw databox elements
  #-----------------------------------------------------------------------------
  def render
    self.applyMetrics
    # used to call the set-up procedure from the battle scene
    self.setUp
    @loaded = true
    self.refreshExpLevel
    # position databox
    rmd = (@sprites["base"].width%8)*(@playerpoke ? -1 : 1)
    self.x = self.defX + (@playerpoke ? @sprites["base"].width : -@sprites["base"].width) + rmd
    self.y = self.defY
    self.refresh
    @loaded = false
  end
  #-----------------------------------------------------------------------------
  #  queue databox for entry animation
  #-----------------------------------------------------------------------------
  def appear
    @inposition = false
    @loaded = true
  end
  #-----------------------------------------------------------------------------
  #  force new battler data
  #-----------------------------------------------------------------------------
  def battler=(val)
    @battler = val
    @pokemon = @battler.displayPokemon
    @trainer = @battle.opponent ? @battle.opponent[0] : nil
    self.refresh
  end
  #-----------------------------------------------------------------------------
  #  set databox position
  #-----------------------------------------------------------------------------
  def position
    self.x = self.defX
  end
  #-----------------------------------------------------------------------------
  #  get default X position
  #-----------------------------------------------------------------------------
  def defX
    x = @defX
    x += (@battler.index/2)*8 if @playerpoke
    x += (@battle.pbParty(1).length - 1 - @battler.index/2)*8 - (@battle.pbParty(1).length - 1)*8 if !@playerpoke
    return x
  end
  #-----------------------------------------------------------------------------
  #  get default Y position
  #-----------------------------------------------------------------------------
  def defY
    y = @defY
    y -= 50*((2-@battler.index)/2) - 64 + (48*(@battle.pbMaxSize(0) - 1))  + (@expandDouble && @battler.index == 0 ? 20 : 0) if @playerpoke && @battle.pbMaxSize(0) > 1
    y += 50*(@battler.index/2) - 16 if !@playerpoke && @battle.pbMaxSize(1) > 1
    return y
  end
  #-----------------------------------------------------------------------------
  #  configure all the sprite elements for databox
  #-----------------------------------------------------------------------------
  def setUp
    # reset of the set-up procedure
    @loaded = false
    @showing = false
    pbDisposeSpriteHash(@sprites)
    @sprites.clear
    # caches the bitmap used for coloring
    @colors = pbBitmap(@path + @colors)
    # initializes all the necessary components
    @sprites["base"] = Sprite.new(@viewport)
    @sprites["base"].bitmap = pbBitmap(@path+@baseBitmap)
    @sprites["base"].mirror = @playerpoke

    @sprites["status"] = Sprite.new(@viewport)
    @sprites["status"].bitmap = pbBitmap(@path + "status")
    @sprites["status"].z = self.getMetric("status", :z)
    @sprites["status"].src_rect.height /= 5
    @sprites["status"].src_rect.width = 0
    @sprites["status"].ex = self.getMetric("status", :x)
    @sprites["status"].ey = self.getMetric("status", :y)

    @sprites["mega"] = Sprite.new(@viewport)
    @sprites["mega"].z = self.getMetric("mega", :z)
    @sprites["mega"].mirror = @playerpoke
    @sprites["mega"].ex = self.getMetric("mega", :x)
    @sprites["mega"].ey = self.getMetric("mega", :y)

    @sprites["container"] = Sprite.new(@viewport)
    @sprites["container"].bitmap = pbBitmap(@path + @containerBmp)
    @sprites["container"].z = self.getMetric("container", :z)
    @sprites["container"].src_rect.height = @showexp ? 26 : 14
    @sprites["container"].ex = self.getMetric("container", :x)
    @sprites["container"].ey = self.getMetric("container", :y)

    @sprites["hp"] = Sprite.new(@viewport)
    @sprites["hp"].bitmap = Bitmap.new(1, 6)
    @sprites["hp"].z = @sprites["container"].z
    @sprites["hp"].ex = @sprites["container"].ex + @hpBarX
    @sprites["hp"].ey = @sprites["container"].ey + @hpBarY

    @sprites["exp"] = Sprite.new(@viewport)
    @sprites["exp"].bitmap = Bitmap.new(1, 4)
    @sprites["exp"].bitmap.blt(0, 0, @colors, Rect.new(0, 6, 2, 4))
    @sprites["exp"].z = @sprites["container"].z
    @sprites["exp"].ex = @sprites["container"].ex + @expBarX
    @sprites["exp"].ey = @sprites["container"].ey + @expBarY

    @sprites["textName"] = Sprite.new(@viewport)
    @sprites["textName"].bitmap = Bitmap.new(@sprites["container"].bitmap.width + 32, @sprites["base"].bitmap.height)
    @sprites["textName"].z = self.getMetric("name", :z)
    @sprites["textName"].ex = self.getMetric("name", :x) - 16
    @sprites["textName"].ey = self.getMetric("name", :y)
    pbSetSmallFont(@sprites["textName"].bitmap)

    @sprites["caught"] = Sprite.new(@viewport)
    @sprites["caught"].bitmap = pbBitmap(@path + "battleBoxOwned") if !@playerpoke && @battler.owned? && !@scene.battle.opponent
    @sprites["caught"].z = @sprites["container"].z
    @sprites["caught"].ex = @sprites["container"].ex - 18
    @sprites["caught"].ey = @sprites["container"].ey - 2

    @sprites["textHP"] = Sprite.new(@viewport)
    @sprites["textHP"].bitmap = Bitmap.new(@sprites["container"].bitmap.width, @sprites["base"].bitmap.height + 8)
    @sprites["textHP"].z = self.getMetric("hp", :z)
    @sprites["textHP"].ex = self.getMetric("hp", :x)
    @sprites["textHP"].ey = self.getMetric("hp", :y)
    pbSetSmallFont(@sprites["textHP"].bitmap)

    @megaBmp = pbBitmap(@path + "symMega")
    @prKyogre = pbBitmap("Graphics/Pictures/Battle/icon_primal_Kyogre")
    @prGroudon = pbBitmap("Graphics/Pictures/Battle/icon_primal_Groudon")
  end
  #-----------------------------------------------------------------------------
  #  positioning functions
  #-----------------------------------------------------------------------------
  def x; return @sprites["base"].x; end
  def y; return @sprites["base"].y; end
  def z; return @sprites["base"].z; end
  def visible; return @sprites["base"] ? @sprites["base"].visible : false; end
  def opacity; return @sprites["base"].opacity; end
  def color; return @sprites["base"].color; end
  def x=(val)
    return if !@loaded
    # calculates the relative X positions of all elements
    @sprites["base"].x = val
    for key in @sprites.keys
      next if key == "base"
      @sprites[key].x = @sprites["base"].x + @sprites[key].ex
    end
  end
  def y=(val)
    return if !@loaded
    # calculates the relative X positions of all elements
    @sprites["base"].y = val
    for key in @sprites.keys
      next if key == "base" || !@sprites[key]
      @sprites[key].y = @sprites["base"].y + @sprites[key].ey
    end
  end
  def visible=(val)
    for key in @sprites.keys
      next if !@sprites[key]
      @sprites[key].visible = val
    end
  end
  def temphide(val)
    if val
      @temphide = self.visible
      self.visible = false
    else
      self.visible = @temphide
      @temphide = false
    end
  end
  def opacity=(val)
    for key in @sprites.keys
      next if !@sprites[key]
      @sprites[key].opacity = val
    end
  end
  def color=(val)
    for sprite in @sprites.values
      sprite.color = val
    end
  end
  def positionX=(val)
    val = 4 if val < 4
    val = (@viewport.width - @sprites["base"].bitmap.width) if val > (@viewport.width - @sprites["base"].bitmap.width)
    self.x = val
  end
  #-----------------------------------------------------------------------------
  #  update HP bar (performance gains)
  #-----------------------------------------------------------------------------
  def updateHpBar
    return if self.disposed?
    # updates the current state of the HP bar
    zone = 0
    zone = 1 if self.hp <= @battler.totalhp*0.50
    zone = 2 if self.hp <= @battler.totalhp*0.25
    @sprites["hp"].bitmap.blt(0,0,@colors,Rect.new(zone*2,0,2,6))
    hpbar = @battler.totalhp == 0 ? 0 : (self.hp*@hpBarWidth/@battler.totalhp.to_f)
    @sprites["hp"].zoom_x = hpbar
    # updates the HP text
    str = "#{self.hp}/#{@battler.totalhp}"
    @sprites["textHP"].bitmap.clear
    textpos = [[str,@sprites["textHP"].bitmap.width,0,1,Color.white,Color.new(0,0,0,125)]]
    pbDrawTextPositions(@sprites["textHP"].bitmap,textpos) if @showhp
  end
  #-----------------------------------------------------------------------------
  #  update EXP bar (performance gains)
  #-----------------------------------------------------------------------------
  def updateExpBar
    return if self.disposed?
    @sprites["exp"].zoom_x = @showexp ? self.exp : 0
  end
  #-----------------------------------------------------------------------------
  #  refresh databox contents
  #-----------------------------------------------------------------------------
  def refresh
    return if self.disposed?
    # refreshes data
    @pokemon = @battler.displayPokemon
    # failsafe
    return if @pokemon.nil?
    @hidden = EliteBattle.get_data(@pokemon.species, :Species, :HIDENAME, (@pokemon.form rescue 0)) && !$Trainer.owned?(@pokemon.species)
    # exits the refresh if the databox isn't fully set up yet
    return if !@loaded
    # update for HP/EXP bars
    self.updateHpBar
    # clears the current bitmap containing text and adjusts its font
    @sprites["textName"].bitmap.clear
    # used to calculate the potential offset of elements should they exceed the
    # width of the HP bar
    str = ""
    str = _INTL("♂") if @pokemon.gender == 0 && !@hidden
    str = _INTL("♀") if @pokemon.gender == 1 && !@hidden
    w = @sprites["textName"].bitmap.text_size("#{@battler.name.force_encoding("UTF-8")}#{str.force_encoding("UTF-8")}Lv.#{@pokemon.level}").width
    o = (w > @hpBarWidth + 4) ? (w-(@hpBarWidth + 4))/2.0 : 0; o = o.ceil
    # writes the Pokemon's name
    str = @battler.name.nil? ? "" : @battler.name
    str += " "
    color = @pokemon.shiny? ? Color.new(222,197,95) : Color.white
    pbDrawOutlineText(@sprites["textName"].bitmap,18-o,3,@sprites["textName"].bitmap.width-40,@sprites["textName"].bitmap.height,str,color,Color.new(0,0,0,125),0)
    # writes the Pokemon's gender
    x = @sprites["textName"].bitmap.text_size(str).width + 18
    str = ""
    str = _INTL("♂") if @pokemon.gender == 0 && !@hidden
    str = _INTL("♀") if @pokemon.gender == 1 && !@hidden
    color = (@pokemon.gender == 0) ? Color.new(53,107,208) : Color.new(180,37,77)
    pbDrawOutlineText(@sprites["textName"].bitmap,x-o,3,@sprites["textName"].bitmap.width-40,@sprites["textName"].bitmap.height,str,color,Color.new(0,0,0,125),0)
    # writes the Pokemon's level
    str = "Lv.#{@battler.level}"
    pbDrawOutlineText(@sprites["textName"].bitmap,18+o,3,@sprites["textName"].bitmap.width-40,@sprites["textName"].bitmap.height,str,Color.white,Color.new(0,0,0,125),2)
    # changes the Mega symbol graphics (depending on Mega or Primal)
    if @battler.mega?
      @sprites["mega"].bitmap = @megaBmp.clone
    elsif @battler.primal?
      @sprites["mega"].bitmap = @prKyogre.clone if @battler.isSpecies?(:KYOGRE)
      @sprites["mega"].bitmap = @prGroudon.clone if @battler.isSpecies?(:GROUDON)
    elsif @sprites["mega"].bitmap
      @sprites["mega"].bitmap.clear
      @sprites["mega"].bitmap = nil
    end
    self.updateHpBar
    self.updateExpBar
  end
  #-----------------------------------------------------------------------------
  #  update databox
  #-----------------------------------------------------------------------------
  def update
    return if self.disposed?
    # updates the HP increase/decrease animation
    if @animatingHP
      if @currenthp < @endhp
        @currenthp += (@endhp - @currenthp)/10.0.delta_add(false)
        @currenthp = @currenthp.ceil
        @currenthp = @endhp if @currenthp > @endhp
      elsif @currenthp > @endhp
        @currenthp -= (@currenthp - @endhp)/10.0.delta_add(false)
        @currenthp = @currenthp.floor
        @currenthp = @endhp if @currenthp < @endhp
      end
      self.updateHpBar
      @animatingHP = false if @currenthp == @endhp
    end
    # updates the EXP increase/decrease animation
    if @animatingEXP
      if !@showexp
        @currentexp = @endexp
      elsif @currentexp < @endexp
        @currentexp += (@endexp - @currentexp)/10.0.delta_add(false)
        @currentexp = @currentexp.ceil
        @currentexp = @endexp if @currentexp > @endexp
      elsif @currentexp > @endexp
        @currentexp -= (@currentexp - @endexp)/10.0.delta_add(false)
        @currentexp = @currentexp.floor
        @currentexp = @endexp if @currentexp < @endexp
      end
      self.updateExpBar
      if @currentexp == @endexp
        # tints the databox blue and plays a sound when EXP is full
        if @currentexp >= @expBarWidth
          pbSEPlay("Pkmn exp full")
          @sprites["base"].color = Color.new(61, 141, 179)
          @animatingEXP = false
          refreshExpLevel
          self.refresh
        else
          @animatingEXP = false
        end
      end
    end
    return if !@loaded
    # moves into position
    unless @animatingHP || @animatingEXP || @inposition
      if @playerpoke && self.x > self.defX
        self.x -= @sprites["base"].width/8
      elsif !@playerpoke && self.x < self.defX
        self.x += @sprites["base"].width/8
      end
    end
    # shows status condition
    status = GameData::Status.get(@battler.status).id_number
    @sprites["status"].src_rect.y = @sprites["status"].src_rect.height * (status - 1)
    @sprites["status"].src_rect.width = status > 0 ? @sprites["status"].bitmap.width : 0
    # gets rid of the level up tone
    @sprites["base"].color.alpha -= 16 if @sprites["base"].color.alpha > 0
    self.y = self.defY
  end
  #-----------------------------------------------------------------------------
end

#===============================================================================
#  Player Side Safari Zone data box
#===============================================================================
class SafariDataBoxEBDX < SpriteWrapper
  attr_accessor :selected
  attr_reader :appearing
  #-----------------------------------------------------------------------------
  #  safari bar constructor
  #-----------------------------------------------------------------------------
  def initialize(battle, viewport=nil)
    @viewport = viewport
    super(viewport)
    @selected = 0
    @battle = battle
    bmp = pbBitmap("Graphics/EBDX/Pictures/UI/safariBar")
    @spriteX = @viewport.width - bmp.width
    @spriteY = @viewport.height - 184
    # looks up globally defined settings
    data = EliteBattle.get_data(:SAFARI_DATABOX, :Metrics, :METRICS)
    unless data.nil?
      # applies a set of predefined keys
      @spriteX = data[:X] if data.has_key?(:X) && data[:X].is_a?(Numeric)
      @spriteY = data[:Y] if data.has_key?(:Y) && data[:Y].is_a?(Numeric)
    end
    @temphide = false
    @appearing = false
    @contents = BitmapWrapper.new(bmp.width, 78)
    bmp.dispose
    self.bitmap = @contents
    pbSetSmallFont(self.bitmap)
    self.visible = false
    self.z = 50
    refresh
  end
  #-----------------------------------------------------------------------------
  #  hide databox
  #-----------------------------------------------------------------------------
  def temphide(val)
    if val
      @temphide = self.visible
      self.visible = false
    else
      self.visible = @temphide
      @temphide = false
    end
  end
  #-----------------------------------------------------------------------------
  #  toggle the bar to appear
  #-----------------------------------------------------------------------------
  def appear
    refresh
    self.visible = true
    self.opacity = 255
  end
  #-----------------------------------------------------------------------------
  #  refresh bar
  #-----------------------------------------------------------------------------
  def refresh
    self.bitmap.clear
    bmp = pbBitmap("Graphics/EBDX/Pictures/UI/safariBar")
    self.bitmap.blt((self.bitmap.width-bmp.width)/2,self.bitmap.height-bmp.height,bmp,Rect.new(0,0,bmp.width,bmp.height))
    str = _INTL("Safari Balls: {1}", @battle.ballCount)
    pbDrawOutlineText(self.bitmap,0,38,self.bitmap.width,self.bitmap.height,str,Color.white,Color.new(0,0,0,125),1)
  end
  #-----------------------------------------------------------------------------
  #  update (temp)
  #-----------------------------------------------------------------------------
  def update; end
  def width; return self.bitmap.width; end
  #-----------------------------------------------------------------------------
end

#===============================================================================
#  Target selection UI
#===============================================================================
class TargetWindowEBDX
  attr_reader :index
  #-----------------------------------------------------------------------------
  #  PBS metadata
  #-----------------------------------------------------------------------------
  def applyMetrics
    # sets default values
    @btnImg = "btnEmpty"
    @selImg = "cmdSel"
    # looks up next cached metrics first
    d1 = EliteBattle.get(:nextUI)
    d1 = d1[:TARGETMENU] if !d1.nil? && d1.has_key?(:TARGETMENU)
    # looks up globally defined settings
    d2 = EliteBattle.get_data(:TARGETMENU, :Metrics, :METRICS)
    # looks up globally defined settings
    d7 = EliteBattle.get_map_data(:TARGETMENU_METRICS)
    # look up trainer specific metrics
    d6 = @battle.opponent ? EliteBattle.get_trainer_data(@battle.opponent[0].trainer_type, :TARGETMENU_METRICS, @battle.opponent[0]) : nil
    # looks up species specific metrics
    d5 = !@battle.opponent ? EliteBattle.get_data(@battle.battlers[1].species, :Species, :TARGETMENU_METRICS, (@battle.battlers[1].form rescue 0)) : nil
    # proceeds with parameter definition if available
    for data in [d2, d7, d6, d5, d1]
      if !data.nil?
        # applies a set of predefined keys
        @btnImg = data[:BUTTONGRAPHIC] if data.has_key?(:BUTTONGRAPHIC) && data[:BUTTONGRAPHIC].is_a?(String)
        @selImg = data[:SELECTORGRAPHIC] if data.has_key?(:SELECTORGRAPHIC) && data[:SELECTORGRAPHIC].is_a?(String)
      end
    end
  end
  #-----------------------------------------------------------------------------
  #  initialize all the required components
  #-----------------------------------------------------------------------------
  def initialize(viewport, battle, scene)
    @viewport = viewport
    @battle = battle
    @scene = scene
    @index = 0
    @disposed = false
    # button sprite hash
    @buttons = {}
    # apply all the graphic path data
    @path = "Graphics/EBDX/Pictures/UI/"
    self.applyMetrics
    # set up selector sprite
    @sel = SelectorSprite.new(@viewport, 4)
    @sel.filename = @path + @selImg
    @sel.z = 99999
    # set up background graphic
    @background = Sprite.new(@viewport)
    @background.create_rect(@viewport.width, 64, Color.new(0, 0, 0, 150))
    @background.bitmap = pbBitmap(@path + @barImg) if !@barImg.nil?
    @background.y = Graphics.height - @background.bitmap.height + 80
    @background.z = 100
  end
  #-----------------------------------------------------------------------------
  #  re-draw buttons for current context and selectable battlers
  #-----------------------------------------------------------------------------
  def refresh(texts)
    # dispose current buttons
    pbDisposeSpriteHash(@buttons)
    # cache bitmap and calc width/height
    bmp = pbBitmap(@path + @btnImg)
    rw = @battle.pbMaxSize*(bmp.width + 8)
    rh = 2*(bmp.height + 4)
    # render each button
    for i in 0...texts.length
      @buttons["#{i}"] = Sprite.new(@viewport)
      @buttons["#{i}"].bitmap = Bitmap.new(bmp.width, bmp.height)
      @buttons["#{i}"].bitmap.blt(0, 0, bmp, bmp.rect)
      # apply icon sprite if valid target
      if !texts[i].nil? && @battle.battlers[i].displayPokemon
        pkmn = @battle.battlers[i].displayPokemon
        icon = pbBitmap(GameData::Species.icon_filename_from_pokemon(pkmn))
        ix = (bmp.width - icon.width/2)/2
        iy = (bmp.height - icon.height)/2 - 9
        @buttons["#{i}"].bitmap.blt(ix, iy, icon, Rect.new(0, 0, icon.width/2, bmp.height - 4 - iy), 216) if @battle.battlers[i].hp > 0
      else
        @buttons["#{i}"].opacity = i/2 > @battle.pbMaxSize(i%2) - 1 ? 0 : 128
      end
      # calculate x and y positions
      x = (@viewport.width - rw)/2 + (i%2 == 0 ? i/2 : @battle.pbMaxSize(1) - 1 - (i-1)/2)*(bmp.width + 8)
      dif = @battle.pbMaxSize(1 - i%2) - @battle.pbMaxSize(i%2)
      x += dif*0.5*(bmp.width + 8) if dif > 0
      y = (@viewport.height - rh - 4) + (1 - i%2)*(bmp.height + 4)
      # apply positioning
      @buttons["#{i}"].x = x
      @buttons["#{i}"].y = y + 120
      @buttons["#{i}"].z = 100
    end
    bmp.dispose
  end
  #-----------------------------------------------------------------------------
  #  set new index
  #-----------------------------------------------------------------------------
  def index=(val)
    @index = val
    return if @buttons.nil? || @buttons["#{@index}"].nil?
    @sel.target(@buttons["#{@index}"])
    @buttons["#{@index}"].src_rect.y = -4
  end
  def shiftMode=(val); end
  #-----------------------------------------------------------------------------
  #  update target window
  #-----------------------------------------------------------------------------
  def update
    for key in @buttons.keys
      @buttons[key].src_rect.y += 1 if @buttons[key].src_rect.y < 0
    end
    @sel.update
  end
  #-----------------------------------------------------------------------------
  #  play animation for showing window
  #-----------------------------------------------------------------------------
  def showPlay
    10.times do
      for key in @buttons.keys
        @buttons[key].y -= 12
      end
      @background.y -= 8
      @scene.wait
    end
  end
  #-----------------------------------------------------------------------------
  #  play animation for hiding window
  #-----------------------------------------------------------------------------
  def hidePlay
    @sel.visible = false
    10.times do
      for key in @buttons.keys
        @buttons[key].y += 12
      end
      @background.y += 8
      @scene.wait
    end
  end
  #-----------------------------------------------------------------------------
  #  dispose all sprites
  #-----------------------------------------------------------------------------
  def dispose
    return if self.disposed?
    @sel.dispose
    @background.dispose
    pbDisposeSpriteHash(@buttons)
    @disposed = true
  end
  def disposed?; return @disposed; end
  #-----------------------------------------------------------------------------
end

#===============================================================================
#  Class to handle the construction and animation of opposing and player
#  party indicators
#===============================================================================
class PartyLineupEBDX
  attr_reader :loaded
  attr_accessor :toggle
  #-----------------------------------------------------------------------------
  #  class constructor
  #-----------------------------------------------------------------------------
  def initialize(viewport, scene, battle, side)
    @viewport = viewport
    @scene = scene
    @sprites = @scene.sprites
    @battle = battle
    @side = side
    @num = PokeBattle_SceneConstants::NUM_BALLS
    # is the animation appearing or not
    @toggle = true
    @loaded = false
    @disposed = false
    # cache bitmaps
    @partyBar = pbBitmap("Graphics/EBDX/Pictures/UI/partyBar")
    @partyBalls = pbBitmap("Graphics/EBDX/Pictures/UI/partyBalls")
    # draw main line up bar
    @sprites["partyLine_#{@side}"] = Sprite.new(@viewport)
    @sprites["partyLine_#{@side}"].z = 99999
    # draw individual party indicators
    for k in 0...@num
      @sprites["partyLine_#{@side}_#{k}"] = Sprite.new(@viewport)
      @sprites["partyLine_#{@side}_#{k}"].z = 99999
    end
  end
  #-----------------------------------------------------------------------------
  #  refresh both graphics and animation parameters
  #-----------------------------------------------------------------------------
  def refresh
    @toggle = true
    # get party details
    pty = self.party; pty.reverse! if (@side%2 == 1)
    # assign graphic ands position party line
    @sprites["partyLine_#{@side}"].bitmap = @partyBar.clone
    @sprites["partyLine_#{@side}"].mirror = (@side%2 == 0)
    @sprites["partyLine_#{@side}"].ox = @side%2 == 0 ? @partyBar.width : 0
    @sprites["partyLine_#{@side}"].opacity = 255
    @sprites["partyLine_#{@side}"].zoom_x = 1
    # position party balls relative to main party line up
    for k in 0...@num
      @sprites["partyLine_#{@side}_#{k}"].bitmap = Bitmap.new(@partyBalls.height, @partyBalls.height)
      # select the appropriate party line up ball graphic
      if pty[k].nil?
        pin = 3
      elsif pty[k].hp < 1 || pty[k].egg?
        pin = 2
      elsif GameData::Status.get(pty[k].status).id_number > 0
        pin = 1
      else
        pin = 0
      end
      # render ball graphic
      @sprites["partyLine_#{@side}_#{k}"].bitmap.blt(0, 0, @partyBalls, Rect.new(@partyBalls.height*pin, 0, @partyBalls.height, @partyBalls.height))
      @sprites["partyLine_#{@side}_#{k}"].center!
      @sprites["partyLine_#{@side}_#{k}"].ex = (@side%2 == 0 ? 26 : 12) + 24*k + @sprites["partyLine_#{@side}_#{k}"].ox
      @sprites["partyLine_#{@side}_#{k}"].ey = -12 + @sprites["partyLine_#{@side}_#{k}"].oy
      @sprites["partyLine_#{@side}_#{k}"].opacity = 255
      @sprites["partyLine_#{@side}_#{k}"].angle = 0
    end
    # position full line up graphics
    self.x = @side%2 == 0 ? (@viewport.width + @partyBar.width + 10) : (-@partyBar.width - 10)
    mult = (EliteBattle::USE_FOLLOWER_EXCEPTION && EliteBattle.follower(@battle).nil?) ? 0.65 : 0.5
    self.y = @side%2 == 0 ? @viewport.height*mult : @viewport.height*0.3
    # register as loaded
    @loaded = true
  end
  #-----------------------------------------------------------------------------
  #  set X value
  #-----------------------------------------------------------------------------
  def x=(val)
    @sprites["partyLine_#{@side}"].x = val
    for k in 0...@num
      @sprites["partyLine_#{@side}_#{k}"].x = @sprites["partyLine_#{@side}"].x + @sprites["partyLine_#{@side}_#{k}"].ex - @sprites["partyLine_#{@side}"].ox
    end
  end
  #-----------------------------------------------------------------------------
  #  set Y value
  #-----------------------------------------------------------------------------
  def y=(val)
    @sprites["partyLine_#{@side}"].y = val
    for k in 0...@num
      @sprites["partyLine_#{@side}_#{k}"].y = @sprites["partyLine_#{@side}"].y + @sprites["partyLine_#{@side}_#{k}"].ey
    end
  end
  #-----------------------------------------------------------------------------
  #  get X, Y values of party line up
  #-----------------------------------------------------------------------------
  def x; return @sprites["partyLine_#{@side}"].x; end
  def y; return @sprites["partyLine_#{@side}"].y; end
  #-----------------------------------------------------------------------------
  #  get the end X position
  #-----------------------------------------------------------------------------
  def end_x
    return @side%2 == 0 ? @viewport.width + 10 : -10
  end
  #-----------------------------------------------------------------------------
  #  check if animation has yet to be completed
  #-----------------------------------------------------------------------------
  def animating?
    return false if !@loaded
    return @side%2 == 0 ? (self.x > self.end_x) : (self.x < self.end_x) if @toggle
    return @sprites["partyLine_#{@side}"].opacity > 0 if !@toggle
    return false
  end
  #-----------------------------------------------------------------------------
  #  main animation update "loop"
  #-----------------------------------------------------------------------------
  def update
    # exit if animation already finished
    if !self.animating?
      # level icon balls
      for k in 0...@num
        @sprites["partyLine_#{@side}_#{k}"].angle = 0
      end
      return
    end
    # animate appearing
    if @toggle
      self.x += ((@partyBar.width/16)/self.delta) * (@side%2 == 0 ? -1 : 1)
      # rotate icon balls
      for k in 0...@num
        @sprites["partyLine_#{@side}_#{k}"].angle -= ((360/16) * (@side%2 == 0 ? -1 : 1))/self.delta
      end
    # animate removal
    else
      @sprites["partyLine_#{@side}"].zoom_x += (1.0/16)/self.delta
      @sprites["partyLine_#{@side}"].opacity -= 24/self.delta
      # rotate icon balls
      for k in 0...@num
        m = @side%2 == 0 ? -k : (@num - k)
        @sprites["partyLine_#{@side}_#{k}"].angle -= ((360/16) * (@side%2 == 0 ? -1 : 1))/self.delta
        @sprites["partyLine_#{@side}_#{k}"].angle = 0 if @sprites["partyLine_#{@side}_#{k}"].angle >= 360 || @sprites["partyLine_#{@side}_#{k}"].angle <= -360
        @sprites["partyLine_#{@side}_#{k}"].opacity -= 24/self.delta
        @sprites["partyLine_#{@side}_#{k}"].x += (((@partyBar.width/16) * (@side%2 == 0 ? -1 : 1)) - m)/self.delta
      end
    end
  end
  #-----------------------------------------------------------------------------
  #  get full party of the current side
  #-----------------------------------------------------------------------------
  def party
    party = @battle.pbParty(@side).clone
    (@num - party.length).times { party.push(nil) }
    return party
  end
  #-----------------------------------------------------------------------------
  #  dispose and check for disposal
  #-----------------------------------------------------------------------------
  def delta; return Graphics.frame_rate/40.0; end
  def disposed?; return @disposed; end
  def dispose
    return if @disposed
    @partyBar.dispose
    @partyBalls.dispose
    @disposed = true
  end
  #-----------------------------------------------------------------------------
end

#===============================================================================
#  Command Choices
#  UI ovarhaul
#===============================================================================
class ChoiceWindowEBDX
  attr_accessor :index
  attr_reader :over
  #-----------------------------------------------------------------------------
  #  initialize the choice boxes
  #-----------------------------------------------------------------------------
  def initialize(viewport,commands,scene)
    @commands = commands
    @scene = scene
    @index = 0
    offset = 0
    @path = "Graphics/EBDX/Pictures/UI/"
    @viewport = viewport
    @sprites = {}
    @visibility = [false,false,false,false]
    baseColor = Color.white
    shadowColor = Color.new(0,0,0,192)
    # apply styling from PBS
    self.applyMetrics
    # generate sprites
    @sprites["sel"] = SpriteSheet.new(@viewport,4)
    @sprites["sel"].setBitmap(pbSelBitmap(@path+@selImg,Rect.new(0,0,92,38)))
    @sprites["sel"].speed = 4
    @sprites["sel"].ox = @sprites["sel"].src_rect.width/2
    @sprites["sel"].oy = @sprites["sel"].src_rect.height/2
    @sprites["sel"].z = 99999
    @sprites["sel"].visible = false
    # fill sprites with text
    bmp = pbBitmap(@path+@btnImg)
    for i in 0...@commands.length
      k = @commands.length - 1 - i
      @sprites["choice#{i}"] = Sprite.new(@viewport)
      @sprites["choice#{i}"].x = Graphics.width - bmp.width - 14 + bmp.width/2
      # Position choice window higher to avoid overlapping player databoxes
      # Original: Graphics.height - 136; changed to center vertically in the battle area
      @sprites["choice#{i}"].y = Graphics.height/2 - 30 - k*(bmp.height+4) + bmp.height/2
      @sprites["choice#{i}"].z = 99998
      @sprites["choice#{i}"].bitmap = Bitmap.new(bmp.width,bmp.height)
      @sprites["choice#{i}"].center!
      @sprites["choice#{i}"].opacity = 0
      choice = @sprites["choice#{i}"].bitmap
      pbSetSystemFont(choice)
      choice.blt(0,0,bmp,bmp.rect)
      pbDrawOutlineText(choice,0,8,bmp.width,bmp.height,@commands[i],baseColor,shadowColor,1)
    end
    bmp.dispose
  end
  #-----------------------------------------------------------------------------
  #  apply styling from PBS
  #-----------------------------------------------------------------------------
  def applyMetrics
    # sets default values
    @btnImg = "btnEmpty"
    @selImg = "cmdSel"
    # looks up next cached metrics first
    d1 = EliteBattle.get(:nextUI)
    d1 = d1[:CHOICE_MENU] if !d1.nil? && d1.has_key?(:CHOICE_MENU)
    # looks up globally defined settings
    d2 = EliteBattle.get_data(:CHOICE_MENU, :Metrics, :METRICS)
    # proceeds with parameter definition if available
    for data in [d2, d1]
      if !data.nil?
        # applies a set of predefined keys
        @btnImg = data[:BUTTONS] if data.has_key?(:BUTTONS) && data[:BUTTONS].is_a?(String)
        @selImg = data[:SELECTOR] if data.has_key?(:SELECTOR) && data[:SELECTOR].is_a?(String)
      end
    end
  end
  #-----------------------------------------------------------------------------
  #  dispose of the sprites
  #-----------------------------------------------------------------------------
  def dispose(scene)
    2.times do
      @sprites["sel"].opacity -= 128
      for i in 0...@commands.length
        @sprites["choice#{i}"].opacity -= 128
      end
      scene.animateScene(true)
      scene.pbGraphicsUpdate
    end
    pbDisposeSpriteHash(@sprites)
  end
  #-----------------------------------------------------------------------------
  #  update choice selection
  #-----------------------------------------------------------------------------
  def update
    @sprites["sel"].visible = true
    @sprites["sel"].x = @sprites["choice#{@index}"].x
    @sprites["sel"].y = @sprites["choice#{@index}"].y - 2
    @sprites["sel"].update
    if Input.trigger?(Input::UP)
      pbSEPlay("EBDX/SE_Select1")
      @index -= 1
      @index = @commands.length-1 if @index < 0
      @sprites["choice#{@index}"].src_rect.y -= 6
    elsif Input.trigger?(Input::DOWN)
      pbSEPlay("EBDX/SE_Select1")
      @index += 1
      @index = 0  if @index >= @commands.length
      @sprites["choice#{@index}"].src_rect.y -= 6
    end
    for i in 0...@commands.length
      @sprites["choice#{i}"].opacity += 128 if @sprites["choice#{i}"].opacity < 255
      @sprites["choice#{i}"].src_rect.y += 1 if @sprites["choice#{i}"].src_rect.y < 0
    end
  end
  def shiftMode=(val); end
  #-----------------------------------------------------------------------------
end

#===============================================================================
#  EBDX UI animation on battler capture
#===============================================================================
class EliteBattle_Pokedex
  #-----------------------------------------------------------------------------
  #  constructs class
  #-----------------------------------------------------------------------------
  def initialize(viewport, battler)
    @viewport = viewport
    @viewport.color = Color.new(0, 0, 0, 0)
    16.times do
      @viewport.color.alpha += 16
      Graphics.update
    end
    @path = "Graphics/EBDX/Pictures/Pokedex/"
    @pokemon = battler
    @species = @pokemon.species
    @pkmnbmp = pbLoadPokemonBitmap(@pokemon)
    @sprites = {}
    @disposed = false
    @typebitmap = pbBitmap("Graphics/EBDX/Pictures/UI/types2")
    self.applyMetrics
    self.drawPage
    self.drawNick
    self.main
  end
  #-----------------------------------------------------------------------------
  #  draws page contents
  #-----------------------------------------------------------------------------
  def drawPage
    # queue dex data
    species_data = GameData::Species.get_species_form(@species, @pokemon.form)
    # draw UI background
    @sprites["bg"] = ScrollingSprite.new(@viewport)
    @sprites["bg"].setBitmap(@path + @imgBg)
    @sprites["bg"].speed = 1
    @sprites["bg"].color = Color.new(0, 0, 0, 0)
    # draw Pokemon sprite
    @sprites["poke"] = Sprite.new(@viewport)
    @sprites["poke"].bitmap = @pkmnbmp.bitmap
    @sprites["poke"].center!
    @sprites["poke"].x = 90
    @sprites["poke"].y = 122
    @sprites["poke"].z = 10
    @sprites["poke"].mirror = true
    # draw sprite silhouette
    @sprites["sil"] = Sprite.new(@viewport)
    @sprites["sil"].bitmap = @pkmnbmp.bitmap
    @sprites["sil"].center!
    @sprites["sil"].x = 90
    @sprites["sil"].y = 122
    @sprites["sil"].z = 10
    @sprites["sil"].mirror = true
    @sprites["sil"].color = Color.black
    # draw UI overlay
    @sprites["contents"] = Sprite.new(@viewport)
    @sprites["contents"].bitmap = Bitmap.new(@viewport.width, @viewport.height)
    @sprites["contents"].color = Color.new(0, 0, 0, 0)
    # draw UI highlight
    @sprites["highlight"] = Sprite.new(@viewport)
    @sprites["highlight"].bitmap = pbBitmap(@path + @imgHh)
    @sprites["highlight"].color = Color.new(0, 0, 0, 0)
    @sprites["highlight"].opacity = 0
    @sprites["highlight"].toggle = 1
    # set up overlay bitmap
    pbSetSystemFont(@sprites["contents"].bitmap)
    overlay = @sprites["contents"].bitmap
    olbmp = pbBitmap(@path + @imgOl)
    overlay.blt(0, 0, olbmp, olbmp.rect)
    olbmp.dispose
    # draw overlay contents
    base   = Color.new(88, 88, 80)
    shadow = Color.new(168, 184, 184)
    textpos = []
    # region and dexlist config
    region = -1
    if Settings::USE_CURRENT_REGION_DEX
      region = pbGetCurrentRegion
      region = -1 if region >= $Trainer.pokedex.dexes_count - 1
    else
      region = $PokemonGlobal.pokedexDex   # National Dex -1, regional Dexes 0, 1, etc.
    end
    dexnum = pbGetRegionalNumber(region, @species)
    dexnumshift = Settings::DEXES_WITH_OFFSETS.include?(region)
    dexlist = [[@species, GameData::Species.get(@species).name, 0, 0, dexnum, dexnumshift]]
    # dex number
    indexText = "???"
    if dexlist[0][4] > 0
      indexNumber = dexlist[0][4]
      indexNumber -= 1 if dexlist[0][5]
      indexText = sprintf("%03d", indexNumber)
    end
    # push text into array
    textpos.push([_INTL("{1}   {2}", indexText, species_data.real_name), 262, 30, 0, base, shadow])
    textpos.push([_INTL("Height"), 274, 158, 0, base, shadow])
    textpos.push([_INTL("Weight"), 274, 190, 0, base, shadow])
    # Pokemon kind
    textpos.push([_INTL("{1} Pokémon", species_data.category), 262, 66, 0, base, shadow])
    # height and weight
    height = species_data.height
    weight = species_data.weight
    if System.user_language[3..4] == "US"   # If the user is in the United States
      inches = (height/0.254).round
      pounds = (weight/0.45359).round
      textpos.push([_ISPRINTF("{1:d}'{2:02d}''", inches/12, inches%12), 482, 158, 1, base, shadow])
      textpos.push([_ISPRINTF("{1:4.1f} lbs.", pounds/10.0), 482, 190, 1, base, shadow])
    else
      textpos.push([_ISPRINTF("{1:.1f} m", height/10.0), 482, 158, 1, base, shadow])
      textpos.push([_ISPRINTF("{1:.1f} kg", weight/10.0), 482, 190, 1, base, shadow])
    end
    # Pokédex entry text
    drawTextEx(overlay, 32, 250, Graphics.width - 60, 4, species_data.pokedex_entry, base, shadow)
    # footprint
    footprintfile = GameData::Species.footprint_filename(@species, @pokemon.form)
    if footprintfile
      footprint = pbBitmap(footprintfile)
      overlay.blt(214, 154, footprint, footprint.rect)
      footprint.dispose
    end
    # Draw the type icon(s)
    type1 = GameData::Type.get(species_data.type1).id_number
    type2 = GameData::Type.get(species_data.type2).id_number
    height = @typebitmap.height/GameData::Type.values.length
    type1rect = Rect.new(0, type1*height, @typebitmap.width, height)
    type2rect = Rect.new(0, type2*height, @typebitmap.width, height)
    overlay.blt(292, 122, @typebitmap, type1rect)
    overlay.blt(376, 122, @typebitmap, type2rect) if type1 != type2
    # draw all text
    pbDrawTextPositions(overlay, textpos)
  end
  #-----------------------------------------------------------------------------
  #  draws nicknaming page
  #-----------------------------------------------------------------------------
  def drawNick
    @sprites["color"] = Sprite.new(@viewport)
    @sprites["color"].bitmap = pbBitmap(@path + @imgDk)
    @sprites["color"].z = 5
    @sprites["color"].opacity = 0
    for i in [3,2,1]
      @sprites["c#{i}"] = Sprite.new(@viewport)
      @sprites["c#{i}"].bitmap = pbBitmap(@path + sprintf("#{@imgEl}%03d",i))
      @sprites["c#{i}"].center!
      @sprites["c#{i}"].x = @viewport.width/2
      @sprites["c#{i}"].y = @sprites["poke"].y
      @sprites["c#{i}"].z = 5
      @sprites["c#{i}"].speed = i*0.001
      @sprites["c#{i}"].toggle = 1
      @sprites["c#{i}"].opacity = 0
    end
  end
  #-----------------------------------------------------------------------------
  #  applies alteration if applicable
  #-----------------------------------------------------------------------------
  def applyMetrics
    # sets default values
    @imgBg = "dexBg"
    @imgOl = "dexOverlay"
    @imgDk = "dexEnd"
    @imgEl = "dexElement"
    @imgHh = "dexHighlight"
    # looks up next cached metrics first
    d1 = EliteBattle.get(:nextUI)
    d1 = d1[:DEX_CAPTURE] if !d1.nil? && d1.has_key?(:DEX_CAPTURE)
    # looks up globally defined settings
    d2 = EliteBattle.get_data(:DEX_CAPTURE, :Metrics, :METRICS)
    # looks up species specific metrics
    d5 = EliteBattle.get_data(@species, :Species, :DEX_CAPTURE, (@pokemon.form rescue 0))
    # proceeds with parameter definition if available
    for data in [d2, d1,d5]
      if !data.nil?
        # applies a set of predefined keys
        @imgBg = data[:BACKGROUND] if data.has_key?(:BACKGROUND) && data[:BACKGROUND].is_a?(String)
        @imgOl = data[:OVERLAY] if data.has_key?(:OVERLAY) && data[:OVERLAY].is_a?(String)
        @imgHh = data[:HIGHLIGHT] if data.has_key?(:HIGHLIGHT) && data[:HIGHLIGHT].is_a?(String)
        @imgDk = data[:END_SCREEN] if data.has_key?(:END_SCREEN) && data[:END_SCREEN].is_a?(String)
        @imgEl = data[:ELEMENTS] if data.has_key?(:ELEMENTS) && data[:ELEMENTS].is_a?(String)
      end
    end
  end
  #-----------------------------------------------------------------------------
  #  main loop of scene
  #-----------------------------------------------------------------------------
  def main
    # fade in scene
    16.times do
      self.update
      @viewport.color.alpha -= 16
      Graphics.update
    end
    # hide silhouette
    h = (@sprites["sil"].bitmap.height/32.0).ceil
    32.times do
      self.update
      @sprites["sil"].src_rect.height -= h
      Graphics.update
    end
    # play cry
    GameData::Species.cry_filename_from_pokemon(@pokemon)
    # begin loop
    loop do
      Graphics.update
      Input.update
      self.update
      break if Input.trigger?(Input::C)
    end
    # moves Pokemon sprite to middle of screen
    w = (@viewport.width/2 - @sprites["poke"].x)/32
    32.times do
      @sprites["contents"].color.alpha += 16
      @sprites["bg"].color.alpha += 16
      @sprites["highlight"].color.alpha += 16
      @sprites["poke"].x += w
      @sprites["color"].opacity += 8
      for i in 1..3
        @sprites["c#{i}"].opacity += 8
      end
      self.update
      Graphics.update
    end
    @sprites["poke"].x = @viewport.width/2
    Graphics.update
  end
  #-----------------------------------------------------------------------------
  #  updates scene
  #-----------------------------------------------------------------------------
  def update
    return if self.disposed?
    @sprites["bg"].update
    @sprites["highlight"].opacity += @sprites["highlight"].toggle*8
    @sprites["highlight"].toggle *= -1 if @sprites["highlight"].opacity <= 0 || @sprites["highlight"].opacity >= 255
    for i in 1..3
      @sprites["c#{i}"].zoom_x -= @sprites["c#{i}"].speed * @sprites["c#{i}"].toggle
      @sprites["c#{i}"].zoom_y -= @sprites["c#{i}"].speed * @sprites["c#{i}"].toggle
      @sprites["c#{i}"].toggle *= -1 if @sprites["c#{i}"].zoom_x <= 0.96 || @sprites["c#{i}"].zoom_x >= 1.04
    end
  end
  #-----------------------------------------------------------------------------
  #  disposes of all sprites
  #-----------------------------------------------------------------------------
  def dispose
    @pkmnbmp.dispose
    pbDisposeSpriteHash(@sprites)
    @disposed = true
  end
  #-----------------------------------------------------------------------------
  #  checks if room is disposed
  #-----------------------------------------------------------------------------
  def disposed?; return @disposed; end
  #-----------------------------------------------------------------------------
  #  compatibility layers for scene transitions
  #-----------------------------------------------------------------------------
  def color; return @viewport.color; end
  def color=(val); @viewport.color = val; end
  def visible; return @sprites["bg"].visible; end
  def visible=(val)
    for key in @sprites.keys
      @sprites[key].visible = val
    end
  end
  #-----------------------------------------------------------------------------
end
