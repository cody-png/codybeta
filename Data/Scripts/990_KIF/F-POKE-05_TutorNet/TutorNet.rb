#===============================================================================
# F-POKE-05 – Tutor.net (DemICE)
# Source: KIF 0.20.7 102_DemICE's Tutor.net/Tutor.net.rb (whole plugin),
#   016_UI/001_UI_PauseMenu.rb:139, :447-464 (pause entry, tmtutor_convert),
#   016_UI/015_UI_Options.rb:2785-2790 option "Tutor.net" (default On)
#   Graphics/Pictures/Tutor.net/* -> Graphics/Pictures/KIF/Tutor.net/*
#
# Pause menu "Tutor.net" (option On, not in the Bug Contest or the Elite Four
# rooms): a list of every TM you own and every move tutor you have used.
# TMs are free; a move tutor's move is unlocked for good the first time it is
# bought (P10,000 for tutors registered by pbMoveTutorChoose). SHIFT (or L/R,
# added for controllers) + a party member shows only that member's moves; ACTION (Z) shows the move's data.
# Party icons show who can learn the highlighted move.
# Moves are registered when TMs are obtained (found, received, bought) and
# when a move tutor teaches; opening Tutor.net also registers every TM in the
# Bag (KIF tmtutor_convert).
#
# 6.8.2 adaptations:
#   * The plugin is copied with KIF's settings (permanent unlock, bigger frame,
#     black party background) held in KIF::TutorNet instead of Settings.
#   * KIF replaced pbItemBall, pbReceiveItem, the Mart's addItem and
#     pbMoveTutorChoose; here they are wrapped: a TM that arrived in the Bag
#     during the call is registered (this also catches randomized TMs).
#   * Not ported: KIF's global Bitmap#draw_text / PictureOrigin overrides
#     (6.8.2 already has both) and its Pokégear entry (dead code in KIF).
#   * Bag calls use 6.8.2 names (pbQuantity / pbDeleteItem).
#===============================================================================
KIF::Options.define(:tutornet, 1, :save)

KIF::Options.add(:others, :save) {
  EnumOption.new(_INTL("Tutor.net"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.tutornet },
                 proc { |value| $PokemonSystem.tutornet = value },
                 [_INTL("Save Tutors/TMs in a handy list: OFF"),
                  _INTL("Save Tutors/TMs in a handy list: ON")])
}

module KIF
  module TutorNet
    PERMANENT_TUTOR_MOVE_UNLOCK = true
    USE_TUTOR_MOVE_ALIASES = false
    TUTOR_MOVE_ALIASES = []
    BIGGER_FRAME_STYLE = true
    BLUE_PARTY_BACKGROUND = false

    # Machine moves currently in the Bag, with quantities
    def self.bag_machines
      ret = Hash.new(0)
      return ret unless $PokemonBag
      $PokemonBag.pockets.each do |pocket|
        next unless pocket
        pocket.each do |slot|
          next unless slot.is_a?(Array)
          item = GameData::Item.try_get(slot[0]) rescue nil
          next unless item && item.is_machine? && item.move
          ret[item.move] += slot[1].to_i
        end
      end
      return ret
    end

    # Registers machine moves that arrived in the Bag during the block
    def self.watch_bag
      before = bag_machines
      ret = yield
      begin
        bag_machines.each { |move, qty| pbTutorNetAdd(move) if qty > before[move] }
      rescue => e
        KIF.log("Tutor.net registration failed: #{e.message}")
      end
      return ret
    end

    # The item is known: register its move without scanning the Bag (port –
    # KIF rescanned the whole Bag twice per purchase / received item). A
    # non-machine item still gets the full watch (randomized TM balls).
    def self.watch_item(item)
      data = GameData::Item.try_get(item) rescue nil
      return watch_bag { yield } unless data && data.is_machine?
      ret = yield
      begin
        pbTutorNetAdd(data.move) if data.move && ret   # false = the Bag refused it
      rescue => e
        KIF.log("Tutor.net registration failed: #{e.message}")
      end
      return ret
    end

    def self.open
      tmtutor_convert
      scene = PokemonTutorNet_Scene.new
      screen = PokemonTutorNetScreen.new(scene)
      screen.pbStartScreen
    end
  end
end

class Trainer
  attr_accessor :tutorlist
  attr_accessor :tutornet
  attr_accessor :tutornet_old_user
end

class Window_TutorNet < Window_DrawableCommand
  attr_reader :commands
  attr_reader :ignore_input
  
  def initialize(commands, width = nil)
    @starting = true
    @commands = []
    dims = []
    super(0, 0, 32, 32)
    getAutoDims(commands, dims, width)
    self.width = dims[0]
    self.height = dims[1]
    @commands = commands
    @partysel = false
    refresh
    @starting = false
  end 
  
  def self.newWithSize(commands, x, y, width, height, viewport = nil)
    ret = self.new(commands, width)
    ret.x = x
    ret.y = y
    ret.width = width
    ret.height = height
    ret.viewport = viewport
    return ret
  end
  
  def self.newEmpty(x, y, width, height, viewport = nil)
    ret = self.new([], width)
    ret.x = x
    ret.y = y
    ret.width = width
    ret.height = height
    ret.viewport = viewport
    return ret
  end
  
  def index=(value)
    super
    refresh if !@starting
  end
  
  def commands=(value)
    @commands = value
    @item_max = commands.length
    self.update_cursor_rect
    self.refresh
  end
  
  def move(list,index=self.index)
    return list[index]
  end
  
  def width=(value)
    super
    if !@starting
      self.index = self.index
      self.update_cursor_rect
    end
  end
  
  def height=(value)
    super
    if !@starting
      self.index = self.index
      self.update_cursor_rect
    end
  end
  
  def resizeToFit(commands, width = nil)
    dims = []
    getAutoDims(commands, dims, width)
    self.width = dims[0]
    self.height = dims[1]
  end
  
  def itemCount
    return @commands ? @commands.length : 0
  end
  
  def drawItem(index, _count, rect)
    pbSetSystemFont(self.contents) if @starting
    rect = drawCursor(index, rect)
    pbDrawShadowText(self.contents, rect.x, rect.y + ((self.contents.text_offset_y rescue 0) || 0),
      rect.width, rect.height, @commands[index], Color.new(0,0,95), Color.new(128,128,128))
  end
  
end  

#===============================================================================

class TutorNetPartyBlankPanel < SpriteWrapper
  
  def initialize(_pokemon,index,viewport=nil)
    super(viewport)
    self.x = (index % 2) * 112 + 4
    self.y = (index % 2) + 96 + 2
    @panelbgsprite = AnimatedBitmap.new("Graphics/Pictures/KIF/Tutor.net/blank")
    self.bitmap = @panelbgsprite.bitmap
  end
  
  def dispose
    super
  end
  
  def selected; return false; end
  def selected=(value); end
  def preselected; return false; end
  def preselected=(value); end
  def switching; return false; end
  def switching=(value); end
  def refresh; end
end

#===============================================================================

class TutorNetPartyPanel < SpriteWrapper
  attr_reader :pokemon
  attr_reader :selected
  
  
  def initialize(pokemon, index, viewport=nil, comp=0)
    super(viewport)
    @pokemon = pokemon
    @comp = comp
    @selmon=index
    @refreshing = true
    # Port: columns centred in the background's party panel (x 404-508);
    # KIF's 440/500 put the right column's icons past the screen edge.
    case index
    when 0,2,4
      self.x=430
    when 1,3,5
      self.x=482
    end
    case index
    when 0
      self.y=130
    when 1
      self.y=130
    when 2
      self.y=218
    when 3
      self.y=218
    when 4
      self.y=306
    when 5
      self.y=306
    end  
    @pkmnsprite = PokemonIconSprite.new(pokemon, viewport)
    @pkmnsprite.setOffset(PictureOrigin::Center)
    @pkmnsprite.z      = self.z + 1
    # Port: 48x48 / 20x28 surfaces (KIF used two full-screen bitmaps per
    # panel, 12 per scene start, which is re-run after every purchase).
    @overlaysprite = BitmapSprite.new(48, 48, viewport)
    @overlaysprite.z = self.z + 4
    @cursorsprite = BitmapSprite.new(20, 28, viewport)
    @cursorsprite.z = self.z + 6
    @compat = AnimatedBitmap.new(_INTL("Graphics/Pictures/KIF/Tutor.net/compat"))
    @monsel = AnimatedSprite.create("Graphics/Pictures/KIF/Tutor.net/moncursor", 4, 3)
    @monsel.visible= false
    @selected      = false
    @refreshBitmap = true
    @refreshing    = false
    refresh
  end
  
  def dispose
    @cursorsprite.dispose
    @pkmnsprite.dispose
    @compat.dispose
    @monsel.dispose
    @overlaysprite.bitmap.dispose
    @overlaysprite.dispose
    super
  end
  
  def x=(value)
    super
    refresh
  end
  
  def y=(value)
    super
    refresh
  end
  
  def color=(value)
    super
    refresh
  end
  
  
  def pokemon=(value)
    @pokemon = value
    @pkmnsprite.pokemon = value if @pkmnsprite && !@pkmnsprite.disposed?
    @refreshBitmap = true
    refresh
  end
  
  def selected=(value)
    if @selected != value
      @selected = value
      refresh
    end
  end
  
  def comp=(value)
    if @comp != value
      @comp = value
      refresh
    end
  end
  
  def selmon=(value)
    if @selmon != value
      @selmon = value
      refresh
    end
  end  
  
  def refresh
    return if disposed?
    return if @refreshing
    @refreshing = true    if @panelbgsprite && !@panelbgsprite.disposed?
    if @pkmnsprite && !@pkmnsprite.disposed?
      @pkmnsprite.x        = self.x
      @pkmnsprite.y        = self.y 
      @pkmnsprite.color    = self.color
      @pkmnsprite.selected = self.selected
    end
    if @monsel && !@monsel.disposed?
      @monsel.x     = self.x-20
      @monsel.y     = self.y-40
      @monsel.color = self.color
      if self.selected
        @monsel.visible=true
      else
        @monsel.visible=false
      end
    end
    if @cursorsprite && !@cursorsprite.disposed?
      @cursorsprite.x     = self.x-12
      @cursorsprite.y     = self.y-44
      @cursorsprite.color = self.color
    end
    if @overlaysprite && !@overlaysprite.disposed?
      @overlaysprite.x     = self.x-20
      @overlaysprite.y     = self.y
      @overlaysprite.color = self.color
    end
    @cursorsprite.bitmap.clear if @cursorsprite.bitmap
    baseColor   = Color.new(248, 248, 248)
    outlineColor = Color.new(0, 0, 0)
    pbSetSystemFont(@cursorsprite.bitmap)
    pbSetSmallFont(@cursorsprite.bitmap)
    if self.selected
      cursorrect = Rect.new(0, 0, 20, 28)
      @cursorsprite.bitmap.blt(0, 0, @monsel.bitmap,cursorrect)
    end
    @overlaysprite.bitmap.clear if @overlaysprite.bitmap
    baseColor   = Color.new(248, 248, 248)
    outlineColor = Color.new(0, 0, 0)
    pbSetSystemFont(@overlaysprite.bitmap)
    pbSetSmallFont(@overlaysprite.bitmap)
    if !@pokemon.egg?
      compatrect = Rect.new(0, 48 * @comp, 48, 48)
      @overlaysprite.bitmap.blt(0, 0, @compat.bitmap, compatrect)
    end
    @refreshing = false
  end
  
  def update
    super
    @pkmnsprite.update if @pkmnsprite && !@pkmnsprite.disposed?
  end
end

#===============================================================================

class PokemonTutorNet_Scene
  def pbUpdate
    pbUpdateSpriteHash(@sprites)
  end
  
  def pbStartScene(commands,party,move_list,last_move_index=0,last_mon_index=0)
    @commands = commands
    @move_list=move_list
    @last_move_index=last_move_index
    @last_mon_index=last_mon_index
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99999
    @party      = party
    @sprites = {}
    @sprites["background"] = IconSprite.new(0, 0, @viewport)
    if KIF::TutorNet::BLUE_PARTY_BACKGROUND 
      if KIF::TutorNet::BIGGER_FRAME_STYLE 
        @sprites["background"].setBitmap("Graphics/Pictures/KIF/Tutor.net/tutornetbg_bigger_frame_blue")
        @sprites["commands"] = Window_TutorNet.newWithSize(
          @commands, 22, -12, 424, 424, @viewport
        )
      else  
        @sprites["background"].setBitmap("Graphics/Pictures/KIF/Tutor.net/tutornetbg_default_blue")
        @sprites["commands"] = Window_TutorNet.newWithSize(
          @commands, -8, -12, 424, 424, @viewport
        )
      end  
    else
      if KIF::TutorNet::BIGGER_FRAME_STYLE 
        @sprites["background"].setBitmap("Graphics/Pictures/KIF/Tutor.net/tutornetbg_bigger_frame")
        @sprites["commands"] = Window_TutorNet.newWithSize(
          @commands, 22, -12, 424, 424, @viewport
        )
      else  
        @sprites["background"].setBitmap("Graphics/Pictures/KIF/Tutor.net/tutornetbg_default")
        @sprites["commands"] = Window_TutorNet.newWithSize(
          @commands, -8, -12, 424, 424, @viewport
        )
      end  
    end  
    for i in 0...Settings::MAX_PARTY_SIZE
      if @party[i]
        @sprites["pokemon#{i}"] = TutorNetPartyPanel.new(@party[i], i, @viewport)
      else
        @sprites["pokemon#{i}"] = TutorNetPartyBlankPanel.new(@party[i], i, @viewport)
      end
    end
    @sprites["commands"].viewport    = @viewport
    @sprites["commands"].windowskin = nil
    @sprites["commands"].index = @last_move_index
    update_indicators
    pbFadeInAndShow(@sprites) { pbUpdate }
  end
  
  def pbScene(noshift=false)
    ret = -1
    loop do
      Graphics.update
      Input.update
      pbUpdate
      update_indicators
      if Input.trigger?(Input::BACK)
        break
      elsif (Input.trigger?(Input::SHIFT) || Input.trigger?(Input::AUX1) || Input.trigger?(Input::AUX2)) && !noshift   # KIF port: L/R for controllers
        pbPlayCursorSE
        newcommands=[]
        newmovelist=[]
        newmoves=[]
        loop do
          monindex=pbChoosePokemon
          break if monindex < 0
          pokemon = $Trainer.party[monindex]
          if pokemon.egg?
            pbMessage(_INTL("Eggs can't be taught any moves."))
          elsif pokemon.shadowPokemon?
            pbMessage(_INTL("Shadow Pokémon can't be taught any moves."))
          else
            list=@sprites["commands"]
            for i in 0..@move_list.length
              moveindex=list.move(@move_list,i)
              if moveindex.is_a?(Array)
                movebatch=moveindex[0]
                move=movebatch[0]
                if pokemon.compatible_with_move?(move)
                  newcommands.push(@commands[i])
                  newmovelist.push(@move_list[i])
                  newmoves.push(move)
                end
              else
                newcommands[cmdTurnOff2 = newcommands.length]              = _INTL("Back")
              end 
            end  
            pbSetCommands(newcommands, 0)
            @sprites["pokemon#{monindex}"].selected = true
            Graphics.update
            Input.update
            pbUpdate
            update_indicators(newmovelist)
            return [newmovelist,monindex,newcommands,cmdTurnOff2,newmoves]
            break
          end  
        end  
      elsif Input.trigger?(Input::ACTION)
        move_info
      elsif Input.trigger?(Input::USE)
        ret = @sprites["commands"].index
        break
      end
    end
    return ret
  end
  
  def pbSetCommands(newcommands, newindex)
    @sprites["commands"].commands = (!newcommands) ? @commands : newcommands
    @sprites["commands"].index    = newindex
  end
  
  def pbEndScene
    pbFadeOutAndHide(@sprites) { pbUpdate }
    pbDisposeSpriteHash(@sprites)
    @viewport.dispose
  end
  
  def pbChangeSelection(key,currentsel)
    numsprites = @party.length - 1
    case key
    when Input::LEFT
      begin
        currentsel -= 1
      end while currentsel >= 0 && currentsel < @party.length && !@party[currentsel]
      if currentsel >= @party.length && currentsel < Settings::MAX_PARTY_SIZE
        currentsel = @party.length - 1
      end
      currentsel = numsprites if currentsel < 0 || currentsel > numsprites
    when Input::RIGHT
      begin
        currentsel += 1
      end while currentsel < @party.length && !@party[currentsel]
      currentsel = 0 if currentsel == @party.length
    when Input::UP
      if currentsel > numsprites
        currentsel -= 1
        while currentsel > 0 && currentsel < numsprites && !@party[currentsel]
          currentsel -= 1
        end 
      else
        begin
          currentsel -= 2
        end while currentsel > 0 && !@party[currentsel]
      end
      if currentsel > numsprites && currentsel < numsprites
        currentsel = numsprites
      end
      currentsel = numsprites if currentsel < 0
    when Input::DOWN
      if currentsel >= Settings::MAX_PARTY_SIZE - 1
        currentsel += 1
      else
        currentsel += 2
        currentsel = Settings::MAX_PARTY_SIZE if currentsel < Settings::MAX_PARTY_SIZE && !@party[currentsel]
      end
      if currentsel >= @party.length && currentsel < Settings::MAX_PARTY_SIZE
        currentsel = Settings::MAX_PARTY_SIZE
      elsif currentsel > numsprites
        currentsel = 0
      end
    end
    return currentsel
  end
  
  def pbChoosePokemon
    @sprites["commands"].ignore_input=true
    @activecmd = @last_mon_index
    for i in 0...Settings::MAX_PARTY_SIZE
      @sprites["pokemon#{i}"].selected = (i == @activecmd)
    end
    loop do
      Graphics.update
      Input.update
      pbUpdate
      oldsel = @activecmd
      key = -1
      key = Input::DOWN if Input.repeat?(Input::DOWN) && @party.length > 2
      key = Input::RIGHT if Input.repeat?(Input::RIGHT)
      key = Input::LEFT if Input.repeat?(Input::LEFT)
      key = Input::UP if Input.repeat?(Input::UP) && @party.length > 2
      if key >= 0 && @party.length > 1
        @activecmd = pbChangeSelection(key,@activecmd)
      end
      numsprites = Settings::MAX_PARTY_SIZE
      if @activecmd != oldsel   # Changing selection
        pbPlayCursorSE
        for i in 0...numsprites
          @sprites["pokemon#{i}"].selected = (i == @activecmd)
        end
      end
      if Input.trigger?(Input::C)
        @sprites["commands"].ignore_input=false
        return @activecmd
      elsif Input.trigger?(Input::B)
        @sprites["commands"].ignore_input=false
        for i in 0...numsprites
          @sprites["pokemon#{i}"].selected = false
        end
        pbPlayCancelSE
        return -1
      end
    end
    @sprites["commands"].ignore_input=false
  end  
  
  def move_info(move_list=@move_list)
    list=@sprites["commands"]
    moveindex = list.move(move_list)
    if moveindex.is_a?(Array)
      movebatch=moveindex[0]
      move=Pokemon::Move.new(movebatch[0])
      typename=GameData::Type.get(move.type).name
      case move.category
      when 0
        category="Physical"
      when 1
        category="Special"
      when 2 
        category="Utility"
      else
        category="???"
      end
      power=move.base_damage
      power="--" if power==0
      accuracy=move.accuracy
      accuracy="--" if accuracy==0
      info=[]
      info.push(_INTL("Type: {1}",typename))
      info.push(_INTL("Category: {1}",category))
      info.push(_INTL("Power: {1}",power))
      info.push(_INTL("Accuracy: {1}",accuracy))
      info.push(_INTL("PP: {1}",move.total_pp))
      pbMessage((_INTL"{1}",move.description),info, info.length)   
    end
  end
  
  def update_indicators(move_list=@move_list)
    list=@sprites["commands"]
    moveindex = list.move(move_list)
    # Port: runs every frame of pbScene; the party checks (compatible_with_move?
    # scans move lists) only re-run when the highlighted move or party changed.
    key = [moveindex.is_a?(Array) ? moveindex[0][0] : nil,
           $Trainer.party.map { |p| [p.species, p.egg?, p.moves.map(&:id)] }]
    return if key == @kif_last_indicator_key
    @kif_last_indicator_key = key
    if moveindex.is_a?(Array)
      movebatch=moveindex[0]
      move=movebatch[0]
      movelist = nil
      if movelist!=nil && movelist.is_a?(Array)
        for i in 0...movelist.length
          movelist[i] = GameData::Move.get(movelist[i]).id
        end
      end
      $Trainer.party.each_with_index do |pkmn, i|
        if pkmn.egg?
          @sprites["pokemon#{i}"].comp=0
        elsif pkmn.hasMove?(move)
          @sprites["pokemon#{i}"].comp=3
        else
          species = pkmn.species
          if movelist && movelist.any? { |j| j == species }
            # Checked data from movelist given in parameter
            @sprites["pokemon#{i}"].comp=1
          elsif pkmn.compatible_with_move?(move)
            # Checked data from Pokémon's tutor moves in pokemon.txt
            @sprites["pokemon#{i}"].comp=1
          else
            @sprites["pokemon#{i}"].comp=2
          end
        end
      end
    else
      $Trainer.party.each_with_index do |pkmn, i|
        @sprites["pokemon#{i}"].comp=0
      end    
    end  
  end
  
  def pbRefresh(index)
    @last_mon_index=index
  end  
  
  def pbMaintainIndex(index)
    @sprites["pokemon#{index}"].selected = true
  end
  
end

#===============================================================================

class PokemonTutorNetScreen
  def initialize(scene)
    @scene = scene
  end
  
  def pbStartScreen(movelist=[])
    commands = []
    cmdTurnOff = -1
    moveDefault=0
    realcommands = tutor_net_build_list(commands,moveDefault,movelist)
    realcommands[cmdTurnOff = realcommands.length]              = _INTL("Exit")
    @scene.pbStartScene(realcommands, $Trainer.party,commands)
    if !$Trainer.tutornet_old_user
      pbMessage(_INTL("This is your first time logging in Tutor.net! Welcome!"))
      pbMessage(_INTL("By pressing SHIFT (or L/R) and selecting a party member you can view only the moves that specific member can learn!"))
      pbMessage(_INTL("By pressing the ACTION button (default: Z) you can view information of the move the cursor currently points to."))
      $Trainer.tutornet_old_user=true
    end
    loop do
      cmd = @scene.pbScene
      if cmd.is_a?(Array)
        @scene.pbEndScene
        @scene.pbStartScene(cmd[2], $Trainer.party, cmd[0],0,cmd[1])
        @scene.pbMaintainIndex(cmd[1])
        loop do
          cmd2 = @scene.pbScene(true)
          if cmd2 < 0
            pbPlayCloseMenuSE
            break
          elsif cmd[3] >= 0 && cmd2 == cmd[3]
            pbPlayCloseMenuSE
            break
          elsif cmd2<cmd[0].length
            pbPlayCursorSE
            pbMoveTutorNetChoose(cmd[0],cmd2,false,false,false,movelist,cmd,cmd[4])
            @scene.pbMaintainIndex(cmd[1])
          else   # Exit
            pbPlayCloseMenuSE
            break
          end
        end  
        @scene.pbEndScene
        @scene.pbStartScene(realcommands, $Trainer.party,commands)
      else
        if cmd < 0
          pbPlayCloseMenuSE
          break
        elsif cmdTurnOff >= 0 && cmd == cmdTurnOff
          pbPlayCloseMenuSE
          break
        elsif cmd<realcommands.length
          pbPlayCursorSE
          pbMoveTutorNetChoose(commands,cmd,false,false,false,movelist)
        else   # Exit
          pbPlayCloseMenuSE
          break
        end
      end  
    end
    @scene.pbEndScene
  end
end

def tutor_net_build_list(commands,moveDefault,movelist,monspecificlist=nil)
  if !($Trainer.tutorlist)
    $Trainer.tutorlist=[]
  end
  for i in 0...$Trainer.tutorlist.length  
    if !$Trainer.tutorlist[i].is_a?(Array)
      makeit=[$Trainer.tutorlist[i],0]
      $Trainer.tutorlist[i]=makeit
    end
  end   
  for i in $Trainer.tutorlist
    if monspecificlist.is_a?(Array)
      next if !monspecificlist.include?(i[0])
    end  
    if i[2]!="$" && i[2]!="c"
      if i[1]>1
        currencyname=GameData::Item.get(i[2]).name_plural
      else
        currencyname=GameData::Item.get(i[2]).name
      end
      if KIF::TutorNet::USE_TUTOR_MOVE_ALIASES
        aliaslist=KIF::TutorNet::TUTOR_MOVE_ALIASES
        for j in aliaslist
          currencyname = j[1] if j[0] == i[2]
        end
      end
    end     
    if movelist.length>0
      next if !movelist.include?(i[0])
    end  
    name=GameData::Move.get(i[0]).name
    if i[1]>0
      if i[2] == "$"
        name+=" - "+"$"+i[1].to_s
      elsif i[2] == "c"
        name+=" - "+i[1].to_s+" "+"Coins"
      else  
        name+=" - "+i[1].to_s+" "+currencyname
      end  
    end  
    commands.push([i,name]) if name!=nil && name!=""
  end
  commands.sort! {|a,b| a[1]<=>b[1]}
  commands.each_with_index {|item,index|
    moveDefault=index if item[0]==0
  }
  realcommands=[]
  for command in commands
    realcommands.push(_ISPRINTF("{1:s}",command[1]))
  end
  return realcommands
end  

def pbTutorNetTutor(movelist)
  pbFadeOutIn {
    scene = PokemonTutorNet_Scene.new
    screen = PokemonTutorNetScreen.new(scene)
    screen.pbStartScreen(movelist)
  }  
end  

def pbMoveTutorNetChoose(commands, cmd, movelist = nil, bymachine = false, oneusemachine = false ,tutorlist=[],mode=[[],-1],monspecificlist=[])
  ret = false
  move = commands[cmd][0][0]
  move = GameData::Move.get(move).id
  cost = commands[cmd][0][1]
  currency = commands[cmd][0][2]
  movelist=nil
  if movelist.is_a?(Array)
    movelist.map! { |m| GameData::Move.get(m).id }
  end
  movename = GameData::Move.get(move).name
  annot = pbMoveTutorAnnotations(move, movelist)
  loop do
    chosen=mode[1]
    if chosen < 0
      chosen = @scene.pbChoosePokemon
    end
    break if chosen < 0
    pokemon = $Trainer.party[chosen]
    if pokemon.egg?
      pbMessage(_INTL("Eggs can't be taught any moves."))
    elsif pokemon.shadowPokemon?
      pbMessage(_INTL("Shadow Pokémon can't be taught any moves."))
    elsif movelist && movelist.none? { |j| j == pokemon.species }
      pbMessage(_INTL("{1} can't learn {2}.", pokemon.name, movename))
    elsif !pokemon.compatible_with_move?(move)
      pbMessage(_INTL("{1} can't learn {2}.", pokemon.name, movename))
    else
      if cost>0
        if currency == "$"
          purchase_msg = _INTL("Purchase this move for {1}{2}?\nYou currently have ${3}",currency,cost,$Trainer.money)
        elsif currency == "c"
          purchase_msg = _INTL("Purchase this move for {1} Coins?\nYou currently have {2}",cost,$Trainer.coins)
        else
          purchase_msg = _INTL("Purchase this move for {1} {2}?\nYou currently have: {3}",cost,GameData::Item.get(currency).name_plural,$PokemonBag.pbQuantity(currency))
        end  
        bought=false
        if KIF::TutorNet::PERMANENT_TUTOR_MOVE_UNLOCK
          bought = pbConfirmMessage(purchase_msg) 
        else
          bought=true
        end
        if bought
          case currency
            #######################################
            # MONEY SECTION
            #######################################
          when "$"
            if $Trainer.money>=cost
              for i in 0...$Trainer.tutorlist.length
                if $Trainer.tutorlist[i][0]==move         
                  if pbLearnMove(pokemon,move,false,false)
                    pokemon.add_first_move(move) # DemICE Move Remember
                    pbSEPlay("Slots coin",volume=80,pitch=80)
                    $Trainer.money-=cost
                    if KIF::TutorNet::PERMANENT_TUTOR_MOVE_UNLOCK 
                      cost=0
                      $Trainer.tutorlist[i][1]=0  
                      @scene.pbEndScene
                      if mode[1]<0
                        commands=[]
                        realcommands = tutor_net_build_list(commands,0,tutorlist)
                        realcommands[cmdTurnOff = realcommands.length]              = _INTL("Exit")
                      else  
                        commands=[]
                        realcommands = tutor_net_build_list(commands,0,tutorlist,monspecificlist)
                        realcommands[cmdTurnOff = realcommands.length]              = _INTL("Back")
                      end  
                      @scene.pbStartScene(realcommands, $Trainer.party, commands,cmd,chosen)
                    end  
                    @scene.pbRefresh(chosen)
                    ret=true
                    return ret if mode[1]>=0
                  else
                    break if mode[1]>=0
                  end
                end
              end
            else
              pbMessage(_INTL("You don't have enough money."))
            end
            break if mode[1]>=0
            #######################################
            # COINS SECTION
            #######################################
          when "c"
            if $Trainer.coins>=cost
              for i in 0...$Trainer.tutorlist.length
                if $Trainer.tutorlist[i][0]==move         
                  if pbLearnMove(pokemon,move,false,false)
                    pokemon.add_first_move(move) # DemICE Move Remember
                    pbSEPlay("Slots coin",volume=80,pitch=80)
                    $Trainer.coins-=cost
                    if KIF::TutorNet::PERMANENT_TUTOR_MOVE_UNLOCK 
                      cost=0
                      $Trainer.tutorlist[i][1]=0  
                      @scene.pbEndScene
                      if mode[1]<0
                        commands=[]
                        realcommands = tutor_net_build_list(commands,0,tutorlist)
                        realcommands[cmdTurnOff = realcommands.length]              = _INTL("Exit")
                      else  
                        commands=[]
                        realcommands = tutor_net_build_list(commands,0,tutorlist,monspecificlist)
                        realcommands[cmdTurnOff = realcommands.length]              = _INTL("Back")
                      end  
                      @scene.pbStartScene(realcommands, $Trainer.party, commands,cmd,chosen)
                    end  
                    @scene.pbRefresh(chosen)
                    ret=true
                    return ret if mode[1]>=0
                  else
                    break if mode[1]>=0
                  end
                end
              end
            else
              pbMessage(_INTL("You don't have enough coins."))
            end
            break if mode[1]>=0
          else
            if $PokemonBag.pbQuantity(currency)>=cost
              for i in 0...$Trainer.tutorlist.length
                if $Trainer.tutorlist[i][0]==move       
                  if pbLearnMove(pokemon,move,false,false)
                    pokemon.add_first_move(move) # DemICE Move Remember
                    pbSEPlay("Slots coin",volume=80,pitch=80)
                    $PokemonBag.pbDeleteItem(currency,cost)
                    if KIF::TutorNet::PERMANENT_TUTOR_MOVE_UNLOCK 
                      cost=0
                      $Trainer.tutorlist[i][1]=0   
                      @scene.pbEndScene
                      if mode[1]<0
                        commands=[]
                        realcommands = tutor_net_build_list(commands,0,tutorlist)
                        realcommands[cmdTurnOff = realcommands.length]              = _INTL("Exit")
                      else  
                        commands=[]
                        realcommands = tutor_net_build_list(commands,0,tutorlist,monspecificlist)
                        realcommands[cmdTurnOff = realcommands.length]              = _INTL("Back")
                      end  
                      @scene.pbStartScene(realcommands, $Trainer.party, commands,cmd,chosen)
                    end  
                    @scene.pbRefresh(chosen)
                    ret=true
                    return ret if mode[1]>=0
                  else
                    break if mode[1]>=0
                  end
                end
              end
            else
              pbMessage(_INTL("You don't have enough {1}.",GameData::Item.get(currency).name_plural))
            end    
            break if mode[1]>=0       
          end
          @scene.pbRefresh(chosen)
        else
          break if mode[1]>=0
        end
      else 
        loop do           
          if pbLearnMove(pokemon, move, false, false) 
            pokemon.add_first_move(move) # DemICE Move Remember
            @scene.pbEndScene
            if mode[1]<0
              commands=[]
              realcommands = tutor_net_build_list(commands,0,tutorlist)
              realcommands[cmdTurnOff = realcommands.length]              = _INTL("Exit")
            else  
              commands=[]
              realcommands = tutor_net_build_list(commands,0,tutorlist,monspecificlist)
              realcommands[cmdTurnOff = realcommands.length]              = _INTL("Back")
            end  
            @scene.pbStartScene(realcommands, $Trainer.party, commands,cmd,chosen)
            @scene.pbRefresh(chosen)
            ret = true
            break
          else
            break
          end
        end  
        break if mode[1]>=0
      end
    end
    @scene.pbRefresh(chosen)
  end
  return ret   # Returns whether the move was learned by a Pokemon
end

def pbTutorNetAdd(move,cost=0,currency="$")
  if !($Trainer.tutorlist)
    $Trainer.tutorlist=[]
  end
  #if !$Trainer.tutornet
    #pbMessage(_INTL("By the way are you aware of Tutor.net? It's a cellphone app where tutors have set up to make our services more accessible. Here, let me help you make an account."))
    #pbSEPlay("Voltorb flip gain coins",volume=80,pitch=80)
    #pbMessage(_INTL("All done! Just boot up the Tutor.net app from your cellphone at any time now!"))
    #!$Trainer.tutornet=true
  #end
  for i in 0...$Trainer.tutorlist.length  
    if !$Trainer.tutorlist[i].is_a?(Array)
      makeit=[$Trainer.tutorlist[i],0,"$"]
      $Trainer.tutorlist[i]=makeit
    end
  end
  found=false
  for i in 0...$Trainer.tutorlist.length
    if $Trainer.tutorlist[i][0]==move  
      found=true
      if ($Trainer.tutorlist[i][1]!=cost || $Trainer.tutorlist[i][2]!=currency) && $Trainer.tutorlist[i][1]>0 
        if cost ==0
          pbMessage(_INTL("{1} is now free on your Tutor.net account!",GameData::Move.get(move).name))
          $Trainer.tutorlist[i][1]=cost      
          $Trainer.tutorlist[i][2]=currency       
        elsif $Trainer.tutorlist[i][1]>0
          pbMessage(_INTL("{1} is already registered on your Tutor.net account with a different cost!",GameData::Move.get(move).name))
          current_cost = ""
          new_cost = ""
          if $Trainer.tutorlist[i][2]=="$"
            current_cost = _INTL("Current cost: ${1}",$Trainer.tutorlist[i][1])
          else
            current_cost = _INTL("Current cost: {1} {2}",$Trainer.tutorlist[i][1],GameData::Item.get($Trainer.tutorlist[i][2]).name_plural)
          end  
          if currency=="$"
            new_cost = _INTL("New cost: ${1}",cost)
          else
            new_cost = _INTL("New cost: {1} {2}",cost,GameData::Item.get(currency).name_plural)
          end
          cost_swap_msg = current_cost+"\n"+new_cost  
          pbMessage(cost_swap_msg)    
          if pbConfirmMessage(_INTL("Swap costs?"))
            $Trainer.tutorlist[i][1]=cost      
            $Trainer.tutorlist[i][2]=currency 
            pbMessage(_INTL("The cost for {1} has been successfully changed!",GameData::Move.get(move).name))
          else  
            pbMessage(_INTL("You decided to keep the old cost."))
          end
        end  
      end  
    end
  end 
  unlock_message = "Purchase"
  unlock_message = "Permanently unlock" if KIF::TutorNet::PERMANENT_TUTOR_MOVE_UNLOCK       
  if !found
    $Trainer.tutorlist.push([move,cost,currency])
    if $PokemonSystem.tutornet == 1
      if cost==0
        pbMessage(_INTL("{1} is now available on your Tutor.net account!",GameData::Move.get(move).name))
      else  
        pbMessage(_INTL("{1} has been added to your Tutor.net wishlist!",GameData::Move.get(move).name))
      end  
    end
    return true             
  end
  return false
end

#Change the cost and the currency of said cost of a registered move in Tutor.net
def pbTutorNetChangeMoveCost(move,cost=0,currency="$")
  for i in 0...$Trainer.tutorlist.length
    if $Trainer.tutorlist[i][0]==move       
      $Trainer.tutorlist[i][1]=cost      
      $Trainer.tutorlist[i][2]=currency 
    end
  end
end  



# KIF tmtutor_convert: register every TM in the Bag (quietly)
def tmtutor_convert
  enabled = $PokemonSystem.tutornet == 1
  $PokemonSystem.tutornet = 0 if enabled
  begin
    KIF::TutorNet.bag_machines.each_key { |move| pbTutorNetAdd(move) }
  ensure
    $PokemonSystem.tutornet = 1 if enabled
  end
end

alias kif_tn_pbItemBall pbItemBall unless defined?(kif_tn_pbItemBall)
alias kif_tn_pbReceiveItem pbReceiveItem unless defined?(kif_tn_pbReceiveItem)
alias kif_tn_pbMoveTutorChoose pbMoveTutorChoose unless defined?(kif_tn_pbMoveTutorChoose)

def pbItemBall(*args)
  return KIF::TutorNet.watch_bag { kif_tn_pbItemBall(*args) }
end

def pbReceiveItem(item, *args)
  return KIF::TutorNet.watch_item(item) { kif_tn_pbReceiveItem(item, *args) }
end

# KIF: a move tutor's move is registered at P10,000
def pbMoveTutorChoose(move, *args)
  begin
    pbTutorNetAdd(GameData::Move.get(move).id, 10000)
  rescue => e
    KIF.log("Tutor.net registration failed: #{e.message}")
  end
  return kif_tn_pbMoveTutorChoose(move, *args)
end

class PokemonMartAdapter
  alias kif_tn_addItem addItem unless method_defined?(:kif_tn_addItem)

  def addItem(item)
    return KIF::TutorNet.watch_item(item) { kif_tn_addItem(item) }
  end
end

KIF::PauseMenu.add(:kif_tutornet, "Tutor.net", icon: "menuIcons/POKENAV", order: 40,
  condition: proc { $PokemonSystem.tutornet == 1 && !pbInBugContest? },
  handler: proc { |scene|
    if KIF::PauseMenu.restricted?(KIF::PauseMenu::SHOP_RESTRICTED_MAPS)
      scene.pbHideMenu
      pbMessage(_INTL("Can't use that here."))
      next :close
    end
    pbPlayDecisionSE
    pbFadeOutIn {
      KIF::TutorNet.open
      scene.pbRefresh
    }
    :stay
  })
