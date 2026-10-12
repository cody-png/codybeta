#===== FILE: ATTRACT.rb =====#
#===============================================================================
#  Common Animation: ATTRACT
#===============================================================================
EliteBattle.defineCommonAnimation(:ATTRACT) do
  @vector.set(@scene.getRealVector(@userIndex, @userIsPlayer))
  fp = {}
  # set up animation
  @scene.wait(5,true)
  shake = 6
  for i in 0...12
    @userSprite.still
	pbSEPlay("Cries/#{@userSprite.species}",85) if i == 4
    if i.between?(4,12)
      @userSprite.ox += shake
      shake = -6 if @userSprite.ox > @userSprite.bitmap.width/2 + 2
      shake = 6 if @userSprite.ox < @userSprite.bitmap.width/2 - 2
    end
    @scene.wait(1,true)
  end
  #taunt
  @vector.set(@scene.getRealVector(@targetIndex, @targetIsPlayer))
  @scene.wait(16,true)
  factor = @targetSprite.zoom_x
  cx, cy = @targetSprite.getCenter(true)
  dx = []
  dy = []
  t = 2
  for j in 0..t
    fp["#{j}"] = Sprite.new(@viewport)
    fp["#{j}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/eb636_2")
    fp["#{j}"].ox = fp["#{j}"].bitmap.width/2
    fp["#{j}"].oy = fp["#{j}"].bitmap.height/2
    fp["#{j}"].x = cx + 20 if j == 0
    fp["#{j}"].x = cx - 20 if j == 1    
	fp["#{j}"].x = cx      if j == 2
    fp["#{j}"].y = cy - 40 if j < 2
    fp["#{j}"].y = cy - 10 if j == 2
    fp["#{j}"].z = @targetSprite.z
    fp["#{j}"].visible = false
    z = [0.5,1,0.75][rand(3)]
    fp["#{j}"].zoom_x = z
    fp["#{j}"].zoom_y = z
  end
  # start animation
  for i in 0...30
	pbSEPlay("Anim/Love",100) if i == 3 || i == 9 || i == 15
    for j in 0..t
      next if j>(i*2)
	  next if i <= 5 && j == 1
      fp["#{j}"].visible = true
      if i > 20
        fp["#{j}"].opacity -= 32
      else
		if fp["#{j}"].zoom <= 1.5
			fp["#{j}"].zoom += 0.1
		else
		    fp["#{j}"].opacity -= 32
		end
      end
    end
    @scene.wait
  end
  @targetSprite.ox = @targetSprite.bitmap.width/2
  @vector.reset if !@multiHit
  pbDisposeSpriteHash(fp)
end

#===== FILE: AURAFLARE.rb =====#
#===============================================================================
#  Common Animation: AURAFLARE
#===============================================================================
EliteBattle.defineCommonAnimation(:AURAFLARE) do
  #-----------------------------------------------------------------------------
  #  hides UI elements
  @scene.pbHideAllDataboxes
  fp = {}
  #-----------------------------------------------------------------------------
  #  vector config
  back = !@battle.opposes?(@targetIndex)
  @vector.set(@scene.getRealVector(@targetIndex, back))
  @scene.wait(16, true)
  factor = @targetSprite.zoom_x
  #-----------------------------------------------------------------------------
  # particle initialization
  for i in 0...16
    fp["c#{i}"] = Sprite.new(@viewport)
    fp["c#{i}"].z = @targetSprite.z + 10
    fp["c#{i}"].bitmap = pbBitmap(sprintf("Graphics/EBDX/Animations/Moves/ebMega%03d",rand(4)+1))
    fp["c#{i}"].center!
    fp["c#{i}"].opacity = 0
  end
  #-----------------------------------------------------------------------------
  # ray initialization
  rangle = []
  cx, cy = @targetSprite.getCenter(true)
  for i in 0...8; rangle.push((360/8)*i +  15); end
  for j in 0...8
    fp["r#{j}"] = Sprite.new(@viewport)
    fp["r#{j}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/ebMega005")
    fp["r#{j}"].ox = 0
    fp["r#{j}"].color = Color.new(186, 86, 102)
    fp["r#{j}"].oy = fp["r#{j}"].bitmap.height/2
    fp["r#{j}"].opacity = 0
    fp["r#{j}"].zoom_x = 0
    fp["r#{j}"].zoom_y = 0
    fp["r#{j}"].x = cx
    fp["r#{j}"].y = cy
    a = rand(rangle.length)
    fp["r#{j}"].angle = rangle[a]
    fp["r#{j}"].z = @targetSprite.z + 2
    rangle.delete_at(a)
  end
  #-----------------------------------------------------------------------------
  # ripple initialization
  for j in 0...3
    fp["v#{j}"] = Sprite.new(@viewport)
    fp["v#{j}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/ebMega006")
    fp["v#{j}"].center!
    fp["v#{j}"].x = cx
    fp["v#{j}"].y = cy
    fp["v#{j}"].opacity = 0
    fp["v#{j}"].zoom_x = 2*factor
    fp["v#{j}"].zoom_y = 2*factor
    fp["v#{j}"].z = @targetSprite.z + 1
    fp["v#{j}"].toggle = 1
    fp["v#{j}"].color = Color.new(186,86,102)
  end
  #-----------------------------------------------------------------------------
  @sprites["battlebg"].defocus
  pbSEPlay("Anim/Harden",120)
  @targetSprite.color = Color.new(221,68,92,0)
  for i in 0...104
    @targetSprite.color.alpha += 8
    @targetSprite.anim = true
    # particle animation
    for j in 0...16
      next if j > (i/8)
      if fp["c#{j}"].opacity == 0 && i < 72
        fp["c#{j}"].opacity = 255
        x, y = randCircleCord(96*factor)
        fp["c#{j}"].x = cx - 96*factor + x
        fp["c#{j}"].y = cy - 96*factor + y
      end
      x2 = cx; y2 = cy
      x0 = fp["c#{j}"].x; y0 = fp["c#{j}"].y
      fp["c#{j}"].x += (x2 - x0)*0.1
      fp["c#{j}"].y += (y2 - y0)*0.1
      fp["c#{j}"].opacity -= 16
    end
    #-----------------------------------------------------------------------------
    # ray animation
    for j in 0...8
      if fp["r#{j}"].opacity == 0 && j <= (i%128)/16 && i < 96
        fp["r#{j}"].opacity = 255
        fp["r#{j}"].zoom_x = 0
        fp["r#{j}"].zoom_y = 0
      end
      fp["r#{j}"].opacity -= 4
      fp["r#{j}"].zoom_x += 0.05
      fp["r#{j}"].zoom_y += 0.05
    end
    #-----------------------------------------------------------------------------
    pbSEPlay("Anim/Twine", 80) if i == 40
    pbSEPlay("Anim/Refresh") if i == 56
    #-----------------------------------------------------------------------------
    if i >= 24
      # ripple animation
      for j in 0...3
        next if j > (i-32)/12
        next if fp["v#{j}"].zoom_x <= 0
        fp["v#{j}"].opacity += 16*fp["v#{j}"].toggle
        fp["v#{j}"].zoom_x -= 0.05
        fp["v#{j}"].zoom_y -= 0.05
        fp["v#{j}"].toggle = -0.2 if fp["v#{j}"].zoom_x < 1.6*factor
      end
    end
    @scene.wait(1,true)
  end
  @viewport.color = Color.white
  @targetSprite.color.alpha = 0
  pbDisposeSpriteHash(fp)
  @sprites["battlebg"].focus
  #-----------------------------------------------------------------------------
  # animate impact
  fp["impact"] = Sprite.new(@viewport)
  fp["impact"].bitmap = pbBitmap("Graphics/EBDX/Pictures/impact")
  fp["impact"].center!(true)
  fp["impact"].z = 999
  fp["impact"].opacity = 0
  @targetSprite.charged = true# unless !@hitNum.nil?
  playBattlerCry(@battlers[@targetIndex])
  k = -2
  for i in 0...24
    fp["impact"].opacity += 64
    fp["impact"].angle += 180 if i%4 == 0
    fp["impact"].mirror = !fp["impact"].mirror if i%4 == 2
    k *= -1 if i%4 == 0
    @viewport.color.alpha -= 16 if i > 1
    @scene.moveEntireScene(0,k,true,true)
    @scene.wait(1,false)
  end
  for i in 0...16
    fp["impact"].opacity -= 64
    fp["impact"].angle += 180 if i%4 == 0
    fp["impact"].mirror = !fp["impact"].mirror if i%4 == 2
    @scene.wait
  end
  #-----------------------------------------------------------------------------
  #  return to original and dispose particles
  @scene.pbShowAllDataboxes
  fp["impact"].dispose
  #-----------------------------------------------------------------------------
end

#===== FILE: BIRDSPLASH.rb =====#
#-------------------------------------------------------------------------------
#  BIRDSPLASH
#-------------------------------------------------------------------------------
EliteBattle.defineCommonAnimation(:BIRDSPLASH) do
  #vector = @scene.getRealVector(@targetIndex, @targetIsPlayer)
  factor = @targetIsPlayer ? 2 : 1.5
  # set up animation
  fp = {}
  bomb = true
  idxStonesM = 10
  idxSontesS = 5
  #@vector.set(@scene.getRealVector(@targetIndex, @targetIsPlayer))
  # rest of the particles
  for j in 0...idxStonesM
    fp["p#{j}"] = Sprite.new(@viewport)
    fp["p#{j}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/ebConfused")
    fp["p#{j}"].center!
    fp["p#{j}"].x, fp["p#{j}"].y = @targetSprite.getCenter(true)
    r = (40 + rand(24))*@targetSprite.zoom_x
    x, y = randCircleCord(r)
    fp["p#{j}"].end_x = fp["p#{j}"].x - r + x
    fp["p#{j}"].end_y = fp["p#{j}"].y - r + y
    fp["p#{j}"].zoom_x = 0
    fp["p#{j}"].zoom_y = 0
    fp["p#{j}"].angle = rand(360)
    fp["p#{j}"].z = @targetSprite.z + 1
  end
  for j in 0...idxSontesS
    fp["c#{j}"] = Sprite.new(@viewport)
    fp["c#{j}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/ebConfused")
    fp["c#{j}"].center!
    fp["c#{j}"].x, fp["c#{j}"].y = @targetSprite.getCenter(true)
    #fp["c#{j}"].y -= (@targetSprite.bitmap.height*0.5)*@userSprite.zoom_y
    r = (48 + rand(32))*@targetSprite.zoom_x
    fp["c#{j}"].end_x = fp["c#{j}"].x - r + rand(r*2)
    fp["c#{j}"].end_y = fp["c#{j}"].y - r + rand(r*2)#(52 - rand(64))*@targetSprite.zoom_y
    fp["c#{j}"].zoom_x = 0
    fp["c#{j}"].zoom_y = 0
    fp["c#{j}"].opacity = 0
    fp["c#{j}"].z = @targetSprite.z + 1
    fp["c#{j}"].toggle = 1.2 + rand(10)/10.0
    fp["c#{j}"].visible = bomb
  end
  # splash
  for i in 0...idxStonesM * 5
    break if !bomb && i > 15
	pbSEPlay("Anim/confusion1") if i%(idxStonesM/2) == 0
    for j in 0...idxStonesM
      next if !bomb
      next if i < 8
      next if j > (i-8)*2
      fp["p#{j}"].zoom_x += (1.6 - fp["p#{j}"].zoom_x)*0.05
      fp["p#{j}"].zoom_y += (1.6 - fp["p#{j}"].zoom_y)*0.05
      fp["p#{j}"].x += (fp["p#{j}"].end_x - fp["p#{j}"].x)*0.05
      fp["p#{j}"].y += (fp["p#{j}"].end_y - fp["p#{j}"].y)*0.05
      if fp["p#{j}"].zoom_x >= 1
        fp["p#{j}"].opacity -= 16
      end
      fp["p#{j}"].color.alpha -= 8
    end
    for j in 0...idxSontesS
      next if j > i
      fp["c#{j}"].x += (fp["c#{j}"].end_x - fp["c#{j}"].x)*0.05
      fp["c#{j}"].y += (fp["c#{j}"].end_y - fp["c#{j}"].y)*0.05
      fp["c#{j}"].opacity += 16
      fp["c#{j}"].toggle = -1 if fp["c#{j}"].opacity >= 255
      fp["c#{j}"].zoom_x += (fp["c#{j}"].toggle - fp["c#{j}"].zoom_x)*0.05
      fp["c#{j}"].zoom_y += (fp["c#{j}"].toggle - fp["c#{j}"].zoom_y)*0.05
	  if fp["c#{j}"].zoom_x >= 0.5
        fp["c#{j}"].opacity -= 20
      end
    end
    @targetSprite.color.alpha -= 16 if i >= 48
    @targetSprite.anim = true
    @targetSprite.still
    @scene.wait(1,i < 8)
  end
end
#===== FILE: BURN.rb =====#
#===============================================================================
#  Common Animation: BURN
#===============================================================================
EliteBattle.defineCommonAnimation(:BURN) do
  #-----------------------------------------------------------------------------
  #  configure variables
  @scene.wait(16, true) if @scene.afterAnim
  fp = {}; rndx = []; rndy = []; shake = 2; k = -1
  factor = @targetIsPlayer ? 1 : 0.5
  cx, cy = @targetSprite.getCenter(true)
  #-----------------------------------------------------------------------------
  #  set up sprites
  for i in 0...3
    fp["#{i}"] = Sprite.new(@viewport)
    fp["#{i}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/eb136")
    fp["#{i}"].src_rect.set(0, 101*rand(3), 53, 101)
    fp["#{i}"].ox = 26
    fp["#{i}"].oy = 101
    fp["#{i}"].opacity = 0
    fp["#{i}"].z = (@targetIsPlayer ? 29 : 19)
    rndx.push(rand(64))
    rndy.push(rand(64))
    fp["#{i}"].x = cx - 32*factor + rndx[i]*factor
    fp["#{i}"].y = cy - 32*factor + rndy[i]*factor + 50*factor
  end
  #-----------------------------------------------------------------------------
  #  begin animation
  pbSEPlay("EBDX/Anim/fire1", 80)
  for i in 0...32
    k *= -1 if i%16 == 0
    for j in 0...3
      if fp["#{j}"].opacity == 0 && fp["#{j}"].tone.gray == 0
        fp["#{j}"].zoom_x = factor; fp["#{j}"].zoom_y = factor
        fp["#{j}"].y -= 2*factor
      end
      next if j > (i/4)
      fp["#{j}"].src_rect.x += 53 if i%4 == 0
      fp["#{j}"].src_rect.x = 0 if fp["#{j}"].src_rect.x >= fp["#{j}"].bitmap.width
      if fp["#{j}"].opacity == 255 || fp["#{j}"].tone.gray > 0
        fp["#{j}"].opacity -= 16
        fp["#{j}"].tone.gray += 8
        fp["#{j}"].tone.red -= 2; fp["#{j}"].tone.green -= 2; fp["#{j}"].tone.blue -= 2
        fp["#{j}"].zoom_x -= 0.01; fp["#{j}"].zoom_y += 0.02
      else
        fp["#{j}"].opacity += 51
      end
    end
    @targetSprite.tone.red += 2.4*k
    @targetSprite.tone.green -= 1.2*k
    @targetSprite.tone.blue -= 2.4*k
    @targetSprite.ox += shake
    shake = -2 if @targetSprite.ox > @targetSprite.bitmap.width/2 + 2
    shake = 2 if @targetSprite.ox < @targetSprite.bitmap.width/2 - 2
    @targetSprite.still
    @scene.wait(1, true)
  end
  #-----------------------------------------------------------------------------
  #  restore parameters
  @targetSprite.ox = @targetSprite.bitmap.width/2
  pbDisposeSpriteHash(fp)
  #-----------------------------------------------------------------------------
end

#===== FILE: CLAMP.rb =====#
#-------------------------------------------------------------------------------
#  CLAMP	
#-------------------------------------------------------------------------------
EliteBattle.defineCommonAnimation(:CLAMP) do
  vector = @scene.getRealVector(@targetIndex, @targetIsPlayer)
  factor = @targetIsPlayer ? 2 : 1.5
  # set up animation
  fp = {}
  #
  fp["bg"] = Sprite.new(@viewport)
  fp["bg"].bitmap = Bitmap.new(@viewport.width,@viewport.height)
  fp["bg"].bitmap.fill_rect(0,0,fp["bg"].bitmap.width,fp["bg"].bitmap.height,Color.black)
  fp["bg"].opacity = 0
  #
  shake = 8
  zoom = -1
  # start animation
  @vector.set(vector)
  @sprites["battlebg"].defocus
  for i in 0...55
    pbSEPlay("Anim/Wrap",80) if i == 20
	if i < 10
      fp["bg"].opacity += 12
    elsif i >= 20
	  @targetSprite.ox += shake
      shake = -8 if @targetSprite.ox > @targetSprite.bitmap.width/2 + 4
      shake = 8 if @targetSprite.ox < @targetSprite.bitmap.width/2 - 4
      @targetSprite.still
    elsif i > 10
       	@targetSprite.zoom_x -= 0.04*factor
	    @targetSprite.zoom_y += 0.04*factor
	    @targetSprite.still
	end
    zoom *= -1 if i%2 == 0
    fp["bg"].update
    fp["bg"].zoom_y += 0.04*zoom
    @scene.wait(1,true)
  end
  @targetSprite.ox = @targetSprite.bitmap.width/2
  10.times do
    @targetSprite.zoom_x -= 0.04*factor
    @targetSprite.zoom_y += 0.04*factor
    @targetSprite.still
    @scene.wait
  end
  @scene.wait(8)
  @vector.reset if !@multiHit
  10.times do
    fp["bg"].opacity -= 25.5
    @targetSprite.still
    @scene.wait(1,true)
  end
  @sprites["battlebg"].focus
  pbDisposeSpriteHash(fp)
end
#===== FILE: CONFUSION.rb =====#
#===============================================================================
#  Common Animation: CONFUSION
#===============================================================================
EliteBattle.defineCommonAnimation(:CONFUSION) do
  #-----------------------------------------------------------------------------
  #  configure variables
  @scene.wait(16, true) if @scene.afterAnim
  fp = {}; k = -1
  factor = @targetSprite.zoom_x
  reversed = []; cx, cy = @targetSprite.getCenter(true)
  #-----------------------------------------------------------------------------
  #  set up sprites
  for j in 0...8
    fp["#{j}"] = Sprite.new(@viewport)
    fp["#{j}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/ebConfused")
    fp["#{j}"].ox = fp["#{j}"].bitmap.width/2
    fp["#{j}"].oy = fp["#{j}"].bitmap.height/2
    fp["#{j}"].zoom_x = factor
    fp["#{j}"].zoom_y = factor
    fp["#{j}"].opacity
    fp["#{j}"].y = cy - 32*factor
    fp["#{j}"].x = cx + 64*factor - (j%4)*32*factor
    reversed.push([false,true][j/4])
  end
  #-----------------------------------------------------------------------------
  #  play animation
  vol = 80
  for i in 0...64
    k = i if i < 16
    pbSEPlay("EBDX/Anim/confusion1",vol) if i%8 == 0
    vol -= 5 if i%8 == 0
    for j in 0...8
      reversed[j] = true if fp["#{j}"].x <= cx - 64*factor
      reversed[j] = false if fp["#{j}"].x >= cx + 64*factor
      fp["#{j}"].z = reversed[j] ? @targetSprite.z - 1 : @targetSprite.z + 1
      fp["#{j}"].y = cy - 48*factor - k*2*factor - (reversed[j] ? 4*factor : 0)
      fp["#{j}"].x -= reversed[j] ? -4*factor : 4*factor
      fp["#{j}"].opacity += 16 if i < 16
      fp["#{j}"].opacity -= 16 if i >= 48
    end
    @scene.wait(1,true)
  end
  #-----------------------------------------------------------------------------
  #  dispose sprites
  pbDisposeSpriteHash(fp)
  #-----------------------------------------------------------------------------
end

#===== FILE: DISTORTION.rb =====#
#===============================================================================
#  Common Animation: DISTORTION
#===============================================================================
EliteBattle.defineCommonAnimation(:DISTORTION) do
  @scene.wait(2)
  # initial metrics
  bmp = Graphics.snap_to_bitmap
  max = 50; amax = 4; frames = {}; zoom = 1
  # sets viewport color
  @viewport.color = Color.new(255, 255, 155, 0)
  # animates initial viewport color
  20.times do
    @viewport.color.alpha += 2
    Graphics.update
  end
  # animates screen blur pattern
  for i in 0...(max + 20)
    if !(i%2 == 0)
      zoom += (i > max*0.75) ? 0.3 : -0.01
      angle = 0 if angle.nil?
      angle = (i%3 == 0) ? rand(amax*2) - amax : angle
      # creates necessary sprites
      frames[i] = Sprite.new(@viewport)
      frames[i].bitmap = Bitmap.new(@viewport.width, @viewport.height)
      frames[i].bitmap.blt(0, 0, bmp, @viewport.rect)
      frames[i].center!(true)
      frames[i].z = 999999
      frames[i].angle = angle
      frames[i].zoom = zoom
      frames[i].tone = Tone.new(i/4,i/4,i/4)
      frames[i].opacity = 30
    end
    # colors viewport
    if i >= max
      @viewport.color.alpha += 12
      @viewport.color.blue += 5
    end
    Graphics.update
  end
  # ensures viewport goes to black
  frames[(max+19)].tone = Tone.new(255, 255, 255)
  @viewport.color.alpha = 255
  @sprites["battlebg"].configure
  Graphics.update
  # disposes unused sprites
  pbDisposeSpriteHash(frames)
  # animate out
  32.times do
    @viewport.color.alpha -= 8
    @scene.wait
  end
end

#===== FILE: EXPLOSION.rb =====#
#-------------------------------------------------------------------------------
#  EXPLOSION
#-------------------------------------------------------------------------------
EliteBattle.defineCommonAnimation(:EXPLOSION) do
  @vector.set(@scene.getRealVector(@targetIndex, @targetIsPlayer))
  @scene.wait(7,true)
  cx, cy = @targetSprite.getCenter(true)
  dx = []
  dy = []
  factor = @targetSprite.zoom_x
  fp = {}
  for j in 0...24
    fp["#{j}"] = Sprite.new(@viewport)
	if rand(0..1)==0
		fp["#{j}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/eb010")
	else
		fp["#{j}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/eb010_2")
	end
    fp["#{j}"].ox = fp["#{j}"].bitmap.width/2
    fp["#{j}"].oy = fp["#{j}"].bitmap.height/2
    r = 64*factor
    x, y = randCircleCord(r)
    x = cx - r + x
    y = cy - r + y
    fp["#{j}"].x = cx
    fp["#{j}"].y = cx
    fp["#{j}"].z = @userSprite.z
    fp["#{j}"].visible = false
    fp["#{j}"].angle = rand(360)
    z = [0.5,1,0.75][rand(3)]
    fp["#{j}"].zoom_x = z
    fp["#{j}"].zoom_y = z
    dx.push(x)
    dy.push(y)
  end
  # rest of the particles
  for i in 0...48
	pbSEPlay("Anim/Explosion1",100) if i%8 == 0
    for j in 0...24
      next if j>(i*2)
      fp["#{j}"].visible = true
      if ((fp["#{j}"].x - dx[j])*0.1).abs < 1
        fp["#{j}"].opacity -= 32
      else
        fp["#{j}"].x -= (fp["#{j}"].x - dx[j])*0.1
        fp["#{j}"].y -= (fp["#{j}"].y - dy[j])*0.1
		fp["#{j}"].color.alpha += rand(-50..50)
      end
    end
	if i.between?(5,19)
		@targetSprite.tone.all-=12
	end
	if i.between?(20,34)
		@targetSprite.tone.all+=12
	end
    @scene.wait
  end
  pbDisposeSpriteHash(fp)
  @vector.reset
end
#===== FILE: EXPLOSION_SELF.rb =====#
#-------------------------------------------------------------------------------
#  EXPLOSION_SELF
#-------------------------------------------------------------------------------
EliteBattle.defineCommonAnimation(:EXPLOSION_SELF) do
  @vector.set(@scene.getRealVector(@userIndex, @userIsPlayer))
  @scene.wait(7,true)
  cx, cy = @userSprite.getCenter(true)
  dx = []
  dy = []
  factor = @userSprite.zoom_x
  fp = {}
  for j in 0...24
    fp["#{j}"] = Sprite.new(@viewport)
	if rand(0..1)==0
		fp["#{j}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/eb010")
	else
		fp["#{j}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/eb010_2")
	end
    fp["#{j}"].ox = fp["#{j}"].bitmap.width/2
    fp["#{j}"].oy = fp["#{j}"].bitmap.height/2
    r = 64*factor
    x, y = randCircleCord(r)
    x = cx - r + x
    y = cy - r + y
    fp["#{j}"].x = cx
    fp["#{j}"].y = cx
    fp["#{j}"].z = @userSprite.z
    fp["#{j}"].visible = false
    fp["#{j}"].angle = rand(360)
    z = [0.5,1,0.75][rand(3)]
    fp["#{j}"].zoom_x = z
    fp["#{j}"].zoom_y = z
    dx.push(x)
    dy.push(y)
  end
  # rest of the particles
  for i in 0...48
	pbSEPlay("Anim/Explosion1",100) if i%8 == 0
    for j in 0...24
      next if j>(i*2)
      fp["#{j}"].visible = true
      if ((fp["#{j}"].x - dx[j])*0.1).abs < 1
        fp["#{j}"].opacity -= 32
      else
        fp["#{j}"].x -= (fp["#{j}"].x - dx[j])*0.1
        fp["#{j}"].y -= (fp["#{j}"].y - dy[j])*0.1
		fp["#{j}"].color.alpha += rand(-50..50)
      end
    end
	if i.between?(5,19)
		@userSprite.tone.all-=12
	end
	if i.between?(20,34)
		@userSprite.tone.all+=12
	end
    @scene.wait
  end
  pbDisposeSpriteHash(fp)
  @vector.reset
end
#===== FILE: FIRESPIN.rb =====#
#===============================================================================
#  Common Animation: FIRESPIN
#===============================================================================
EliteBattle.defineCommonAnimation(:FIRESPIN) do
  #-----------------------------------------------------------------------------
  #  configure variables
  @scene.wait(16, true) if @scene.afterAnim
  fp = {}; rndx = []; rndy = []; shake = 2; k = -1
  factor = @targetIsPlayer ? 1 : 0.5
  cx, cy = @targetSprite.getCenter(true)
  #-----------------------------------------------------------------------------
  #  set up sprites
  for i in 0...3
    fp["#{i}"] = Sprite.new(@viewport)
    fp["#{i}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/eb136")
    fp["#{i}"].src_rect.set(0, 101*rand(3), 53, 101)
    fp["#{i}"].ox = 26
    fp["#{i}"].oy = 101
    fp["#{i}"].opacity = 0
    fp["#{i}"].z = (@targetIsPlayer ? 29 : 19)
    rndx.push(rand(64))
    rndy.push(rand(64))
    fp["#{i}"].x = cx - 32*factor + rndx[i]*factor
    fp["#{i}"].y = cy - 32*factor + rndy[i]*factor + 50*factor
  end
  #-----------------------------------------------------------------------------
  #  begin animation
  pbSEPlay("EBDX/Anim/fire1", 80)
  for i in 0...32
    k *= -1 if i%16 == 0
    for j in 0...3
      if fp["#{j}"].opacity == 0 && fp["#{j}"].tone.gray == 0
        fp["#{j}"].zoom_x = factor; fp["#{j}"].zoom_y = factor
        fp["#{j}"].y -= 2*factor
      end
      next if j > (i/4)
      fp["#{j}"].src_rect.x += 53 if i%4 == 0
      fp["#{j}"].src_rect.x = 0 if fp["#{j}"].src_rect.x >= fp["#{j}"].bitmap.width
      if fp["#{j}"].opacity == 255 || fp["#{j}"].tone.gray > 0
        fp["#{j}"].opacity -= 16
        fp["#{j}"].tone.gray += 8
        fp["#{j}"].tone.red -= 2; fp["#{j}"].tone.green -= 2; fp["#{j}"].tone.blue -= 2
        fp["#{j}"].zoom_x -= 0.01; fp["#{j}"].zoom_y += 0.02
      else
        fp["#{j}"].opacity += 51
      end
    end
    @targetSprite.tone.red += 2.4*k
    @targetSprite.tone.green -= 1.2*k
    @targetSprite.tone.blue -= 2.4*k
    @targetSprite.ox += shake
    shake = -2 if @targetSprite.ox > @targetSprite.bitmap.width/2 + 2
    shake = 2 if @targetSprite.ox < @targetSprite.bitmap.width/2 - 2
    @targetSprite.still
    @scene.wait(1, true)
  end
  #-----------------------------------------------------------------------------
  #  restore parameters
  @targetSprite.ox = @targetSprite.bitmap.width/2
  pbDisposeSpriteHash(fp)
  #-----------------------------------------------------------------------------
end

#===== FILE: FOCUSPUNCH.rb =====#
#-------------------------------------------------------------------------------
#  FOCUSPUNCH
#-------------------------------------------------------------------------------
EliteBattle.defineCommonAnimation(:FOCUSPUNCH) do
  vector = @scene.getRealVector(@targetIndex, @targetIsPlayer)
  vector2 = @scene.getRealVector(@userIndex, @userIsPlayer)
  # set up animation
  fp = {}
  speed = []
  for j in 0...32
    fp["#{j}"] = Sprite.new(@viewport)
    fp["#{j}"].z = @userIsPlayer ? 29 : 19
    fp["#{j}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/eb615")
    fp["#{j}"].ox = fp["#{j}"].bitmap.width/2
    fp["#{j}"].oy = fp["#{j}"].bitmap.height/2
    fp["#{j}"].color = Color.new(255,255,255,255)
    z = [0.5,1.5,1,0.75,1.25][rand(5)]
    fp["#{j}"].zoom_x = z
    fp["#{j}"].zoom_y = z
    fp["#{j}"].opacity = 0
    speed.push((rand(8)+1)*4)
  end
  for j in 0...8
    fp["s#{j}"] = Sprite.new(@viewport)
    fp["s#{j}"].z = @userIsPlayer ? 29 : 19
    fp["s#{j}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/eb057_2")
    fp["s#{j}"].ox = fp["s#{j}"].bitmap.width/2
    fp["s#{j}"].oy = fp["s#{j}"].bitmap.height
    #z = [0.5,1.5,1,0.75,1.25][rand(5)]
    fp["s#{j}"].color = Color.new(255,255,255,255)
    #fp["s#{j}"].zoom_y = z
    fp["s#{j}"].opacity = 0
  end
  @userSprite.color = Color.new(255,0,0,0)
  # start animation
  @vector.set(vector2)
  @vector.inc = 0.1
  oy = @userSprite.oy
  k = -1
  for i in 0...64
    k *= -1 if i%4==0
    pbSEPlay("EBDX/Anim/dragon2") if i == 12
    cx, cy = @userSprite.getCenter(true)
    for j in 0...32
      next if i < 8
      next if j>(i-8)
      if fp["#{j}"].opacity == 0 && fp["#{j}"].color.alpha == 255
        fp["#{j}"].y = @userSprite.y + 8*@userSprite.zoom_y - rand(24)*@userSprite.zoom_y
        fp["#{j}"].x = cx - 64*@userSprite.zoom_x + rand(128)*@userSprite.zoom_x
      end
      if fp["#{j}"].color.alpha <= 96
        fp["#{j}"].opacity -= 32
      else
        fp["#{j}"].opacity += 32
      end
      fp["#{j}"].color.alpha -= 16
      fp["#{j}"].y -= speed[j]
    end
    for j in 0...8
      next if i < 12
      next if j>(i-12)/2
      if fp["s#{j}"].opacity == 0 && fp["s#{j}"].color.alpha == 255
        fp["s#{j}"].y = @userSprite.y + 48*@userSprite.zoom_y - rand(16)*@userSprite.zoom_y
        fp["s#{j}"].x = cx - 64*@userSprite.zoom_x + rand(128)*@userSprite.zoom_x
      end
      if fp["s#{j}"].color.alpha <= 96
        fp["s#{j}"].opacity -= 32
      else
        fp["s#{j}"].opacity += 32
      end
      fp["s#{j}"].color.alpha -= 16
      fp["s#{j}"].zoom_y += speed[j]*0.25*0.01
      fp["s#{j}"].y -= speed[j]
    end
    if i < 48
      @userSprite.color.alpha += 4
    else
      @userSprite.color.alpha -= 16
    end
    @userSprite.oy -= 2*k if i%2==0
    @userSprite.still
    @userSprite.anim = true
    @scene.wait(1,true)
  end
  @userSprite.oy = oy
  @targetSprite.ox = @targetSprite.bitmap.width/2
  @vector.reset if !@multiHit
  pbDisposeSpriteHash(fp)
end

#===== FILE: FORMCHANGE.rb =====#
#===============================================================================
#  Common Animation: FORMCHANGE
#===============================================================================
EliteBattle.defineCommonAnimation(:FORMCHANGE) do | pokemon |
  #-----------------------------------------------------------------------------
  #  transition sprite
  10.times do
    @targetSprite.tone.all += 51 if @targetSprite.tone.all < 255
    @scene.wait(1)
  end
  #-----------------------------------------------------------------------------
  #  apply new Pokemon bitmap
  @targetSprite.setPokemonBitmap(pokemon[0], @targetIsPlayer)
  @targetDatabox.refresh
  @scene.wait
  #-----------------------------------------------------------------------------
  #  transition sprite
  10.times do
    @targetSprite.tone.all -= 51 if @targetSprite.tone.all > 0
    @scene.wait(1)
  end
  #-----------------------------------------------------------------------------
end

#===== FILE: FROZEN.rb =====#
#===============================================================================
#  Common Animation: FROZEN
#===============================================================================
EliteBattle.defineCommonAnimation(:FROZEN) do
  #-----------------------------------------------------------------------------
  #  configure variables
  @scene.wait(16, true) if @scene.afterAnim
  fp = {}; rndx = []; rndy = []; k = -1
  factor = @targetSprite.zoom_x
  #-----------------------------------------------------------------------------
  #  set up sprites
  for i in 0...12
    fp["#{i}"] = Sprite.new(@viewport)
    fp["#{i}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/eb248")
    fp["#{i}"].src_rect.set(rand(2)*26, 0, 26, 42)
    fp["#{i}"].ox = 13
    fp["#{i}"].oy = 21
    fp["#{i}"].opacity = 0
    fp["#{i}"].z = (@targetIsPlayer ? 29 : 19)
    r = rand(101)
    fp["#{i}"].zoom_x = (factor - r*0.0075*factor)
    fp["#{i}"].zoom_y = (factor - r*0.0075*factor)
    rndx.push(rand(96))
    rndy.push(rand(96))
  end
  #-----------------------------------------------------------------------------
  #  play animation
  pbSEPlay("EBDX/Anim/ice1")
  for i in 0...32
    k *= -1 if i%8 == 0
    for j in 0...12
      next if j>(i/2)
      if fp["#{j}"].opacity == 0
        cx, cy = @targetSprite.getCenter(true)
        fp["#{j}"].x = cx - 48*factor + rndx[j]*factor
        fp["#{j}"].y = cy - 48*factor + rndy[j]*factor
      end
      fp["#{j}"].src_rect.x += 26 if i%4 == 0 && fp["#{j}"].opacity >= 255
      fp["#{j}"].src_rect.x = 78 if fp["#{j}"].src_rect.x > 78
      if fp["#{j}"].src_rect.x == 78
        fp["#{j}"].opacity -= 24
        fp["#{j}"].zoom_x += 0.02
        fp["#{j}"].zoom_y += 0.02
      elsif fp["#{j}"].opacity >= 255
        fp["#{j}"].opacity -= 24
      else
        fp["#{j}"].opacity += 45 if (i)/2 > k
      end
    end
    @targetSprite.tone.red += 3.2*k; @targetSprite.tone.green += 3.2*k; @targetSprite.tone.blue += 3.2*k
    @targetSprite.still
    @scene.wait(1, true)
  end
  #-----------------------------------------------------------------------------
  #  dispose sprites
  pbDisposeSpriteHash(fp)
  #-----------------------------------------------------------------------------
end

#===== FILE: GRUDGE.rb =====#
#===============================================================================
#  Common Animation: GRUDGE
#===============================================================================
EliteBattle.defineCommonAnimation(:GRUDGE) do
  #-----------------------------------------------------------------------------
  #  configure variables
  @scene.wait(16, true) if @scene.afterAnim
  fp = {}; rndx = []; rndy = []; shake = 2; k = -1
  factor = @targetIsPlayer ? 1 : 0.5
  cx, cy = @targetSprite.getCenter(true)
  #-----------------------------------------------------------------------------
  #  set up sprites
  for i in 0...3
    fp["#{i}"] = Sprite.new(@viewport)
    fp["#{i}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/eb136_3")
    fp["#{i}"].src_rect.set(0, 101*rand(3), 53, 101)
    fp["#{i}"].ox = 26
    fp["#{i}"].oy = 101
    fp["#{i}"].opacity = 0
    fp["#{i}"].z = (@targetIsPlayer ? 29 : 19)
    rndx.push(rand(64))
    rndy.push(rand(64))
    fp["#{i}"].x = cx - 32*factor + rndx[i]*factor
    fp["#{i}"].y = cy - 32*factor + rndy[i]*factor + 50*factor
  end
  #-----------------------------------------------------------------------------
  #  begin animation
  pbSEPlay("Anim/Nightshade", 100)
  for i in 0...32
    k *= -1 if i%16 == 0
    for j in 0...3
      if fp["#{j}"].opacity == 0 && fp["#{j}"].tone.gray == 0
        fp["#{j}"].zoom_x = factor; fp["#{j}"].zoom_y = factor
        fp["#{j}"].y -= 2*factor
      end
      next if j > (i/4)
      fp["#{j}"].src_rect.x += 53 if i%4 == 0
      fp["#{j}"].src_rect.x = 0 if fp["#{j}"].src_rect.x >= fp["#{j}"].bitmap.width
      if fp["#{j}"].opacity == 255 || fp["#{j}"].tone.gray > 0
        fp["#{j}"].opacity -= 16
        fp["#{j}"].tone.gray += 8
        fp["#{j}"].tone.red -= 2; fp["#{j}"].tone.green -= 2; fp["#{j}"].tone.blue -= 2
        fp["#{j}"].zoom_x -= 0.01; fp["#{j}"].zoom_y += 0.02
      else
        fp["#{j}"].opacity += 51
      end
    end
	@targetSprite.tone.red -= 2.4*k*5
    @targetSprite.tone.green -= 2.4*k*5
    @targetSprite.tone.blue -= 2.4*k*5
    @targetSprite.ox += shake
    shake = -2 if @targetSprite.ox > @targetSprite.bitmap.width/2 + 2
    shake = 2 if @targetSprite.ox < @targetSprite.bitmap.width/2 - 2
    @targetSprite.still
    @scene.wait(1, true)
  end
  #-----------------------------------------------------------------------------
  #  restore parameters
  @targetSprite.ox = @targetSprite.bitmap.width/2
  pbDisposeSpriteHash(fp)
  #-----------------------------------------------------------------------------
end
#===== FILE: HEALTHUP.rb =====#
#===============================================================================
#  Common Animation: HEALTHUP
#===============================================================================
EliteBattle.defineCommonAnimation(:HEALTHUP) do
  #-----------------------------------------------------------------------------
  #  configure variables
  @scene.wait(16, true) if @scene.afterAnim
  pt = {}; rndx = []; rndy = []; tone = []; timer = []; speed = []
  endy = @targetSprite.y - @targetSprite.bitmap.height*(@targetIsPlayer ? 1.5 : 1)
  #-----------------------------------------------------------------------------
  #  set up sprites
  for i in 0...32
    s = rand(2)
    y = rand(64) + 1
    c = [Color.new(92,202,81),Color.new(68,215,105),Color.new(192,235,180)][rand(3)]
    pt["#{i}"] = Sprite.new(@viewport)
    pt["#{i}"].bitmap = Bitmap.new(14,14)
    pt["#{i}"].bitmap.bmp_circle(c)
    pt["#{i}"].ox = pt["#{i}"].bitmap.width/2
    pt["#{i}"].oy = pt["#{i}"].bitmap.height/2
    width = (96/@targetSprite.bitmap.width*0.5).to_i
    pt["#{i}"].x = @targetSprite.x + rand((64 + width)*@targetSprite.zoom_x - 32)*(s==0 ? 1 : -1)
    pt["#{i}"].y = @targetSprite.y
    pt["#{i}"].z = @targetSprite.z + (rand(2)==0 ? 1 : -1)
    r = rand(4)
    pt["#{i}"].zoom_x = @targetSprite.zoom_x*[1,0.9,0.75,0.5][r]*0.84
    pt["#{i}"].zoom_y = @targetSprite.zoom_y*[1,0.9,0.75,0.5][r]*0.84
    pt["#{i}"].opacity = 0
    pt["#{i}"].tone = Tone.new(128,128,128)
    tone.push(128)
    rndx.push(pt["#{i}"].x + rand(32)*(s==0 ? 1 : -1))
    rndy.push(endy - y*@targetSprite.zoom_y)
    timer.push(0)
    speed.push((rand(50)+1)*0.002)
  end
  for j in 0...12
    pt["s#{j}"] = Sprite.new(@viewport)
    pt["s#{j}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/ebHealing")
    pt["s#{j}"].ox = pt["s#{j}"].bitmap.width/2
    pt["s#{j}"].oy = pt["s#{j}"].bitmap.height/2
    pt["s#{j}"].opacity = 0
    z = [1,0.75,1.25,0.5][rand(4)]*@targetSprite.zoom_x
    pt["s#{j}"].zoom_x = z
    pt["s#{j}"].zoom_y = z
    cx, cy = @targetSprite.getCenter(true)
    pt["s#{j}"].x = cx - 32*@targetSprite.zoom_x + rand(64)*@targetSprite.zoom_x
    pt["s#{j}"].y = cy - 32*@targetSprite.zoom_x + rand(64)*@targetSprite.zoom_x
    pt["s#{j}"].opacity = 0
    pt["s#{j}"].z = @targetIsPlayer ? 29 : 19
  end
  #-----------------------------------------------------------------------------
  #  play animation
  pbSEPlay("Anim/Recovery",80)
  for i in 0...64
    for j in 0...32
      next if j > (i)
      timer[j] += 1
      pt["#{j}"].x += (rndx[j] - pt["#{j}"].x)*speed[j]
      pt["#{j}"].y -= (pt["#{j}"].y - rndy[j])*speed[j]
      tone[j] -= 8 if tone[j] > 0
      pt["#{j}"].tone.all = tone[j]
      pt["#{j}"].angle += 4
      if timer[j] > 8
        pt["#{j}"].opacity -= 8
        pt["#{j}"].zoom_x -= 0.02*@targetSprite.zoom_x if pt["#{j}"].zoom_x > 0
        pt["#{j}"].zoom_y -= 0.02*@targetSprite.zoom_y if pt["#{j}"].zoom_y > 0
      else
        pt["#{j}"].opacity += 25 if pt["#{j}"].opacity < 200
        pt["#{j}"].zoom_x += 0.025*@targetSprite.zoom_x
        pt["#{j}"].zoom_y += 0.025*@targetSprite.zoom_y
      end
    end
    for k in 0...12
      next if k > i
      pt["s#{k}"].opacity += 51
      pt["s#{k}"].zoom_x -= pt["s#{k}"].zoom_x*0.25 if pt["s#{k}"].opacity >= 255 && pt["s#{k}"].zoom_x > 0
      pt["s#{k}"].zoom_y -= pt["s#{k}"].zoom_y*0.25 if pt["s#{k}"].opacity >= 255 && pt["s#{k}"].zoom_y > 0
    end
    @scene.wait(1, true)
  end
  #-----------------------------------------------------------------------------
  #  dispose sprites
  pbDisposeSpriteHash(pt)
  #-----------------------------------------------------------------------------
end

#===== FILE: INFESTATION.rb =====#
#===============================================================================
#  Common Animation: INFESTATION
#===============================================================================
EliteBattle.defineCommonAnimation(:INFESTATION) do
  # configure animation
  @scene.wait(16,true)
  factor = @targetSprite.zoom_x
  cx, cy = @targetSprite.getCenter(true)
  dx = []
  dy = []
  fp = {}
  numElements = 60
  for j in 0...numElements
    fp["#{j}"] = Sprite.new(@viewport)
    fp["#{j}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/eb010_5")
    fp["#{j}"].ox = fp["#{j}"].bitmap.width/2
    fp["#{j}"].oy = fp["#{j}"].bitmap.height/2
    r = 45*factor
    x, y = randCircleCord(r)
    x = cx - r + x
    y = cy - r + y
    fp["#{j}"].x = cx
    fp["#{j}"].y = cy
    fp["#{j}"].z = @targetSprite.z + 1
    fp["#{j}"].visible = false
    fp["#{j}"].angle = rand(360)
    z = [0.5,1,0.75][rand(3)]
    fp["#{j}"].zoom_x = z
    fp["#{j}"].zoom_y = z
    dx.push(x)
    dy.push(y)
  end
  # target coloring
  @targetSprite.color = Color.new(11,50,10,0)
  # start animation
  pbSEPlay("EBDX/Anim/ground1",80)
  for i in 0...48
    for j in 0...numElements
      next if j>(i*2)
      fp["#{j}"].visible = true
      if ((fp["#{j}"].x - dx[j])*0.1).abs < 1
        fp["#{j}"].opacity -= 32
      else
        fp["#{j}"].x -= (fp["#{j}"].x - dx[j])*0.1
        fp["#{j}"].y -= (fp["#{j}"].y - dy[j])*0.1
      end
    end
	if i < 24
      @targetSprite.color.alpha += 10
    else
      @targetSprite.color.alpha -= 10
    end
	@targetSprite.still
    @targetSprite.anim = true
    @scene.wait
  end
  @vector.reset if !@multiHit
  pbDisposeSpriteHash(fp)
end


#===== FILE: LEECHSEED.rb =====#
#-------------------------------------------------------------------------------
#  LEECHSEED
#-------------------------------------------------------------------------------
EliteBattle.defineCommonAnimation(:LEECHSEED) do | args |
  type = args[0]; type = "absorb" if type.nil?
  # set up animation
  fp = {}
  fp["bg"] = Sprite.new(@viewport)
  fp["bg"].bitmap = Bitmap.new(@viewport.width, @viewport.height)
  fp["bg"].bitmap.fill_rect(0,0,fp["bg"].bitmap.width,fp["bg"].bitmap.height,Color.black)
  fp["bg"].bitmap.fill_rect(0,0,fp["bg"].bitmap.width,fp["bg"].bitmap.height,Color.new(100,166,94)) if type == "mega"
  fp["bg"].opacity = 0
  ext = ["eb210","eb210_2"]
  cxT, cyT = @targetSprite.getCenter(true)
  cxP, cyP = @userSprite.getCenter(true)
  mx = !@targetIsPlayer ? (cxT-cxP)/2 : (cxP-cxT)/2
  mx += @targetIsPlayer ? cxT : cxP
  my = !@targetIsPlayer ? (cyP-cyT)/2 : (cyT-cyP)/2
  my += @targetIsPlayer ? cyP : cyT
  curves = []
  zoom = []
  frames =  16
  factor = 1
  pbSEPlay("Anim/Absorb2", 80)
  for j in 0...frames
    fp["#{j}"] = Sprite.new(@viewport)
    fp["#{j}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/"+ext[rand(ext.length)])
    fp["#{j}"].ox = fp["#{j}"].bitmap.width/2
    fp["#{j}"].oy = fp["#{j}"].bitmap.height/2
    fp["#{j}"].x = cxT
    fp["#{j}"].y = cyT
    z = [1,0.75,0.5,0.25][rand(4)]
    fp["#{j}"].zoom_x = z*@userSprite.zoom_x
    fp["#{j}"].zoom_y = z*@userSprite.zoom_y
    v = type == "mega" ? 1 : 0
    ox = -16*factor + rand(32*factor) - 32*v + rand(64*v)
    oy = -16*factor + rand(32*factor) - 32*v + rand(64*v)
    vert = rand(96)*(rand(2)==0 ? 1 : -1)*(factor**2)
    fp["#{j}"].z = 50
    fp["#{j}"].opacity = 0
    curve = calculateCurve(cxT+ox,cyT+oy,mx,my+vert+oy,cxP+ox,cyP+oy,32)
    curves.push(curve)
    zoom.push(z)
  end
  max = type == "giga" ? 16 : 8
  for j in 0...max
    fp["s#{j}"] = Sprite.new(@viewport)
    fp["s#{j}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/ebHealing")
    fp["s#{j}"].ox = fp["s#{j}"].bitmap.width/2
    fp["s#{j}"].oy = fp["s#{j}"].bitmap.height/2
    fp["s#{j}"].zoom_x = @userSprite.zoom_x
    fp["s#{j}"].zoom_y = @userSprite.zoom_x
    cx, cy = @userSprite.getCenter(true)
    fp["s#{j}"].x = cx - 48*@userSprite.zoom_x + rand(96)*@userSprite.zoom_x
    fp["s#{j}"].y = cy - 48*@userSprite.zoom_y + rand(96)*@userSprite.zoom_y
    fp["s#{j}"].visible = false
    fp["s#{j}"].z = 51
  end
  @sprites["battlebg"].defocus
  for i in 0...64
    fp["bg"].opacity += 16 if fp["bg"].opacity < 128
    for j in 0...frames
      next if j>i/(32/frames)
      k = i - j*(32/frames)
      fp["#{j}"].visible = false if k >= frames
      k = frames - 1 if k >= frames
      k = 0 if k < 0
      if type == "giga"
        fp["#{j}"].tone.red += 4
        fp["#{j}"].tone.blue += 4
        fp["#{j}"].tone.green += 4
      end
      fp["#{j}"].x = curves[j][k][0]
      fp["#{j}"].y = curves[j][k][1]
      fp["#{j}"].opacity += (k < 16) ? 64 : -16
      fp["#{j}"].zoom_x -= (fp["#{j}"].zoom_x - @targetSprite.zoom_x*zoom[j])*0.1
      fp["#{j}"].zoom_y -= (fp["#{j}"].zoom_y - @targetSprite.zoom_y*zoom[j])*0.1
    end
    for k in 0...max
      next if type == "absorb"
      next if i < frames/2
      next if k>(i-frames/2)/(16/max)
      fp["s#{k}"].visible = true
      fp["s#{k}"].opacity -= 16
      fp["s#{k}"].y -= 2
    end
    if type == "giga"
      @userSprite.tone.red += 8 if @userSprite.tone.red < 128
      @userSprite.tone.green += 8 if @userSprite.tone.green < 128
      @userSprite.tone.blue += 8 if @userSprite.tone.blue < 128
    end
    pbSEPlay("Anim/Recovery",80) if type != "absorb" && i == (frames/2)
    @scene.wait(1,true)
  end
  for i in 0...8
    fp["bg"].opacity -= 16
    if type == "giga"
      @userSprite.tone.red -= 16
      @userSprite.tone.green -= 16
      @userSprite.tone.blue -= 16
    end
    @scene.wait(1,true)
  end
  @sprites["battlebg"].focus
  pbDisposeSpriteHash(fp)
end

#===== FILE: MEGAEVOLUTION.rb =====#
#===============================================================================
#  Common Animation: MEGAEVOLUTION
#===============================================================================
EliteBattle.defineCommonAnimation(:MEGAEVOLUTION2) do
  #-----------------------------------------------------------------------------
  # clear UI elements for mega evolution
  #  hides UI elements
  isVisible = []
  @battlers.each_with_index do |b, i|
    isVisible.push(false)
    next if !b
    isVisible[i] = @sprites["dataBox_#{i}"].visible
    @sprites["dataBox_#{i}"].visible = false
  end
  @scene.clearMessageWindow
  #-----------------------------------------------------------------------------
  fp = {}
  pokemon = @battlers[@targetIndex]
  #-----------------------------------------------------------------------------
  back = @targetIndex%2 == 0
  @vector.set(@scene.getRealVector(@targetIndex, back))
  @scene.wait(16, true)
  factor = @targetSprite.zoom_x
  #-----------------------------------------------------------------------------
  fp["bg"] = ScrollingSprite.new(@viewport)
  fp["bg"].setBitmap("Graphics/EBDX/Animations/Moves/ebMegaBg")
  fp["bg"].speed = 32
  fp["bg"].opacity = 0
  #-----------------------------------------------------------------------------
  # particle initialization
  for i in 0...16
    fp["c#{i}"] = Sprite.new(@viewport)
    fp["c#{i}"].z = @targetSprite.z + 10
    fp["c#{i}"].bitmap = pbBitmap(sprintf("Graphics/EBDX/Animations/Moves/ebMega%03d", rand(4)+1))
    fp["c#{i}"].center!
    fp["c#{i}"].opacity = 0
  end
  #-----------------------------------------------------------------------------
  # ray initialization
  rangle = []
  cx, cy = @targetSprite.getCenter(true)
  for i in 0...8; rangle.push((360/8)*i +  15); end
  for j in 0...8
    fp["r#{j}"] = Sprite.new(@viewport)
    fp["r#{j}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/ebMega005")
    fp["r#{j}"].ox = 0
    fp["r#{j}"].oy = fp["r#{j}"].bitmap.height/2
    fp["r#{j}"].opacity = 0
    fp["r#{j}"].zoom_x = 0
    fp["r#{j}"].zoom_y = 0
    fp["r#{j}"].x = cx
    fp["r#{j}"].y = cy
    a = rand(rangle.length)
    fp["r#{j}"].angle = rangle[a]
    fp["r#{j}"].z = @targetSprite.z + 2
    rangle.delete_at(a)
  end
  #-----------------------------------------------------------------------------
  # ripple initialization
  for j in 0...3
    fp["v#{j}"] = Sprite.new(@viewport)
    fp["v#{j}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/ebMega006")
    fp["v#{j}"].center!
    fp["v#{j}"].x = cx
    fp["v#{j}"].y = cy
    fp["v#{j}"].opacity = 0
    fp["v#{j}"].zoom_x = 2
    fp["v#{j}"].zoom_y = 2
  end
  #-----------------------------------------------------------------------------
  fp["circle"] = Sprite.new(@viewport)
  fp["circle"].bitmap = Bitmap.new(@targetSprite.bitmap.width*1.25,@targetSprite.bitmap.height*1.25)
  fp["circle"].bitmap.bmp_circle
  fp["circle"].center!
  fp["circle"].x = cx
  fp["circle"].y = cy
  fp["circle"].z = @targetSprite.z + 10
  fp["circle"].zoom_x = 0
  fp["circle"].zoom_y = 0
  #-----------------------------------------------------------------------------
  z = 0.02
  @sprites["battlebg"].defocus
  pbSEPlay("Anim/Harden",120)
  for i in 0...128
    fp["bg"].opacity += 8
    fp["bg"].update
    @targetSprite.tone.all += 8 if @targetSprite.tone.all < 255
    # particle animation
    for j in 0...16
      next if j > (i/8)
      if fp["c#{j}"].opacity == 0 && i < 72
        fp["c#{j}"].opacity = 255
        x, y = randCircleCord(96*factor)
        fp["c#{j}"].x = cx - 96*factor + x
        fp["c#{j}"].y = cy - 96*factor + y
      end
      x2 = cx
      y2 = cy
      x0 = fp["c#{j}"].x
      y0 = fp["c#{j}"].y
      fp["c#{j}"].x += (x2 - x0)*0.1
      fp["c#{j}"].y += (y2 - y0)*0.1
      fp["c#{j}"].opacity -= 16
    end
    #---------------------------------------------------------------------------
    # ray animation
    for j in 0...8
      if fp["r#{j}"].opacity == 0 && j <= (i%128)/16 && i < 96
        fp["r#{j}"].opacity = 255
        fp["r#{j}"].zoom_x = 0
        fp["r#{j}"].zoom_y = 0
      end
      fp["r#{j}"].opacity -= 4
      fp["r#{j}"].zoom_x += 0.05
      fp["r#{j}"].zoom_y += 0.05
    end
    #---------------------------------------------------------------------------
    # circle animation
    if i < 48
    elsif i < 64
      fp["circle"].zoom_x += factor/16.0
      fp["circle"].zoom_y += factor/16.0
    elsif i >= 124
      fp["circle"].zoom_x += factor
      fp["circle"].zoom_y += factor
    else
      z *= -1 if (i-96)%4 == 0
      fp["circle"].zoom_x += z
      fp["circle"].zoom_y += z
    end
    #---------------------------------------------------------------------------
    pbSEPlay("Anim/Twine", 80) if i == 40
    pbSEPlay("Anim/Refresh") if i == 56
    #---------------------------------------------------------------------------
    if i >= 24
      # ripple animation
      for j in 0...3
        next if j > (i-32)/8
        next if fp["v#{j}"].zoom_x <= 0
        fp["v#{j}"].opacity += 16
        fp["v#{j}"].zoom_x -= 0.05
        fp["v#{j}"].zoom_y -= 0.05
      end
    end
    @scene.wait(1,true)
  end
  #-----------------------------------------------------------------------------
  # finish up animation
  @viewport.color = Color.white
  pbSEPlay("Vs flash", 80)
  @targetSprite.tone.all = 0
  pbDisposeSpriteHash(fp)
  @sprites["battlebg"].focus
  fp["impact"] = Sprite.new(@viewport)
  fp["impact"].bitmap = pbBitmap("Graphics/EBDX/Pictures/impact")
  fp["impact"].center!(true)
  fp["impact"].z = 999
  fp["impact"].opacity = 0
  @targetSprite.setPokemonBitmap(pokemon, back)
  @targetDatabox.refresh
  playBattlerCry(@battlers[@targetIndex])
  k = -2
  for i in 0...24
    fp["impact"].opacity += 64
    fp["impact"].angle += 180 if i%4 == 0
    fp["impact"].mirror = !fp["impact"].mirror if i%4 == 2
    k *= -1 if i%4 == 0
    @viewport.color.alpha -= 16 if i > 1
    @scene.moveEntireScene(0, k, true, true)
    @scene.wait(1, false)
  end
  for i in 0...16
    fp["impact"].opacity -= 64
    fp["impact"].angle += 180 if i%4 == 0
    fp["impact"].mirror = !fp["impact"].mirror if i%4 == 2
    @scene.wait
  end
  #-----------------------------------------------------------------------------
  #  return to original and dispose particles
  @battlers.each_with_index do |b, i|
    next if !b
    @sprites["dataBox_#{i}"].visible = true if isVisible[i]
  end
  fp["impact"].dispose
  @vector.reset
  @scene.wait(16, true)
  #-----------------------------------------------------------------------------
end

#===== FILE: NIGHTMARE.rb =====#
#===============================================================================
#  Common Animation: NIGHTMARE
#===============================================================================
EliteBattle.defineCommonAnimation(:NIGHTMARE) do
  #-----------------------------------------------------------------------------
  #  configure variables
  @scene.wait(16, true) if @scene.afterAnim
  fp = {}; rndx = []; rndy = []; shake = 2; k = -1
  factor = @targetIsPlayer ? 1 : 0.5
  cx, cy = @targetSprite.getCenter(true)
  #-----------------------------------------------------------------------------
  #  set up sprites
  for i in 0...3
    fp["#{i}"] = Sprite.new(@viewport)
    fp["#{i}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/eb136_3")
    fp["#{i}"].src_rect.set(0, 101*rand(3), 53, 101)
    fp["#{i}"].ox = 26
    fp["#{i}"].oy = 101
    fp["#{i}"].opacity = 0
    fp["#{i}"].z = (@targetIsPlayer ? 29 : 19)
    rndx.push(rand(64))
    rndy.push(rand(64))
    fp["#{i}"].x = cx - 32*factor + rndx[i]*factor
    fp["#{i}"].y = cy - 32*factor + rndy[i]*factor + 50*factor
  end
  #-----------------------------------------------------------------------------
  #  begin animation
  pbSEPlay("Anim/Nightshade", 100)
  for i in 0...32
    k *= -1 if i%16 == 0
    for j in 0...3
      if fp["#{j}"].opacity == 0 && fp["#{j}"].tone.gray == 0
        fp["#{j}"].zoom_x = factor; fp["#{j}"].zoom_y = factor
        fp["#{j}"].y -= 2*factor
      end
      next if j > (i/4)
      fp["#{j}"].src_rect.x += 53 if i%4 == 0
      fp["#{j}"].src_rect.x = 0 if fp["#{j}"].src_rect.x >= fp["#{j}"].bitmap.width
      if fp["#{j}"].opacity == 255 || fp["#{j}"].tone.gray > 0
        fp["#{j}"].opacity -= 16
        fp["#{j}"].tone.gray += 8
        fp["#{j}"].tone.red -= 2; fp["#{j}"].tone.green -= 2; fp["#{j}"].tone.blue -= 2
        fp["#{j}"].zoom_x -= 0.01; fp["#{j}"].zoom_y += 0.02
      else
        fp["#{j}"].opacity += 51
      end
    end
	@targetSprite.tone.red -= 2.4*k*5
    @targetSprite.tone.green -= 2.4*k*5
    @targetSprite.tone.blue -= 2.4*k*5
    @targetSprite.ox += shake
    shake = -2 if @targetSprite.ox > @targetSprite.bitmap.width/2 + 2
    shake = 2 if @targetSprite.ox < @targetSprite.bitmap.width/2 - 2
    @targetSprite.still
    @scene.wait(1, true)
  end
  #-----------------------------------------------------------------------------
  #  restore parameters
  @targetSprite.ox = @targetSprite.bitmap.width/2
  pbDisposeSpriteHash(fp)
  #-----------------------------------------------------------------------------
end
#===== FILE: PARALYSIS.rb =====#
#===============================================================================
#  Common Animation: PARALYSIS
#===============================================================================
EliteBattle.defineCommonAnimation(:PARALYSIS) do
  #-----------------------------------------------------------------------------
  #  configure variables
  @scene.wait(16, true) if @scene.afterAnim
  fp = {}; k = -1
  factor = @targetSprite.zoom_x
  #-----------------------------------------------------------------------------
  #  set up sprites
  for i in 0...12
    fp["#{i}"] = Sprite.new(@viewport)
    fp["#{i}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/eb064_3")
    fp["#{i}"].ox = fp["#{i}"].bitmap.width/2
    fp["#{i}"].oy = fp["#{i}"].bitmap.height/2
    fp["#{i}"].opacity = 0
    fp["#{i}"].z = @targetIsPlayer ? 29 : 19
  end
  #-----------------------------------------------------------------------------
  #  play animation
  pbSEPlay("EBDX/Anim/electric1")
  for i in 0...32
    k *= -1 if i%16 == 0
    for n in 0...12
      next if n>(i/2)
      if fp["#{n}"].opacity == 0 && fp["#{n}"].tone.gray == 0
        r2 = rand(4)
        fp["#{n}"].zoom_x = [0.2,0.25,0.5,0.75][r2]
        fp["#{n}"].zoom_y = [0.2,0.25,0.5,0.75][r2]
        cx, cy = @targetSprite.getCenter(true)
        x, y = randCircleCord(32*factor)
        fp["#{n}"].x = cx - 32*factor*@targetSprite.zoom_x + x*@targetSprite.zoom_x
        fp["#{n}"].y = cy - 32*factor*@targetSprite.zoom_y + y*@targetSprite.zoom_y
        fp["#{n}"].angle = -Math.atan(1.0*(fp["#{n}"].y-cy)/(fp["#{n}"].x-cx))*(180.0/Math::PI) + rand(2)*180 + rand(90)
      end
      fp["#{n}"].opacity += 155 if i < 27
      fp["#{n}"].angle += 180 if i%2 == 0
      fp["#{n}"].opacity -= 51 if i >= 27
    end
    @targetSprite.tone.all -= 14*k
    @targetSprite.still
    @scene.wait(1,true)
  end
  #-----------------------------------------------------------------------------
  #  dispose sprites
  pbDisposeSpriteHash(fp)
  #-----------------------------------------------------------------------------
end

#===== FILE: POISON.rb =====#
#===============================================================================
#  Common Animation: POISON
#===============================================================================
EliteBattle.defineCommonAnimation(:POISON) do
  #-----------------------------------------------------------------------------
  #  configure variables
  @scene.wait(16, true) if @scene.afterAnim
  fp = {}; shake = 1; k = -0.1; inc = 1
  factor = @targetSprite.zoom_x
  cx, cy = @targetSprite.getCenter(true)
  endy = []
  #-----------------------------------------------------------------------------
  #  set up sprites
  for j in 0...12
    fp["#{j}"] = Sprite.new(@viewport)
    fp["#{j}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/ebPoison#{rand(3)+1}")
    fp["#{j}"].ox = fp["#{j}"].bitmap.width/2
    fp["#{j}"].oy = fp["#{j}"].bitmap.height/2
    fp["#{j}"].x = cx - 48*factor + rand(96)*factor
    fp["#{j}"].y = cy
    z = [1,0.9,0.8][rand(3)]
    fp["#{j}"].zoom_x = z*factor
    fp["#{j}"].zoom_y = z*factor
    fp["#{j}"].opacity = 0
    fp["#{j}"].z = @targetIsPlayer ? 29 : 19
    endy.push(cy - 64*factor - rand(32)*factor)
  end
  #-----------------------------------------------------------------------------
  #  play animation
  for i in 0...32
    pbSEPlay("EBDX/Anim/poison1", 80) if i%8 == 0
    @targetSprite.ox += shake
    k *= -1 if i%16 == 0
    inc += k
    for j in 0...12
      next if j>(i/2)
      fp["#{j}"].y -= (fp["#{j}"].y - endy[j])*0.06
      fp["#{j}"].opacity += 51 if i < 16
      fp["#{j}"].opacity -= 16 if i >= 16
      fp["#{j}"].x -= 1*factor*(fp["#{j}"].x < cx ? 1 : -1)
      fp["#{j}"].angle += 4*(fp["#{j}"].x < cx ? 1 : -1)
    end
    shake = -1*inc.round if @targetSprite.ox > @targetSprite.bitmap.width/2
    shake = 1*inc.round if @targetSprite.ox < @targetSprite.bitmap.width/2
    @targetSprite.still
    @targetSprite.color.alpha += k*60
    @targetSprite.anim = true
    @scene.wait(1,true)
  end
  #-----------------------------------------------------------------------------
  #  restore original
  @targetSprite.ox = @targetSprite.bitmap.width/2
  pbDisposeSpriteHash(fp)
  #-----------------------------------------------------------------------------
end

#===== FILE: ROAR.rb =====#
#===============================================================================
#  Common Animation: ROAR
#===============================================================================
EliteBattle.defineCommonAnimation(:ROAR) do
  #-----------------------------------------------------------------------------
  fp = {}
  #-----------------------------------------------------------------------------
  #  vector config
  back = !@battle.opposes?(@targetIndex)
  @vector.set(@scene.getRealVector(@targetIndex, back))
  @scene.wait(16, true)
  factor = @targetSprite.zoom_x
  #-----------------------------------------------------------------------------
  # animate impact
  fp["impact"] = Sprite.new(@viewport)
  fp["impact"].bitmap = pbBitmap("Graphics/EBDX/Pictures/impact")
  fp["impact"].center!(true)
  fp["impact"].z = 999
  fp["impact"].opacity = 0
  playBattlerCry(@battlers[@targetIndex])
  k = -2
  for i in 0...24
    fp["impact"].opacity += 64
    fp["impact"].angle += 180 if i%4 == 0
    fp["impact"].mirror = !fp["impact"].mirror if i%4 == 2
    k *= -1 if i%4 == 0
    @viewport.color.alpha -= 16 if i > 1
    @scene.moveEntireScene(0,k,true,true)
    @scene.wait(1,false)
  end
  for i in 0...16
    fp["impact"].opacity -= 64
    fp["impact"].angle += 180 if i%4 == 0
    fp["impact"].mirror = !fp["impact"].mirror if i%4 == 2
    @scene.wait
  end
  #-----------------------------------------------------------------------------
  fp["impact"].dispose
  @vector.reset
  @scene.wait(16, true)
  #-----------------------------------------------------------------------------
end

#===== FILE: ROCKSPLASH.rb =====#
#-------------------------------------------------------------------------------
#  ROCKSPLASH
#-------------------------------------------------------------------------------
EliteBattle.defineCommonAnimation(:ROCKSPLASH) do
  vector = @scene.getRealVector(@targetIndex, @targetIsPlayer)
  factor = @targetIsPlayer ? 2 : 1.5
  # set up animation
  fp = {}
  bomb = true
  idxStonesM = 20
  idxSontesS = 15
  @vector.set(@scene.getRealVector(@targetIndex, @targetIsPlayer))
  @targetSprite.color = Color.new(112,81,41,0)
  # zooming onto the target
  8.times do
    @targetSprite.color.alpha += 18
    @targetSprite.anim = true
    @targetSprite.still
    @scene.wait(1,true)
  end
  # rest of the particles
  for j in 0...idxStonesM
    fp["p#{j}"] = Sprite.new(@viewport)
    fp["p#{j}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/eb504_1")
    fp["p#{j}"].center!
    fp["p#{j}"].x, fp["p#{j}"].y = @targetSprite.getCenter(true)
    r = (40 + rand(24))*@targetSprite.zoom_x
    x, y = randCircleCord(r)
    fp["p#{j}"].end_x = fp["p#{j}"].x - r + x
    fp["p#{j}"].end_y = fp["p#{j}"].y - r + y
    fp["p#{j}"].zoom_x = 0
    fp["p#{j}"].zoom_y = 0
    fp["p#{j}"].angle = rand(360)
    fp["p#{j}"].z = @targetSprite.z + 1
  end
  for j in 0...idxSontesS
    fp["c#{j}"] = Sprite.new(@viewport)
    fp["c#{j}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/eb504_2")
    fp["c#{j}"].center!
    fp["c#{j}"].x, fp["c#{j}"].y = @targetSprite.getCenter(true)
    #fp["c#{j}"].y -= (@targetSprite.bitmap.height*0.5)*@userSprite.zoom_y
    r = (48 + rand(32))*@targetSprite.zoom_x
    fp["c#{j}"].end_x = fp["c#{j}"].x - r + rand(r*2)
    fp["c#{j}"].end_y = fp["c#{j}"].y - r + rand(r*2)#(52 - rand(64))*@targetSprite.zoom_y
    fp["c#{j}"].zoom_x = 0
    fp["c#{j}"].zoom_y = 0
    fp["c#{j}"].opacity = 0
    fp["c#{j}"].z = @targetSprite.z + 1
    fp["c#{j}"].toggle = 1.2 + rand(10)/10.0
    fp["c#{j}"].visible = bomb
  end
  # splash
  for i in 0...idxStonesM * 3
    break if !bomb && i > 15
	pbSEPlay("Anim/rock2") if i%15 == 0
    for j in 0...idxStonesM
      next if !bomb
      next if i < 8
      next if j > (i-8)*2
      fp["p#{j}"].zoom_x += (1.6 - fp["p#{j}"].zoom_x)*0.05
      fp["p#{j}"].zoom_y += (1.6 - fp["p#{j}"].zoom_y)*0.05
      fp["p#{j}"].x += (fp["p#{j}"].end_x - fp["p#{j}"].x)*0.05
      fp["p#{j}"].y += (fp["p#{j}"].end_y - fp["p#{j}"].y)*0.05
      if fp["p#{j}"].zoom_x >= 1
        fp["p#{j}"].opacity -= 16
      end
      fp["p#{j}"].color.alpha -= 8
    end
    for j in 0...idxSontesS
      next if j > i
      fp["c#{j}"].x += (fp["c#{j}"].end_x - fp["c#{j}"].x)*0.05
      fp["c#{j}"].y += (fp["c#{j}"].end_y - fp["c#{j}"].y)*0.05
      fp["c#{j}"].opacity += 16
      fp["c#{j}"].toggle = -1 if fp["c#{j}"].opacity >= 255
      fp["c#{j}"].zoom_x += (fp["c#{j}"].toggle - fp["c#{j}"].zoom_x)*0.05
      fp["c#{j}"].zoom_y += (fp["c#{j}"].toggle - fp["c#{j}"].zoom_y)*0.05
	  if fp["c#{j}"].zoom_x >= 0.5
        fp["c#{j}"].opacity -= 20
      end
    end
    @targetSprite.color.alpha -= 16 if i >= 48
    @targetSprite.anim = true
    @targetSprite.still
    @scene.wait(1,i < 8)
  end
end
#===== FILE: SANDTOMB.rb =====#
#===============================================================================
#  Common Animation: SANDTOMB
#===============================================================================
EliteBattle.defineCommonAnimation(:SANDTOMB) do
  #-----------------------------------------------------------------------------
  #  configure variables
  @scene.wait(16, true) if @scene.afterAnim
  fp = {}; rndx = []; rndy = []; shake = 2; k = -1; idxSand = 10
  factor = @targetIsPlayer ? 1 : 0.5
  cx, cy = @targetSprite.getCenter(true)
  #-----------------------------------------------------------------------------
  #  set up sprites
  for i in 0...idxSand
    fp["#{i}"] = Sprite.new(@viewport)
    fp["#{i}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/eb504_2")
    fp["#{i}"].src_rect.set(0, 0*rand(3), 53, 101)
    fp["#{i}"].ox = 26
    fp["#{i}"].oy = 101
    fp["#{i}"].opacity = 0
    fp["#{i}"].z = (@targetIsPlayer ? 29 : 19)
    rndx.push(rand(64))
    rndy.push(rand(64))
    fp["#{i}"].x = cx - 32*factor + rndx[i]*factor
    fp["#{i}"].y = cy - 32*factor + rndy[i]*factor + 50*factor
  end
  #-----------------------------------------------------------------------------
  #  begin animation
  for i in 0...32
  pbSEPlay("EBDX/Anim/ground1", 80) if i%8 == 0
    k *= -1 if i%16 == 0
    for j in 0...idxSand
      if fp["#{j}"].opacity == 0 && fp["#{j}"].tone.gray == 0
        fp["#{j}"].zoom_x = factor; fp["#{j}"].zoom_y = factor
        fp["#{j}"].y -= 2*factor
      end
      next if j > (i/4)
      if fp["#{j}"].opacity == 255 || fp["#{j}"].tone.gray > 0
        fp["#{j}"].opacity -= 16
        fp["#{j}"].tone.gray += 8
        fp["#{j}"].zoom_x -= 0.01; fp["#{j}"].zoom_y += 0.02
      else
        fp["#{j}"].opacity += 51
      end
    end
    @targetSprite.ox += shake
    shake = -2 if @targetSprite.ox > @targetSprite.bitmap.width/2 + 2
    shake = 2 if @targetSprite.ox < @targetSprite.bitmap.width/2 - 2
    @targetSprite.still
    @scene.wait(1, true)
  end
  #-----------------------------------------------------------------------------
  #  restore parameters
  @targetSprite.ox = @targetSprite.bitmap.width/2
  pbDisposeSpriteHash(fp)
  #-----------------------------------------------------------------------------
end

#===== FILE: SHINY.rb =====#
#===============================================================================
#  Common Animation: SHINY
#===============================================================================
EliteBattle.defineCommonAnimation(:SHINY) do
  #-----------------------------------------------------------------------------
  #  configure variables
  @scene.wait(16, true) if @scene.afterAnim
  fp = {}; k = -1
  factor = @targetSprite.zoom_x
  #-----------------------------------------------------------------------------
  #  set up sprites
  for i in 0...16
    cx, cy = @targetSprite.getCenter(true)
    fp["#{i}"] = Sprite.new(@viewport)
    str = "Graphics/EBDX/Animations/Moves/ebShiny1"
    str = "Graphics/EBDX/Animations/Moves/ebShiny2" if i >= 8
    fp["#{i}"].bitmap = pbBitmap(str).clone
    fp["#{i}"].bitmap.hue_change(180) if i < 8 && @battlers[@targetIndex].pokemon.superShiny?
    fp["#{i}"].center!
    fp["#{i}"].x = cx
    fp["#{i}"].y = cy
    fp["#{i}"].zoom_x = factor
    fp["#{i}"].zoom_y = factor
    fp["#{i}"].opacity = 0
    fp["#{i}"].z = @targetIsPlayer ? 29 : 19
  end
  for j in 0...8
    fp["s#{j}"] = Sprite.new(@viewport)
    fp["s#{j}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/ebShiny3").clone
    fp["s#{j}"].bitmap.hue_change(180) if @battlers[@targetIndex].pokemon.superShiny?
    fp["s#{j}"].center!
    fp["s#{j}"].opacity = 0
    z = [1,0.75,1.25,0.5][rand(4)]*factor
    fp["s#{j}"].zoom_x = z
    fp["s#{j}"].zoom_y = z
    cx, cy = @targetSprite.getCenter(true)
    fp["s#{j}"].x = cx - 32*factor + rand(64)*factor
    fp["s#{j}"].y = cy - 32*factor + rand(64)*factor
    fp["s#{j}"].opacity = 0
    fp["s#{j}"].z = @targetIsPlayer ? 29 : 19
  end
  #-----------------------------------------------------------------------------
  #  play animation part 1
  pbSEPlay("EBDX/Shiny")
  for i in 0...48
    k *= -1 if i%24 == 0
    cx, cy = @targetSprite.getCenter(true)
    for j in 0...16
      next if (j >= 8 && i < 16)
      a = (j < 8 ? -30 : -15) + 45*(j%8) + i*2
      r = @targetSprite.width*factor/2.5
      x = cx + r*Math.cos(a*(Math::PI/180))
      y = cy - r*Math.sin(a*(Math::PI/180))
      x = (x - fp["#{j}"].x)*0.1
      y = (y - fp["#{j}"].y)*0.1
      fp["#{j}"].x += x
      fp["#{j}"].y += y
      fp["#{j}"].angle += 8
      if j < 8
        fp["#{j}"].opacity += 51 if i < 16
        if i >= 16
          fp["#{j}"].opacity -= 16
          fp["#{j}"].zoom_x -= 0.04*factor
          fp["#{j}"].zoom_y -= 0.04*factor
        end
      else
        fp["#{j}"].opacity += 51 if i < 32
        if i >= 32
          fp["#{j}"].opacity -= 16
          fp["#{j}"].zoom_x -= 0.02*factor
          fp["#{j}"].zoom_y -= 0.02*factor
        end
      end
    end
    @targetSprite.tone.all += 3.2*k/2
    @scene.wait(1,true)
  end
  #-----------------------------------------------------------------------------
  #  play animation part 2
  pbSEPlay("EBDX/Anim/shine1",80)
  for i in 0...16
    for j in 0...8
      next if j>i
      fp["s#{j}"].opacity += 51
      fp["s#{j}"].zoom_x -= fp["s#{j}"].zoom_x*0.25 if fp["s#{j}"].opacity >= 255
      fp["s#{j}"].zoom_y -= fp["s#{j}"].zoom_y*0.25 if fp["s#{j}"].opacity >= 255
    end
    @scene.wait(1,true)
  end
  #-----------------------------------------------------------------------------
  #  dispose sprites
  pbDisposeSpriteHash(fp)
  #-----------------------------------------------------------------------------
end

#===== FILE: SLEEP.rb =====#
#===============================================================================
#  Common Animation: SLEEP
#===============================================================================
EliteBattle.defineCommonAnimation(:SLEEP) do
  #-----------------------------------------------------------------------------
  #  configure variables
  @scene.wait(16, true) if @scene.afterAnim
  fp = {}; r = []
  factor = @targetSprite.zoom_x
  #-----------------------------------------------------------------------------
  #  set up sprites
  for i in 0...3
    fp["#{i}"] = Sprite.new(@viewport)
    fp["#{i}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/ebSleep")
    fp["#{i}"].center!
    fp["#{i}"].angle = @targetIsPlayer ? 55 : 125
    fp["#{i}"].zoom_x = 0
    fp["#{i}"].zoom_y = 0
    fp["#{i}"].z = @targetIsPlayer ? 29 : 19
    fp["#{i}"].tone = Tone.new(192,192,192)
    r.push(0)
  end
  #-----------------------------------------------------------------------------
  #  play animation
  pbSEPlay("EBDX/Anim/snore",80)
  for j in 0...48
    cx, cy = @targetSprite.getCenter(true)
    for i in 0...3
      next if i > (j/12)
      fp["#{i}"].zoom_x += ((1*factor) - fp["#{i}"].zoom_x)*0.1
      fp["#{i}"].zoom_y += ((1*factor) - fp["#{i}"].zoom_y)*0.1
      a = @targetIsPlayer ? 55 : 125
      r[i] += 4*factor
      x = cx + r[i]*Math.cos(a*(Math::PI/180)) + 16*factor*(@targetIsPlayer ? 1 : -1)
      y = cy - r[i]*Math.sin(a*(Math::PI/180)) - 32*factor
      fp["#{i}"].x = x; fp["#{i}"].y = y
      fp["#{i}"].opacity -= 16 if r[i] >= 64
      fp["#{i}"].tone.all -= 16 if fp["#{i}"].tone.all > 0
      fp["#{i}"].angle += @targetIsPlayer ? - 1 : 1
    end
    @scene.wait(1,true)
  end
  #-----------------------------------------------------------------------------
  #  dispose sprites
  pbDisposeSpriteHash(fp)
  #-----------------------------------------------------------------------------
end

#===== FILE: SPARKLE_YELLOW.rb =====#
#-------------------------------------------------------------------------------
#  SPARKLE_YELLOW
#-------------------------------------------------------------------------------
EliteBattle.defineCommonAnimation(:SPARKLE_YELLOW) do
  # configure animation
  @vector.set(@scene.getRealVector(@targetIndex, @targetIsPlayer))
  @scene.wait(16,true)
  factor = @targetSprite.zoom_x
  cx, cy = @targetSprite.getCenter(true)
  dx = []
  dy = []
  fp = {}
  t = 35
  for j in 0...t
    fp["#{j}"] = Sprite.new(@viewport)
    fp["#{j}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/eb619")
    fp["#{j}"].ox = fp["#{j}"].bitmap.width/2
    fp["#{j}"].oy = fp["#{j}"].bitmap.height/2
    r = 64*factor
    x, y = randCircleCord(r)
    x = cx - r + x
    y = cy - r + y
    fp["#{j}"].x = cx
    fp["#{j}"].y = cx
    fp["#{j}"].z = @targetSprite.z
    fp["#{j}"].visible = false
    fp["#{j}"].angle = rand(360)
    z = [0.5,1,0.75][rand(3)]
    fp["#{j}"].zoom_x = z
    fp["#{j}"].zoom_y = z
    dx.push(x)
    dy.push(y)
  end
  # start animation
  pbSEPlay("Anim/Wish",80)
  for i in 0...2*t
    for j in 0...t
      next if j>(i*2)
      fp["#{j}"].visible = true
      if ((fp["#{j}"].x - dx[j])*0.1).abs < 1
        fp["#{j}"].opacity -= 32
      else
        fp["#{j}"].x -= (fp["#{j}"].x - dx[j])*0.1
        fp["#{j}"].y -= (fp["#{j}"].y - dy[j])*0.1
      end
    end
    @scene.wait
  end
  @vector.reset if !@multiHit
  pbDisposeSpriteHash(fp)
end

#===== FILE: STATDOWN.rb =====#
#===============================================================================
#  Common Animation: STATDOWN
#===============================================================================
EliteBattle.defineCommonAnimation(:STATDOWN) do
  #-----------------------------------------------------------------------------
  #  configure variables
  @scene.wait(16, true) if @scene.afterAnim
  pt = {}; rndx = []; rndy = []; tone = []; timer = []; speed = []
  endy = @targetSprite.y - @targetSprite.height*(@targetIsPlayer ? 1.5 : 1)
  #-----------------------------------------------------------------------------
  #  set up sprites
  for i in 0...64
    s = rand(2)
    y = rand(@targetSprite.height*0.25)+1
    c = [Color.new(128,183,238),Color.new(74,128,208),Color.new(54,141,228)][rand(3)]
    pt["#{i}"] = Sprite.new(@viewport)
    pt["#{i}"].bitmap = Bitmap.new(14,14)
    pt["#{i}"].bitmap.bmp_circle(c)
    pt["#{i}"].center!
    width = (96/@targetSprite.width*0.5).to_i
    pt["#{i}"].x = @targetSprite.x + rand((64 + width)*@targetSprite.zoom_x - 16)*(s==0 ? 1 : -1)
    pt["#{i}"].y = endy - y*@targetSprite.zoom_y
    pt["#{i}"].z = @targetSprite.z + (rand(2)==0 ? 1 : -1)
    r = rand(4)
    pt["#{i}"].zoom_x = @targetSprite.zoom_x*[1,0.9,0.95,0.85][r]*0.84
    pt["#{i}"].zoom_y = @targetSprite.zoom_y*[1,0.9,0.95,0.85][r]*0.84
    pt["#{i}"].opacity = 0
    pt["#{i}"].tone = Tone.new(128,128,128)
    tone.push(128)
    rndx.push(pt["#{i}"].x + rand(32)*(s==0 ? 1 : -1))
    rndy.push(@targetSprite.y + @targetSprite.height - @targetSprite.oy)
    timer.push(0)
    speed.push((rand(50)+1)*0.002)
  end
  #-----------------------------------------------------------------------------
  #  play animation
  pbSEPlay("Anim/decrease")
  for i in 0...64
    for j in 0...64
      next if j>(i*2)
      timer[j] += 1
      pt["#{j}"].x += (rndx[j] - pt["#{j}"].x)*speed[j]
      pt["#{j}"].y -= (pt["#{j}"].y - rndy[j])*speed[j]
      tone[j] -= 8 if tone[j] > 0
      pt["#{j}"].tone.all = tone[j]
      pt["#{j}"].angle += 4
      if timer[j] > 8
        pt["#{j}"].opacity -= 8
        pt["#{j}"].zoom_x -= 0.02*@targetSprite.zoom_x if pt["#{j}"].zoom_x > 0
        pt["#{j}"].zoom_y -= 0.02*@targetSprite.zoom_y if pt["#{j}"].zoom_y > 0
      else
        pt["#{j}"].opacity += 25 if pt["#{j}"].opacity < 200
        pt["#{j}"].zoom_x += 0.025*@targetSprite.zoom_x
        pt["#{j}"].zoom_y += 0.025*@targetSprite.zoom_y
      end
    end
    @scene.wait(1,true)
  end
  #-----------------------------------------------------------------------------
  #  dispose sprites
  pbDisposeSpriteHash(pt)
  #-----------------------------------------------------------------------------
end

#===== FILE: STATUP.rb =====#
#===============================================================================
#  Common Animation: STATUP
#===============================================================================
EliteBattle.defineCommonAnimation(:STATUP) do
  #-----------------------------------------------------------------------------
  #  configure variables
  @scene.wait(16, true) if @scene.afterAnim
  pt = {}; rndx = []; rndy = []; tone = []; timer = []; speed = []
  endy = @targetSprite.y - @targetSprite.height*(@targetIsPlayer ? 1.5 : 1)
  #-----------------------------------------------------------------------------
  #  set up sprites
  for i in 0...64
    s = rand(2)
    y = rand(64) + 1
    c = [Color.new(238,83,17),Color.new(236,112,19),Color.new(242,134,36)][rand(3)]
    pt["#{i}"] = Sprite.new(@viewport)
    pt["#{i}"].bitmap = Bitmap.new(14,14)
    pt["#{i}"].bitmap.bmp_circle(c)
    pt["#{i}"].center!
    width = (96/@targetSprite.width*0.5).to_i
    pt["#{i}"].x = @targetSprite.x + rand((64 + width)*@targetSprite.zoom_x - 16)*(s==0 ? 1 : -1)
    pt["#{i}"].y = @targetSprite.y
    pt["#{i}"].z = @targetSprite.z + (rand(2)==0 ? 1 : -1)
    r = rand(4)
    pt["#{i}"].zoom_x = @targetSprite.zoom_x*[1,0.9,0.95,0.85][r]*0.84
    pt["#{i}"].zoom_y = @targetSprite.zoom_y*[1,0.9,0.95,0.85][r]*0.84
    pt["#{i}"].opacity = 0
    pt["#{i}"].tone = Tone.new(128,128,128)
    tone.push(128)
    rndx.push(pt["#{i}"].x + rand(32)*(s==0 ? 1 : -1))
    rndy.push(endy - y*@targetSprite.zoom_y)
    timer.push(0)
    speed.push((rand(50)+1)*0.002)
  end
  #-----------------------------------------------------------------------------
  #  play animation
  pbSEPlay("Anim/increase")
  for i in 0...64
    for j in 0...64
      next if j > (i*2)
      timer[j] += 1
      pt["#{j}"].x += (rndx[j] - pt["#{j}"].x)*speed[j]
      pt["#{j}"].y -= (pt["#{j}"].y - rndy[j])*speed[j]
      tone[j] -= 8 if tone[j] > 0
      pt["#{j}"].tone.all = tone[j]
      pt["#{j}"].angle += 4
      if timer[j] > 8
        pt["#{j}"].opacity -= 8
        pt["#{j}"].zoom_x -= 0.02*@targetSprite.zoom_x if pt["#{j}"].zoom_x > 0
        pt["#{j}"].zoom_y -= 0.02*@targetSprite.zoom_y if pt["#{j}"].zoom_y > 0
      else
        pt["#{j}"].opacity += 25 if pt["#{j}"].opacity < 200
        pt["#{j}"].zoom_x += 0.025*@targetSprite.zoom_x
        pt["#{j}"].zoom_y += 0.025*@targetSprite.zoom_y
      end
    end
    @scene.wait(1, true)
  end
  #-----------------------------------------------------------------------------
  #  dispose sprites
  pbDisposeSpriteHash(pt)
  #-----------------------------------------------------------------------------
end

#===== FILE: SUBSTITUTE.rb =====#
#===============================================================================
#  Common Animation: SUBSTITUTE
#===============================================================================
EliteBattle.defineCommonAnimation(:SUBSTITUTE) do | targets, set |
  #-----------------------------------------------------------------------------
  #  transition sprites
  8.times do
    for t in targets
      @sprites["pokemon_#{t}"].x += ((t%2==0) ? -6 : 3)
      @sprites["pokemon_#{t}"].y -= ((t%2==0) ? -4 : 2)
      @sprites["pokemon_#{t}"].opacity -= 32
    end
    @scene.wait(1, false)
  end
  #-----------------------------------------------------------------------------
  #  change sprites
  for t in targets
    if (@battle.battlers[t].effects[PBEffects::Substitute] > 0 && !@sprites["pokemon_#{t}"].isSub) || set
      @sprites["pokemon_#{t}"].setSubstitute
    else
      @sprites["pokemon_#{t}"].removeSubstitute
    end
  end
  #-----------------------------------------------------------------------------
  #  transition sprites
  8.times do
    for t in targets
      @sprites["pokemon_#{t}"].x -= ((t%2 == 0) ? -6 : 3)
      @sprites["pokemon_#{t}"].y += ((t%2 == 0) ? -4 : 2)
      @sprites["pokemon_#{t}"].opacity += 32
    end
    @scene.wait(1, false)
  end
  #-----------------------------------------------------------------------------
end

#===== FILE: TOXIC.rb =====#
#===============================================================================
#  Common Animation: TOXIC
#===============================================================================
EliteBattle.defineCommonAnimation(:TOXIC) do
  #-----------------------------------------------------------------------------
  #  configure variables
  @scene.wait(16, true) if @scene.afterAnim
  fp = {}; shake = 1; k = -0.1; inc = 1
  factor = @targetSprite.zoom_x
  cx, cy = @targetSprite.getCenter(true)
  endy = []
  #-----------------------------------------------------------------------------
  #  set up sprites
  for j in 0...20
    fp["#{j}"] = Sprite.new(@viewport)
    fp["#{j}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/ebToxic#{rand(3)+1}")
    fp["#{j}"].ox = fp["#{j}"].bitmap.width/2
    fp["#{j}"].oy = fp["#{j}"].bitmap.height/2
    fp["#{j}"].x = cx - 48*factor + rand(96)*factor
    fp["#{j}"].y = cy
    z = [1,0.9,0.8][rand(3)]
    fp["#{j}"].zoom_x = z*factor
    fp["#{j}"].zoom_y = z*factor
    fp["#{j}"].opacity = 0
    fp["#{j}"].z = @targetIsPlayer ? 29 : 19
    endy.push(cy - 64*factor - rand(32)*factor)
  end
  #-----------------------------------------------------------------------------
  #  play animation
  for i in 0...32
    pbSEPlay("EBDX/Anim/poison1", 80) if i%8 == 0
    @targetSprite.ox += shake
    k *= -1 if i%16 == 0
    inc += k
    for j in 0...20
      next if j>(i/2)
      fp["#{j}"].y -= (fp["#{j}"].y - endy[j])*0.06
      fp["#{j}"].opacity += 51 if i < 16
      fp["#{j}"].opacity -= 16 if i >= 16
      fp["#{j}"].x -= 1*factor*(fp["#{j}"].x < cx ? 1 : -1)
      fp["#{j}"].angle += 4*(fp["#{j}"].x < cx ? 1 : -1)
    end
    shake = -1*inc.round if @targetSprite.ox > @targetSprite.bitmap.width/2
    shake = 1*inc.round if @targetSprite.ox < @targetSprite.bitmap.width/2
    @targetSprite.still
    @targetSprite.color.alpha += k*60
    @targetSprite.anim = true
    @scene.wait(1,true)
  end
  #-----------------------------------------------------------------------------
  #  restore original
  @targetSprite.ox = @targetSprite.bitmap.width/2
  pbDisposeSpriteHash(fp)
  #-----------------------------------------------------------------------------
end

#===== FILE: USEITEM.rb =====#
#===============================================================================
#  Common Animation: HEALTHUP
#===============================================================================
EliteBattle.defineCommonAnimation(:USEITEM) do
  #-----------------------------------------------------------------------------
  #  configure variables
  @scene.wait(16, true) if @scene.afterAnim
  pt = {}; rndx = []; rndy = []; tone = []; timer = []; speed = []
  endy = @targetSprite.y - @targetSprite.bitmap.height*(@targetIsPlayer ? 1.5 : 1)
  #-----------------------------------------------------------------------------
  #  set up sprites
  for j in 0...3
    pt["c#{j}"] = Sprite.new(@viewport)
    pt["c#{j}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/ebItem1")
    pt["c#{j}"].center!
    pt["c#{j}"].x, pt["c#{j}"].y = @targetSprite.getCenter(true)
    pt["c#{j}"].zx = @targetSprite.zoom_x * 2; pt["c#{j}"].zoom_x = pt["c#{j}"].zx
    pt["c#{j}"].zy = @targetSprite.zoom_y * 2; pt["c#{j}"].zoom_y = pt["c#{j}"].zy
    pt["c#{j}"].z = @targetSprite.z + 1
    pt["c#{j}"].opacity = 0
  end
  #-----------------------------------------------------------------------------
  #  play circle animation
  pbSEPlay("EBDX/Anim/shine1",80)
  for i in 0...48
    for j in 0...3
      next if (i/6) < j
      pt["c#{j}"].zoom_x -= pt["c#{j}"].zx/32
      pt["c#{j}"].zoom_y -= pt["c#{j}"].zy/32
      pt["c#{j}"].opacity += 16*(pt["c#{j}"].zoom_x > pt["c#{j}"].zx/2 ? 1 : -1)
    end
    @scene.wait(1, true)
  end
  #-----------------------------------------------------------------------------
  #  initialize shiny particles
  for j in 0...12
    pt["s#{j}"] = Sprite.new(@viewport)
    pt["s#{j}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/ebShiny3")
    pt["s#{j}"].ox = pt["s#{j}"].bitmap.width/2
    pt["s#{j}"].oy = pt["s#{j}"].bitmap.height/2
    pt["s#{j}"].opacity = 0
    z = [1,0.75,1.25,0.5][rand(4)]*@targetSprite.zoom_x
    pt["s#{j}"].zoom_x = z
    pt["s#{j}"].zoom_y = z
    cx, cy = @targetSprite.getCenter(true)
    pt["s#{j}"].x = cx - 32*@targetSprite.zoom_x + rand(64)*@targetSprite.zoom_x
    pt["s#{j}"].y = cy - 32*@targetSprite.zoom_x + rand(64)*@targetSprite.zoom_x
    pt["s#{j}"].opacity = 0
    pt["s#{j}"].z = @targetIsPlayer ? 29 : 19
  end
  #-----------------------------------------------------------------------------
  #  play shiny particle animation
  pbSEPlay("Anim/Recovery",80)
  for i in 0...32
    for k in 0...12
      next if k > i
      pt["s#{k}"].opacity += 51
      pt["s#{k}"].zoom_x -= pt["s#{k}"].zoom_x*0.25 if pt["s#{k}"].opacity >= 255 && pt["s#{k}"].zoom_x > 0
      pt["s#{k}"].zoom_y -= pt["s#{k}"].zoom_y*0.25 if pt["s#{k}"].opacity >= 255 && pt["s#{k}"].zoom_y > 0
    end
    @scene.wait(1, true)
  end
  #-----------------------------------------------------------------------------
  #  dispose sprites
  pbDisposeSpriteHash(pt)
  #-----------------------------------------------------------------------------
end

#===== FILE: WHIRLPOOL.rb =====#
#===============================================================================
#  Common Animation: WHIRLPOOL
#===============================================================================
EliteBattle.defineCommonAnimation(:WHIRLPOOL) do
  #-----------------------------------------------------------------------------
  #  configure variables
  @scene.wait(16, true) if @scene.afterAnim
  fp = {}; rndx = []; rndy = []; shake = 2; k = -1
  factor = @targetIsPlayer ? 1 : 0.5
  cx, cy = @targetSprite.getCenter(true)
  #-----------------------------------------------------------------------------
  #  set up sprites
  for i in 0...10
	randBubble = rand(3)
    fp["#{i}"] = Sprite.new(@viewport)
	if randBubble == 0 || randBubble == 1
		fp["#{i}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/eb618_2")
	elsif randBubble == 2
		fp["#{i}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/eb618")
	else
		fp["#{i}"].bitmap = pbBitmap("Graphics/EBDX/Animations/Moves/eb618_3")
	end
    #fp["#{i}"].src_rect.set(0, 0, 53, 101)
    fp["#{i}"].ox = 26
    fp["#{i}"].oy = 101
    fp["#{i}"].opacity = 0
    fp["#{i}"].z = (@targetIsPlayer ? 29 : 19)
    rndx.push(rand(64))
    rndy.push(rand(64))
    fp["#{i}"].x = cx - 32*factor + rndx[i]*factor
    fp["#{i}"].y = cy - 32*factor + rndy[i]*factor + 50*factor
  end
  #-----------------------------------------------------------------------------
  #  begin animation
  pbSEPlay("Anim/Bubble1", 80)
  for i in 0...32
    k *= -1 if i%16 == 0
	pbSEPlay("Anim/Bubble2", 90) if i%4 == 0
	pbSEPlay("Anim/Bubble1", 90) if i%8 == 0
    for j in 0...10
      if fp["#{j}"].opacity == 0 && fp["#{j}"].tone.gray == 0
        fp["#{j}"].zoom_x = factor; fp["#{j}"].zoom_y = factor
        fp["#{j}"].y -= 2*factor
      end
      next if j > (i/4)
      #fp["#{j}"].src_rect.x += 53 if i%4 == 0
      #fp["#{j}"].src_rect.x = 0 if fp["#{j}"].src_rect.x >= fp["#{j}"].bitmap.width
      if fp["#{j}"].opacity == 255 || fp["#{j}"].tone.gray > 0
        fp["#{j}"].opacity -= 16
        #fp["#{j}"].tone.gray += 8
        fp["#{j}"].tone.red -= 2; fp["#{j}"].tone.green -= 2; fp["#{j}"].tone.blue -= 2
        fp["#{j}"].zoom_x -= 0.01; fp["#{j}"].zoom_y += 0.02
      else
        fp["#{j}"].opacity += 51
      end
    end
    @targetSprite.tone.red -= 2.4*k
    @targetSprite.tone.green -= 1.2*k
    @targetSprite.tone.blue += 2.4*k
    @targetSprite.ox += shake
    shake = -2 if @targetSprite.ox > @targetSprite.bitmap.width/2 + 2
    shake = 2 if @targetSprite.ox < @targetSprite.bitmap.width/2 - 2
    @targetSprite.still
    @scene.wait(1, true)
  end
  #-----------------------------------------------------------------------------
  #  restore parameters
  @targetSprite.ox = @targetSprite.bitmap.width/2
  pbDisposeSpriteHash(fp)
  #-----------------------------------------------------------------------------
end

#===== FILE: WRAP.rb =====#
#-------------------------------------------------------------------------------
#  WRAP
#-------------------------------------------------------------------------------
EliteBattle.defineCommonAnimation(:WRAP) do
  vector = @scene.getRealVector(@targetIndex, @targetIsPlayer)
  factor = @targetIsPlayer ? 2 : 1.5
  # set up animation
  fp = {}
  #
  fp["bg"] = Sprite.new(@viewport)
  fp["bg"].bitmap = Bitmap.new(@viewport.width,@viewport.height)
  fp["bg"].bitmap.fill_rect(0,0,fp["bg"].bitmap.width,fp["bg"].bitmap.height,Color.black)
  fp["bg"].opacity = 0
  #
  shake = 8
  zoom = -1
  # start animation
  @vector.set(vector)
  @sprites["battlebg"].defocus
  for i in 0...55
    pbSEPlay("Anim/Wrap",80) if i == 20
	if i < 10
      fp["bg"].opacity += 12
    elsif i >= 20
	  @targetSprite.ox += shake
      shake = -8 if @targetSprite.ox > @targetSprite.bitmap.width/2 + 4
      shake = 8 if @targetSprite.ox < @targetSprite.bitmap.width/2 - 4
      @targetSprite.still
    elsif i > 10
       	@targetSprite.zoom_x -= 0.04*factor
	    @targetSprite.zoom_y += 0.04*factor
	    @targetSprite.still
	end
    zoom *= -1 if i%2 == 0
    fp["bg"].update
    fp["bg"].zoom_y += 0.04*zoom
    @scene.wait(1,true)
  end
  @targetSprite.ox = @targetSprite.bitmap.width/2
  10.times do
    @targetSprite.zoom_x -= 0.04*factor
    @targetSprite.zoom_y += 0.04*factor
    @targetSprite.still
    @scene.wait
  end
  @scene.wait(8)
  @vector.reset if !@multiHit
  10.times do
    fp["bg"].opacity -= 25.5
    @targetSprite.still
    @scene.wait(1,true)
  end
  @sprites["battlebg"].focus
  pbDisposeSpriteHash(fp)
end
