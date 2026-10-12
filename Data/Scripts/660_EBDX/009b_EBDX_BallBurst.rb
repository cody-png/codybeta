#===============================================================================
#  Class handling the ball burst animation (ported from original EBDX)
#===============================================================================
class EBBallBurst
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
    @disposed = false
    # ray particles
    for j in 0...8
      @fp["s#{j}"] = Sprite.new(@viewport)
      @fp["s#{j}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Ballburst/#{balltype.to_s}_ray") rescue nil
      next if !@fp["s#{j}"].bitmap
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
    @fp["cir"].bitmap = pbBitmap("Graphics/EBDX/Animations/Ballburst/#{balltype.to_s}_shine") rescue nil
    if @fp["cir"].bitmap
      @fp["cir"].center! if @fp["cir"].respond_to?(:center!)
      @fp["cir"].ox = @fp["cir"].bitmap.width/2
      @fp["cir"].oy = @fp["cir"].bitmap.height/2
    end
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
      @fp["p#{k}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Ballburst/#{balltype.to_s}_#{str}") rescue nil
      if @fp["p#{k}"].bitmap
        @fp["p#{k}"].center! if @fp["p#{k}"].respond_to?(:center!)
        @fp["p#{k}"].ox = @fp["p#{k}"].bitmap.width/2
        @fp["p#{k}"].oy = @fp["p#{k}"].bitmap.height/2
      end
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
    return if @disposed
    # reverses the animation if capturing a Pokemon
    return self.reverse if @catching
    # @index mainly used for animation frame separation
    # animates ray particles
    for j in 0...8
      next if @index < 4; next if j > (@index-4)/2
      next if !@fp["s#{j}"] || !@fp["s#{j}"].bitmap
      @fp["s#{j}"].zoom_x += (@szoom[j]*0.1)
      @fp["s#{j}"].zoom_y += (@szoom[j]*0.1)
      @fp["s#{j}"].opacity -= 8 if @fp["s#{j}"].zoom_x >= 1
    end
    # animaties additional particle effects
    for k in 0...16
      next if @index < 4; next if k > (@index-4)
      next if !@fp["p#{k}"] || !@fp["p#{k}"].bitmap
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
        @fp["s#{j}"].opacity -= 26 if @fp["s#{j}"]
      end
      for k in 0...16
        @fp["p#{k}"].opacity -= 26 if @fp["p#{k}"]
      end
      @fp["cir"].opacity -= 26 if @fp["cir"]
    end
    # changes tone of animation depending on position in animation
    @tone -= 25.5 if @index >= 4 && @tone > 0
    for j in 0...8
      @fp["s#{j}"].tone = Tone.new(@tone,@tone,@tone) if @fp["s#{j}"]
    end
    for k in 0...16
      @fp["p#{k}"].tone = Tone.new(@tone,@tone,@tone) if @fp["p#{k}"]
    end
    # animates center shine
    if @fp["cir"]
      @fp["cir"].tone = Tone.new(@tone,@tone,@tone)
      @fp["cir"].zoom_x += (@factor*1.5 - @fp["cir"].zoom_x)*0.06
      @fp["cir"].zoom_y += (@factor*1.5 - @fp["cir"].zoom_y)*0.06
      @fp["cir"].angle -= 4
    end
    # increments index
    @index += 1
  end
  #-----------------------------------------------------------------------------
  #  plays reversed animation (for recall/capture)
  #-----------------------------------------------------------------------------
  def reverse
    return if @disposed
    # changes tone of animation depending on position in animation
    @tone -= 25.5 if @index >= 4 && @tone > 0
    # animates shine (but not if recalling battlers)
    for j in 0...8
      next if @index < 4; next if j > (@index-4)/2; next if @recall
      next if !@fp["s#{j}"] || !@fp["s#{j}"].bitmap
      @fp["s#{j}"].zoom_x += (@szoom[j]*0.1)
      @fp["s#{j}"].zoom_y += (@szoom[j]*0.1)
      @fp["s#{j}"].opacity -= 8 if @fp["s#{j}"].zoom_x >= 1
    end
    if @index >= 22
      for j in 0...8
        @fp["s#{j}"].opacity -= 26 if @fp["s#{j}"]
      end
    end
    for j in 0...8
      @fp["s#{j}"].tone = Tone.new(@tone,@tone,@tone) if @fp["s#{j}"]
    end
    # animates additional particles
    for k in 0...16
      next if !@fp["p#{k}"] || !@fp["p#{k}"].bitmap
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
    if @fp["cir"]
      @fp["cir"].tone = Tone.new(@tone,@tone,@tone)
      @fp["cir"].zoom_x -= (@fp["cir"].zoom_x - 0.5*@factor)*0.06
      @fp["cir"].zoom_y -= (@fp["cir"].zoom_y - 0.5*@factor)*0.06
      @fp["cir"].opacity += 25.5 if @index < 16
      @fp["cir"].opacity -= 16 if @index >= 16
      @fp["cir"].angle -= 4
    end
    # increments index
    @index += 1
  end
  #-----------------------------------------------------------------------------
  #  check if animation is finished
  #-----------------------------------------------------------------------------
  def finished?
    return @index >= 40
  end
  #-----------------------------------------------------------------------------
  #  disposes all particle effects
  #-----------------------------------------------------------------------------
  def dispose
    return if @disposed
    @fp.each_value { |sprite| sprite.dispose if sprite && !sprite.disposed? }
    @disposed = true
  end
  def disposed?
    return @disposed
  end
  #-----------------------------------------------------------------------------
  #  configures animation for when capturing Pokemon
  #-----------------------------------------------------------------------------
  def catching
    @catching = true
    for k in 0...16
      next if !@fp["p#{k}"] || !@fp["p#{k}"].bitmap
      a = k*22.5 + 11.5
      r = 128*@factor
      x = @x + r*Math.cos(a*(Math::PI/180))
      y = @y - r*Math.sin(a*(Math::PI/180))
      @fp["p#{k}"].x = x
      @fp["p#{k}"].y = y
      @fp["p#{k}"].tone = Tone.new(0,0,0)
      @fp["p#{k}"].opacity = 0
      str = ["particle", "eff"][k%2]
      @fp["p#{k}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Ballburst/#{@balltype.to_s}_#{str}") rescue nil
      if @fp["p#{k}"].bitmap
        @fp["p#{k}"].ox = @fp["p#{k}"].bitmap.width/2
        @fp["p#{k}"].oy = @fp["p#{k}"].bitmap.height/2
      end
    end
    if @fp["cir"]
      @fp["cir"].zoom_x = 2*@factor
      @fp["cir"].zoom_y = 2*@factor
    end
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
