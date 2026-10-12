#===============================================================================
#  BitmapEBDX - Animated bitmap wrapper for EBDX sprites
#  Used primarily for UI elements and animated textures
#===============================================================================
class BitmapEBDX
  attr_reader :width, :height, :totalFrames, :animationFrames, :currentIndex
  attr_accessor :constrict, :scale, :frameSkip
  @@disableBitmapAnimation = false

  def initialize(file, scale = 2, skip = 1)
    if file.nil?
      EliteBattle.log.warn("BitmapEBDX filename is nil.") rescue nil
      file = "Graphics/EBDX/Battlers/000"
    end
    @scale = scale
    @constrict = nil
    @width = 0
    @height = 0
    @frame = 0
    @frames = 2
    @frameSkip = skip
    @direction = 1
    @animationFinish = false
    @totalFrames = 0
    @currentIndex = 0
    @changed_hue = false
    @speed = 1
    @bitmapFile = file
    @bitmaps = []
    self.refresh
  end

  def is_bitmap?
    return @bitmapFile.is_a?(BitmapWrapper) || @bitmapFile.is_a?(Bitmap)
  end

  def delta; return Graphics.frame_rate/40.0; end
  def length; return @totalFrames; end
  def disposed?; return @bitmaps.length < 1; end

  def dispose
    for bmp in @bitmaps
      bmp.dispose
    end
    @bitmaps.clear
    @tempBmp.dispose if @tempBmp && !@tempBmp.disposed?
  end

  def copy; return @bitmaps[@currentIndex].clone; end

  def bitmap
    return @bitmapFile if self.is_bitmap? && !@bitmapFile.disposed?
    return nil if self.disposed?
    x, y, w, h = self.box
    @tempBmp.clear
    @tempBmp.blt(x, y, @bitmaps[@currentIndex], Rect.new(x, y, w, h))
    return @tempBmp
  end

  def bitmap=(val)
    return if !val.is_a?(String)
    @bitmapFile = val
    self.refresh
  end

  def each; end
  def alter_bitmap(index); return @strip[index]; end

  def prepare_strip
    @strip = []
    bmp = Bitmap.new(@bitmapFile)
    for i in 0...@totalFrames
      bitmap = Bitmap.new(@width, @height)
      bitmap.stretch_blt(Rect.new(0, 0, @width, @height), bmp, Rect.new((@width/@scale)*i, 0, @width/@scale, @height/@scale))
      @strip.push(bitmap)
    end
  end

  def compile_strip
    self.refresh(@strip)
  end

  def compile_loop(data)
    f_bmp = Bitmap.new(@bitmapFile)
    r = f_bmp.height; w = 0; x = 0
    @width = r*@scale
    @height = r*@scale
    bitmaps = []
    for p in data
      w += p[:range].to_a.length * p[:repeat] * r
    end
    for m in 0...data.length
      range = data[m][:range].to_a
      repeat = data[m][:repeat]
      x += m > 0 ? (data[m-1][:range].to_a.length * data[m-1][:repeat] * r) : 0
      for i in 0...repeat
        for j in 0...range.length
          bitmap = Bitmap.new(@width, @height)
          bitmap.stretch_blt(Rect.new(0, 0, @width, @height), f_bmp, Rect.new(range[j]*r, 0, r, r))
          bitmaps.push(bitmap)
        end
      end
    end
    f_bmp.dispose
    self.refresh(bitmaps)
  end

  def refresh(bitmaps = nil)
    self.dispose
    if bitmaps.nil? && @bitmapFile.is_a?(String)
      begin
        f_bmp = Bitmap.new(@bitmapFile)
      rescue
        f_bmp = Bitmap.new(2, 2)
      end
      @width = f_bmp.height*@scale
      @height = f_bmp.height*@scale
      for i in 0...(f_bmp.width.to_f/f_bmp.height).ceil
        x = i*f_bmp.height
        bitmap = Bitmap.new(@width, @height)
        bitmap.stretch_blt(Rect.new(0, 0, @width, @height), f_bmp, Rect.new(x, 0, f_bmp.height, f_bmp.height))
        @bitmaps.push(bitmap)
      end
      f_bmp.dispose
    else
      @bitmaps = bitmaps
    end
    if !self.is_bitmap? && @bitmaps.length > 0
      @totalFrames = @bitmaps.length
      @animationFrames = @totalFrames*@frames
      @tempBmp = Bitmap.new(@bitmaps[0].width, @bitmaps[0].width)
    end
  end

  def reverse
    if @direction > 0
      @direction = -1
    elsif @direction < 0
      @direction = +1
    end
  end

  def setSpeed(value); @speed = value; end

  def to_frame(frame)
    if frame.is_a?(String)
      frame = (frame == "last") ? @totalFrames - 1 : 0
    end
    frame = @totalFrames - 1 if frame >= @totalFrames
    frame = 0 if frame < 0
    @currentIndex = frame
  end

  def hue_change(value)
    for bmp in @bitmaps
      bmp.hue_change(value)
    end
    @changed_hue = true
  end
  def changedHue?; return @changed_hue; end

  def play
    return if self.finished?
    self.update
  end

  def finished?
    return (@currentIndex >= @totalFrames - 1)
  end

  def box
    x = (@constrict.nil? || @width <= @constrict) ? 0 : ((@width-@constrict)/2.0).ceil
    y = (@constrict.nil? || @width <= @constrict) ? 0 : ((@height-@constrict)/2.0).ceil
    w = (@constrict.nil? || @width <= @constrict) ? @width : @constrict
    h = (@constrict.nil? || @width <= @constrict) ? @height : @constrict
    return x, y, w, h
  end

  def update
    return false if @@disableBitmapAnimation
    return false if self.disposed?
    return false if @speed < 1
    case @speed
    when 2 then @frames = 4
    when 3 then @frames = 5
    else @frames = 2
    end
    @frame += 1
    if @frame >= @frames*@frameSkip*self.delta
      @currentIndex += @direction
      @currentIndex = 0 if @currentIndex >= @totalFrames
      @currentIndex = @totalFrames - 1 if @currentIndex < 0
      @frame = 0
    end
  end

  def deanimate
    @frame = 0
    @currentIndex = 0
  end

  def disable_animation(val = true)
    @@disableBitmapAnimation = val
  end
end
