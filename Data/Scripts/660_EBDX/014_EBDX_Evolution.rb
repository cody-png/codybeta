#===============================================================================
#  EBDX Evolution Scene Override
#===============================================================================
#  Ported from original EBDX Scene Evolution.rb for KIF compatibility.
#  Uses PokemonSprite instead of DynamicPokemonSprite.
#  Includes KIF kuraycustomfile handling for fusion sprites.
#===============================================================================

class PokemonEvolutionSceneEBDX
  #-----------------------------------------------------------------------------
  # main update function
  #-----------------------------------------------------------------------------
  def update(poke = true, bar = false)
    self.updateBackground
    @sprites["poke"].update if poke && @sprites["poke"] && @sprites["poke"].respond_to?(:update)
    @sprites["poke2"].update if poke && @sprites["poke2"] && @sprites["poke2"].respond_to?(:update)
    if bar
      @sprites["bar1"].y -= 8 if @sprites["bar1"] && @sprites["bar1"].y > -@viewport.height * 0.5
      @sprites["bar2"].y += 8 if @sprites["bar2"] && @sprites["bar2"].y < @viewport.height * 1.5
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
  # update for particle effects
  #-----------------------------------------------------------------------------
  def updateParticles
    for j in 0...16
      next if !@sprites["s#{j}"]
      @sprites["s#{j}"].visible = true
      if @sprites["s#{j}"].opacity == 0
        @sprites["s#{j}"].opacity = 255
        @sprites["s#{j}"].speed = 1
        @sprites["s#{j}"].x = @sprites["poke"].x
        @sprites["s#{j}"].y = @sprites["poke"].y
        x, y = randCircleCord(256)
        @sprites["s#{j}"].end_x = @sprites["poke"].x - 256 + x
        @sprites["s#{j}"].end_y = @sprites["poke"].y - 256 + y
      end
      @sprites["s#{j}"].x -= (@sprites["s#{j}"].x - @sprites["s#{j}"].end_x) * 0.01 * @sprites["s#{j}"].speed
      @sprites["s#{j}"].y -= (@sprites["s#{j}"].y - @sprites["s#{j}"].end_y) * 0.01 * @sprites["s#{j}"].speed
      @sprites["s#{j}"].opacity -= 4 * @sprites["s#{j}"].speed
    end
  end
  #-----------------------------------------------------------------------------
  # update for the light rays going out of the Pokemon
  #-----------------------------------------------------------------------------
  def updateRays(i)
    for j in 0...8
      next if !@sprites["r#{j}"]
      next if j > i / 8
      if @sprites["r#{j}"].opacity == 0
        @sprites["r#{j}"].opacity = 255
        @sprites["r#{j}"].zoom_x = 0
        @sprites["r#{j}"].zoom_y = 0
      end
      @sprites["r#{j}"].opacity -= 4
      @sprites["r#{j}"].zoom_x += 0.04
      @sprites["r#{j}"].zoom_y += 0.04
    end
  end
  #-----------------------------------------------------------------------------
  #  applies species-specific metrics
  #-----------------------------------------------------------------------------
  def applyMetrics
    @imgBg = "evobg"
    d1 = EliteBattle.get_data(@pokemon.species, :Species, :EVOBG, (@pokemon.form rescue 0)) rescue nil
    @imgBg = d1 if d1 && d1.is_a?(String)
  end
  #-----------------------------------------------------------------------------
  # initializes sprites for animation
  #-----------------------------------------------------------------------------
  def pbStartScreen(pokemon, newspecies, reversing = false)
    @path = "Graphics/EBDX/Pictures/Evolution/"
    @pokemon = pokemon
    @newspecies = newspecies
    self.applyMetrics
    @sprites = {}
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
    # message window
    @sprites["msgwindow"] = pbCreateMessageWindow(@viewport)
    @sprites["msgwindow"].visible = false
    @sprites["msgwindow"].z = 9999
    # background graphics
    @sprites["bg1"] = Sprite.new(@viewport)
    @sprites["bg1"].bitmap = pbBitmap(@path + @imgBg)
    @sprites["bg2"] = Sprite.new(@viewport)
    @sprites["bg2"].bitmap = pbBitmap(@path + "overlay")
    @sprites["bg2"].z = 5
    # background light particles
    for j in 0...6
      @sprites["l#{j}"] = Sprite.new(@viewport)
      @sprites["l#{j}"].bitmap = pbBitmap(@path + "line")
      @sprites["l#{j}"].y = (@viewport.height / 6) * j
      @sprites["l#{j}"].ox = @sprites["l#{j}"].bitmap.width / 2
      @sprites["l#{j}"].x = @viewport.width / 2
    end
    # Original Pokemon sprite - KIF: Use PokemonSprite
    @sprites["poke"] = PokemonSprite.new(@viewport)
    @sprites["poke"].setOffset(PictureOrigin::Center)
    @sprites["poke"].setPokemonBitmap(@pokemon)
    @sprites["poke"].x = @viewport.width / 2
    @sprites["poke"].y = @viewport.height / 2
    @sprites["poke"].z = 50
    # Evolved Pokemon sprite - handle KIF kuraycustomfile for fusion sprites
    if @pokemon.respond_to?(:kuraycustomfile=) && @pokemon.respond_to?(:oldkuraycustomfile=)
      begin
        @pokemon.oldkuraycustomfile = @pokemon.kuraycustomfile?
        @pokemon.kuraycustomfile = nil
        @pokemon.kuraycustomfile = kurayGetCustomSprite(GameData::Species.get(@newspecies).id_number)
      rescue
        # kuraycustomfile not available, skip
      end
    end
    @sprites["poke2"] = PokemonSprite.new(@viewport)
    @sprites["poke2"].setOffset(PictureOrigin::Center)
    @sprites["poke2"].setPokemonBitmapSpecies(@pokemon, @newspecies, false)
    @sprites["poke2"].x = @viewport.width / 2
    @sprites["poke2"].y = @viewport.height / 2
    @sprites["poke2"].z = 50
    @sprites["poke2"].zoom_x = 0
    @sprites["poke2"].zoom_y = 0
    @sprites["poke2"].tone = Tone.new(255, 255, 255)
    # Initial shine sprite
    @sprites["shine"] = Sprite.new(@viewport)
    @sprites["shine"].bitmap = pbBitmap(@path + "shine1")
    @sprites["shine"].ox = @sprites["shine"].bitmap.width / 2
    @sprites["shine"].oy = @sprites["shine"].bitmap.height / 2
    @sprites["shine"].x = @sprites["poke"].x
    @sprites["shine"].y = @sprites["poke"].y
    @sprites["shine"].zoom_x = 0
    @sprites["shine"].zoom_y = 0
    @sprites["shine"].opacity = 0
    @sprites["shine"].z = 60
    # Shine during animation
    @sprites["shine2"] = Sprite.new(@viewport)
    @sprites["shine2"].bitmap = pbBitmap(@path + "shine3")
    @sprites["shine2"].ox = @sprites["shine2"].bitmap.width / 2
    @sprites["shine2"].oy = @sprites["shine2"].bitmap.height / 2
    @sprites["shine2"].x = @sprites["poke"].x
    @sprites["shine2"].y = @sprites["poke"].y
    @sprites["shine2"].zoom_x = 0
    @sprites["shine2"].zoom_y = 0
    @sprites["shine2"].opacity = 0
    @sprites["shine2"].z = 40
    # Shine at end
    @sprites["shine3"] = Sprite.new(@viewport)
    @sprites["shine3"].bitmap = pbBitmap(@path + "shine4")
    @sprites["shine3"].ox = @sprites["shine3"].bitmap.width / 2
    @sprites["shine3"].oy = @sprites["shine3"].bitmap.height / 2
    @sprites["shine3"].x = @sprites["poke"].x
    @sprites["shine3"].y = @sprites["poke"].y
    @sprites["shine3"].zoom_x = 0.5
    @sprites["shine3"].zoom_y = 0.5
    @sprites["shine3"].opacity = 0
    @sprites["shine3"].z = 60
    # Particles
    for j in 0...16
      @sprites["s#{j}"] = Sprite.new(@viewport)
      @sprites["s#{j}"].bitmap = pbBitmap(@path + "shine2")
      @sprites["s#{j}"].ox = @sprites["s#{j}"].bitmap.width / 2
      @sprites["s#{j}"].oy = @sprites["s#{j}"].bitmap.height / 2
      @sprites["s#{j}"].x = @sprites["poke"].x
      @sprites["s#{j}"].y = @sprites["poke"].y
      @sprites["s#{j}"].z = 60
      s = rand(4) + 1
      x, y = randCircleCord(192)
      @sprites["s#{j}"].end_x = @sprites["s#{j}"].x - 192 + x
      @sprites["s#{j}"].end_y = @sprites["s#{j}"].y - 192 + y
      @sprites["s#{j}"].speed = s
      @sprites["s#{j}"].visible = false
    end
    # Light rays
    rangle = []
    for i in 0...8; rangle.push((360 / 8) * i + 15); end
    for j in 0...8
      @sprites["r#{j}"] = Sprite.new(@viewport)
      @sprites["r#{j}"].bitmap = pbBitmap(@path + "ray")
      @sprites["r#{j}"].ox = 0
      @sprites["r#{j}"].oy = @sprites["r#{j}"].bitmap.height / 2
      @sprites["r#{j}"].opacity = 0
      @sprites["r#{j}"].zoom_x = 0
      @sprites["r#{j}"].zoom_y = 0
      @sprites["r#{j}"].x = @viewport.width / 2
      @sprites["r#{j}"].y = @viewport.height / 2
      a = rand(rangle.length)
      @sprites["r#{j}"].angle = rangle[a]
      @sprites["r#{j}"].z = 60
      rangle.delete_at(a)
    end
    @viewport.color.alpha = 0
  end
  #-----------------------------------------------------------------------------
  # initial glow animation
  #-----------------------------------------------------------------------------
  def glow
    t = 0
    pbSEPlay("Anim/Ice1")
    16.times do
      Graphics.update
      self.update(false)
      @sprites["shine"].zoom_x += 0.08
      @sprites["shine"].zoom_y += 0.08
      @sprites["shine"].opacity += 16
      t += 16
      @sprites["poke"].tone = Tone.new(t, t, t)
      @sprites["bar1"].y += 3 if @sprites["bar1"]
      @sprites["bar2"].y -= 3 if @sprites["bar2"]
    end
    16.times do
      Graphics.update
      self.update(false)
      @sprites["shine"].zoom_x -= 0.02
      @sprites["shine"].zoom_y -= 0.02
      @sprites["shine"].opacity -= 16
      t -= 16
      @sprites["poke"].tone = Tone.new(t, t, t)
      @sprites["bar1"].y += 3 if @sprites["bar1"]
      @sprites["bar2"].y -= 3 if @sprites["bar2"]
      self.updateParticles
    end
  end
  #-----------------------------------------------------------------------------
  # flash animation after evolution completes or is cancelled
  #-----------------------------------------------------------------------------
  def flash(cancel)
    srt = cancel ? "poke" : "poke2"
    pbSEPlay("Flash2", 80) if !cancel
    for key in @sprites.keys
      next if ["bar1", "bar2", "bg1", "bg2", "msgwindow",
               "l0", "l1", "l2", "l3", "l4", "l5"].include?(key)
      @sprites[key].visible = false
    end
    @sprites[srt].visible = true
    @sprites[srt].zoom_x = 1
    @sprites[srt].zoom_y = 1
    @sprites[srt].tone = Tone.new(0, 0, 0)
    for i in 0...(cancel ? 32 : 64)
      Graphics.update
      @viewport.color.alpha -= cancel ? 8 : 4
      self.update(true, true)
    end
    return if cancel
    # Sparkle burst animation
    pbSEPlay("Anim/Saint6")
    for j in 0...64
      @sprites["p#{j}"] = Sprite.new(@viewport)
      n = [5, 2][rand(2)]
      @sprites["p#{j}"].bitmap = pbBitmap(@path + "shine#{n}")
      @sprites["p#{j}"].z = 10
      @sprites["p#{j}"].ox = @sprites["p#{j}"].bitmap.width / 2
      @sprites["p#{j}"].oy = @sprites["p#{j}"].bitmap.height / 2
      @sprites["p#{j}"].x = rand(@viewport.width + 1)
      @sprites["p#{j}"].y = @viewport.height / 2 + rand(@viewport.height / 2 - 64)
      z = [0.2, 0.4, 0.5, 0.6, 0.8, 1.0][rand(6)]
      @sprites["p#{j}"].zoom_x = z
      @sprites["p#{j}"].zoom_y = z
      @sprites["p#{j}"].opacity = 0
      @sprites["p#{j}"].speed = 2 + rand(5)
    end
    for i in 0...64
      Graphics.update
      self.update
      for j in 0...64
        @sprites["p#{j}"].opacity += (i < 32 ? 2 : -2) * @sprites["p#{j}"].speed
        @sprites["p#{j}"].y -= 1 if i % @sprites["p#{j}"].speed == 0
        if @sprites["p#{j}"].opacity > 128
          @sprites["p#{j}"].zoom_x /= 1.5
          @sprites["p#{j}"].zoom_y /= 1.5
        end
      end
    end
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
  # main evolution animation sequence
  #-----------------------------------------------------------------------------
  def pbEvolution(cancancel = true)
    # Stop BGM and open cinema bars
    pbBGMStop()
    16.times do
      Graphics.update
      self.update
      @sprites["bar1"].y -= @sprites["bar1"].bitmap.height / 16
      @sprites["bar2"].y += @sprites["bar2"].bitmap.height / 16
    end
    pbMEPlay("EBDX/Evolution Start")
    @sprites["msgwindow"].visible = true
    pbMessageDisplay(@sprites["msgwindow"],
      _INTL("\\se[]What?\r\n{1} is evolving!\\^", @pokemon.name)) { self.update }
    pbMessageWaitForInput(@sprites["msgwindow"], 100, true) { self.update }
    @sprites["msgwindow"].visible = false
    # Play Pokemon's cry
    GameData::Species.play_cry(@pokemon) rescue nil
    frames = GameData::Species.cry_length(@pokemon.species, @pokemon.form) rescue 30
    frames.times { Graphics.update; self.update }
    pbBGMPlay("EBDX/Evolution")
    canceled = false
    # Beginning glow effect
    self.glow
    k1 = 1 # zoom factor for the Pokemon
    k2 = 1 # zoom factor for the shine
    s = 1  # speed of the animation
    @viewport.color = Color.new(255, 255, 255, 0)
    pbSEPlay("Anim/Ice1") rescue nil
    # Main animation loop - 256 frames of accelerating oscillation
    for i in 0...256
      k1 *= -1 if i % (32 / s) == 0
      k2 *= -1 if i % 16 == 0
      s *= 2 if i % 64 == 0 && i > 0 && s < 8
      Graphics.update
      Input.update
      self.update(false)
      self.updateParticles
      self.updateRays(i)
      @sprites["poke"].zoom_x += 0.03125 * k1 * s
      @sprites["poke"].zoom_y += 0.03125 * k1 * s
      @sprites["poke"].tone.red += 16
      @sprites["poke"].tone.green += 16
      @sprites["poke"].tone.blue += 16
      @sprites["poke2"].zoom_x -= 0.03125 * k1 * s
      @sprites["poke2"].zoom_y -= 0.03125 * k1 * s
      if @sprites["shine2"].opacity < 255
        @sprites["shine2"].opacity += 16
        @sprites["shine2"].zoom_x += 0.08
        @sprites["shine2"].zoom_y += 0.08
      else
        @sprites["shine2"].zoom_x += 0.01 * k2
        @sprites["shine2"].zoom_y += 0.01 * k2
        @sprites["shine2"].tone.red += 0.5
        @sprites["shine2"].tone.green += 0.5
        @sprites["shine2"].tone.blue += 0.5
      end
      if i >= 240
        @sprites["shine3"].opacity += 16
        @sprites["shine3"].zoom_x += 0.1
        @sprites["shine3"].zoom_y += 0.1
      end
      @viewport.color.alpha += 32 if i >= 248
      if Input.trigger?(Input::BACK) && cancancel
        pbBGMStop()
        canceled = true
        break
      end
    end
    @viewport.color = Color.white
    self.flash(canceled)
    if canceled
      # Evolution was cancelled
      @sprites["msgwindow"].visible = true
      pbMessageDisplay(@sprites["msgwindow"],
        _INTL("Huh?\r\n{1} stopped evolving!", @pokemon.name)) { self.update }
      # Restore KIF kuraycustomfile if cancelled
      begin
        if @pokemon.respond_to?(:kuraycustomfile=) && @pokemon.respond_to?(:oldkuraycustomfile?)
          @pokemon.kuraycustomfile = @pokemon.oldkuraycustomfile?
          @pokemon.oldkuraycustomfile = nil
        end
      rescue; end
    else
      # Evolution succeeded
      self.createEvolved
    end
  end
  #-----------------------------------------------------------------------------
  # creates the evolved Pokemon and handles post-evolution logic
  #-----------------------------------------------------------------------------
  def createEvolved
    # Play evolved Pokemon's cry
    frames = GameData::Species.cry_length(@newspecies, @pokemon.form) rescue 30
    pbBGMStop()
    GameData::Species.play_cry_from_species(@newspecies) rescue nil
    frames.times do
      Graphics.update
      self.update
    end
    pbMEPlay("EBDX/Capture Success")
    pbBGMPlay("EBDX/Victory Against Wild")
    # Get species names
    newspeciesname = GameData::Species.get(@newspecies).real_name
    oldspeciesname = GameData::Species.get(@pokemon.species).real_name
    @sprites["msgwindow"].visible = true
    pbMessageDisplay(@sprites["msgwindow"],
      _INTL("\\se[]Congratulations! Your {1} evolved into {2}!\\wt[80]",
        @pokemon.name, newspeciesname)) { self.update }
    @sprites["msgwindow"].text = ""
    # Check for consumed item and duplication
    pbEvolutionMethodAfterEvolution rescue nil
    # Handle KIF kuraycustomfile for fusion sprites
    begin
      if @pokemon.respond_to?(:kuraycustomfile) && @pokemon.respond_to?(:oldkuraycustomfile)
        if @pokemon.oldkuraycustomfile == @pokemon.kuraycustomfile
          @pokemon.kuraycustomfile = nil
        end
      end
    rescue; end
    # Modify Pokemon to evolved species
    @pokemon.species = @newspecies
    @pokemon.name    = newspeciesname if @pokemon.name == oldspeciesname
    @pokemon.form    = 0 if @pokemon.isSpecies?(:MOTHIM)
    @pokemon.calc_stats
    # Clean up KIF kuraycustomfile
    begin
      @pokemon.oldkuraycustomfile = nil if @pokemon.respond_to?(:oldkuraycustomfile=)
    rescue; end
    # Register in Pokedex
    if $Trainer && $Trainer.pokedex
      if !$Trainer.pokedex.owned?(@newspecies)
        $Trainer.pokedex.register(@pokemon)
        $Trainer.pokedex.set_owned(@newspecies)
        pbMessageDisplay(@sprites["msgwindow"],
          _INTL("{1}'s data was added to the Pokédex", newspeciesname)) { self.update }
      end
      # KIF: register unfused Pokemon if applicable
      if $Trainer.pokedex.respond_to?(:register_unfused_pkmn)
        begin
          $Trainer.pokedex.register_unfused_pkmn(@pokemon).each do |unfused|
            unfused_name = GameData::Species.get(unfused).name rescue "???"
            pbMessageDisplay(@sprites["msgwindow"],
              _INTL("{1}'s data was added to the Pokédex", unfused_name)) { self.update }
          end
        rescue; end
      end
    end
    # Learn moves upon evolution
    movelist = @pokemon.getMoveList
    for i in movelist
      next if i[0] != 0 && i[0] != @pokemon.level  # 0 = learn upon evolution
      pbLearnMove(@pokemon, i[1], true) { self.update }
    end
  end
  #-----------------------------------------------------------------------------
  # close animation sequence
  #-----------------------------------------------------------------------------
  def pbEndScreen
    $game_temp.message_window_showing = false if $game_temp
    @viewport.color = Color.new(0, 0, 0, 0)
    16.times do
      Graphics.update
      self.update
      @viewport.color.alpha += 16
    end
    pbDisposeSpriteHash(@sprites)
    16.times do
      @viewport.color.alpha -= 16
      Graphics.update
    end
    @viewport.dispose
  end
  #-----------------------------------------------------------------------------
  def pbEvolutionMethodAfterEvolution
    @pokemon.action_after_evolution(@newspecies) rescue nil
  end
  #-----------------------------------------------------------------------------
end

#===============================================================================
#  Override PokemonEvolutionScene.new to use EBDX version when toggle is on
#===============================================================================
if defined?(PokemonEvolutionScene)
  class << PokemonEvolutionScene
    alias ebdx_original_new new unless method_defined?(:ebdx_original_new)
    def new(*args)
      if EBDXToggle.enabled?
        return PokemonEvolutionSceneEBDX.new(*args)
      else
        return ebdx_original_new(*args)
      end
    end
  end
end
