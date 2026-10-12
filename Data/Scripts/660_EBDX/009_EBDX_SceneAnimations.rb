#===============================================================================
#  009_EBDX_SceneAnimations.rb
#  Combined EBDX Scene Animations adapted for KIF Multiplayer
#
#  Contains:
#    - EliteBattle module: move/common animation storage and playback
#    - AnimationHelperEBDX: helper class for constructing battle animations
#    - EBBallBurst: ball burst particle animation class
#    - EBDustParticle: dust particle animation class
#    - EBDXSceneAnimationMethods: module with all PokeBattle_Scene methods
#      (to be included in PokeBattle_SceneEBDX)
#
#  KIF Notes:
#    - DynamicPokemonSprite references removed; uses PokemonBattlerSprite instead
#    - DynamicTrainerSprite references removed; uses standard trainer sprites
#===============================================================================

#===============================================================================
#  Module core used to store and load common and move animations
#===============================================================================
module EliteBattle
  #-----------------------------------------------------------------------------
  # animation map
  @@physical = {}
  @@special = {}
  @@status = {}
  @@allOpp = {}
  @@nonUsr = {}
  @@multihit = {}
  #-----------------------------------------------------------------------------
  # registered animations
  @@moveAnimations = {}
  @@commonAnimations = {}
  #-----------------------------------------------------------------------------
  #  function used to run Move Animations with implicit variables
  #-----------------------------------------------------------------------------
  def self.withMoveParams(anim, id, scene, userindex, targetindex, hitnum, multihit, *args)
    # initialize wrapper and pass instance variables
    MultiplayerDebug.info("EBDX-ANIM", "withMoveParams START: id=#{id}, userindex=#{userindex}, targetindex=#{targetindex}") if defined?(MultiplayerDebug)
    scene.inMoveAnim = 0 if !anim.nil?
    wrapper = CallbackWrapper.new
    system  =   { :scene => scene, :battle => scene.battle, :sprites => scene.sprites,
                 :userSprite => scene.sprites["pokemon_#{userindex}"],
                 :targetSprite => scene.sprites["pokemon_#{targetindex}"],
                 :userDatabox => scene.sprites["dataBox_#{userindex}"],
                 :targetDatabox => scene.sprites["dataBox_#{targetindex}"],
                 :multiHit => multihit, :hitNum => hitnum, :itself => (userindex == targetindex),
                 :userIsPlayer => (userindex%2 == 0), :targetIsPlayer => (targetindex%2 == 0),
                 :vector => scene.vector, :battlers => scene.battlers, :opponent => scene.battle.opponent,
                 :userIndex => userindex, :targetIndex => targetindex, :viewport => scene.viewport
    }
    system[:helper] = AnimationHelperEBDX.new(system, id)
    wrapper.set(system)
    # run animation code
    success = false
    begin
      MultiplayerDebug.info("EBDX-ANIM", "withMoveParams EXECUTING animation...") if defined?(MultiplayerDebug)
      wrapper.execute(anim, *args)
      MultiplayerDebug.info("EBDX-ANIM", "withMoveParams SUCCESS") if defined?(MultiplayerDebug)
      success = true
    rescue => e
      # safety code, no need to crash game for bad animation
      msg  = "\r\nUnable to play animation for: #{id.to_s}\r\n"
      msg += "Error: #{e.message}\r\n"
      msg += "Backtrace:\r\n"
      e.backtrace[0, 10].each { |i| msg += "#{i}\r\n" }
      EliteBattle.log.warn(msg)
      MultiplayerDebug.warn("EBDX-ANIM", "withMoveParams FAILED: #{e.message}") if defined?(MultiplayerDebug)
    ensure
      # Safety cleanup: reset viewport color/tone to prevent lingering tints
      # (e.g., if animation crashed after creating a dark overlay or setting viewport color)
      if scene && scene.viewport
        scene.viewport.color = Color.new(0, 0, 0, 0) rescue nil
        scene.viewport.tone = Tone.new(0, 0, 0, 0) rescue nil
      end
    end
    return success
  end
  #-----------------------------------------------------------------------------
  #  function used to run Common Animations with implicit variables
  #-----------------------------------------------------------------------------
  def self.withCommonParams(anim, id, scene, userindex, targetindex, hitnum, *args)
    # initialize wrapper and pass instance variables
    MultiplayerDebug.info("EBDX-ANIM", "withCommonParams START: id=#{id}, userindex=#{userindex}, targetindex=#{targetindex}") if defined?(MultiplayerDebug)
    wrapper = CallbackWrapper.new
    system  =   { :scene => scene, :battle => scene.battle, :sprites => scene.sprites,
                 :userSprite => scene.sprites["pokemon_#{userindex}"],
                 :targetSprite => scene.sprites["pokemon_#{targetindex}"],
                 :userDatabox => scene.sprites["dataBox_#{userindex}"],
                 :targetDatabox => scene.sprites["dataBox_#{targetindex}"],
                 :hitNum => hitnum, :itself => (userindex == targetindex),
                 :userIsPlayer => (userindex%2 == 0), :targetIsPlayer => (targetindex%2 == 0),
                 :vector => scene.vector, :battlers => scene.battlers, :opponent => scene.battle.opponent,
                 :userIndex => userindex, :targetIndex => targetindex, :viewport => scene.viewport
    }
    system[:helper] = AnimationHelperEBDX.new(system, id)
    wrapper.set(system)
    # run animation code
    success = false
    begin
      MultiplayerDebug.info("EBDX-ANIM", "withCommonParams EXECUTING animation...") if defined?(MultiplayerDebug)
      wrapper.execute(anim, *args)
      MultiplayerDebug.info("EBDX-ANIM", "withCommonParams SUCCESS") if defined?(MultiplayerDebug)
      success = true
    rescue => e
      # safety code, no need to crash game for bad animation
      msg  = "\r\nUnable to play animation for: #{id.to_s}\r\n"
      msg += "Error: #{e.message}\r\n"
      msg += "Backtrace:\r\n"
      e.backtrace[0, 10].each { |i| msg += "#{i}\r\n" }
      EliteBattle.log.warn(msg)
      MultiplayerDebug.warn("EBDX-ANIM", "withCommonParams FAILED: #{e.message}") if defined?(MultiplayerDebug)
    ensure
      # Safety cleanup: reset viewport color/tone to prevent lingering tints
      if scene && scene.viewport
        scene.viewport.color = Color.new(0, 0, 0, 0) rescue nil
        scene.viewport.tone = Tone.new(0, 0, 0, 0) rescue nil
      end
    end
    return success
  end
  #-----------------------------------------------------------------------------
  #  function used to store Move Animations
  #-----------------------------------------------------------------------------
  def self.defineMoveAnimation(id, species = nil, process = nil, &block)
    if species.is_a?(Proc)
      process = species
      species = nil
    end
    # raise error message for incorrectly defined moves
    if process.nil? && block.nil?
      msg = "EBDX: No code block defined for move #{id}!"
      EliteBattle.log.error(msg)
    end
    # format ID for species specific move animation
    id = "#{species}=>#{id}" if !species.nil?
    # register regular move animation
    @@moveAnimations[id] = !process.nil? ? process : block
  end
  #-----------------------------------------------------------------------------
  #  function bulk copy Move Animations
  #-----------------------------------------------------------------------------
  def self.copyMoveAnimation(key, *args)
    return if !@@moveAnimations.has_key?(key)
    for k in args
      next if key == k
      @@moveAnimations[k] = key
    end
  end
  #-----------------------------------------------------------------------------
  #  function used to load Move Animations
  #-----------------------------------------------------------------------------
  def self.playMoveAnimation(id, scene, userindex, targetindex, hitnum = 0, multihit = false, species = nil, *args)
    # Normalize string IDs to symbols - animations are always registered with symbol keys
    id = id.to_sym if id.is_a?(String)
    MultiplayerDebug.info("EBDX-ANIM", "playMoveAnimation: id=#{id.inspect}, registered=#{@@moveAnimations.has_key?(id)}, all_keys=#{@@moveAnimations.keys.inspect}") if defined?(MultiplayerDebug)
    # attempt to play species specific move animation
    if !species.nil? && @@moveAnimations.has_key?("#{species}=>#{id}")
      return self.withMoveParams(@@moveAnimations["#{species}=>#{id}"], id, scene, userindex, targetindex, hitnum, multihit, *args)
    end
    # attempt to play regular move animation
    if !@@moveAnimations.has_key?(id)
      EliteBattle.log.debug("No EBDX Move Animation found for: #{id}")
      return false
    end
    # playback of cloned move animations
    if @@moveAnimations[id].is_a?(Symbol)
      return self.withMoveParams(@@moveAnimations[@@moveAnimations[id]], id, scene, userindex, targetindex, hitnum, multihit, *args)
    # playback of regular move animations
    else
      return self.withMoveParams(@@moveAnimations[id], id, scene, userindex, targetindex, hitnum, multihit, *args)
    end
  end
  #-----------------------------------------------------------------------------
  #  function used to get all defined animations (for Debug purposes)
  #-----------------------------------------------------------------------------
  def self.getDefinedAnimations
    moves = []; common = []
    for key in @@moveAnimations.keys
      key = getConstantName(PBMoves, key) if key.is_a?(Numeric)
      moves.push(key.to_s)
    end
    for key in @@commonAnimations.keys
      common.push(key.to_s)
    end
    return moves, common
  end
  #-----------------------------------------------------------------------------
  #  function used to store Common Animations
  #-----------------------------------------------------------------------------
  def self.defineCommonAnimation(symbol, process = nil, &block)
    @@commonAnimations[symbol] = !process.nil? ? process : block
  end
  #-----------------------------------------------------------------------------
  #  function bulk copy Common Animations
  #-----------------------------------------------------------------------------
  def self.copyCommonAnimation(key, *args)
    return if !@@commonAnimations.has_key?(key)
    for k in args
      next if key == k
      @@commonAnimations[k] = key
    end
  end
  #-----------------------------------------------------------------------------
  #  function used to load Common Animations
  #-----------------------------------------------------------------------------
  def self.playCommonAnimation(id, scene, userindex, targetindex = nil, hitnum = 0, *args)
    targetindex = userindex if targetindex.nil?
    MultiplayerDebug.info("EBDX-ANIM", "playCommonAnimation: id=#{id.inspect}, registered=#{@@commonAnimations.has_key?(id)}, all_keys=#{@@commonAnimations.keys.inspect}") if defined?(MultiplayerDebug)
    if !@@commonAnimations.has_key?(id)
      EliteBattle.log.debug("No EBDX Common Animation found for: #{id}")
      return false
    end
    # playback of cloned common animations
    if @@commonAnimations[id].is_a?(Symbol)
      return self.withCommonParams(@@commonAnimations[@@commonAnimations[id]], id, scene, userindex, targetindex, hitnum, *args)
    # playback of regular common animations
    else
      return self.withCommonParams(@@commonAnimations[id], id, scene, userindex, targetindex, hitnum, *args)
    end
  end
  #-----------------------------------------------------------------------------
  #  map move to one of global animations
  #-----------------------------------------------------------------------------
  def self.mapMoveGlobal(scene, type, userindex, targetindex, hitnum, multihit, multitarget, category)
    return false if type.nil?
    id = nil
    id = @@allOpp[type] if id.nil? && multitarget == :AllFoes
    id = @@nonUsr[type] if id.nil? && multitarget == :AllNearFoes
    id = @@multihit[type] if id.nil? && multihit
    id = [@@physical, @@special, @@status][category][type] if id.nil?
    return false if id.nil?
    return false if hitnum > 0
    return EliteBattle.playMoveAnimation(id, scene, userindex, targetindex, 0, multihit)
  end
  #-----------------------------------------------------------------------------
end

#===============================================================================
#  Animation helper for constructing battle animations
#===============================================================================
class AnimationHelperEBDX
  attr_accessor :anchor, :buffer
  attr_reader :cur_frame, :max_duration, :components
  #-----------------------------------------------------------------------------
  #  main constructor for helper
  #-----------------------------------------------------------------------------
  def initialize(data, anim)
    # configure component variables
    @data = data
    @anim = anim
    @scene = data[:scene]
    @sprites = data[:sprites]
    @vector = data[:vector]
    @components = {}
    @anchor = false
    # default functions for animation components
    @comp_func = {
      "finished?" => "return @finished",
      "hit=(val)" => "@with_hit=val",
      "hit?" => "return @hit",
      "default_duration" => "return @options[:duration] ? @options[:duration] : 1.5",
      "dispose" => "@sprites.keys.each{|k|@sprites[k].dispose};self.reset"
    }
    # configure components to calculate
    @max_duration = 0.0
    @cur_frame = 0.0
    @fin_frame = -1
    @buffer = 0.5
    @all_finished = false
  end
  #-----------------------------------------------------------------------------
  #  register animation helper component
  #-----------------------------------------------------------------------------
  def add_component(id, type, start, duration, options = {})
    if !id.is_a?(Symbol) && !id.is_a?(String)
      EliteBattle.log.warn("Animation component ID for animation `#{@anim.to_s}` has to be expressed as a string or symbol. #{id} is not valid.")
    elsif eval("defined?(EBDX_Anim_#{type.to_s.upcase})")
      # exception for basic sprites (to apply stacked effects)
      if type == :BASIC_SPRITE && @components.keys.include?(id)
        i = 0
        loop do
          break if !@components.keys.include?("#{id}_#{i}"); i += 1
        end
        # set new ID and modify options
        options[:sprite] = @components[id].sprite
        id = "#{id}_#{i}"
      end
      # construct component
      @components[id] = eval("EBDX_Anim_#{type.to_s.upcase}.new")
      # set the mandatory config variables for each component
      { :options => options,
        :start => start,
        :duration => duration,
        :hit => false,
        :with_hit => nil,
        :hit_time => 0,
        :finished => false,
        :sprites => {}
      }.each { |key, value| @components[id].instance_variable_set("@#{key.to_s}", value) }
      # define mandatory setter and getter
      [:start, :duration, :finished, :hit_time, :with_hit
      ].each { |arg| @components[id].singleton_class.class_eval("def #{arg.to_s};@#{arg.to_s};end") }
      [:start, :duration, :finished].each { |arg| @components[id].singleton_class.class_eval("def #{arg.to_s}=(val);@#{arg.to_s}=val;end") }
      # define other mandatory functions
      @comp_func.each do |key, func|
        func = "def #{key};#{func};end"
        key = key.include?("=") ? key.split("=")[0] : key
        @components[id].singleton_class.class_eval(func) if !@components[id].singleton_class.method_defined?(key.to_sym)
      end
      # associate all the instance variables
      @data.each do |key, value|
        next if [:sprites].include?(key)
        @components[id].instance_variable_set("@#{key.to_s}", value)
      end
      # begin configuration
      @components[id].configure
      # calculate overall animation duration
      self.calc_duration(id)
    else
      # print message if component not found
      EliteBattle.log.warn("Cannot load non-existent animation component for animation `#{@anim.to_s}`: EBDX_Anim_#{type.to_s.upcase}.")
    end
  end
  #-----------------------------------------------------------------------------
  #  play constructed animation
  #-----------------------------------------------------------------------------
  def play
    @sprites["battlebg"].defocus
    # start the main loop
    loop do
      break if @cur_frame > (@all_finished ? @fin_frame : @max_duration)
      @anchor = false
      @all_finished = true
      # play components
      for key in @components.keys
        comp = @components[key]
        if @cur_frame >= (comp.start)
          next if comp.with_hit && !@components[comp.with_hit].hit?
          comp.finished = true if self.elapsed(comp, true) > comp.duration - @buffer
          comp.play
        end
        @all_finished = false if !comp.finished?
      end
      # update scene
      @scene.wait(1, @anchor)
      # increment by delta
      @cur_frame += 1.0/(self.delta*40.0)
      # register animation for end of life if all components have finished
      @fin_frame = @cur_frame + (@buffer*Graphics.frame_rate)/(self.delta*40.0) if @all_finished && @fin_frame < 0
    end
    # dispose of the components
    self.dispose
    @sprites["battlebg"].focus
    @vector.reset if !@data[:multiHit]
    @vector.inc = 0.2
  end
  #-----------------------------------------------------------------------------
  #  calculate duration for component
  #-----------------------------------------------------------------------------
  def calc_duration(id)
    comp = @components[id]
    # basic duration calculation
    if comp.start.is_a?(Numeric) && comp.duration.is_a?(Numeric)
      @max_duration = [@max_duration, (comp.start + comp.duration)].max
      return
    end
    # duration based on components
    if @components.has_key?(comp.start)
      # register start time
      start = @components[comp.start].start
      # calculate based on association
      if comp.duration.is_a?(Numeric)
        duration = comp.duration
      elsif [:WITH, :HIT].include?(comp.duration)
        comp.hit = comp.start if comp.duration == :HIT
        duration = @components[comp.start].duration
      elsif comp.duration == :MID
        start = @components[comp.start].start + @components[comp.start].duration/2.0
        duration = comp.default_duration
      elsif comp.duration == :AFTER
        start = @components[comp.start].start + @components[comp.start].duration
        duration = comp.default_duration
      end
      # apply new start and duration
      comp.start = start
      comp.duration = duration
      # calculate max duration
      @max_duration = [@max_duration, (start + duration)].max
    else
      # failsafe
      comp.start = 0
      comp.duration = 0
    end
  end
  #-----------------------------------------------------------------------------
  #  utility functions
  #-----------------------------------------------------------------------------
  def dispose; @components.keys.each { |k| @components[k].dispose }; end
  def delta; return Graphics.frame_rate/40.0; end
  def elapsed(comp, local = false)
    # get the number of frames elapsed from the component animation start
    return @cur_frame - comp.start if !comp.with_hit || local
    return @cur_frame - (@components[comp.with_hit].start + @components[comp.with_hit].hit_time)
  end
  #-----------------------------------------------------------------------------
end

#===============================================================================
#  Class handling the ball burst animation
#===============================================================================
class EBBallBurst
  #-----------------------------------------------------------------------------
  #  class inspector
  #-----------------------------------------------------------------------------
  def inspect
    str = self.to_s.chop
    str << format(' ball type: %s>', @balltype)
    return str
  end
  #-----------------------------------------------------------------------------
  #  class constructor; setting up all the particles
  #-----------------------------------------------------------------------------
  def initialize(viewport, x = 0, y = 0, z = 50, factor = 1, balltype = :POKEBALL)
    # defaults to regular Pokeball particles if specific ones cannot be found
    balltype = :POKEBALL if pbResolveBitmap("Graphics/EBDX/Animations/Ballburst/#{balltype.to_s}_shine").nil?
    # configuring main variables
    @balltype = balltype
    @viewport = viewport
    @factor = factor
    @fp = {}; @index = 0; @tone = 255.0
    @pzoom = []; @szoom = []; @poy = []; @rangl = []; @rad = []
    @catching = false
    @recall = false
    # ray particles
    for j in 0...8
      @fp["s#{j}"] = Sprite.new(@viewport)
      @fp["s#{j}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Ballburst/#{balltype.to_s}_ray")
      @fp["s#{j}"].oy = @fp["s#{j}"].bitmap.height/2
      @fp["s#{j}"].zoom_x = 0
      @fp["s#{j}"].zoom_y = 0
      @fp["s#{j}"].tone = Tone.new(255,255,255)
      @fp["s#{j}"].x = x
      @fp["s#{j}"].y = y
      @fp["s#{j}"].z = z
      @fp["s#{j}"].angle = rand(360)
      @szoom.push([1.0,1.25,0.75,0.5][rand(4)]*@factor)
    end
    # inner glow particle
    @fp["cir"] = Sprite.new(@viewport)
    @fp["cir"].bitmap = pbBitmap("Graphics/EBDX/Animations/Ballburst/#{balltype.to_s}_shine")
    @fp["cir"].center!
    @fp["cir"].x = x
    @fp["cir"].y = y
    @fp["cir"].zoom_x = 0
    @fp["cir"].zoom_y = 0
    @fp["cir"].tone = Tone.new(255,255,255)
    @fp["cir"].z = z
    # additional particle effects
    for k in 0...16
      str = ["particle","eff"][rand(2)]
      @fp["p#{k}"] = Sprite.new(@viewport)
      @fp["p#{k}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Ballburst/#{balltype.to_s}_#{str}")
      @fp["p#{k}"].center!
      @pzoom.push([1.0,0.3,0.75,0.5][rand(4)]*@factor)
      @fp["p#{k}"].zoom_x = 1*@factor
      @fp["p#{k}"].zoom_y = 1*@factor
      @fp["p#{k}"].tone = Tone.new(255,255,255)
      @fp["p#{k}"].x = x
      @fp["p#{k}"].y = y
      @fp["p#{k}"].z = z
      @fp["p#{k}"].opacity = 0
      @fp["p#{k}"].angle = rand(360)
      @rangl.push(rand(360))
      @poy.push(rand(4)+3)
      @rad.push(0)
    end
    # applies coordinates throughout whole class
    @x = x; @y = y; @z = z
  end
  #-----------------------------------------------------------------------------
  #  updates the entire animation
  #-----------------------------------------------------------------------------
  def update
    # reverses the animation if capturing a Pokemon
    return self.reverse if @catching
    # @index mainly used for animation frame separation
    # animates ray particles
    for j in 0...8
      next if @index < 4; next if j > (@index-4)/2
      @fp["s#{j}"].zoom_x += (@szoom[j]*0.1)
      @fp["s#{j}"].zoom_y += (@szoom[j]*0.1)
      @fp["s#{j}"].opacity -= 8 if @fp["s#{j}"].zoom_x >= 1
    end
    # animates additional particle effects
    for k in 0...16
      next if @index < 4; next if k > (@index-4)
      @fp["p#{k}"].opacity += 25.5 if @index < 22
      @fp["p#{k}"].zoom_x -= (@fp["p#{k}"].zoom_x - @pzoom[k])*0.1
      @fp["p#{k}"].zoom_y -= (@fp["p#{k}"].zoom_y - @pzoom[k])*0.1
      a = @rangl[k]
      @rad[k] += @poy[k]*@factor; r = @rad[k]
      x = @x + r*Math.cos(a*(Math::PI/180))
      y = @y - r*Math.sin(a*(Math::PI/180))
      @fp["p#{k}"].x = x
      @fp["p#{k}"].y = y
      @fp["p#{k}"].angle += 4
    end
    # changes the opacity value depending on position in animation
    if @index >= 22
      for j in 0...8
        @fp["s#{j}"].opacity -= 26
      end
      for k in 0...16
        @fp["p#{k}"].opacity -= 26
      end
      @fp["cir"].opacity -= 26
    end
    # changes tone of animation depending on position in animation
    @tone -= 25.5 if @index >= 4 && @tone > 0
    for j in 0...8
      @fp["s#{j}"].tone = Tone.new(@tone,@tone,@tone)
    end
    for k in 0...16
      @fp["p#{k}"].tone = Tone.new(@tone,@tone,@tone)
    end
    # animates center shine
    @fp["cir"].tone = Tone.new(@tone,@tone,@tone)
    @fp["cir"].zoom_x += (@factor*1.5 - @fp["cir"].zoom_x)*0.06
    @fp["cir"].zoom_y += (@factor*1.5 - @fp["cir"].zoom_y)*0.06
    @fp["cir"].angle -= 4 if $PokemonSystem.screensize < 2
    # increments index
    @index += 1
  end
  #-----------------------------------------------------------------------------
  #  plays reversed animation
  #-----------------------------------------------------------------------------
  def reverse
    # changes tone of animation depending on position in animation
    @tone -= 25.5 if @index >= 4 && @tone > 0
    # animates shine (but not if recalling battlers)
    for j in 0...8
      next if @index < 4; next if j > (@index-4)/2; next if @recall
      @fp["s#{j}"].zoom_x += (@szoom[j]*0.1)
      @fp["s#{j}"].zoom_y += (@szoom[j]*0.1)
      @fp["s#{j}"].opacity -= 8 if @fp["s#{j}"].zoom_x >= 1
    end
    if @index >= 22
      for j in 0...8
        @fp["s#{j}"].opacity -= 26
      end
    end
    for j in 0...8
      @fp["s#{j}"].tone = Tone.new(@tone,@tone,@tone)
    end
    # animates additional particles
    for k in 0...16
      a = k*22.5 + 11.5 + @index*4
      r = 128*@factor - @index*8*@factor
      x = @x + r*Math.cos(a*(Math::PI/180))
      y = @y - r*Math.sin(a*(Math::PI/180))
      @fp["p#{k}"].x = x
      @fp["p#{k}"].y = y
      @fp["p#{k}"].angle += 8
      @fp["p#{k}"].opacity += 32 if @index < 8
      @fp["p#{k}"].opacity -= 32 if @index >= 8
    end
    # animates central shine particle
    @fp["cir"].tone = Tone.new(@tone,@tone,@tone)
    @fp["cir"].zoom_x -= (@fp["cir"].zoom_x - 0.5*@factor)*0.06
    @fp["cir"].zoom_y -= (@fp["cir"].zoom_y - 0.5*@factor)*0.06
    @fp["cir"].opacity += 25.5 if @index < 16
    @fp["cir"].opacity -= 16 if @index >= 16
    @fp["cir"].angle -= 4 if $PokemonSystem.screensize < 2
    # increments index
    @index += 1
  end
  #-----------------------------------------------------------------------------
  #  disposes all particle effects
  #-----------------------------------------------------------------------------
  def dispose
    pbDisposeSpriteHash(@fp)
  end
  #-----------------------------------------------------------------------------
  #  configures animation for when capturing Pokemon
  #-----------------------------------------------------------------------------
  def catching
    @catching = true
    for k in 0...16
      a = k*22.5 + 11.5
      r = 128*@factor
      x = @x + r*Math.cos(a*(Math::PI/180))
      y = @y - r*Math.sin(a*(Math::PI/180))
      @fp["p#{k}"].x = x
      @fp["p#{k}"].y = y
      @fp["p#{k}"].tone = Tone.new(0,0,0)
      @fp["p#{k}"].opacity = 0
      str = ["particle", "eff"][k%2]
      @fp["p#{k}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Ballburst/#{@balltype.to_s}_#{str}")
      @fp["p#{k}"].ox = @fp["p#{k}"].bitmap.width/2
      @fp["p#{k}"].oy = @fp["p#{k}"].bitmap.height/2
    end
    @fp["cir"].zoom_x = 2*@factor
    @fp["cir"].zoom_y = 2*@factor
  end
  #-----------------------------------------------------------------------------
  #  configures animation for when Recalling
  #-----------------------------------------------------------------------------
  def recall
    @recall = true
    self.catching
  end
  #-----------------------------------------------------------------------------
end

#===============================================================================
#  Class handling the dust animation when heavy battlers enter scene
#===============================================================================
class EBDustParticle
  #-----------------------------------------------------------------------------
  #  class inspector
  #-----------------------------------------------------------------------------
  def inspect
    str = self.to_s.chop
    str << format(' sprite: %s>', @sprite.inspect)
    return str
  end
  #-----------------------------------------------------------------------------
  #  class constructor
  #-----------------------------------------------------------------------------
  def initialize(viewport, sprite, factor = 1)
    @viewport = viewport
    @sprite = sprite
    @x = sprite.x; @y = sprite.y; @z = sprite.z
    @factor = sprite.zoom_x
    @index = 0; @fp = {}
    width = sprite.bitmap.width/2 - 16
    @max = 16 + (width/16)
    # initializes all the particles
    for j in 0...@max
      @fp["#{j}"] = Sprite.new(@viewport)
      @fp["#{j}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/ebDustParticle")
      @fp["#{j}"].ox = @fp["#{j}"].bitmap.width/2
      @fp["#{j}"].oy = @fp["#{j}"].bitmap.height/2
      @fp["#{j}"].opacity = 0
      @fp["#{j}"].angle = rand(360)
      @fp["#{j}"].x = @x - width*@factor + rand(width*2*@factor)
      @fp["#{j}"].y = @y - 16*@factor + rand(32*@factor)
      @fp["#{j}"].z = @z + (@fp["#{j}"].y < @y ? -1 : 1)
      zoom = [1,0.8,0.9,0.7][rand(4)]
      @fp["#{j}"].zoom_x = zoom*@factor
      @fp["#{j}"].zoom_y = zoom*@factor
    end
  end
  #-----------------------------------------------------------------------------
  #  updates animation frame
  #-----------------------------------------------------------------------------
  def update
    i = @index
    for j in 0...@max
      @fp["#{j}"].opacity += 25.5 if i < 10
      @fp["#{j}"].opacity -= 25.5 if i >= 14
      if @fp["#{j}"].x >= @x
        @fp["#{j}"].angle += 4
        @fp["#{j}"].x += 2
      else
        @fp["#{j}"].angle -= 4
        @fp["#{j}"].x -= 2
      end
    end
    @index += 1
  end
  #-----------------------------------------------------------------------------
  #  disposes of particles
  #-----------------------------------------------------------------------------
  def dispose
    pbDisposeSpriteHash(@fp)
  end
  #-----------------------------------------------------------------------------
end

#===============================================================================
#  Module containing all EBDX scene animation methods
#  Include this in PokeBattle_SceneEBDX to gain all functionality
#===============================================================================
module EBDXSceneAnimationMethods
  #-----------------------------------------------------------------------------
  #  Scene Camera / Vector
  #-----------------------------------------------------------------------------
  # attr_reader :vector  # (defined on the including class if needed)

  #-----------------------------------------------------------------------------
  #  Misc code to automate sprite animation and placement
  #-----------------------------------------------------------------------------
  def animateScene(align = false, smanim = false, &block)
    # special intro animations
    @smTrainerSequence.update if @smTrainerSequence && @smTrainerSequence.started
    @smSpeciesSequence.update if @smSpeciesSequence && @smSpeciesSequence.started
    @integratedVSSequence.update if @integratedVSSequence
    @integratedVSSequence.finish if @introdone && @integratedVSSequence
    @playerLineUp.update if @playerLineUp && !@playerLineUp.disposed?
    @opponentLineUp.update if @opponentLineUp && !@opponentLineUp.disposed?
    # update block if given
    block.call if block
    @fancyMsg.update if @fancyMsg && !@fancyMsg.disposed?
    # dex data
    @sprites["dexdata"].update if @sprites["dexdata"]
    pbHideAllDataboxes if @sprites["dexdata"]
    # vector update
    @vector.update
    # trick for clearing message windows
    if @inMoveAnim.is_a?(Numeric)
      @inMoveAnim += 1
      if @inMoveAnim > Graphics.frame_rate*0.5
        clearMessageWindow
        @inMoveAnim = false
      end
    end
    # backdrop update
    @sprites["battlebg"].update
    @sprites["trainer_Anim"].update if @sprites["trainer_Anim"]
    if @sprites["trainer_Anim"] && @introdone && @sprites["trainer_Anim"].opacity > 0
      @sprites["trainer_Anim"].opacity -= 8
    end
    @idleTimer += 1 if @idleTimer && @idleTimer >= 0
    @lastMotion = nil if @idleTimer && @idleTimer < 0
    @sprites["player_"].x += (40-@sprites["player_"].x)/4 if @safaribattle && @sprites["player_"] && @playerfix
    # update battler sprites
    # KIF: Uses PokemonBattlerSprite instead of DynamicPokemonSprite
    @battle.battlers.each_with_index do |b, i|
      if b
        unless EliteBattle.get(:smAnim)
          if @sprites["pokemon_#{i}"] && @sprites["pokemon_#{i}"].loaded
            status = @battle.battlers[i].status
            case status
            when :SLEEP
              @sprites["pokemon_#{i}"].actualBitmap.setSpeed(3) if @sprites["pokemon_#{i}"].respond_to?(:actualBitmap)
            when :PARALYSIS
              @sprites["pokemon_#{i}"].actualBitmap.setSpeed(2) if @sprites["pokemon_#{i}"].respond_to?(:actualBitmap)
              @sprites["pokemon_#{i}"].status = 2 if @sprites["pokemon_#{i}"].respond_to?(:status=)
            when :FROZEN
              @sprites["pokemon_#{i}"].actualBitmap.setSpeed(0) if @sprites["pokemon_#{i}"].respond_to?(:actualBitmap)
              @sprites["pokemon_#{i}"].status = 3 if @sprites["pokemon_#{i}"].respond_to?(:status=)
            when :POISON
              @sprites["pokemon_#{i}"].status = 1 if @sprites["pokemon_#{i}"].respond_to?(:status=)
            when :BURN
              @sprites["pokemon_#{i}"].status = 4 if @sprites["pokemon_#{i}"].respond_to?(:status=)
            else
              @sprites["pokemon_#{i}"].actualBitmap.setSpeed(1) if @sprites["pokemon_#{i}"].respond_to?(:actualBitmap)
              @sprites["pokemon_#{i}"].status = 0 if @sprites["pokemon_#{i}"].respond_to?(:status=)
            end
          end
          if @sprites["pokemon_#{i}"]
            @sprites["pokemon_#{i}"].update(@sprites["battlebg"].scale_y) if @sprites["pokemon_#{i}"].respond_to?(:update)
            @sprites["pokemon_#{i}"].shadowUpdate if @sprites["pokemon_#{i}"].respond_to?(:shadowUpdate)
            @sprites["pokemon_#{i}"].chargedUpdate if @sprites["pokemon_#{i}"].respond_to?(:chargedUpdate)
            @sprites["pokemon_#{i}"].energyUpdate if @sprites["pokemon_#{i}"].respond_to?(:energyUpdate)
          end
          @sprites["dataBox_#{i}"].update if @sprites["dataBox_#{i}"] && @sprites["pokemon_#{i}"] && @sprites["pokemon_#{i}"].loaded
        end
        if !@orgPos.nil? && @idleTimer && @idleTimer > (@lastMotion.nil? ? EliteBattle::BATTLE_MOTION_TIMER*Graphics.frame_rate : EliteBattle::BATTLE_MOTION_TIMER*Graphics.frame_rate*0.5) && @vector.finished? && !@safaribattle
          @vector.inc = 0.005*(rand(4)+1)
          a = EliteBattle.random_vector(@battle, @lastMotion)
          @lastMotion = rand(a.length)
          setVector(a[@lastMotion])
        end
      end
      # update trainer sprites
      # KIF: Uses standard trainer sprites instead of DynamicTrainerSprite
      if @battle.opponent
        for t in 0...@battle.opponent.length
          next if !@sprites["trainer_#{t}"]
          @sprites["trainer_#{t}"].scale_y = @sprites["battlebg"].scale_y if @sprites["trainer_#{t}"].respond_to?(:scale_y=)
        end
      end
      next if !align
      # align the positions of all sprites in scene
      zoom = (i%2 == 0) ? 2 : 1
      if @sprites["pokemon_#{i}"]
        dmax = (i%2 == 0) ? 4/EliteBattle::BACK_SPRITE_SCALE : 4
        is_dynamax = @sprites["pokemon_#{i}"].respond_to?(:dynamax) && @sprites["pokemon_#{i}"].dynamax
        zoomer = (@vector.zoom1**0.75) * zoom * (is_dynamax ? dmax : 1)
        @sprites["pokemon_#{i}"].x = @sprites["battlebg"].battler(i).x - (i%2 == 0 ? 64 : -32) * (is_dynamax ? 1 : 0)
        @sprites["pokemon_#{i}"].y = @sprites["battlebg"].battler(i).y + (is_dynamax ? 38 : 0)
        @sprites["pokemon_#{i}"].zoom_x = zoomer
        @sprites["pokemon_#{i}"].zoom_y = zoomer
      end
      if @battle.opponent
        for t in 0...@battle.opponent.length
          next if !@sprites["trainer_#{t}"]
          @sprites["trainer_#{t}"].x = @sprites["battlebg"].trainer(t*2 + 1).x
          @sprites["trainer_#{t}"].y = @sprites["battlebg"].trainer(t*2 + 1).y
          @sprites["trainer_#{t}"].zoom_x = (@vector.zoom1**0.75)
          @sprites["trainer_#{t}"].zoom_y = (@vector.zoom1**0.75)
        end
      end
    end
  end
  #-----------------------------------------------------------------------------
  #  moves all elements inside the scene
  #-----------------------------------------------------------------------------
  def moveEntireScene(x=0, y=0, lock=true, bypass=false, except=nil)
    return if !bypass && EliteBattle::DISABLE_SCENE_MOTION
    for i in 0...4
      next if !i.nil? && i == except
      @sprites["pokemon_#{i}"].x += x if @sprites["pokemon_#{i}"]
      @sprites["pokemon_#{i}"].y += y if @sprites["pokemon_#{i}"]
    end
    @vector.x += x; @vector.y += y
    return if !lock; return if @orgPos.nil?
    @orgPos[0] += x; @orgPos[1] += y
  end
  #-----------------------------------------------------------------------------
  #  scene wait with animation
  #-----------------------------------------------------------------------------
  def wait(frames = 1, align = false, &block)
    frames.times do
      animateScene(align, &block)
      Graphics.update if !EliteBattle.get(:smAnim)
    end
  end
  #-----------------------------------------------------------------------------
  #  sets scene vector
  #-----------------------------------------------------------------------------
  def setVector(*args)
    return if EliteBattle::DISABLE_SCENE_MOTION
    if args[0].is_a?(Array)
      return if args[0].length < 5
      x, y, angle, scale, zoom = args[0]
    else
      return if args.length < 5
      x, y, angle, scale, zoom = args
    end
    vector = EliteBattle.get_vector(:MAIN, @battle)
    x += @orgPos[0] - vector[0]
    y += @orgPos[1] - vector[1]
    angle += @orgPos[2] - vector[2]
    scale += @orgPos[3] - vector[3]
    zoom += @orgPos[4] - vector[4]
    @vector.set(x, y, angle, scale, zoom, 1)
  end
  #-----------------------------------------------------------------------------
  #  resets sprites for move transformations
  #-----------------------------------------------------------------------------
  def revertMoveTransformations(index)
    if @sprites["pokemon_#{index}"] && @sprites["pokemon_#{index}"].respond_to?(:hidden) && @sprites["pokemon_#{index}"].hidden
      @sprites["pokemon_#{index}"].hidden = false
      @sprites["pokemon_#{index}"].visible = true
    end
  end

  #=============================================================================
  #  Animation Core - Common/Damage/HP/EXP/Faint animations
  #=============================================================================

  #-----------------------------------------------------------------------------
  #  Core to play Common Animations
  #-----------------------------------------------------------------------------
  def pbCommonAnimation(animname, user = nil, targets = nil)
    # skips certain common animations from playing
    return false if ["Rain", "HeavyRain", "Hail", "Sandstorm", "Sun", "HarshSun", "StrongWinds", "ShadowSky", "HealthDown"].include?(animname)
    $skipMegaChange = true if animname == "MegaEvolution" && !EliteBattle::CUSTOM_COMMON_ANIM
    return false if ["MegaEvolution", "Shadow"].include?(animname) && !EliteBattle::CUSTOM_COMMON_ANIM
    # plays common animation unless specified to use custom ones
    unless EliteBattle::CUSTOM_COMMON_ANIM || animname.nil? || user.nil?
      symbol = (animname.upcase).to_sym
      targetindex = targets.nil? ? (user.respond_to?(:index) ? user.index : nil) : (targets.respond_to?(:index) ? targets.index : nil)
      return true if EliteBattle.playCommonAnimation(symbol, self, user.index, targetindex)
    end
    # falls back to original def
    return pbCommonAnimation_ebdx(animname, user, targets) if self.respond_to?(:pbCommonAnimation_ebdx)
    return false
  end
  #-----------------------------------------------------------------------------
  #  New methods of displaying the fainting animation
  #-----------------------------------------------------------------------------
  def pbFaintBattler(pkmn)
    # reset variables
    @vector.reset
    # setup objects
    # KIF: Uses PokemonBattlerSprite instead of DynamicPokemonSprite
    poke = @sprites["pokemon_#{pkmn.index}"]
    poke.resetParticles if poke.respond_to?(:resetParticles)
    databox = @sprites["dataBox_#{pkmn.index}"]
    # play cry
    playBattlerCry(@battlers[pkmn.index])
    self.wait(GameData::Species.cry_length(pkmn.species, pkmn.form), true)
    # begin animation
    pbSEPlay("Pkmn faint")
    poke.showshadow = false if poke.respond_to?(:showshadow=)
    if poke.respond_to?(:sprite)
      poke.sprite.src_rect.height = poke.oy
    end
    16.times do
      poke.still if poke.respond_to?(:still)
      if poke.respond_to?(:sprite)
        poke.sprite.src_rect.y -= 7
      end
      poke.opacity -= 16
      databox.opacity -= 32
      self.wait(1, true)
    end
    clearMessageWindow(true)
    # try to remove low HP BGM
    setBGMLowHP(false)
    # reset src_rect
    if poke.bitmap
      poke.src_rect.set(0, 0, poke.bitmap.width, poke.bitmap.height)
    end
    poke.fainted = true if poke.respond_to?(:fainted=)
    poke.charged = false if poke.respond_to?(:charged=)
  end
  #-----------------------------------------------------------------------------
  #  Animate damage state for single battler
  #-----------------------------------------------------------------------------
  def ebDamageStateAnim(battler, effectiveness, i, state)
    sprite = @sprites["pokemon_#{battler.index}"]
    databox = @sprites["dataBox_#{battler.index}"]
    mult = (effectiveness == 0) ? 2 : ((effectiveness == 1) ? 1 : 3)
    # animate sprite
    if i < 2
      sprite.tone.all -= 255*(mult/3.0)
    elsif i < 4
      sprite.tone.all = 255*(mult/3.0)
    elsif i < 6
      sprite.visible = false
      sprite.tone.all = 0
    else
      sprite.visible = true
    end
    sprite.still if sprite.respond_to?(:still)
    # animate databox
    unless state
      databox.x += mult*(i < 4 ? 1 : -1)*(playerBattler?(battler) ? 1 : -1)
      databox.y -= mult*(i < 4 ? 1 : -1)*(playerBattler?(battler) ? 1 : -1)
    end
    databox.update
  end
  #-----------------------------------------------------------------------------
  #  New Pokemon damage animations
  #-----------------------------------------------------------------------------
  def pbHitAndHPLossAnimation(targets)
    @briefMessage = false
    self.afterAnim = false
    # wait
    self.wait(4, true)
    # prepare soundeffect
    effect = []
    indexes = []
    for t in targets
      effect.push(t[2])
      indexes.push(t[0].index)
      @sprites["dataBox_#{t[0].index}"].damage
      @sprites["dataBox_#{t[0].index}"].animateHP(t[1], t[0].hp)
    end
    # play damage SE
    case effect.max
    when 0; pbSEPlay("Battle damage normal")
    when 1; pbSEPlay("Battle damage weak")
    when 2; pbSEPlay("Battle damage super")
    end
    # begin animation
    for k in 1..(effect.max == 2 ? 3 : 2)
      for i in 0...8
        for t in targets
          next if k > (t[2] == 2 ? 3 : 2)
          ebDamageStateAnim(t[0], t[2], i, k > 1)
        end
        # wait frames
        self.wait(1, true)
      end
    end
    # animations for triggering Substitute
    self.substitueAll(indexes)
    # try set low HP BGM music
    setBGMLowHP(false)
    setBGMLowHP(true)
    # try to process the speech
    for t in targets
      # displays opposing trainer message if Pokemon falls to low HP
      hpchange = t[0].hp - t[1]
      handled = pbTrainerBattleSpeech(playerBattler?(t[0]) ? "damage" : "damageOpp") if hpchange.abs/t[0].totalhp.to_f >= 0.6 && hpchange < 0
      handled = pbTrainerBattleSpeech(playerBattler?(t[0]) ? "resist" : "resistOpp") if hpchange.abs/t[0].totalhp.to_f <= 0.1 && hpchange < 0 && !handled
      handled = pbTrainerBattleSpeech(playerBattler?(t[0]) ? "lowHP" : "lowHPOpp") if t[0].hp > 0 && (t[0].hp < t[0].totalhp*0.3) && !handled
      handled = pbTrainerBattleSpeech(playerBattler?(t[0]) ? "halfHP" : "halfHPOpp") if t[0].hp > 0 && (t[0].hp < t[0].totalhp*0.5) && !handled
      break if handled
    end
  end
  #-----------------------------------------------------------------------------
  #  Legacy Pokemon damage animation
  #-----------------------------------------------------------------------------
  def pbDamageAnimation(battler, effectiveness = 0)
    # setup variables
    @briefmessage = false
    self.afterAnim = false
    self.wait(4, true)
    # play damage SE
    case effectiveness
    when 0; pbSEPlay("Battle damage normal")
    when 1; pbSEPlay("Battle damage weak")
    when 2; pbSEPlay("Battle damage super")
    end
    # begin animation
    once = false
    @sprites["dataBox_#{battler.index}"].damage
    (effectiveness == 2 ? 3 : 2).times do
      for i in 0...8
        ebDamageStateAnim(battler, effectiveness, i, once)
        self.wait(1, true)
      end
      once = true
    end
    # animations for triggering Substitute
    self.substitueAll([battler.index])
  end
  #-----------------------------------------------------------------------------
  #  Legacy HP bar damage animation
  #-----------------------------------------------------------------------------
  def pbHPChanged(battler, oldhp, anim = false)
    # set up variables
    databox = @sprites["dataBox_#{battler.index}"]
    @briefmessage = false
    hpchange = battler.hp - oldhp
    # show common animation for health change
    if anim && ($PokemonSystem.battlescene == 0)
      if battler.hp > oldhp
        pbCommonAnimation("HealthUp", battler, nil)
      elsif battler.hp < oldhp
        pbCommonAnimation("HealthDown", battler, nil)
      end
    end
    databox.animateHP(oldhp, battler.hp)
    while databox.animatingHP
      databox.update
      self.wait(1, true)
    end
    # try set low HP BGM music
    setBGMLowHP(false)
    setBGMLowHP(true)
    # displays opposing trainer message if Pokemon falls to low HP
    handled = pbTrainerBattleSpeech(playerBattler?(battler) ? "damage" : "damageOpp") if hpchange.abs/battler.totalhp.to_f >= 0.6 && hpchange < 0
    handled = pbTrainerBattleSpeech(playerBattler?(battler) ? "resist" : "resistOpp") if hpchange.abs/battler.totalhp.to_f <= 0.1 && hpchange < 0 && !handled
    handled = pbTrainerBattleSpeech(playerBattler?(battler) ? "lowHP" : "lowHPOpp") if battler.hp > 0 && (battler.hp < battler.totalhp*0.3) && !handled
    handled = pbTrainerBattleSpeech(playerBattler?(battler) ? "halfHP" : "halfHPOpp") if battler.hp > 0 && (battler.hp < battler.totalhp*0.5) && !handled
    # reset vector if necessary
    @vector.reset if battler.hp <= 0
  end
  #-----------------------------------------------------------------------------
  #  override the change form function
  #-----------------------------------------------------------------------------
  def pbChangePokemon(index, pokemon)
    return $skipMegaChange = false if $skipMegaChange
    ndx = index.respond_to?("index") ? index.index : index
    handled = EliteBattle.playCommonAnimation(:FORMCHANGE, self, ndx, ndx, 0, pokemon)
    return pbChangePokemon_ebdx(index, pokemon) if !handled && self.respond_to?(:pbChangePokemon_ebdx)
  end
  #-----------------------------------------------------------------------------
  #  function to replace battler sprite with substitute sprite
  #-----------------------------------------------------------------------------
  def setSubstitute(index, set = true)
    EliteBattle.playCommonAnimation(:SUBSTITUTE, self, 0, 0, 0, [index], set)
  end
  #-----------------------------------------------------------------------------
  #  function to replace battler sprite with substitute sprite
  #-----------------------------------------------------------------------------
  def substitueAll(targets)
    # check if should perform substitution animation
    new = []
    for t in targets
      pkmn = @battle.battlers[t]
      next if !pkmn || !@sprites["pokemon_#{pkmn.index}"]
      sprite = @sprites["pokemon_#{pkmn.index}"]
      new.push(t) if (pkmn.effects[PBEffects::Substitute] > 0 && !sprite.isSub) ||
                    (pkmn.effects[PBEffects::Substitute] == 0 && sprite.isSub)
    end
    return unless new.length > 0
    EliteBattle.playCommonAnimation(:SUBSTITUTE, self, 0, 0, 0, new, false)
  end
  #-----------------------------------------------------------------------------
  #  New EXP bar animations
  #-----------------------------------------------------------------------------
  def pbEXPBar(battler, startExp, endExp, tempExp1, tempExp2)
    return if !battler
    # calculate EXP animation
    dataBox = @sprites["dataBox_#{battler.index}"]
    dataBox.refreshExpLevel
    expRange      = endExp - startExp
    startExpLevel = expRange == 0 ? 0 : (tempExp1 - startExp)*dataBox.expBarWidth/expRange
    endExpLevel   = expRange == 0 ? 0 : (tempExp2 - startExp)*dataBox.expBarWidth/expRange
    # trigger animation
    pbSEPlay("EBDX/Experience Gain")
    dataBox.animateEXP(startExpLevel, endExpLevel)
    i = 0
    while dataBox.animatingEXP || i < 4
      dataBox.update if dataBox.animatingEXP
      self.wait(1, true); i += 1
    end
    # end animation
    Audio.se_stop
    self.wait(8, true)
  end
  #-----------------------------------------------------------------------------
  #  Play ME when leveling up
  #-----------------------------------------------------------------------------
  def pbLevelUp(*args)
    pbMEPlay("EBDX/Level Up", 80)
    pbLevelUp_ebdx(*args) if self.respond_to?(:pbLevelUp_ebdx)
  end

  #=============================================================================
  #  Battler Sendout - Player
  #=============================================================================

  #-----------------------------------------------------------------------------
  #  function to trigger the sendout animation
  #-----------------------------------------------------------------------------
  def playerBattlerSendOut(sendOuts, startBattle = false) # Player sending out Pokemon
    @playerLineUp.toggle = false if @playerLineUp
    # skip for followers
    if sendOuts.length < 2 && !EliteBattle.follower(@battle).nil?
      clearMessageWindow(true)
      playBattlerCry(@battlers[EliteBattle.follower(@battle)])
      @firstsendout = false
      return
    end
    # initial configuration of used variables
    ballframe = 0
    dig = []; alt = []; curve = []; orgcord = []; burst = {}; dust = {}
    # try to remove low HP BGM
    setBGMLowHP(false)
    # prepare graphical assets
    # KIF: Uses PokemonBattlerSprite instead of DynamicPokemonSprite
    sendOuts.each_with_index do |b, m|
      battler = @battlers[b[0]]; i = battler.index
      pkmn = @battle.battlers[b[0]].effects[PBEffects::Illusion] || b[1]
      # additional metrics
      dig.push(EliteBattle.get_data(battler.species, :Species, :GROUNDED, (battler.form rescue 0)))
      if i == EliteBattle.follower(@battle)
        orgcord.push(0); next
      end
      # render databox
      @sprites["dataBox_#{i}"].render
      # draw Pokeball sprites
      bstr = "Graphics/EBDX/Pictures/Pokeballs/#{pkmn.poke_ball}"
      ballbmp = pbResolveBitmap(bstr) ? pbBitmap(bstr) : pbBitmap("Graphics/EBDX/Pictures/Pokeballs/POKEBALL")
      @sprites["pokeball#{i}"] = Sprite.new(@viewport)
      @sprites["pokeball#{i}"].bitmap = ballbmp
      @sprites["pokeball#{i}"].src_rect.set(0, ballframe*40, 41, 40)
      @sprites["pokeball#{i}"].ox = 20
      @sprites["pokeball#{i}"].oy = 20
      @sprites["pokeball#{i}"].zoom_x = 0.75
      @sprites["pokeball#{i}"].zoom_y = 0.75
      @sprites["pokeball#{i}"].z = 19
      @sprites["pokeball#{i}"].opacity = 0
      # set battler bitmap
      @sprites["pokemon_#{i}"].setPokemonBitmap(pkmn, true)
      @sprites["pokemon_#{i}"].showshadow = false if @sprites["pokemon_#{i}"].respond_to?(:showshadow=)
      orgcord.push(@sprites["pokemon_#{i}"].oy)
      @sprites["pokemon_#{i}"].oy = @sprites["pokemon_#{i}"].height/2 if !dig[m]
      @sprites["pokemon_#{i}"].tone = Tone.new(255, 255, 255)
      @sprites["pokemon_#{i}"].opacity = 255
      @sprites["pokemon_#{i}"].visible = false
    end
    # vector alignment
    v = startBattle ? EliteBattle.get_vector(:SENDOUT) : EliteBattle.get_vector(:MAIN, @battle)
    @vector.set(v)
    (startBattle ? 44 : 20).times do
      sendOuts.each_with_index do |b, m|
        next if !startBattle
        next if m < 1 && !EliteBattle.follower(@battle).nil?
        @sprites["player_#{m}"].opacity += 25.5 if @sprites["player_#{m}"]
      end
      self.wait(1, true)
    end
    # player throw animation
    for j in 0...7
      next if !startBattle
      sendOuts.each_with_index do |b, m|
        next if !@sprites["player_#{m}"]
        next if m < 1 && !EliteBattle.follower(@battle).nil?
        @sprites["player_#{m}"].src_rect.x += (@sprites["player_#{m}"].bitmap.width/5) if j == 0
        @sprites["player_#{m}"].x -= 2 if j > 0
      end
      self.wait(1, false)
    end
    self.wait(6, true) if startBattle
    for j in 0...6
      next if !startBattle
      sendOuts.each_with_index do |b, m|
        next if !@sprites["player_#{m}"]
        next if m < 1 && !EliteBattle.follower(@battle).nil?
        @sprites["player_#{m}"].src_rect.x += (@sprites["player_#{m}"].bitmap.width/5) if j%2 == 0
        @sprites["player_#{m}"].x += 3 if j < 4
      end
      self.wait(1, false)
    end
    # throw SE
    pbSEPlay("EBDX/Throw")
    addzoom = (@vector.zoom1**0.75) * 2
    # calculating the curve for the Pokeball trajectory
    posX = (startBattle && !EliteBattle::DISABLE_SCENE_MOTION) ? [80, 30] : [100, 40]
    posY = (startBattle && !EliteBattle::DISABLE_SCENE_MOTION) ? [40, 160, 120] : [70, 170, 120]
    z1 = startBattle ? addzoom : 1
    z2 = startBattle ? addzoom : 2
    z3 = startBattle ? 1 : 2
    # calculate ball curve
    sendOuts.each_with_index do |b, m|
      battler = @battlers[b[0]]; i = battler.index
      y3 = 120 + (orgcord[m] - @sprites["pokemon_#{i}"].oy)*z3
      curve.push(
        calculateCurve(
            @sprites["pokemon_#{i}"].x-posX[0], @sprites["battlebg"].battler(i).y-posY[0]*z1-(orgcord[m]-@sprites["pokemon_#{i}"].oy)*z2,
            @sprites["pokemon_#{i}"].x-posX[1], @sprites["battlebg"].battler(i).y-posY[1]*z1-(orgcord[m]-@sprites["pokemon_#{i}"].oy)*z2,
            @sprites["pokemon_#{i}"].x, @sprites["battlebg"].battler(i).y-y3, 28
        )
      )
      next if i == EliteBattle.follower(@battle)
      @sprites["pokeball#{i}"].zoom_x *= addzoom
      @sprites["pokeball#{i}"].zoom_y *= addzoom
    end
    # initial Pokeball throwing animation
    for j in 0...48
      ballframe += 1
      ballframe = 0 if ballframe > 7
      sendOuts.each_with_index do |b, m|
        battler = @battlers[b[0]]; i = battler.index
        next if i == EliteBattle.follower(@battle)
        @sprites["pokeball#{i}"].src_rect.set(0, ballframe*40, 41, 40)
        @sprites["pokeball#{i}"].x = curve[m][j][0] if j < 28
        @sprites["pokeball#{i}"].y = curve[m][j][1] if j < 28
        @sprites["pokeball#{i}"].opacity += 42
      end
      self.wait(1, false)
    end
    # configuring the Y position of Pokemon sprites
    sendOuts.each_with_index do |b, m|
      battler = @battlers[b[0]]; i = battler.index
      pkmn = @battle.battlers[b[0]].effects[PBEffects::Illusion] || b[1]
      playBattlerCry(battler)
      next if i == EliteBattle.follower(@battle)
      @sprites["pokemon_#{i}"].visible = true
      @sprites["pokemon_#{i}"].y -= 120 + (orgcord[m] - @sprites["pokemon_#{i}"].oy)*z3 if !dig[m]
      @sprites["pokemon_#{i}"].zoom_x = 0
      @sprites["pokemon_#{i}"].zoom_y = 0
      @sprites["dataBox_#{i}"].appear
      burst["#{i}"] = EBBallBurst.new(@viewport, @sprites["pokeball#{i}"].x, @sprites["pokeball#{i}"].y, 29, (startBattle ? 1 : 2), pkmn.poke_ball)
    end
    # starting Pokemon release animation
    pbSEPlay("Battle recall")
    self.clearMessageWindow(true)
    zStep = calculateCurve(0, 0, 1, 20, 2, 10, 20)
    for j in 0...20
      sendOuts.each_with_index do |b, m|
        battler = @battlers[b[0]]; i = battler.index
        @sprites["player_#{m}"].opacity -= 25.5 if @sprites["player_#{m}"] && startBattle
        next if i == EliteBattle.follower(@battle)
        burst["#{i}"].update
        next if j < 4
        @sprites["pokeball#{i}"].opacity -= 51
        if startBattle
          @sprites["pokemon_#{i}"].zoom_x = (zStep[j][1]*addzoom*0.1)
          @sprites["pokemon_#{i}"].zoom_y = (zStep[j][1]*addzoom*0.1)
        else
          @sprites["pokemon_#{i}"].zoom_x = (zStep[j][1]*@vector.zoom1*0.2)
          @sprites["pokemon_#{i}"].zoom_y = (zStep[j][1]*@vector.zoom1*0.2)
        end
        @sprites["pokemon_#{i}"].still if @sprites["pokemon_#{i}"].respond_to?(:still)
        @sprites["dataBox_#{i}"].show
      end
      self.wait(1, false)
    end
    # pokemon burst animation
    for j in 0...22
      sendOuts.each_with_index do |b, m|
        battler = @battlers[b[0]]; i = battler.index
        next if i == EliteBattle.follower(@battle)
        burst["#{i}"].update
        burst["#{i}"].dispose if j == 21
        next if j < 8
        @sprites["pokemon_#{i}"].tone.red -= 51 if @sprites["pokemon_#{i}"].tone.red > 0
        @sprites["pokemon_#{i}"].tone.green -= 51 if @sprites["pokemon_#{i}"].tone.green > 0
        @sprites["pokemon_#{i}"].tone.blue -= 51 if @sprites["pokemon_#{i}"].tone.blue > 0
      end
      self.wait(1, false)
    end
    burst = nil
    # dropping Pokemon onto the ground
    if startBattle
      sendOuts.each_with_index do |b, m|
        battler = @battlers[b[0]]; i = battler.index
        next if i == EliteBattle.follower(@battle)
        @sprites["pokemon_#{i}"].y += (orgcord[m] - @sprites["pokemon_#{i}"].oy)*z3 if !dig[m]
        @sprites["pokemon_#{i}"].oy = orgcord[m] if !dig[m]
      end
    end
    sendoutDropPkmn(sendOuts, orgcord, dig, z3, 12)
    # handler for screenshake (and weight animation upon entry)
    heavy = sendoutScreenShake(sendOuts, dig, startBattle, alt, dust)
    # dust animation upon entry of heavy pokemon
    sendoutDustAnim(sendOuts, heavy, dust, alt)
    # shiny animation upon entry
    sendoutShinyPkmn(sendOuts)
    # done
    @firstsendout = false
    return true
  end

  #=============================================================================
  #  Battler Sendout - Opponent
  #=============================================================================

  #-----------------------------------------------------------------------------
  #  function to trigger the sendout animation
  #-----------------------------------------------------------------------------
  def trainerBattlerSendOut(sendOuts, startBattle = false) # Opponent sending out Pokemon
    @opponentLineUp.toggle = false if @opponentLineUp
    @smTrainerSequence.sendout if @smTrainerSequence
    # initial configuration of used variables
    ballframe = 0
    dig = []; alt = []; curve = []; orgcord = []; burst = {}; dust = {}
    # prepare graphical assets
    # KIF: Uses PokemonBattlerSprite instead of DynamicPokemonSprite
    sendOuts.each_with_index do |b, m|
      battler = @battlers[b[0]]; i = battler.index
      pkmn = @battle.battlers[b[0]].effects[PBEffects::Illusion] || b[1]
      # render databox
      @sprites["dataBox_#{i}"].render
      # draw Pokeball sprites
      bstr = "Graphics/EBDX/Pictures/Pokeballs/#{pkmn.poke_ball}"
      ballbmp = pbResolveBitmap(bstr) ? pbBitmap(bstr) : pbBitmap("Graphics/EBDX/Pictures/Pokeballs/POKEBALL")
      @sprites["pokeball#{i}"] = Sprite.new(@viewport)
      @sprites["pokeball#{i}"].bitmap = ballbmp
      @sprites["pokeball#{i}"].src_rect.set(0, ballframe*40, 41, 40)
      @sprites["pokeball#{i}"].ox = 20
      @sprites["pokeball#{i}"].oy = 20
      @sprites["pokeball#{i}"].zoom_x = 0.75
      @sprites["pokeball#{i}"].zoom_y = 0.75
      @sprites["pokeball#{i}"].z = 19
      @sprites["pokeball#{i}"].opacity = 0
      # additional metrics
      dig.push(EliteBattle.get_data(battler.species, :Species, :GROUNDED, (battler.form rescue 0)))
      # set battler bitmap
      @sprites["pokemon_#{i}"].setPokemonBitmap(pkmn, false)
      @sprites["pokemon_#{i}"].showshadow = false if @sprites["pokemon_#{i}"].respond_to?(:showshadow=)
      orgcord.push(@sprites["pokemon_#{i}"].oy)
      @sprites["pokemon_#{i}"].oy = @sprites["pokemon_#{i}"].height/2 if !dig[m]
      @sprites["pokemon_#{i}"].tone = Tone.new(255, 255, 255)
      @sprites["pokemon_#{i}"].opacity = 255
      @sprites["pokemon_#{i}"].visible = false
      curve.push(
        calculateCurve(
            @sprites["pokemon_#{i}"].x, @sprites["battlebg"].battler(i).y-50-(orgcord[m]-@sprites["pokemon_#{i}"].oy),
            @sprites["pokemon_#{i}"].x, @sprites["battlebg"].battler(i).y-100-(orgcord[m]-@sprites["pokemon_#{i}"].oy),
            @sprites["pokemon_#{i}"].x, @sprites["battlebg"].battler(i).y-50-(orgcord[m]-@sprites["pokemon_#{i}"].oy), 30
        )
      )
    end
    # initial trainer fade and Pokeball throwing animation
    # KIF: Uses standard trainer sprites instead of DynamicTrainerSprite
    pbSEPlay("EBDX/Throw")
    for j in 0...30
      ballframe += 1
      ballframe = 0 if ballframe > 7
      sendOuts.each_with_index do |b, m|
        battler = @battlers[b[0]]; i = battler.index
        # animation for fading out the opponent
        if @firstsendout && @sprites["trainer_#{m}"]
          if @minorAnimation && !@smTrainerSequence
            @sprites["trainer_#{m}"].x += 8
          else
            @sprites["trainer_#{m}"].x += 3
            @sprites["trainer_#{m}"].y -= 2
            @sprites["trainer_#{m}"].zoom_x -= 0.02
            @sprites["trainer_#{m}"].zoom_y -= 0.02
          end
          @sprites["trainer_#{m}"].opacity -= 12.8
        end
        @sprites["pokeball#{i}"].src_rect.set(0, ballframe*40, 41, 40)
        @sprites["pokeball#{i}"].x = curve[m][j][0]
        @sprites["pokeball#{i}"].y = curve[m][j][1]
        @sprites["pokeball#{i}"].opacity += 51
      end
      self.wait
    end
    # configuring the Y position of Pokemon sprites
    sendOuts.each_with_index do |b, m|
      battler = @battlers[b[0]]; i = battler.index
      pkmn = @battle.battlers[b[0]].effects[PBEffects::Illusion] || b[1]
      @sprites["pokemon_#{i}"].visible = true
      @sprites["pokemon_#{i}"].y -= 50 + (orgcord[m] - @sprites["pokemon_#{i}"].oy) if !dig[m]
      @sprites["pokemon_#{i}"].zoom_x = 0
      @sprites["pokemon_#{i}"].zoom_y = 0
      @sprites["dataBox_#{i}"].appear
      playBattlerCry(battler)
      burst["#{i}"] = EBBallBurst.new(@viewport, @sprites["pokeball#{i}"].x, @sprites["pokeball#{i}"].y, 19, 1, pkmn.poke_ball)
    end
    # starting Pokemon release animation
    pbSEPlay("Battle recall")
    @sendingOut = false
    clearMessageWindow
    zStep = calculateCurve(0, 0, 1, 20, 2, 10, 20)
    for j in 0...20
      sendOuts.each_with_index do |b, m|
        battler = @battlers[b[0]]; i = battler.index
        burst["#{i}"].update
        next if j < 4
        @sprites["pokeball#{i}"].opacity -= 51
        @sprites["pokemon_#{i}"].zoom_x = zStep[j][1]*@vector.zoom1*0.1
        @sprites["pokemon_#{i}"].zoom_y = zStep[j][1]*@vector.zoom1*0.1
        @sprites["pokemon_#{i}"].still if @sprites["pokemon_#{i}"].respond_to?(:still)
        @sprites["dataBox_#{i}"].show
      end
      self.wait
    end
    for j in 0...22
      sendOuts.each_with_index do |b, m|
        battler = @battlers[b[0]]; i = battler.index
        burst["#{i}"].update
        burst["#{i}"].dispose if j == 21
        next if j < 8
        @sprites["pokemon_#{i}"].tone.red -= 51 if @sprites["pokemon_#{i}"].tone.red > 0
        @sprites["pokemon_#{i}"].tone.green -= 51 if @sprites["pokemon_#{i}"].tone.green > 0
        @sprites["pokemon_#{i}"].tone.blue -= 51 if @sprites["pokemon_#{i}"].tone.blue > 0
      end
      self.wait
    end
    burst = nil
    # dropping Pokemon onto the ground
    sendoutDropPkmn(sendOuts, orgcord, dig, 1, 5)
    # handler for screenshake (and weight animation upon entry)
    heavy = sendoutScreenShake(sendOuts, dig, startBattle, alt, dust)
    # dust animation upon entry of heavy pokemon
    sendoutDustAnim(sendOuts, heavy, dust, alt)
    # shiny animation upon entry
    sendoutShinyPkmn(sendOuts)
    # done
    @sendingOut = false
    return true
  end

  #=============================================================================
  #  Battler Recall
  #=============================================================================

  #-----------------------------------------------------------------------------
  #  Function to trigger battler recall
  #-----------------------------------------------------------------------------
  def pbRecall(battlerindex)
    return if @battle.battlers[battlerindex].fainted?
    balltype = @battle.battlers[battlerindex].pokemon.poke_ball
    # KIF: Uses PokemonBattlerSprite instead of DynamicPokemonSprite
    poke = @sprites["pokemon_#{battlerindex}"]
    return if poke.respond_to?(:fainted) && poke.fainted
    poke.resetParticles if poke.respond_to?(:resetParticles)
    pbSEPlay("Battle recall") if !(@sprites["pokemon_#{battlerindex}"].respond_to?(:hidden) && @sprites["pokemon_#{battlerindex}"].hidden)
    zoom = poke.zoom_x/20.0
    @sprites["dataBox_#{battlerindex}"].visible = false
    ballburst = EBBallBurst.new(poke.viewport, poke.x, poke.y, 29, poke.zoom_x, balltype)
    ballburst.recall if !(@sprites["pokemon_#{battlerindex}"].respond_to?(:hidden) && @sprites["pokemon_#{battlerindex}"].hidden)
    for i in 0...32
      next if @sprites["pokemon_#{battlerindex}"].respond_to?(:hidden) && @sprites["pokemon_#{battlerindex}"].hidden
      if i < 20
        poke.tone.red += 25.5
        poke.tone.green += 25.5
        poke.tone.blue += 25.5
        if playerBattler?(@battle.battlers[battlerindex])
          @sprites["dataBox_#{battlerindex}"].x += 26
        else
          @sprites["dataBox_#{battlerindex}"].x -= 26
        end
        @sprites["dataBox_#{battlerindex}"].opacity -= 25.5
        poke.zoom_x -= zoom
        poke.zoom_y -= zoom
      end
      ballburst.update
      self.wait
    end
    ballburst.dispose
    ballburst = nil
    poke.visible = false
    # try to remove low HP BGM
    setBGMLowHP(false)
  end
  #-----------------------------------------------------------------------------
  #  Common animation elements for sendouts
  #-----------------------------------------------------------------------------
  #  drop battlers onto the field
  def sendoutDropPkmn(sendOuts, orgcord, dig, z3, drop)
    for j in 0...12
      sendOuts.each_with_index do |b, m|
        battler = @battlers[b[0]]; i = battler.index
        next if i == EliteBattle.follower(@battle)
        if j == 11
          @sprites["pokemon_#{i}"].showshadow = true if @sprites["pokemon_#{i}"].respond_to?(:showshadow=)
        elsif j > 0
          @sprites["pokemon_#{i}"].y += drop if !dig[m]
        else
          @sprites["pokemon_#{i}"].y += (orgcord[m] - @sprites["pokemon_#{i}"].oy)*z3 if !dig[m]
          @sprites["pokemon_#{i}"].oy = orgcord[m] if !dig[m]
        end
      end
      self.wait(1, false) if j > 0 && j < 11
    end
  end
  #-----------------------------------------------------------------------------
  #  shake screen upon drop
  #-----------------------------------------------------------------------------
  def sendoutScreenShake(sendOuts, dig, startBattle, alt, dust)
    # main shake
    sendOuts.each_with_index do |b, m|
      battler = @battlers[b[0]]; i = battler.index
      val = getBattlerAltitude(battler); val = 0 if val.nil?
      val = 1 if dig[m]
      alt.push(val)
      next if i == EliteBattle.follower(@battle)
      dust["#{i}"] = EBDustParticle.new(@viewport, @sprites["pokemon_#{i}"], (startBattle ? 1 : 2))
      @sprites["pokeball#{i}"].dispose
    end
    # register as heavy shake
    shake = false; heavy = false; onlydig = false; shadowless = false
    sendOuts.each_with_index do |b, m|
      battler = @battlers[b[0]]; i = battler.index
      next if i == EliteBattle.follower(@battle)
      shake = true if alt[m] < 1 && !dig[m]
      heavy = true if battler.pbWeight*0.1 >= 291 && alt[m] < 1 && !dig[m]
    end
    sendOuts.each_with_index {|b, m| onlydig = true if !shake && dig[m] }
    # override for shadowless environments
    if @sprites["battlebg"].respond_to?(:data) && @sprites["battlebg"].data.has_key?("noshadow") && @sprites["battlebg"].data["noshadow"] == true
      shake = false; heavy = false; shadowless = true
    end
    # play SE
    pbSEPlay("EBDX/Drop") if shake && !heavy
    pbSEPlay("EBDX/Drop Heavy") if heavy
    mult = heavy ? 2 : 1
    # move scene
    for j in 0...8
      next if onlydig
      sendOuts.each_with_index do |b, m|
        next if alt[m] < 1 && !shadowless
        battler = @battlers[b[0]]; i = battler.index
        next if i == EliteBattle.follower(@battle)
        @sprites["pokemon_#{i}"].y += ((j/4 < 1) ? 4 : -4)
      end
      if shake
        y = (j/4 < 1) ? 2 : -2
        moveEntireScene(0, (y*mult))
      end
      self.wait(1, false)
    end
    return heavy
  end
  #-----------------------------------------------------------------------------
  #  dust animation upon drop
  #-----------------------------------------------------------------------------
  def sendoutDustAnim(sendOuts, heavy, dust, alt)
    for j in 0..24
      next if !heavy
      sendOuts.each_with_index do |b, m|
        battler = @battlers[b[0]]; i = battler.index
        next if i == EliteBattle.follower(@battle)
        dust["#{i}"].update if battler.pbWeight*0.1 >= 291 && alt[m] < 1
        dust["#{i}"].dispose if j == 24
      end
      self.wait(1, false) if j < 24
    end
    dust = nil
  end
  #-----------------------------------------------------------------------------
  #  shiny animation upon entry
  #-----------------------------------------------------------------------------
  def sendoutShinyPkmn(sendOuts)
    sendOuts.each do |b|
      @sprites["dataBox_#{@battlers[b[0]].index}"].inposition = true
      next if @battlers[b[0]].index == EliteBattle.follower(@battle)
      next if !@battle.showAnims || !shinyBattler?(@battlers[b[0]])
      pbCommonAnimation("Shiny", @battlers[b[0]])
    end
  end

  #=============================================================================
  #  Battler Capture
  #=============================================================================

  #-----------------------------------------------------------------------------
  #  Alias unused functions
  #-----------------------------------------------------------------------------
  def pbThrowAndDeflect(ball, targetBattler); end
  def pbHideCaptureBall(idxBattler); end
  #-----------------------------------------------------------------------------
  #  Pokeball throw animation
  #-----------------------------------------------------------------------------
  def pbThrow(ball, shakes, critical, targetBattler, showplayer = nil)
    @orgPos = nil; @playerfix = false if @safaribattle
    ballframe = 0
    # sprites
    bstr = "Graphics/EBDX/Pictures/Pokeballs/#{ball}"
    ballbmp = pbResolveBitmap(bstr) ? pbBitmap(bstr) : pbBitmap("Graphics/EBDX/Pictures/Pokeballs/POKEBALL")
    # KIF: Uses PokemonBattlerSprite instead of DynamicPokemonSprite
    spritePoke = @sprites["pokemon_#{targetBattler}"]
    @sprites["ballshadow"] = Sprite.new(@viewport)
    @sprites["ballshadow"].bitmap = Bitmap.new(34, 34)
    @sprites["ballshadow"].bitmap.bmp_circle(Color.black)
    @sprites["ballshadow"].ox = @sprites["ballshadow"].bitmap.width/2
    @sprites["ballshadow"].oy = @sprites["ballshadow"].bitmap.height/2 + 2
    @sprites["ballshadow"].z = 32
    @sprites["ballshadow"].opacity = 255*0.25
    @sprites["ballshadow"].visible = false
    @sprites["captureball"] = Sprite.new(@viewport)
    @sprites["captureball"].bitmap = ballbmp
    @sprites["captureball"].src_rect.set(0, ballframe*40, 41, 40)
    @sprites["captureball"].ox = 20
    @sprites["captureball"].oy = 20
    @sprites["captureball"].z = 32
    @sprites["captureball"].zoom_x = 4
    @sprites["captureball"].zoom_y = 4
    @sprites["captureball"].visible = false
    pokeball = @sprites["captureball"]
    shadow = @sprites["ballshadow"]
    # position "camera"
    sx, sy = @sprites["battlebg"].spoof(EliteBattle.get_vector(:ENEMY), targetBattler)
    curve = calculateCurve(sx-260,sy-160,sx-60,sy-200,sx,sy-140,24)
    # position pokeball
    pokeball.x = sx - 260
    pokeball.y = sy - 100
    pokeball.visible = true
    shadow.x = pokeball.x
    shadow.y = pokeball.y
    shadow.zoom_x = 0
    shadow.zoom_y = 0
    shadow.visible = true
    # throwing animation
    pbHideAllDataboxes(0)
    critical ? pbSEPlay("EBDX/Throw Critical") : pbSEPlay("EBDX/Throw")
    for i in 0...28
      @vector.set(EliteBattle.get_vector(:ENEMY)) if i == 4
      # fade out player in a safari battle
      if @safaribattle && i < 16
        @sprites["player_0"].x -= 75
        @sprites["player_0"].y += 38
        @sprites["player_0"].zoom_x += 0.125
        @sprites["player_0"].zoom_y += 0.125
      end
      # increment ball frame (spinning)
      ballframe += 1
      ballframe = 0 if ballframe > 7
      if i < 24
        pokeball.x = curve[i][0]
        pokeball.y = curve[i][1]
        pokeball.zoom_x -= (pokeball.zoom_x - spritePoke.zoom_x)*0.2
        pokeball.zoom_y -= (pokeball.zoom_y - spritePoke.zoom_y)*0.2
        shadow.x = pokeball.x
        shadow.y = pokeball.y + 140 + 16 + (24-i)
        shadow.zoom_x += 0.8/24
        shadow.zoom_y += 0.3/24
      end
      # update ball spin
      pokeball.src_rect.set(0, ballframe*40, 41, 40)
      self.wait(1, true)
    end
    # additional spin
    for i in 0...4
      pokeball.src_rect.set(0, (7+i)*40, 41, 40)
      self.wait
    end
    pbSEPlay("Battle recall")
    # Burst animation here
    pokeball.z = spritePoke.z-1; shadow.z = pokeball.z-1
    spritePoke.showshadow = false if spritePoke.respond_to?(:showshadow=)
    ballburst = EBBallBurst.new(pokeball.viewport, pokeball.x, pokeball.y, 50, @vector.zoom1, ball)
    ballburst.catching
    clearMessageWindow
    # play burst animation and sprite zoom
    for i in 0...32
      if i < 20
        spritePoke.zoom_x -= 0.075
        spritePoke.zoom_y -= 0.075
        spritePoke.tone.all += 25.5
        spritePoke.y -= 8
      elsif i == 20
        spritePoke.zoom = 0 if spritePoke.respond_to?(:zoom=)
      end
      ballburst.update
      self.wait
    end
    # dispose of ball burst
    ballburst.dispose
    spritePoke.y += 160
    # reset frame
    pokeball.src_rect.y -= 40; self.wait
    pokeball.src_rect.y = 0; self.wait
    t = 0; i = 51
    # increase tone
    10.times do
      t += i; i =- 51 if t >= 255
      pokeball.tone = Tone.new(t, t, t)
      self.wait
    end
    #################
    pbSEPlay("Battle jump to ball")
    # drop ball to floor
    for i in 0...20
      pokeball.src_rect.y = 40*(((i-6)/2)+1) if i%2 == 0 && i >= 6
      pokeball.y += 7
      shadow.zoom_x += 0.01
      shadow.zoom_y += 0.01
      self.wait
    end
    pokeball.src_rect.y = 0
    pbSEPlay("Battle ball drop")
    # bounce animation
    for i in 0...14
      pokeball.src_rect.y = 40*((i/2)+1) if i%2 == 0
      pokeball.y -= 6 if i < 7
      pokeball.y += 6 if i >= 7
      if i <= 7
        shadow.zoom_x -= 0.005
        shadow.zoom_y -= 0.005
      else
        shadow.zoom_x += 0.005
        shadow.zoom_y += 0.005
      end
      self.wait
    end
    pokeball.src_rect.y = 0
    pbSEPlay("Battle ball drop", 80)
    # ball shake
    [shakes, 3].min.times do
      self.wait(40)
      pbSEPlay("Battle ball shake")
      pokeball.src_rect.y = 11*40
      self.wait
      # change angle sprite
      for i in 0...2
        2.times do
          pokeball.src_rect.y += 40*(i < 1 ? 1 : -1)
          self.wait
        end
      end
      pokeball.src_rect.y = 14*40
      self.wait
      for i in 0...2
        2.times do
          pokeball.src_rect.y += 40*(i < 1 ? 1 : -1)
          self.wait
        end
      end
      pokeball.src_rect.y = 0
      self.wait
    end
    # burst if 3 or less shakes
    if shakes < 4
      clearMessageWindow
      self.wait(40)
      pokeball.src_rect.y = 9*40
      self.wait
      pokeball.src_rect.y += 40
      self.wait
      pbSEPlay("Battle recall")
      spritePoke.showshadow = true if spritePoke.respond_to?(:showshadow=)
      # generate ball burst for escape
      ballburst = EBBallBurst.new(pokeball.viewport, pokeball.x, pokeball.y, 50, @vector.zoom1, ball)
      for i in 0...32
        if i < 20
          pokeball.opacity -= 25.5
          shadow.opacity -= 4
          spritePoke.zoom_x += 0.075
          spritePoke.zoom_y += 0.075
          spritePoke.tone.all -= 25.5 if spritePoke.tone.all > 0
        end
        # update burst
        ballburst.update
        self.wait
      end
      # dispose and clear messages
      ballburst.dispose
      # reset vector
      @vector.reset
      pbShowAllDataboxes(0)
      20.times do
        if @safaribattle
          @sprites["player_0"].x += 60
          @sprites["player_0"].y -= 30
          @sprites["player_0"].zoom_x -= 0.1
          @sprites["player_0"].zoom_y -= 0.1
        end
        self.wait(1, true)
      end
    else
      clearMessageWindow
      # play animation when wild is caught
      @caughtBattler = @battle.pbParty(1)[targetBattler/2]
      spritePoke.visible = false
      spritePoke.resetParticles if spritePoke.respond_to?(:resetParticles)
      spritePoke.charged = false if spritePoke.respond_to?(:charged=)
      self.wait(40)
      pbSEPlay("Battle ball drop", 80)
      pokeball.color = Color.new(0, 0, 0, 0)
      fp = {}
      for j in 0...3
        fp["#{j}"] = Sprite.new(pokeball.viewport)
        fp["#{j}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/ebStar")
        fp["#{j}"].ox = fp["#{j}"].bitmap.width/2
        fp["#{j}"].oy = fp["#{j}"].bitmap.height/2
        fp["#{j}"].x = pokeball.x
        fp["#{j}"].y = pokeball.y
        fp["#{j}"].opacity = 0
        fp["#{j}"].z = pokeball.z + 1
      end
      for i in 0...16
        for j in 0...3
          fp["#{j}"].y -= [3,4,3][j]
          fp["#{j}"].x -= [3,0,-3][j]
          fp["#{j}"].opacity += 32*(i < 8 ? 1 : -1)
          fp["#{j}"].angle += [4,2,-4][j]
        end
        @sprites["dataBox_#{targetBattler}"].opacity -= 25.5
        pokeball.color.alpha += 8
        self.wait
      end
      # if snagging an opponent's battler
      if @battle.opponent
        5.times do
          pokeball.opacity -= 51
          shadow.opacity -= 13
          self.wait
        end
        @vector.reset
        pbShowAllDataboxes(0)
        self.wait(20, true)
      end
      spritePoke.clear if spritePoke.respond_to?(:clear)
    end
    @playerfix = true if @safaribattle
    self.briefmessage = true
  end
  #-----------------------------------------------------------------------------
  #  Function called when capture is successful
  #-----------------------------------------------------------------------------
  def pbThrowSuccess
    return if @battle.opponent
    @briefmessage = true
    # try to resolve the ME jingle
    me = "EBDX/Capture Success"
    try = @caughtBattler ? EliteBattle.get_data(@caughtBattler.species, :Species, :CAPTUREME) : nil
    me = try if !try.nil?
    # play ME
    pbMEPlay(me)
    # wait for audio frames to complete
    frames = (getPlayTime("Audio/ME/#{me}") * Graphics.frame_rate).ceil + 4
    self.wait(frames)
    pbMEStop
    # return scene to normal
    5.times do
      @sprites["ballshadow"].opacity -= 16
      @sprites["captureball"].opacity -= 52
      self.wait
    end
    @sprites["ballshadow"].dispose
    @sprites["captureball"].dispose
    pbShowAllDataboxes(0)
    @vector.reset
  end
  #-----------------------------------------------------------------------------
end
