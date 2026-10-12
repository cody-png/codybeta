#===============================================================================
#  EBDX Egg Hatching Scene Override
#===============================================================================
#  Ported from original EBDX Scene Hatching.rb for KIF compatibility.
#  Uses PokemonSprite instead of DynamicPokemonSprite.
#  Crack overlay displayed as separate sprite instead of blt onto egg bitmap.
#===============================================================================

class PokemonEggHatchSceneEBDX
  #-----------------------------------------------------------------------------
  # main update function
  #-----------------------------------------------------------------------------
  def update
    self.updateBackground
    @sprites["poke"].update if @sprites["poke"] && @sprites["poke"].respond_to?(:update)
    # Update crack overlay
    if @cracks && @frame < 5 && @sprites["crackspr"]
      @sprites["crackspr"].bitmap = @cracks.bitmap
    end
  end
  #-----------------------------------------------------------------------------
  # background update function - animated light lines
  #-----------------------------------------------------------------------------
  def updateBackground
    for j in 0...6
      next if !@sprites["l#{j}"]
      @sprites["l#{j}"].y = @viewport.height if @sprites["l#{j}"].y <= 0
      t = (@sprites["l#{j}"].y.to_f / @viewport.height) * 255
      @sprites["l#{j}"].tone = Tone.new(t, t, t)
      z = ((@sprites["l#{j}"].y.to_f - @viewport.height / 2) / (@viewport.height / 2)) * 1.0
      @sprites["l#{j}"].angle = (z < 0) ? 180 : 0
      @sprites["l#{j}"].zoom_y = z.abs
      @sprites["l#{j}"].y -= 2
    end
  end
  #-----------------------------------------------------------------------------
  # advancing the crack frames
  #-----------------------------------------------------------------------------
  def advance
    @frame += 1
    2.times { @cracks.update } if @cracks
  end
  #-----------------------------------------------------------------------------
  #  applies species-specific metrics
  #-----------------------------------------------------------------------------
  def applyMetrics
    @imgBg = "hatchbg"
    d1 = EliteBattle.get_data(@pokemon.species, :Species, :HATCHBG, (@pokemon.form rescue 0)) rescue nil
    @imgBg = d1 if d1 && d1.is_a?(String)
  end
  #-----------------------------------------------------------------------------
  # initializes sprites for animation
  #-----------------------------------------------------------------------------
  def pbStartScene(pokemon)
    @path = "Graphics/EBDX/Pictures/Hatching/"
    @frame = 0
    @sprites = {}
    @pokemon = pokemon
    self.applyMetrics
    @nicknamed = false
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99999
    @viewport.color = Color.new(0, 0, 0, 0)
    # initial fading transition
    16.times do
      @viewport.color.alpha += 16
      pbWait(1)
    end
    # cinema bars
    @sprites["bar1"] = Sprite.new(@viewport)
    @sprites["bar1"].create_rect(@viewport.width, @viewport.height / 2, Color.black)
    @sprites["bar1"].z = 99999
    @sprites["bar2"] = Sprite.new(@viewport)
    @sprites["bar2"].create_rect(@viewport.width, @viewport.height / 2, Color.black)
    @sprites["bar2"].y = @viewport.height / 2
    @sprites["bar2"].z = 99999
    # background graphics
    @sprites["bg1"] = Sprite.new(@viewport)
    @sprites["bg1"].bitmap = pbBitmap(@path + @imgBg)
    @sprites["bg2"] = Sprite.new(@viewport)
    @sprites["bg2"].bitmap = pbBitmap(@path + "overlay")
    @sprites["bg2"].z = 5
    # message window
    @sprites["msgwindow"] = pbCreateMessageWindow(@viewport)
    @sprites["msgwindow"].visible = false
    @sprites["msgwindow"].z = 9999
    # background light particles
    for j in 0...6
      @sprites["l#{j}"] = Sprite.new(@viewport)
      @sprites["l#{j}"].bitmap = pbBitmap(@path + "line")
      @sprites["l#{j}"].y = (@viewport.height / 6) * j
      @sprites["l#{j}"].ox = @sprites["l#{j}"].bitmap.width / 2
      @sprites["l#{j}"].x = @viewport.width / 2
    end
    # Egg sprite - KIF: Use PokemonSprite instead of DynamicPokemonSprite
    @pokemon.steps_to_hatch = 1
    @sprites["poke"] = PokemonSprite.new(@viewport)
    @sprites["poke"].setOffset(PictureOrigin::Bottom)
    @sprites["poke"].setPokemonBitmap(@pokemon) # Shows egg (steps_to_hatch > 0)
    @sprites["poke"].z = 50
    @sprites["poke"].x = @viewport.width / 2
    @sprites["poke"].y = @viewport.height / 2 + (@sprites["poke"].bitmap ? @sprites["poke"].bitmap.height * 0.5 : 32)
    # Egg crack overlay sprite (separate from egg, positioned on top)
    crackfilename = sprintf("Graphics/EBDX/Battlers/Eggs/%scracks", @pokemon.species) rescue nil
    if !pbResolveBitmap(crackfilename)
      crackfilename = sprintf("Graphics/EBDX/Battlers/Eggs/%03dcracks",
        GameData::Species.get(@pokemon.species).id_number)
      if !pbResolveBitmap(crackfilename)
        crackfilename = sprintf("Graphics/EBDX/Battlers/Eggs/000cracks")
      end
    end
    @cracks = BitmapEBDX.new(crackfilename)
    @sprites["crackspr"] = Sprite.new(@viewport)
    @sprites["crackspr"].z = 51
    if @cracks && @cracks.bitmap && @sprites["poke"].bitmap
      @sprites["crackspr"].ox = @cracks.bitmap.width / 2
      @sprites["crackspr"].oy = @cracks.bitmap.height / 2
      @sprites["crackspr"].x = @sprites["poke"].x
      @sprites["crackspr"].y = @sprites["poke"].y - (@sprites["poke"].bitmap.height / 2)
    end
    @sprites["crackspr"].visible = true
    @pokemon.steps_to_hatch = 0
    @viewport.color.alpha = 0
    # white flash rect
    @sprites["rect"] = Sprite.new(@viewport)
    @sprites["rect"].create_rect(@viewport.width, @viewport.height, Color.white)
    @sprites["rect"].opacity = 0
    @sprites["rect"].z = 100
  end
  #-----------------------------------------------------------------------------
  # main animation sequence
  #-----------------------------------------------------------------------------
  def pbMain(eggindex = 0)
    # Stop BGM and play evolution start jingle
    pbBGMStop()
    pbMEPlay("EBDX/Evolution Start")
    # Cinema bars open
    16.times do
      Graphics.update
      self.update
      @sprites["bar1"].y -= @sprites["bar1"].bitmap.height / 16
      @sprites["bar2"].y += @sprites["bar2"].bitmap.height / 16
    end
    pbBGMPlay("EBDX/Evolution")
    self.wait(32)
    # Egg bounce animation
    2.times do
      3.times do
        @sprites["poke"].zoom_y += 0.04
        wait
      end
      for i in 0...6
        @sprites["poke"].y -= 6 * (i < 3 ? 1 : -1)
        @sprites["crackspr"].y -= 6 * (i < 3 ? 1 : -1) if @sprites["crackspr"]
        wait
      end
      for i in 0...6
        @sprites["poke"].zoom_y -= 0.04 * (i < 3 ? 2 : -1)
        @sprites["poke"].y -= 2 if i >= 3
        @sprites["crackspr"].y -= 2 if i >= 3 && @sprites["crackspr"]
        wait
      end
      3.times do
        @sprites["poke"].y += 2
        @sprites["crackspr"].y += 2 if @sprites["crackspr"]
        wait
      end
      self.advance
      pbSEPlay("EBDX/Anim/ice2", 80)
      self.wait(24)
    end
    # Egg shake animation
    m = 16; n = 2; k = -1
    for j in 0...3
      self.advance if j < 2
      pbSEPlay("EBDX/Anim/ice2", 80) if j < 2
      for i in 0...m
        k *= -1 if i % n == 0
        @sprites["poke"].x += k * 4
        @sprites["crackspr"].x += k * 4 if @sprites["crackspr"]
        @sprites["rect"].opacity += 64 if j == 2 && i >= (m - 5)
        wait
      end
      k = j < 1 ? 1.5 : 2
      n = 3
      m = 42
      self.wait(24) if j < 1
    end
    # Egg burst - swap to hatched Pokemon sprite
    self.advance
    @sprites["crackspr"].visible = false if @sprites["crackspr"]
    pbSEPlay("Battle recall")
    @sprites["poke"].setPokemonBitmap(@pokemon) # Now shows Pokemon (steps_to_hatch == 0)
    @sprites["poke"].setOffset(PictureOrigin::Bottom)
    @sprites["poke"].x = @viewport.width / 2
    @sprites["poke"].y = @viewport.height / 2 + (@sprites["poke"].bitmap ? @sprites["poke"].bitmap.height * 0.5 : 32)
    # Ring shine effect
    @sprites["ring"] = Sprite.new(@viewport)
    @sprites["ring"].z = 200
    @sprites["ring"].bitmap = pbBitmap(@path + "shine7")
    @sprites["ring"].ox = @sprites["ring"].bitmap.width / 2
    @sprites["ring"].oy = @sprites["ring"].bitmap.height / 2
    @sprites["ring"].color = Color.new(32, 92, 42)
    @sprites["ring"].opacity = 0
    @sprites["ring"].x = @viewport.width / 2
    @sprites["ring"].y = @viewport.height / 2
    # Sparkle particles
    for j in 0...16
      @sprites["s#{j}"] = Sprite.new(@viewport)
      @sprites["s#{j}"].z = 200
      @sprites["s#{j}"].bitmap = pbBitmap(@path + "shine6")
      @sprites["s#{j}"].ox = @sprites["s#{j}"].bitmap.width / 2
      @sprites["s#{j}"].oy = @sprites["s#{j}"].bitmap.height / 2
      @sprites["s#{j}"].color = Color.new(232, 92, 42)
      @sprites["s#{j}"].x = @viewport.width / 2
      @sprites["s#{j}"].y = @viewport.height / 2
      @sprites["s#{j}"].opacity = 0
      r = 96 + rand(64)
      x, y = randCircleCord(r)
      @sprites["s#{j}"].end_x = @sprites["s#{j}"].x - r + x
      @sprites["s#{j}"].end_y = @sprites["s#{j}"].y - r + y - 32
      z = 1 - rand(20) * 0.01
      @sprites["s#{j}"].zoom_x = z
      @sprites["s#{j}"].zoom_y = z
    end
    16.times do
      for j in 0...16
        @sprites["s#{j}"].x -= (@sprites["s#{j}"].x - @sprites["s#{j}"].end_x) * 0.05
        @sprites["s#{j}"].y -= (@sprites["s#{j}"].y - @sprites["s#{j}"].end_y) * 0.05
        @sprites["s#{j}"].color.alpha -= 16
        @sprites["s#{j}"].opacity += 32
      end
      @sprites["ring"].color.alpha -= 16
      @sprites["ring"].opacity += 32
      @sprites["ring"].zoom_x += 0.5
      @sprites["ring"].zoom_y += 0.5
      wait
    end
    for i in 0...48
      for j in 0...16
        @sprites["s#{j}"].x -= (@sprites["s#{j}"].x - @sprites["s#{j}"].end_x) * 0.05
        @sprites["s#{j}"].y -= (@sprites["s#{j}"].y - @sprites["s#{j}"].end_y) * 0.05
        @sprites["s#{j}"].end_y += 2
        @sprites["s#{j}"].zoom_x -= 0.01
        @sprites["s#{j}"].zoom_y -= 0.01
        @sprites["s#{j}"].opacity -= 16 if i >= 32
      end
      @sprites["ring"].zoom_x += 0.5
      @sprites["ring"].zoom_y += 0.5
      @sprites["ring"].opacity -= 32
      wait
    end
    16.times do
      @sprites["rect"].opacity -= 16
      wait
    end
    self.wait(32)
    # Pokemon cry and success
    frames = GameData::Species.cry_length(@pokemon.species, @pokemon.form) rescue 30
    pbBGMStop()
    GameData::Species.play_cry(@pokemon) rescue nil
    frames.times do
      Graphics.update
      self.update
    end
    pbMEPlay("EBDX/Capture Success")
    pbBGMPlay("EBDX/Victory Against Wild")
    @sprites["msgwindow"].visible = true
    cmd = [_INTL("Yes"), _INTL("No")]
    pbMessageDisplay(@sprites["msgwindow"],
      _INTL("\\se[]{1} hatched from the Egg!\\wt[80]", @pokemon.name)) { self.update }
    pbMessageDisplay(@sprites["msgwindow"],
      _INTL("Would you like to nickname the newly hatched {1}?", @pokemon.name)) { self.update }
    if pbShowCommands(@sprites["msgwindow"], cmd, 1, 0) { self.update } == 0
      nickname = pbEnterPokemonName(_INTL("{1}'s nickname?", @pokemon.name),
        0, Pokemon::MAX_NAME_SIZE, "", @pokemon, true)
      @pokemon.name = nickname if nickname != ""
      @nicknamed = true
    end
    @sprites["msgwindow"].text = ""
    @sprites["msgwindow"].visible = false
  end
  #-----------------------------------------------------------------------------
  # frame wait function
  #-----------------------------------------------------------------------------
  def wait(frames = 1)
    frames.times do
      Graphics.update
      self.update
    end
  end
  #-----------------------------------------------------------------------------
  # close animation sequence
  #-----------------------------------------------------------------------------
  def pbEndScene
    $game_temp.message_window_showing = false if $game_temp
    16.times do
      @viewport.color.alpha += 16
      wait
    end
    pbDisposeSpriteHash(@sprites)
    @cracks.dispose if @cracks && !@cracks.disposed?
    16.times do
      @viewport.color.alpha -= 16
      pbWait(1)
    end
    @viewport.dispose
  end
  #-----------------------------------------------------------------------------
end

#===============================================================================
#  Override PokemonEggHatch_Scene.new to use EBDX version when toggle is on
#===============================================================================
if defined?(PokemonEggHatch_Scene)
  class << PokemonEggHatch_Scene
    alias ebdx_original_new new unless method_defined?(:ebdx_original_new)
    def new(*args)
      if EBDXToggle.enabled?
        return PokemonEggHatchSceneEBDX.new(*args)
      else
        return ebdx_original_new(*args)
      end
    end
  end
end
