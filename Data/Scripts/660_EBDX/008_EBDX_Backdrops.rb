#===============================================================================
# EBDX Backdrops - Adapted from Elite Battle DX "Scene Backdrops.rb"
# Contains BattleSceneRoom class, EliteBattle backdrop methods, and
# PokeBattle_Scene backdrop loading methods wrapped in EBDXBackdropMethods.
#===============================================================================

#===============================================================================
# Module containing PokeBattle_Scene backdrop methods for mixin
#===============================================================================
module EBDXBackdropMethods
  #-----------------------------------------------------------------------------
  # function to set up the battle room based on battle environment and terrain
  #-----------------------------------------------------------------------------
  def loadBackdrop
    data = EliteBattle.getNextBattleEnv(@battle)
    # applies predefined battle backdrops for Trainer or Pokemon
    if @battle.opponent
      bgdrop = EliteBattle.get_trainer_data(@battle.opponent[0].trainer_type, :BACKDROP, @battle.opponent[0])
    else
      bgdrop = EliteBattle.get_data(@battle.pbParty(1)[0].species, :Species, :BACKDROP, (@battle.pbParty(1)[0].form rescue 0))
    end
    backdrop = bgdrop.clone if !bgdrop.nil?
    # applies global backdrop if cached
    if EliteBattle.get(:nextBattleBack)
      data = EliteBattle.get(:nextBattleBack) if EliteBattle.get(:nextBattleBack).is_a?(Hash)
      data = { "backdrop" => EliteBattle.get(:nextBattleBack) } if EliteBattle.get(:nextBattleBack).is_a?(String)
      data = getConst(EnvironmentEBDX, EliteBattle.get(:nextBattleBack)) if EliteBattle.get(:nextBattleBack).is_a?(Symbol)
    elsif !backdrop.nil?
      data = backdrop.clone
    end
    # adds daylight adjustment if outdoor
    data["outdoor"] = true if !data.has_key?("outdoor") && EliteBattle.outdoor_map? && Settings::TIME_SHADING
    # Apply graphics
    @sprites["battlebg"] = BattleSceneRoom.new(@viewport, self, data)
    # special trainer intro graphic
    @sprites["trainer_Anim"] = ScrollingSprite.new(@viewport)
    # tries to resolve the bitmap before assigning it
    begin
      base = pbResolveBitmap("Graphics/EBDX/Transitions/Common/#{base}") ? base : "outdoor"
    rescue
      base = "outdoor"
    end
    # check if there is an assigned background for the trainer intro
    if @battle.opponent
      begin
        try = sprintf("%03d", GameData::TrainerType.get(@battle.opponent[0].trainer_type).id_number)
        base = try if pbResolveBitmap("Graphics/EBDX/Transitions/Common/#{try}")
      rescue
        # keep current base if lookup fails
      end
    end
    begin
      @sprites["trainer_Anim"].setBitmap("Graphics/EBDX/Transitions/Common/#{base}")
    rescue
      # skip if bitmap not found
    end
    @sprites["trainer_Anim"].direction = -1
    @sprites["trainer_Anim"].speed = 48
    # Only show trainer_Anim for trainer battles with minorAnimation enabled
    # Wild battles (@battle.opponent is nil) should NEVER show this
    @sprites["trainer_Anim"].visible = @battle.opponent && !@smTrainerSequence && @minorAnimation
    @sprites["trainer_Anim"].z = 97
    @sprites["trainer_Anim"].opacity = 0 if !@sprites["trainer_Anim"].visible  # Extra safety
  end
  #-----------------------------------------------------------------------------
end

#===============================================================================
module EliteBattle
  #-----------------------------------------------------------------------------
  # returns a data hash of the next (potentially generated) battle environment
  #-----------------------------------------------------------------------------
  def self.getNextBattleEnv(battle = nil)
    battleRules = $PokemonTemp.battleRules
    if !battleRules["environment"].nil?
      environ = battleRules["environment"]
    elsif !battle.nil? && battle.respond_to?(:environment) && !battle.environment.nil?
      environ = battle.environment
    else
      environ = pbGetEnvironment
    end
    terrain = $game_player.terrain_tag.id
    # base battle scene room data
    # load basic room
    const = (EliteBattle.outdoor_map? ? :OUTDOOR : :INDOOR)
    try = EnvironmentEBDX.const_defined?(const) ? EnvironmentEBDX.const_get(const) : nil
    data = try.clone if !try.nil?
    # applies predefined battle backdrop for map
    try = EliteBattle.get_map_data(:BACKDROP)
    data = try.clone if !try.nil?
    # applies room data for specific environment if defined
    unless [0, 1].include?(environ)
      try = EliteBattle.get_data(environ, :Environment, :BACKDROP)
      if try.nil?
        # fallback: map environment symbols directly to EnvironmentEBDX constants
        # so water/cave/forest scenes work even if add_data registration didn't run
        ebdx_sym = case environ
                   when :MovingWater, :StillWater then :WATER
                   when :Cave, :Rock              then :CAVE
                   when :Forest, :ForestGrass     then :FOREST
                   when :Sand, :Volcano           then :SAND
                   when :Snow, :Ice               then :SNOW
                   when :Sky                      then :SKY
                   when :Underwater               then :UNDERWATER
                   when :Puddle                   then :PUDDLE
                   end
        try = EnvironmentEBDX.const_get(ebdx_sym) if ebdx_sym && EnvironmentEBDX.const_defined?(ebdx_sym)
      end
      data = try.clone if !try.nil?
    end
    # check for fails
    data = {} if data.nil?
    # applies additional terrain data
    try = EliteBattle.get_data(terrain, :TerrainTag, :BACKDROP)
    if !try.nil?
      for key in try.keys
        data[key] = try[key]
      end
    end
    # applies conditional environment/terrain data
    processes = EliteBattle.get(:procData)
    for key in processes.keys
      if key.call(terrain, environ)
        for k in processes[key][:BACKDROP].keys
          data[k] = processes[key][:BACKDROP][k]
        end
      end
    end
    # pushes trees up a little to accomodate base
    if data.has_key?("trees") && data.has_key?("base")
      data["trees"][:y] = [108,117,118,122,122,127,127,128,132]
    end
    # cuts down on grass if in double battle
    if data.has_key?("tallGrass") && !battle.nil? && (battle.doublebattle? || battle.triplebattle?)
      data["tallGrass"][:elements] = 5 if data["tallGrass"][:elements] > 5
    end
    return data.nil? ? {} : data
  end
  #-----------------------------------------------------------------------------
end

#===============================================================================
# custom class to compose and animate the battle background
#===============================================================================
class BattleSceneRoom
  attr_reader :data, :sprites
  attr_accessor :dynamax
  #-----------------------------------------------------------------------------
  # class constructor
  #-----------------------------------------------------------------------------
  def initialize(viewport, scene, data)
    @viewport = viewport
    @scene = scene
    @battle = @scene.battle
    @doublebattle = @battle.doublebattle? rescue false
    @sprites = {}
    @fpIndex = 0
    @wind = 90
    @wWait = 0
    @toggle = 0.5
    @disposed = false
    @strongwind = false
    @dynamax = false
    @weather = nil
    @focused = true
    @queued = nil
    @data = data || {}
    @backup = @data.clone
    @defaultvector = EliteBattle.get_vector(:MAIN, @battle)
    @sunny = false
    @scale = 1.0
    @daylightTone = Tone.new(0, 0, 0)  # Initialize - will be set properly by daylightTint()
    @daylightApplied = false
    # draws elements based on data
    self.refresh(@data)
  end
  #-----------------------------------------------------------------------------
  # applies data hash to object
  #-----------------------------------------------------------------------------
  def refresh(*args)
    unless args[0].is_a?(Hash)
      @sprites[args[0]] = args[1] if args[0].is_a?(String) && args.length > 1
      return
    end
    @data = args[0] || {} if args[0]
    @fpIndex = 0
    # disposes sprites if they exist
    pbDisposeSpriteHash(@sprites)
    # CRITICAL FIX: Calculate sx, sy using @defaultvector (MAIN) directly
    # NOT @scene.vector.spoof() which may be ENEMY vector at init time
    # This ensures battler positions are calculated for MAIN vector from the start
    if @defaultvector && @defaultvector.length >= 4
      angle_rad = @defaultvector[2] * (Math::PI / 180)
      sx = @defaultvector[0] + Math.cos(angle_rad) * @defaultvector[3]
      sy = @defaultvector[1] - Math.sin(angle_rad) * @defaultvector[3]
    else
      sx, sy = @scene.vector.spoof(@defaultvector) rescue [0, 0]
    end
    # void sprite - oversized to ensure full coverage during camera zoom
    @sprites["void"] = Sprite.new(@viewport)
    @sprites["void"].z = -10
    voidWidth = (@viewport.width * 2.5).to_i
    voidHeight = (@viewport.height * 2.5).to_i
    @sprites["void"].bitmap = Bitmap.new(voidWidth, voidHeight)
    @sprites["void"].ox = voidWidth / 2
    @sprites["void"].oy = voidHeight / 2
    @sprites["void"].x = @viewport.width / 2
    @sprites["void"].y = @viewport.height / 2
    # draws backdrop
    @sprites["bg"] = Sprite.new(@viewport)
    @sprites["bg"].z = 0
    @sprites["bg"].bitmap = Bitmap.new(@viewport.width, @viewport.height) # default empty bitmap
    # draws base
    @baseBmp = nil
    # draws elements from data block (prority added to predefined modules)
    return if @data.nil? || !@data.is_a?(Hash)
    for key in ["backdrop", "base", "water", "spinningLights", "outdoor", "sky", "trees", "tallGrass", "spinLights",
               "lightsA", "lightsB", "lightsC", "vacuum", "bubbles", "snowParticles"] # to sort the order
      next if !@data.has_key?(key)
      case key
      when "backdrop" # adds custom background image
        begin
          path = pbResolveBitmap(@data["backdrop"]) ? @data["backdrop"] : "Graphics/EBDX/Battlebacks/battlebg/" + @data["backdrop"]
          tbmp = pbBitmap(path)
          @sprites["bg"].bitmap = Bitmap.new(tbmp.width, tbmp.height)
          @sprites["bg"].bitmap.blt(0, 0, tbmp, tbmp.rect)
          tbmp.dispose
        rescue
          @sprites["bg"].bitmap = Bitmap.new(@viewport.width, @viewport.height)
        end
      when "base" # blt base onto backdrop
        begin
          str = pbResolveBitmap(@data["base"]) ? @data["base"] : "Graphics/EBDX/Battlebacks/base/" + @data["base"]
          @baseBmp = pbBitmap(str) if str
        rescue
          @baseBmp = nil
        end
      when "sky" # adds dynamic sky to scene
        self.drawSky
      when "trees" # adds array of trees to scene
        self.drawTrees
      when "tallGrass" # adds array of tall grass to scene
        self.drawGrass
      when "spinLights" # adds PWT styled spinning base lights
        self.drawSpinLights
      when "lightsA" # adds PWT styled stage lights
        self.drawLightsA
      when "lightsB" # adds disco styled stage lights
        self.drawLightsB
      when "lightsC" # adds ambiental scene lights
        self.drawLightsC
      when "water" # adds water animation effect
        self.drawWater
      when "vacuum"
        self.vacuumWaves(@data[key]) # draws vacuum waves
      when "bubbles"
        self.bubbleStream(@data[key]) # draws bubble particles
      when "snowParticles"
        self.drawSnow # draws snow particle sprites (same as Hail weather)
      end
    end
    # draws additional modules where sequencing is disregarded
    for key in @data.keys
      if key.include?("img")
        self.drawImg(key)
      end
    end
    # CRITICAL: Call adjustMetrics FIRST to set @scale before we use it!
    # adjustMetrics sets @scale = EliteBattle::ROOM_SCALE (2.25)
    # If we set bg.zoom_x = @scale before this, @scale is still 1.0 from constructor
    self.adjustMetrics

    # applies backdrop positioning for MAIN vector
    # Set ALL bg values needed for position() calculation:
    # - bg.x, bg.y = the x2, y2 coordinates for MAIN vector (which is sx, sy)
    # - bg.ox, bg.oy = the offset values based on sx, sy
    # - bg.zoom_x, bg.zoom_y = @scale (now correctly set to 2.25 by adjustMetrics)
    if @sprites["bg"].bitmap
      @sprites["bg"].center!
      @sprites["bg"].x = sx
      @sprites["bg"].y = sy
      @sprites["bg"].ox = sx/1.5 - 16
      @sprites["bg"].oy = sy/1.5 + 16
      @sprites["bg"].zoom_x = @scale
      @sprites["bg"].zoom_y = @scale
      if @baseBmp
        @sprites["bg"].bitmap.blt(0, @sprites["bg"].bitmap.height - @baseBmp.height, @baseBmp, @baseBmp.rect)
      end
      c1 = @sprites["bg"].bitmap.get_pixel(0, 0)
      c2 = @sprites["bg"].bitmap.get_pixel(0, @sprites["bg"].bitmap.height-1)
      # Fill the oversized void sprite with top/bottom colors
      vw = @sprites["void"].bitmap.width
      vh = @sprites["void"].bitmap.height
      @sprites["void"].bitmap.fill_rect(0, 0, vw, vh/2, c1)
      @sprites["void"].bitmap.fill_rect(0, vh/2, vw, vh/2, c2)
    end
    # applies daylight tinting
    self.daylightTint
    # IMPORTANT: Calculate initial battler positions BEFORE ensureBackdropFillsScreen
    # The position() method uses bg.ox/oy which are currently set to MAIN vector values
    # (from lines 246-247). If we call ensureBackdropFillsScreen first, it overwrites
    # these values and battler positions will be calculated wrong.
    self.position
    # Now we can call ensureBackdropFillsScreen for visual display purposes
    # The battler position sprites already have correct x/y values stored
    self.ensureBackdropFillsScreen
  end
  #-----------------------------------------------------------------------------
  # sets color of sprite to match the environment
  #-----------------------------------------------------------------------------
  def setColor(target, sprite, color = true)
    return if !target.bitmap || !sprite.ex || !sprite.ey
    c = target.bitmap.get_pixel(sprite.ex, sprite.ey)
    a = (color == "slight") ? 128 : 255
    sprite.colorize(c, a)
  end
  #-----------------------------------------------------------------------------
  # Fallback method to ensure backdrop fills the screen
  #-----------------------------------------------------------------------------
  def ensureBackdropFillsScreen
    return unless @sprites["bg"] && @sprites["bg"].bitmap
    # Calculate zoom needed to fill the viewport
    bw = @sprites["bg"].bitmap.width
    bh = @sprites["bg"].bitmap.height
    vw = @viewport.rect.width
    vh = @viewport.rect.height
    return if bw <= 0 || bh <= 0
    # Scale to fill screen (cover mode)
    zoom_x = vw.to_f / bw
    zoom_y = vh.to_f / bh
    zoom = [zoom_x, zoom_y].max * 1.1  # Slightly larger to ensure full coverage
    @sprites["bg"].zoom_x = zoom
    @sprites["bg"].zoom_y = zoom
    # Center the backdrop
    @sprites["bg"].ox = bw / 2
    @sprites["bg"].oy = bh / 2
    @sprites["bg"].x = vw / 2
    @sprites["bg"].y = vh / 2
  end
  #-----------------------------------------------------------------------------
  # battle room frame update
  #-----------------------------------------------------------------------------
  def update
    return if self.disposed?
    return unless @sprites["bg"]

    # Debug: Log update being called (once per 120 frames to reduce spam)
    @updateDebugCounter ||= 0
    @updateDebugCounter += 1
    if @updateDebugCounter % 120 == 1 && defined?(MultiplayerDebug)
      #MultiplayerDebug.info("EBDX-TINT", "update() called, frame #{@updateDebugCounter}, @daylightTone=#{@daylightTone.inspect}")
    end

    # Fallback: if no vector or vector issues, just fill the screen
    if !@scene || !@scene.vector
      ensureBackdropFillsScreen
      return
    end
    # updates to the spatial warping with respect to the scene vector
    begin
      sx, sy = @scene.vector.spoof(@defaultvector)
      # Avoid division by zero with a tolerance check
      if (sx - @defaultvector[0]).abs < 0.001 || (sy - @defaultvector[1]).abs < 0.001
        ensureBackdropFillsScreen
        return
      end
      # CRITICAL: Reset ox/oy to EBDX expected values BEFORE setting position
      # This undoes any changes made by ensureBackdropFillsScreen() during refresh()
      # The position formula depends on these specific ox/oy values to work correctly
      @sprites["bg"].ox = sx/1.5 - 16
      @sprites["bg"].oy = sy/1.5 + 16
      # Now set position and zoom based on current vector
      @sprites["bg"].x = @scene.vector.x2
      @sprites["bg"].y = @scene.vector.y2
      @sprites["bg"].zoom_x = @scale*((@scene.vector.x2 - @scene.vector.x)*1.0/(sx - @defaultvector[0])*1.0)**0.6
      @sprites["bg"].zoom_y = @scale*((@scene.vector.y2 - @scene.vector.y)*1.0/(sy - @defaultvector[1])*1.0)**0.6
      # CRITICAL: Recalculate battler positions based on new bg values!
      # Without this, battler(i).x/y return stale values from refresh()
      # and Pokemon won't track camera movement correctly
      self.position
    rescue
      ensureBackdropFillsScreen
    end
    # updates the vacuum waves
    for j in 0...3
      next if j > @fpIndex/50 || !@sprites["ec#{j}"]
      if @sprites["ec#{j}"].param <= 0
        @sprites["ec#{j}"].param = 1.5
        @sprites["ec#{j}"].opacity = 0
        @sprites["ec#{j}"].ex = 234
      end
      @sprites["ec#{j}"].opacity += (@sprites["ec#{j}"].param < 0.75 ? -4 : 4)/self.delta
      @sprites["ec#{j}"].ex += [1, 2/self.delta].max if (@fpIndex*self.delta)%4 == 0 && @sprites["ec#{j}"].ex < 284
      @sprites["ec#{j}"].ey -= [1, 2/self.delta].min if (@fpIndex*self.delta)%4 == 0 && @sprites["ec#{j}"].ey > 108
      @sprites["ec#{j}"].param -= 0.01/self.delta
    end
    # updates bubble particles
    for j in 0...18
      next if !@sprites["bubble#{j}"]
      if @sprites["bubble#{j}"].ey <= -32
        r = rand(5) + 2
        @sprites["bubble#{j}"].param = 0.16 + 0.01*rand(32)
        @sprites["bubble#{j}"].ey = @sprites["bg"].bitmap.height*0.25 + rand(@sprites["bg"].bitmap.height*0.75)
        @sprites["bubble#{j}"].ex = 32 + rand(@sprites["bg"].bitmap.width - 64)
        @sprites["bubble#{j}"].end_y = 64 + rand(72)
        @sprites["bubble#{j}"].end_x = @sprites["bubble#{j}"].ex
        @sprites["bubble#{j}"].toggle = rand(2) == 0 ? 1 : -1
        @sprites["bubble#{j}"].speed = 1 + 2/((r + 1)*0.4)
        @sprites["bubble#{j}"].z = [2,15,25][rand(3)] + rand(6) - (@focused ? 0 : 100)
        @sprites["bubble#{j}"].opacity = 0
      end
      min = @sprites["bg"].bitmap.height/4
      max = @sprites["bg"].bitmap.height/2
      scale = (2*Math::PI)/((@sprites["bubble#{j}"].bitmap.width/64.0)*(max - min) + min)
      @sprites["bubble#{j}"].opacity += 4 if @sprites["bubble#{j}"].opacity < @sprites["bubble#{j}"].end_y
      @sprites["bubble#{j}"].ey -= [1, @sprites["bubble#{j}"].speed/self.delta].max
      @sprites["bubble#{j}"].ex = @sprites["bubble#{j}"].end_x + @sprites["bubble#{j}"].bitmap.width*0.25*Math.sin(@sprites["bubble#{j}"].ey*scale)*@sprites["bubble#{j}"].toggle
    end
    # update weather particles
    self.updateWeather
    # positions all elements according to the battle backdrop
    self.position
    # updates skyline
    self.updateSky
    # turn off shadows if appropriate
    if @data.has_key?("noshadow") && @data["noshadow"] == true
      # for battler sprites
      @battle.battlers.each_with_index do |b, i|
        next if !b || !@scene.sprites["pokemon_#{i}"]
        @scene.sprites["pokemon_#{i}"].noshadow = true
      end
      # for trainer sprites
      if @battle.opponent
        for t in 0...@battle.opponent.length
          next if !@scene.sprites["trainer_#{t}"]
          @scene.sprites["trainer_#{t}"].noshadow = true
        end
      end
    end
    # adjusts for wind affected elements
    if @strongwind
      @wind -= @toggle*2
      @toggle *= -1 if @wind < 65 || (@wind >= 70 && @toggle < 0)
    else
      @wWait += 1
      if @wWait > Graphics.frame_rate*5
        mod = @toggle*(2 + (@wind >= 88 && @wind <= 92 ? 2 : 0))
        @wind -= mod
        @toggle *= -1 if @wind <= 80 || @wind >= 100
        @wWait = 0 if @wWait > Graphics.frame_rate*5 + 33
      end
    end
    # additional metrics
    @fpIndex += 1
    @fpIndex = 150 if @fpIndex > 255*self.delta

    # Apply daylight tint once after initialization is complete
    # This ensures all sprites are created before tinting
    if !@daylightApplied && @fpIndex > 5
      self.daylightTint
      @daylightApplied = true
    end
  end
  #-----------------------------------------------------------------------------
  # positions all the elements inside of the room
  #-----------------------------------------------------------------------------
  def position
    # Update void sprite to follow backdrop position AND zoom (prevents blue rectangle)
    if @sprites["void"] && @sprites["bg"]
      @sprites["void"].x = @sprites["bg"].x
      @sprites["void"].y = @sprites["bg"].y
      # Scale void sprite to match backdrop zoom (with extra margin)
      @sprites["void"].zoom_x = @sprites["bg"].zoom_x * 1.2
      @sprites["void"].zoom_y = @sprites["bg"].zoom_y * 1.2
    end

    for key in @sprites.keys
      next if key == "bg" || key == "0" || key == "void" || key.include?("w_sunny") || key.include?("w_sand") || key.include?("w_fog")
      # updates fancy light effects
      if key.include?("sLight")
        i = key.gsub("sLight","").to_i
        if @sprites["sLight#{i}"] && @scene.vector
          x, y = self.stageLightPos(i)
          @sprites["sLight#{i}"].ex = x
          @sprites["sLight#{i}"].ey = y
          @sprites["sLight#{i}"].update
        end
      end
      x = @sprites["bg"].x - (@sprites["bg"].ox - @sprites[key].ex)*@sprites["bg"].zoom_x
      y = @sprites["bg"].y - (@sprites["bg"].oy - @sprites[key].ey)*@sprites["bg"].zoom_y
      z = @sprites[key].param * @sprites["bg"].zoom_x
      @sprites[key].x = x
      @sprites[key].y = y
      if ["sky", "base", "water"].string_include?(key) || (key.include?("img") && @data[key].try_key?(:flat))
        @sprites[key].zoom_x = @sprites["bg"].zoom_x * (@sprites[key].zx ? @sprites[key].zx : 1)
        @sprites[key].zoom_y = @sprites["bg"].zoom_y * (@sprites[key].zy ? @sprites[key].zy : 1)
      elsif key.include?("sLight") && @sprites[key] && @scene.vector
        z = ((@scene.vector.zoom1**0.6) * ((i%2 == 0) ? 2 : 1) * 1.25)
        @sprites[key].zoom_x = z * @sprites["bg"].zoom_x * @sprites[key].zx
        @sprites[key].zoom_y = z * @sprites["bg"].zoom_y * @sprites[key].zy
      else
        @sprites[key].zoom_x = z
        @sprites[key].zoom_y = z
      end
      # effect for elements blowing side to side with wind
      if (key.include?("grass") || key.include?("tree") || key.include?("img"))
        if key.include?("grass") || key.include?("tree") || (@data[key] && @data[key].has_key?(:effect) && @data[key][:effect] == "wind")
          w = key.include?("tree") ? ((@wind-90)*0.25).to_i + 90 : @wind
          @sprites[key].skew(w)
          @sprites[key].ox = @sprites[key].x_mid
        end
      end
      # effect for rotating elements
      if key.include?("img") && (@data[key].has_key?(:effect) && @data[key][:effect] == "rotate")
        @sprites[key].angle += @sprites[key].direction * @sprites[key].speed/self.delta
      end
      # effect for lighting updates
      if key.include?("aLight") || key.include?("cLight")
        @sprites[key].opacity -= @sprites[key].toggle*@sprites[key].speed/self.delta
        @sprites[key].toggle *= -1 if @sprites[key].opacity <= 95 || @sprites[key].opacity >= @sprites[key].end_x*255
      end
      if key.include?("bLight")
        if @wWait*self.delta % @sprites[key].speed == 0
          @sprites[key].bitmap = @sprites[key].storedBitmap.clone
          @sprites[key].bitmap.hue_change((rand(8)*45/self.delta).round)
          @sprites[key].opacity = (rand(4) < 2 ? 192 : 0)
        end
      end
      @sprites[key].update
      # CRITICAL: Reapply daylight tone to trees and grass AFTER update()
      # The update() call may reset the tone, so we ensure it persists
      # This must be done after update() to have the final say on the tone
      if key.include?("grass") || key.include?("tree")
        # Use stored daylightTone if available, otherwise calculate from time
        tone = @daylightTone
        # Debug log - more aggressive for first 10 frames, then every 120
        @tintDebugCounter ||= 0
        @tintDebugCounter += 1
        shouldLog = (@tintDebugCounter <= 20) || (@tintDebugCounter % 120 == 1)

        # Check tone BEFORE we do anything
        toneBefore = @sprites[key].tone.inspect rescue "nil"

        if shouldLog && defined?(MultiplayerDebug)
          #MultiplayerDebug.info("EBDX-TINT", "position() #{key}: BEFORE tone=#{toneBefore}, @daylightTone=#{@daylightTone.inspect}")
        end

        if tone.nil? || (tone.red == 0 && tone.green == 0 && tone.blue == 0)
          # Recalculate based on current time if stored tone is empty/nil
          if defined?(PBDayNight) && (@data["outdoor"] || @data["sky"])
            isNight = PBDayNight.isNight? rescue false
            isEvening = (PBDayNight.isEvening? || PBDayNight.isMorning?) rescue false
            if shouldLog && defined?(MultiplayerDebug)
              #MultiplayerDebug.info("EBDX-TINT", "position() recalculating: isNight=#{isNight}, isEvening=#{isEvening}")
            end
            if isNight && !@sunny
              tone = Tone.new(-120, -100, -60)
            elsif isEvening && !@sunny
              tone = Tone.new(-16, -52, -56)
            end
          end
        end

        if tone
          @sprites[key].tone = tone
          if shouldLog && defined?(MultiplayerDebug)
            #MultiplayerDebug.info("EBDX-TINT", "position() #{key}: AFTER tone=#{@sprites[key].tone.inspect}")
          end
        end
      end
    end
  end
  #-----------------------------------------------------------------------------
  # loads all the necessary elements for the outdoor skybox
  #-----------------------------------------------------------------------------
  def drawSky
    # drawing additional skylines
    key = "Day"
    if @data.try_key?("outdoor")
      key = "Dawn" if PBDayNight.isEvening? || PBDayNight.isMorning?
      key = "Night" if PBDayNight.isNight?
    end
    @sprites["sky"] = Sprite.new(@viewport)
    begin
      @sprites["sky"].bitmap = pbBitmap("Graphics/EBDX/Battlebacks/elements/sky#{key}")
    rescue
      @sprites["sky"].bitmap = Bitmap.new(512, 192)
    end
    @sprites["sky"].oy = @sprites["sky"].bitmap.height
    @sprites["sky"].ex = 0
    @sprites["sky"].ey = @sprites["sky"].oy
    @sprites["sky"].param = 1
    # loop for drawing clouds
    for i in [1,0]
      @sprites["cloud#{i}"] = ScrollingSprite.new(@viewport)
      begin
        @sprites["cloud#{i}"].setBitmap("Graphics/EBDX/Battlebacks/elements/cloud#{i+1}")
      rescue
        # skip if cloud bitmap not found
      end
      @sprites["cloud#{i}"].speed = [0.5, 0.5, 0.25][i]
      @sprites["cloud#{i}"].direction = [1, -1, 1][i]
      @sprites["cloud#{i}"].oy = @sprites["cloud#{i}"].bitmap.height rescue 0
      @sprites["cloud#{i}"].ex = 0
      @sprites["cloud#{i}"].ey = [98, 91, 30][i]
      @sprites["cloud#{i}"].param = 1
      @sprites["cloud#{i}"].visible = !PBDayNight.isNight? || !@data.try_key?("outdoor")
      self.setColor(@sprites["sky"], @sprites["cloud#{i}"])
    end
    # draws the sun
    if !(PBDayNight.isNight? && @data.try_key?("outdoor"))
      @sprites["sun"] = Sprite.new(@viewport)
      begin
        @sprites["sun"].bitmap = pbBitmap("Graphics/EBDX/Battlebacks/elements/sun")
      rescue
        @sprites["sun"].bitmap = Bitmap.new(64, 64)
      end
      @sprites["sun"].ox = @sprites["sun"].bitmap.width/2
      @sprites["sun"].oy = @sprites["sun"].bitmap.height*4
      @sprites["sun"].ex = 208
      @sprites["sun"].ey = @sprites["sky"].ey - 3
      @sprites["sun"].param = 1
    end
    # loop for the stars
    for i in 0...24
      break if !(PBDayNight.isNight? && @data.try_key?("outdoor"))
      @sprites["star#{i}"] = Sprite.new(@viewport)
      begin
        @sprites["star#{i}"].bitmap = pbBitmap("Graphics/EBDX/Battlebacks/elements/star")
      rescue
        @sprites["star#{i}"].bitmap = Bitmap.new(8, 8)
      end
      @sprites["star#{i}"].center!
      @sprites["star#{i}"].ex = rand(@sprites["sky"].bitmap.width)
      @sprites["star#{i}"].ey = rand(@sprites["sky"].bitmap.height - 24)
      @sprites["star#{i}"].speed = rand(4) + 1
      @sprites["star#{i}"].param = 0.6 + rand(41)/100.0
      @sprites["star#{i}"].opacity = 125
      @sprites["star#{i}"].end_x = 185 + rand(71)
      @sprites["star#{i}"].toggle = 2
    end
  end
  #-----------------------------------------------------------------------------
  # tints all the elements inside of the scene based on daytime conditions
  #-----------------------------------------------------------------------------
  def daylightTint
    # Debug output
    #MultiplayerDebug.info("EBDX-TINT", "daylightTint called - outdoor: #{@data["outdoor"]}, sky: #{@data["sky"]}") if defined?(MultiplayerDebug)

    # Apply if outdoor OR if sky is present (more lenient check)
    if !@data["outdoor"] && !@data["sky"]
      #MultiplayerDebug.info("EBDX-TINT", "daylightTint: Skipping - not outdoor/sky") if defined?(MultiplayerDebug)
      return
    end

    # Check if PBDayNight is available
    if !defined?(PBDayNight)
      #MultiplayerDebug.info("EBDX-TINT", "daylightTint: PBDayNight not defined") if defined?(MultiplayerDebug)
      return
    end

    # Determine time of day
    isNight = false
    isEvening = false
    begin
      isNight = PBDayNight.isNight?
      isEvening = PBDayNight.isEvening? || PBDayNight.isMorning?
    rescue => e
      #MultiplayerDebug.info("EBDX-TINT", "daylightTint: Error checking time: #{e.message}") if defined?(MultiplayerDebug)
    end

    #MultiplayerDebug.info("EBDX-TINT", "daylightTint: isNight=#{isNight}, isEvening=#{isEvening}, sunny=#{@sunny}") if defined?(MultiplayerDebug)

    # Calculate the tone to apply
    tintTone = Tone.new(0, 0, 0)
    if isNight && !@sunny
      tintTone = Tone.new(-120, -100, -60)
    elsif isEvening && !@sunny
      tintTone = Tone.new(-16, -52, -56)
    end

    # Store for scene-wide application
    @daylightTone = tintTone

    # apply daytime shading to backdrop sprites
    #MultiplayerDebug.info("EBDX-TINT", "daylightTint: Applying tone #{tintTone.inspect} to sprites...") if defined?(MultiplayerDebug)
    #MultiplayerDebug.info("EBDX-TINT", "daylightTint: Available sprite keys: #{@sprites.keys.inspect}") if defined?(MultiplayerDebug)

    treeGrassCount = 0
    for key in @sprites.keys
      next if !@sprites[key]
      next if key.include?("trainer") || key.include?("battler") || key.include?("pokemon")
      next if key.include?("sky") || key.include?("sun") || key.include?("star") || key.include?("cloud") || key.include?("Light")
      next if @data[key].is_a?(Hash) && @data[key].has_key?(:shading) && !@data[key][:shading]

      @sprites[key].tone = tintTone.clone

      # Debug specifically for trees and grass
      if key.include?("tree") || key.include?("grass")
        treeGrassCount += 1
        #MultiplayerDebug.info("EBDX-TINT", "daylightTint: Applied to #{key}, tone now: #{@sprites[key].tone.inspect}") if defined?(MultiplayerDebug)
      end
    end

    #MultiplayerDebug.info("EBDX-TINT", "daylightTint: Applied to #{treeGrassCount} tree/grass sprites") if defined?(MultiplayerDebug)
    #MultiplayerDebug.info("EBDX-TINT", "daylightTint: @daylightTone stored as: #{@daylightTone.inspect}") if defined?(MultiplayerDebug)
  end

  #-----------------------------------------------------------------------------
  # Get the current daylight tone for scene-wide application
  #-----------------------------------------------------------------------------
  def daylightTone
    @daylightTone ||= Tone.new(0, 0, 0)
  end
  #-----------------------------------------------------------------------------
  # frame update for the skybox
  #-----------------------------------------------------------------------------
  def updateSky
    return if !@data.try_key?("sky", "outdoor")
    minutes = Time.now.hour*60 + Time.now.min
    # animates twinkling stars
    for i in 0...24
      break if !(PBDayNight.isNight? && @data.try_key?("outdoor"))
      next if !@sprites["star#{i}"]
      @sprites["star#{i}"].opacity += @sprites["star#{i}"].toggle * @sprites["star#{i}"].speed/self.delta
      @sprites["star#{i}"].toggle *= -1 if @sprites["star#{i}"].opacity <= 125 || @sprites["star#{i}"].opacity >= @sprites["star#{i}"].end_x
    end
    # applies sun positioning if it is rendered
    return if !@sprites["sun"]
    if PBDayNight.isEvening?
      oy = 92 - 68*(minutes - 17*60.0)/(3*60.0)
    elsif PBDayNight.isMorning?
      oy = 24 + 68*(minutes - 5*60.0)/(5*60.0)
    else
      oy = @sprites["sun"].bitmap.height*4
    end
    oy = 23 if oy < 23
    @sprites["sun"].src_rect.height = oy
    @sprites["sun"].oy = oy
  end
  #-----------------------------------------------------------------------------
  # set weather data
  #-----------------------------------------------------------------------------
  def setWeather
    # loop once
    for wth in [["Rain", [:Rain, :HeavyRain]], ["Snow", :Hail], ["StrongWind", :StrongWinds], ["Sunny", [:Sun, :HarshSun]], ["Sandstorm", :Sandstorm], ["Fog", :Fog]]
      proceed = false
      for cond in (wth[1].is_a?(Array) ? wth[1] : [wth[1]])
        proceed = true if @battle.pbWeather == cond
      end
      unless proceed
        # don't delete snow particles that were spawned by the environment data itself
        next if wth[0] == "Snow" && @data.is_a?(Hash) && @data["snowParticles"]
        eval("delete" + wth[0])
      end
      eval("draw"  + wth[0]) if proceed
    end
  end
  #-----------------------------------------------------------------------------
  # frame update for the weather particles
  #-----------------------------------------------------------------------------
  def updateWeather
    self.setWeather
    harsh = [:HEAVYRAIN, :HARSHSUN].include?(@battle.pbWeather)
    # snow particles
    for j in 0...72
      next if !@sprites["w_snow#{j}"]
      if @sprites["w_snow#{j}"].opacity <= 0
        z = rand(32)
        @sprites["w_snow#{j}"].param = 0.24 + 0.01*rand(z/2)
        @sprites["w_snow#{j}"].ey = -rand(64)
        @sprites["w_snow#{j}"].ex = 32 + rand(@sprites["bg"].bitmap.width - 64)
        @sprites["w_snow#{j}"].end_x = @sprites["w_snow#{j}"].ex
        @sprites["w_snow#{j}"].toggle = rand(2) == 0 ? 1 : -1
        @sprites["w_snow#{j}"].speed = 1 + 2/((rand(5) + 1)*0.4)
        @sprites["w_snow#{j}"].z = z - (@focused ? 0 : 100)
        @sprites["w_snow#{j}"].opacity = 255
      end
      min = @sprites["bg"].bitmap.height/4
      max = @sprites["bg"].bitmap.height/2
      scale = (2*Math::PI)/((@sprites["w_snow#{j}"].bitmap.width/64.0)*(max - min) + min)
      @sprites["w_snow#{j}"].opacity -= @sprites["w_snow#{j}"].speed/self.delta
      @sprites["w_snow#{j}"].ey += [1, @sprites["w_snow#{j}"].speed/self.delta].max
      @sprites["w_snow#{j}"].ex = @sprites["w_snow#{j}"].end_x + @sprites["w_snow#{j}"].bitmap.width*0.25*Math.sin(@sprites["w_snow#{j}"].ey*scale)*@sprites["w_snow#{j}"].toggle
    end
    # rain particles
    for j in 0...72
      next if !@sprites["w_rain#{j}"]
      if @sprites["w_rain#{j}"].opacity <= 0
        z = rand(32)
        @sprites["w_rain#{j}"].param = 0.24 + 0.01*rand(z/2)
        @sprites["w_rain#{j}"].ox = 0
        @sprites["w_rain#{j}"].ey = -rand(64)
        @sprites["w_rain#{j}"].ex = 32 + rand(@sprites["bg"].bitmap.width - 64)
        @sprites["w_rain#{j}"].speed = 3 + 2/((rand(5) + 1)*0.4)
        @sprites["w_rain#{j}"].z = z - (@focused ? 0 : 100)
        @sprites["w_rain#{j}"].opacity = 255
      end
      @sprites["w_rain#{j}"].opacity -= @sprites["w_rain#{j}"].speed*(harsh ? 3 : 2)/self.delta
      @sprites["w_rain#{j}"].ox += [1, @sprites["w_rain#{j}"].speed*(harsh ? 8 : 6)/self.delta].max
    end
    # sun particles
    for j in 0...3
      next if !@sprites["w_sunny#{j}"]
      #next if j > @shine["count"]/6
      @sprites["w_sunny#{j}"].zoom_x += 0.04*[0.5, 0.8, 0.7][j]/self.delta
      @sprites["w_sunny#{j}"].zoom_y += 0.03*[0.5, 0.8, 0.7][j]/self.delta
      @sprites["w_sunny#{j}"].opacity += (@sprites["w_sunny#{j}"].zoom_x < 1 ? 8 : -12)/self.delta
      if @sprites["w_sunny#{j}"].opacity <= 0
        @sprites["w_sunny#{j}"].zoom_x = 0
        @sprites["w_sunny#{j}"].zoom_y = 0
        @sprites["w_sunny#{j}"].opacity = 0
      end
    end
    # sandstorm particles
    for j in 0...2
      next if !@sprites["w_sand#{j}"]
      @sprites["w_sand#{j}"].update
    end
    # fog particles
    for j in 0...2
      next if !@sprites["w_fog#{j}"]
      @sprites["w_fog#{j}"].update
    end
  end
  #-----------------------------------------------------------------------------
  # reads data from hashtable and draws all tree objects in room
  #-----------------------------------------------------------------------------
  def drawTrees(data = @data["trees"])
    #MultiplayerDebug.info("EBDX-TINT", "drawTrees called, data=#{data.inspect}") if defined?(MultiplayerDebug)
    return if !data.has_key?(:elements)
    bmp = data.has_key?(:bitmap) ? data[:bitmap] : "tree"
    begin
      bmp = pbBitmap("Graphics/EBDX/Battlebacks/elements/#{bmp}")
    rescue
      #MultiplayerDebug.info("EBDX-TINT", "drawTrees: Failed to load bitmap #{bmp}") if defined?(MultiplayerDebug)
      return
    end
    #MultiplayerDebug.info("EBDX-TINT", "drawTrees: Creating #{data[:elements]} tree sprites") if defined?(MultiplayerDebug)
    for i in 0...data[:elements]
      @sprites["tree#{i}"] = Sprite.new(@viewport)
      x0 = data.has_key?(:mirror) && data[:mirror][i] ? bmp.width : 0
      x1 = data.has_key?(:mirror) && data[:mirror][i] ? -bmp.width : bmp.width
      @sprites["tree#{i}"].bitmap = Bitmap.new(bmp.width,bmp.height)
      @sprites["tree#{i}"].bitmap.stretch_blt(bmp.rect,bmp,Rect.new(x0,0,x1,bmp.height))
      @sprites["tree#{i}"].bottom!
      @sprites["tree#{i}"].ex = data.has_key?(:x) ? data[:x][i] : 0
      @sprites["tree#{i}"].ey = data.has_key?(:y) ? data[:y][i] : 0
      @sprites["tree#{i}"].z = data.has_key?(:z) ? data[:z][i] : 1
      @sprites["tree#{i}"].param = data.has_key?(:zoom) ? data[:zoom][i] : 1
      color = data.has_key?(:colorize) ? data[:colorize] : true
      self.setColor(@sprites["bg"], @sprites["tree#{i}"], color) if color
      @sprites["tree#{i}"].memorize_bitmap
      #MultiplayerDebug.info("EBDX-TINT", "drawTrees: Created tree#{i}, z=#{@sprites["tree#{i}"].z}, tone=#{@sprites["tree#{i}"].tone.inspect}") if defined?(MultiplayerDebug)
    end; bmp.dispose
  end
  #-----------------------------------------------------------------------------
  # reads data from hashtable and draws all grass objects in room
  #-----------------------------------------------------------------------------
  def drawGrass(data = @data["tallGrass"])
    #MultiplayerDebug.info("EBDX-TINT", "drawGrass called, data=#{data.inspect}") if defined?(MultiplayerDebug)
    return if !data.has_key?(:elements)
    bmp = data.has_key?(:bitmap) ? data[:bitmap] : "tallGrass"
    begin
      bmp = pbBitmap("Graphics/EBDX/Battlebacks/elements/#{bmp}")
    rescue
      #MultiplayerDebug.info("EBDX-TINT", "drawGrass: Failed to load bitmap #{bmp}") if defined?(MultiplayerDebug)
      return
    end
    #MultiplayerDebug.info("EBDX-TINT", "drawGrass: Creating #{data[:elements]} grass sprites") if defined?(MultiplayerDebug)
    for i in 0...data[:elements]
      @sprites["grass#{i}"] = Sprite.new(@viewport)
      x0 = data.has_key?(:mirror) && data[:mirror][i] ? bmp.width : 0
      x1 = data.has_key?(:mirror) && data[:mirror][i] ? -bmp.width : bmp.width
      @sprites["grass#{i}"].bitmap = Bitmap.new(bmp.width,bmp.height)
      @sprites["grass#{i}"].bitmap.stretch_blt(bmp.rect,bmp,Rect.new(x0,0,x1,bmp.height))
      @sprites["grass#{i}"].bottom!
      @sprites["grass#{i}"].ex = data.has_key?(:x) ? data[:x][i] : 0
      @sprites["grass#{i}"].ey = data.has_key?(:y) ? data[:y][i] : 0
      @sprites["grass#{i}"].z = data[:z][i] if data.has_key?(:z)
      @sprites["grass#{i}"].param = data.has_key?(:zoom) ? data[:zoom][i] : 1
      color = data.has_key?(:colorize) ? data[:colorize] : true
      self.setColor(@sprites["bg"], @sprites["grass#{i}"], color) if color
      @sprites["grass#{i}"].memorize_bitmap
      #MultiplayerDebug.info("EBDX-TINT", "drawGrass: Created grass#{i}, z=#{@sprites["grass#{i}"].z}, tone=#{@sprites["grass#{i}"].tone.inspect}") if defined?(MultiplayerDebug)
    end; bmp.dispose
  end
  #-----------------------------------------------------------------------------
  # function to draw a custom room object based on user-defined parameters
  #-----------------------------------------------------------------------------
  def drawImg(key)
    data = @data[key]
    if data.try_key?(:scrolling) # simple scrolling panorama
      @sprites["#{key}"] = ScrollingSprite.new(@viewport)
    elsif data.try_key?(:sheet) # simple animated sprite sheets
      @sprites["#{key}"] = SpriteSheet.new(@viewport,data.get_key(:frames).nil? ? 1 : data[:frames])
    elsif data.try_key?(:animated) # EBS styled sprite sheets
      @sprites["#{key}"] = SpriteEBDX.new(@viewport)
    elsif data.try_key?(:rainbow) # hue changing sprite
      @sprites["#{key}"] = RainbowSprite.new(@viewport)
    else # regular sprite
      @sprites["#{key}"] = Sprite.new(@viewport)
    end
    @sprites["#{key}"].default!; keys = data.keys;
    if keys.include?(:bitmap) # prioritizes bitmap key from sorted array
      keys.delete(:bitmap); keys.insert(0,:bitmap)
    end
    for m in keys # interprets each parameter
      k = EliteBattle.bg_hash_map(m); next if k.nil? # if parameter can be mapped
      if k == :bitmap # applies bitmap
        begin
          path = pbResolveBitmap(data[m]) ? data[m] : "Graphics/EBDX/Battlebacks/elements/" + data[m]
          if data.try_key?(:scrolling) || data.try_key?(:animated) || data.try_key?(:rainbow) || data.try_key?(:sheet)
            @sprites["#{key}"].setBitmap(path,((data.try_key?(:animated) || data.try_key?(:rainbow)) ? 1 : data.get_key(:vertical)))
          else
            @sprites["#{key}"].bitmap = pbBitmap(path)
          end
        rescue
          # skip if bitmap not found
        end
        next
      end # otherwise applies parameter data
      @sprites["#{key}"].send("#{k}=",data[m]) if @sprites["#{key}"].respond_to?(k)
    end
    @sprites["#{key}"].z = 40 if @sprites["#{key}"].z > 40 # caps Z value
    @sprites["#{key}"].bottom! if @sprites["#{key}"].bitmap && !data.try_key?(:ox) && !data.try_key?(:oy) # sets the anchor to bottom middle, unless otherwise defined
    # check if should apply color
    if data.try_key?(:colorize)
      self.setColor(@sprites["bg"], @sprites["#{key}"]) if data[:colorize] == true
      @sprites["#{key}"].colorize(data[:colorize], data[:colorize].alpha) if data[:colorize].is_a?(Color)
    end
    @sprites["#{key}"].memorize_bitmap # saves the sprite's bitmap just in case
  end
  #-----------------------------------------------------------------------------
  # loads the animated elements for PWT styled base lights
  #-----------------------------------------------------------------------------
  def drawSpinLights
    for i in 0...2
      @sprites["sLight#{i}"] = SpriteEBDX.new(@viewport)
      @sprites["sLight#{i}"].default!
      begin
        @sprites["sLight#{i}"].setBitmap("Graphics/EBDX/Battlebacks/elements/lightDecor",1)
      rescue
        # skip if bitmap not found
      end
      @sprites["sLight#{i}"].z = 1
      @sprites["sLight#{i}"].center!
      @sprites["sLight#{i}"].zx = 1
      @sprites["sLight#{i}"].zy = 0.35
    end
  end
  #-----------------------------------------------------------------------------
  # elements for stage lights style A
  #-----------------------------------------------------------------------------
  def drawLightsA(img = true)
    lgt = img.is_a?(String) ? img : "lightA"
    for i in 0...4
      @sprites["aLight#{i}"] = Sprite.new(@viewport)
      begin
        @sprites["aLight#{i}"].bitmap = pbBitmap("Graphics/EBDX/Battlebacks/elements/#{lgt}")
      rescue
        @sprites["aLight#{i}"].bitmap = Bitmap.new(64, 64)
      end
      @sprites["aLight#{i}"].ex = [183, 135, 70, 0][i]
      @sprites["aLight#{i}"].ey = [-2, -15, -15, -16][i]
      @sprites["aLight#{i}"].param = [0.8, 1, 1.25, 1.4][i]
      @sprites["aLight#{i}"].z = [10, 10, 18, 18][i]
      @sprites["aLight#{i}"].opacity = [0.5, 0.7, 0.9, 1][i]*255
      @sprites["aLight#{i}"].end_x = [0.5, 0.7, 0.9, 1][i]
      @sprites["aLight#{i}"].speed = 1*(1 + rand(4))
      @sprites["aLight#{i}"].toggle = 1
    end
  end
  #-----------------------------------------------------------------------------
  # elements for stage lights style B
  #-----------------------------------------------------------------------------
  def drawLightsB(img = true)
    lgt = img.is_a?(String) ? img : "lightB"
    for i in 0...6
      @sprites["bLight#{i}"] = Sprite.new(@viewport)
      begin
        @sprites["bLight#{i}"].bitmap = pbBitmap("Graphics/EBDX/Battlebacks/elements/#{lgt}")
      rescue
        @sprites["bLight#{i}"].bitmap = Bitmap.new(64, 64)
      end
      @sprites["bLight#{i}"].ox = @sprites["bLight#{i}"].bitmap.width/2
      @sprites["bLight#{i}"].ex = [40,104,146,210,256,320][i]
      @sprites["bLight#{i}"].ey = -8
      @sprites["bLight#{i}"].mirror = (i%2 == 1)
      @sprites["bLight#{i}"].speed = (2 + rand(3))*3
      @sprites["bLight#{i}"].memorize_bitmap
      @sprites["bLight#{i}"].param = 1
      @sprites["bLight#{i}"].z = 3
      @sprites["bLight#{i}"].opacity = 0
    end
  end
  #-----------------------------------------------------------------------------
  # elements for ambiental lights style C
  #-----------------------------------------------------------------------------
  def drawLightsC
    for i in 0...8
      c = [2,3,1,3,2,3,1,3]; l = (100-rand(51))/100.0
      @sprites["cLight#{i}"] = Sprite.new(@viewport)
      begin
        @sprites["cLight#{i}"].bitmap = pbBitmap("Graphics/EBDX/Battlebacks/elements/lightC#{c[i]}")
      rescue
        @sprites["cLight#{i}"].bitmap = Bitmap.new(64, 64)
      end
      @sprites["cLight#{i}"].ex = [-2,10,40,60,100,118,160,168][i]
      @sprites["cLight#{i}"].ey = [-22,-46,-8,-32,-14,-40,0,-58][i]
      @sprites["cLight#{i}"].param = 1
      @sprites["cLight#{i}"].z = 10
      @sprites["cLight#{i}"].opacity = l*255
      @sprites["cLight#{i}"].end_x = l
      @sprites["cLight#{i}"].speed = 1*(1 + rand(4))
      @sprites["cLight#{i}"].toggle = 1
    end
  end
  #-----------------------------------------------------------------------------
  # adds subtle water animation to terrain
  #-----------------------------------------------------------------------------
  def drawWater
    for i in 0...2
      @sprites["water#{i}"] = ScrollingSprite.new(@viewport)
      begin
        @sprites["water#{i}"].setBitmap("Graphics/EBDX/Battlebacks/elements/water#{i}")
      rescue
        # skip if water bitmap not found
      end
      @sprites["water#{i}"].speed = 0.5
      @sprites["water#{i}"].direction = 1
      @sprites["water#{i}"].ex = 0
      @sprites["water#{i}"].ey = 146
      @sprites["water#{i}"].param = 1
      @sprites["water#{i}"].mirror = i > 0
    end
  end
  #-----------------------------------------------------------------------------
  # draws vacuum waves
  #-----------------------------------------------------------------------------
  def vacuumWaves(img = true)
    lgt = img.is_a?(String) ? img : "dark004"
    for j in 0...3
      @sprites["ec#{j}"] = Sprite.new(@viewport)
      begin
        @sprites["ec#{j}"].bitmap = pbBitmap("Graphics/EBDX/Battlebacks/elements/#{lgt}")
      rescue
        @sprites["ec#{j}"].bitmap = Bitmap.new(64, 64)
      end
      @sprites["ec#{j}"].center!
      @sprites["ec#{j}"].ex = 234
      @sprites["ec#{j}"].ey = 128
      @sprites["ec#{j}"].param = 1.5
      @sprites["ec#{j}"].opacity = 0
      @sprites["ec#{j}"].z = 1
    end
  end
  #-----------------------------------------------------------------------------
  # draws bubble stream
  #-----------------------------------------------------------------------------
  def bubbleStream(img = true)
    lgt = img.is_a?(String) ? img : "bubble"
    for j in 0...18
      @sprites["bubble#{j}"] = Sprite.new(@viewport)
      begin
        @sprites["bubble#{j}"].bitmap = pbBitmap("Graphics/EBDX/Battlebacks/elements/#{lgt}")
      rescue
        @sprites["bubble#{j}"].bitmap = Bitmap.new(16, 16)
      end
      @sprites["bubble#{j}"].center!
      @sprites["bubble#{j}"].default!
      @sprites["bubble#{j}"].ey = -32
      @sprites["bubble#{j}"].opacity = 0
    end
  end
  #-----------------------------------------------------------------------------
  # check if sky should be tinted lighter
  #-----------------------------------------------------------------------------
  def weatherTint?
    for wth in [:Hail, :Sun, :HarshSun]
      return true if @battle.pbWeather == wth
    end
    return false
  end
  #-----------------------------------------------------------------------------
  # sunny weather handlers
  #-----------------------------------------------------------------------------
  def drawSunny
    @sunny = true
    # refresh daylight tinting
    if @weather != @battle.pbWeather
      @weather = @battle.pbWeather
      self.daylightTint
    end
    # apply sky tone
    if @sprites["sky"]
      @sprites["sky"].tone.all += 16 if @sprites["sky"].tone.all < 96
      for i in 0..1
        @sprites["cloud#{i}"].tone.all += 16 if @sprites["cloud#{i}"].tone.all < 96
      end
    end
    # draw particles
    for i in 0...3
      next if @sprites["w_sunny#{i}"]
      @sprites["w_sunny#{i}"] = Sprite.new(@viewport)
      @sprites["w_sunny#{i}"].z = 100
      begin
        @sprites["w_sunny#{i}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Weather/ray001")
      rescue
        @sprites["w_sunny#{i}"].bitmap = Bitmap.new(64, 64)
      end
      @sprites["w_sunny#{i}"].oy = @sprites["w_sunny#{i}"].bitmap.height/2
      @sprites["w_sunny#{i}"].angle = 290 + [-10, 32, 10][i]
      @sprites["w_sunny#{i}"].zoom_x = 0
      @sprites["w_sunny#{i}"].zoom_y = 0
      @sprites["w_sunny#{i}"].opacity = 0
      @sprites["w_sunny#{i}"].x = [-2, 20, 10][i]
      @sprites["w_sunny#{i}"].y = [-4, -24, -2][i]
    end
  end
  def deleteSunny
    @sunny = false
    # refresh daylight tinting
    if @weather != @battle.pbWeather
      @weather = @battle.pbWeather
      self.daylightTint
    end
    # apply sky tone
    if @sprites["sky"] && !weatherTint?
      @sprites["sky"].tone.all -= 4 if @sprites["sky"].tone.all > 0
      for i in 0..1
        @sprites["cloud#{i}"].tone.all -= 4 if @sprites["cloud#{i}"].tone.all > 0
      end
    end
    for j in 0...3
      next if !@sprites["w_sunny#{j}"]
      @sprites["w_sunny#{j}"].dispose
      @sprites.delete("w_sunny#{j}")
    end
  end
  #-----------------------------------------------------------------------------
  # sandstorm weather handlers
  #-----------------------------------------------------------------------------
  def drawSandstorm
    for j in 0...2
      next if @sprites["w_sand#{j}"]
      @sprites["w_sand#{j}"] = ScrollingSprite.new(@viewport)
      @sprites["w_sand#{j}"].default!
      @sprites["w_sand#{j}"].z = 100
      begin
        @sprites["w_sand#{j}"].setBitmap("Graphics/EBDX/Animations/Weather/sandstorm#{j}")
      rescue
        # skip if sandstorm bitmap not found
      end
      @sprites["w_sand#{j}"].speed = 32
      @sprites["w_sand#{j}"].direction = j == 0 ? 1 : -1
    end
  end
  def deleteSandstorm
    for j in 0...2
      next if !@sprites["w_sand#{j}"]
      @sprites["w_sand#{j}"].dispose
      @sprites.delete("w_sand#{j}")
    end
  end
  #-----------------------------------------------------------------------------
  # fog weather handlers
  #-----------------------------------------------------------------------------
  def drawFog
    for j in 0...2
      next if @sprites["w_fog#{j}"]
      @sprites["w_fog#{j}"] = ScrollingSprite.new(@viewport)
      @sprites["w_fog#{j}"].default!
      @sprites["w_fog#{j}"].z = 100
      begin
        @sprites["w_fog#{j}"].setBitmap("Graphics/EBDX/Animations/Weather/fog#{j}", false, true)
      rescue
        # skip if fog bitmap not found
      end
      @sprites["w_fog#{j}"].speed = 2 - j
      @sprites["w_fog#{j}"].min_o = 105
      @sprites["w_fog#{j}"].max_o = 205
      @sprites["w_fog#{j}"].opacity = 205
      @sprites["w_fog#{j}"].direction = j == 0 ? 1 : -1
    end
  end
  def deleteFog
    for j in 0...2
      next if !@sprites["w_fog#{j}"]
      @sprites["w_fog#{j}"].dispose
      @sprites.delete("w_fog#{j}")
    end
  end
  #-----------------------------------------------------------------------------
  # snow weather handlers
  #-----------------------------------------------------------------------------
  def drawSnow
    for j in 0...72
      next if @sprites["w_snow#{j}"]
      @sprites["w_snow#{j}"] = Sprite.new(@viewport)
      begin
        @sprites["w_snow#{j}"].bitmap = pbBitmap("Graphics/EBDX/Battlebacks/elements/snow")
      rescue
        @sprites["w_snow#{j}"].bitmap = Bitmap.new(8, 8)
      end
      @sprites["w_snow#{j}"].center!
      @sprites["w_snow#{j}"].default!
      @sprites["w_snow#{j}"].opacity = 0
    end
  end
  def deleteSnow
    for j in 0...72
      next if !@sprites["w_snow#{j}"]
      @sprites["w_snow#{j}"].dispose
      @sprites.delete("w_snow#{j}")
    end
  end
  #-----------------------------------------------------------------------------
  # rain weather handlers
  #-----------------------------------------------------------------------------
  def drawRain
    harsh = @battle.pbWeather == :HEAVYRAIN
    # apply sky tone
    if @sprites["sky"]
      @sprites["sky"].tone.all -= 2 if @sprites["sky"].tone.all > -16
      @sprites["sky"].tone.gray += 16 if @sprites["sky"].tone.gray < 128
      for i in 0..1
        @sprites["cloud#{i}"].tone.all -= 2 if @sprites["cloud#{i}"].tone.all > -16
        @sprites["cloud#{i}"].tone.gray += 16 if @sprites["cloud#{i}"].tone.gray < 128
      end
    end
    for j in 0...72
      next if @sprites["w_rain#{j}"]
      @sprites["w_rain#{j}"] = Sprite.new(@viewport)
      @sprites["w_rain#{j}"].create_rect(harsh ? 28 : 24, 3, Color.white)
      @sprites["w_rain#{j}"].default!
      @sprites["w_rain#{j}"].angle = 80
      @sprites["w_rain#{j}"].oy = 2
      @sprites["w_rain#{j}"].opacity = 0
    end
  end
  def deleteRain
    # apply sky tone
    if @sprites["sky"]
      @sprites["sky"].tone.all += 2 if @sprites["sky"].tone.all < 0
      @sprites["sky"].tone.gray -= 16 if @sprites["sky"].tone.gray > 0
      for i in 0..1
        @sprites["cloud#{i}"].tone.all += 2 if @sprites["cloud#{i}"].tone.all < 0
        @sprites["cloud#{i}"].tone.gray -= 16 if @sprites["cloud#{i}"].tone.gray > 0
      end
    end
    for j in 0...72
      next if !@sprites["w_rain#{j}"]
      @sprites["w_rain#{j}"].dispose
      @sprites.delete("w_rain#{j}")
    end
  end
  #-----------------------------------------------------------------------------
  # strong wind weather handlers
  #-----------------------------------------------------------------------------
  def drawStrongWind; @strongwind = true; end
  def deleteStrongWind; @strongwind = false; end
  #-----------------------------------------------------------------------------
  # records the proper positioning
  #-----------------------------------------------------------------------------
  def adjustMetrics
    @scale = EliteBattle::ROOM_SCALE rescue 2.25
    data = EliteBattle.get(:battlerMetrics)

    # Default positions for battlers (used when metrics data is missing)
    # These are approximate EBDX-style positions on the battlefield
    # Format: [ex, ey, z] - ex/ey are backdrop-relative coordinates (512x288 backdrop)
    # In EBDX coordinate system: higher ex = more right, higher ey = more down
    # Player side appears in lower-right (closer to camera), enemy in upper-left (farther)
    defaultPositions = {
      # Player side (back sprites) - lower right of backdrop
      0 => { ex: 350, ey: 220, z: 15 },   # Player battler 0
      2 => { ex: 380, ey: 210, z: 14 },   # Player battler 2 (doubles)
      # Enemy side (front sprites) - upper center-left of backdrop
      1 => { ex: 180, ey: 140, z: 25 },   # Enemy battler 1
      3 => { ex: 150, ey: 130, z: 26 },   # Enemy battler 3 (doubles)
      # Trainer positions
      -1 => { ex: 160, ey: 150, z: 20 },  # Trainer position (enemy side)
      -2 => { ex: 360, ey: 230, z: 10 },  # Player position
    }

    # Safety check - if no metrics data or empty hash, use defaults
    if data.nil? || !data.is_a?(Hash) || data.empty?
      # Create sprites for battler positions with default positions
      [-2, -1, 0, 1, 2, 3].each do |idx|
        @sprites["battler#{idx}"] = Sprite.new(@viewport)
        @sprites["battler#{idx}"].default! if @sprites["battler#{idx}"].respond_to?(:default!)
        # Set default positions
        pos = defaultPositions[idx] || { ex: 256, ey: 180, z: 15 }
        @sprites["battler#{idx}"].ex = pos[:ex]
        @sprites["battler#{idx}"].ey = pos[:ey]
        @sprites["battler#{idx}"].z = pos[:z]
        @sprites["battler#{idx}"].param = 1.0

        @sprites["trainer_#{idx}"] = Sprite.new(@viewport)
        @sprites["trainer_#{idx}"].default! if @sprites["trainer_#{idx}"].respond_to?(:default!)
        @sprites["trainer_#{idx}"].ex = pos[:ex]
        @sprites["trainer_#{idx}"].ey = pos[:ey]
        @sprites["trainer_#{idx}"].z = pos[:z]
        @sprites["trainer_#{idx}"].param = 1.0
      end
      return
    end
    # Ensure we have at least some keys to iterate
    max_keys = [data.keys.length, 6].max
    for j in -2...max_keys
      @sprites["battler#{j}"] = Sprite.new(@viewport)
      @sprites["battler#{j}"].default!
      @sprites["trainer_#{j}"] = Sprite.new(@viewport)
      @sprites["trainer_#{j}"].default!
      # Map battler index (j) to metrics index (i)
      # Essentials uses: 1v1=0,1  2v2=0,4,1,5  3v3=0,2,4,1,3,5
      # EBDX metrics use: BATTLERPOS-0 to BATTLERPOS-5 sequentially
      # For 2v2: battler 4 should use BATTLERPOS-2, battler 5 should use BATTLERPOS-3
      # For 3v3: battler indices match metrics indices
      i = j
      i = 0 if j == -2
      i = 1 if j == -1
      if @battle.pbMaxSize == 2  # 2v2 battle
        i = 2 if j == 4  # 2nd player Pokemon uses BATTLERPOS-2
        i = 3 if j == 5  # 2nd enemy Pokemon uses BATTLERPOS-3
      end
      for param in [:X, :Y, :Z]
        next if data[i].nil? || !data[i].has_key?(param)
        dat = data[i][param]
        # Position index based on battle size:
        # Single=0, Double=1, Triple=2
        # Each BATTLERPOS entry has positions for [Single, Double, Triple]
        # Use the battle's max size to determine which position to use
        n = @battle.pbMaxSize - 1
        m = @battle.opponent ? [@battle.pbMaxSize - 1, (@battle.opponent.length - 1)].min : n
        n = dat.length - 1 if n >= dat.length
        m = dat.length - 1 if m >= dat.length
        n = 0 if n < 0; m = 0 if m < 0
        k = [:X, :Y].include?(param) ? "E#{param.to_s}" : param.to_s
        @sprites["battler#{j}"].send("#{k.downcase}=", dat[n])
        @sprites["trainer_#{j}"].send("#{k.downcase}=", dat[m])
      end
    end
  end
  #-----------------------------------------------------------------------------
  # disposes of all sprites
  #-----------------------------------------------------------------------------
  def dispose
    pbDisposeSpriteHash(@sprites)
    @disposed = true
  end
  #-----------------------------------------------------------------------------
  # checks if room is disposed
  #-----------------------------------------------------------------------------
  def disposed?; return @disposed; end
  #-----------------------------------------------------------------------------
  # compatibility layers for scene transitions
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
  # compatibility layer for move animations with backgrounds
  #-----------------------------------------------------------------------------
  def defocus
    return if @sprites["bg"].z < 0
    for key in @sprites.keys
      @sprites[key].z -= 100
    end
    @focused = false
  end
  def focus
    return if @sprites["bg"].z >= 0
    for key in @sprites.keys
      @sprites[key].z += 100
    end
    @focused = true
  end
  #-----------------------------------------------------------------------------
  # battler sprite positioning
  #-----------------------------------------------------------------------------
  def delta; return Graphics.frame_rate/40.0; end
  def scale_y; return @sprites["bg"].zoom_y; end
  def battler(i); return @sprites["battler#{i}"]; end
  def trainer(i); return @sprites["trainer_#{i}"]; end
  def stageLightPos(j)
    data = EliteBattle.get(:battlerMetrics)
    return if data.nil?
    x = 0; y = 0
    for param in [:X, :Y, :Z]
      next if data[j].nil? || !data[j].has_key?(param)
      dat = data[j][param]
      x = dat[0] if param == :X
      y = dat[0] if param == :Y
    end
    return x, y
  end
  def spoof(vector, index = 1)
    target = self.battler(index)
    bx, by = @scene.vector.spoof(vector)
    # updates to the spatial warping with respect to the scene vector
    dx, dy = @scene.vector.spoof(@defaultvector)
    bzoom_x = @scale*((bx - vector[0])*1.0/(dx - @defaultvector[0])*1.0)**0.6
    bzoom_y = @scale*((by - vector[1])*1.0/(dy - @defaultvector[1])*1.0)**0.6
    x = bx - (@sprites["bg"].ox - target.ex)*bzoom_x
    y = by - (@sprites["bg"].oy - target.ey)*bzoom_y
    return x, y
  end
  #-----------------------------------------------------------------------------
  # change out the data hash and redraw battle environment
  #-----------------------------------------------------------------------------
  def reconfigure(data, transition = Color.black, userIndex = 0, targetIndex = 0, hitnum = 0)
    data = getConst(EnvironmentEBDX, data) if data.is_a?(Symbol)
    # failsafe
    if !data.is_a?(Hash)
      EliteBattle.log.warn("Unable to load battle environment for: #{data}")
      return
    end
    # if with transition
    if transition.is_a?(Symbol)
      @queued = data.clone
      return EliteBattle.playCommonAnimation(transition, @scene, userIndex, targetIndex, hitnum)
    end
    # construct transition animation object
    trans = Sprite.new(@viewport) if !transition.nil?
    if transition.is_a?(Color)
      trans.create_rect(@viewport.width, @viewport.height, transition)
    elsif transition.is_a?(String)
      begin
        trans.bitmap = pbBitmap(transition)
      rescue
        trans.bitmap = Bitmap.new(@viewport.width, @viewport.height)
      end
    end
    trans.opacity = 0  if !transition.nil?
    # push elements out of focus
    self.defocus
    # fade through transition element
    if !transition.nil?
      8.times { trans.opacity += 32; @scene.wait }
    end
    # set new data Hash
    @data = data.clone
    self.refresh(data)
    self.defocus
    # fade through transition element
    if !transition.nil?
      8.times { trans.opacity -= 32; @scene.wait }
    end
    self.focus
    # dispose of transition element
    trans.dispose if !transition.nil?
  end
  #-----------------------------------------------------------------------------
  # change out data hash (simple)
  #-----------------------------------------------------------------------------
  def configure
    return if @queued.nil? || !@queued.is_a?(Hash)
    @data = @queued.clone
    self.refresh(@data)
    @queued = nil
  end
  #-----------------------------------------------------------------------------
  # reset to original data hash
  #-----------------------------------------------------------------------------
  def reset(transition = Color.black)
    self.reconfigure(@backup, transition)
  end
  #-----------------------------------------------------------------------------
end
