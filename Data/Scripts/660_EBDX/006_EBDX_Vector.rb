#===============================================================================
#  Vector class for EBDX camera/scene positioning
#===============================================================================
class Vector
  attr_reader :x, :y
  attr_reader :angle, :scale
  attr_reader :x2, :y2
  attr_accessor :zoom1, :zoom2
  attr_accessor :inc, :set, :battle

  def initialize(x = 0, y = 0, angle = 0, scale = 1, zoom1 = 1, zoom2 = 1)
    @battle = false
    @x = x.to_f
    @y = y.to_f
    @angle = angle.to_f
    @scale = scale.to_f
    @zoom1 = zoom1.to_f
    @zoom2 = zoom2.to_f
    @inc = 0.2
    @set = [@x, @y, @scale, @angle, @zoom1, @zoom2]
    @locked = false
    @force = false
    @constant = 1
    self.calculate
  end

  def calculate
    angle = @angle*(Math::PI/180)
    width = Math.cos(angle)*@scale
    height = Math.sin(angle)*@scale
    @x2 = @x + width
    @y2 = @y - height
  end

  def spoof(*args)
    if args[0].is_a?(Array)
      x, y, angle, scale, zoom1, zoom2 = *args[0]
    else
      x, y, angle, scale, zoom1, zoom2 = *args
    end
    angle = angle*(Math::PI/180)
    width = Math.cos(angle)*scale
    height = Math.sin(angle)*scale
    x2 = x + width
    y2 = y - height
    return x2, y2
  end

  def angle=(val)
    @angle = val
    self.calculate
  end

  def scale=(val)
    @scale = val
    self.calculate
  end

  def x=(val)
    @x = val
    @set[0] = val
    self.calculate
  end

  def y=(val)
    @y = val
    @set[1] = val
    self.calculate
  end

  def force
    @force = true
  end

  def reset
    @inc = 0.2
    self.set(EliteBattle.get_vector(:MAIN, @battle))
  end

  def set(*args)
    return if EliteBattle::DISABLE_SCENE_MOTION && !@force
    @force = false
    if args[0].is_a?(Array)
      @set = args[0]
    else
      @set = args
    end
    @constant = rand(4) + 1
  end

  def setXY(x, y)
    @set[0] = x
    @set[1] = y
  end

  def locked?
    return @locked
  end

  def lock
    @locked = !@locked
  end

  def update
    @x += ((@set[0] - @x)*@inc)/self.delta
    @y += ((@set[1] - @y)*@inc)/self.delta
    @angle += ((@set[2] - @angle)*@inc)/self.delta
    @scale += ((@set[3] - @scale)*@inc)/self.delta
    @zoom1 += ((@set[4] - @zoom1)*@inc)/self.delta
    @zoom2 += ((@set[5] - @zoom2)*@inc)/self.delta
    self.calculate
  end

  def get
    return [@x, @y, @angle, @scale, @zoom1, @zoom2]
  end

  def finished?
    return ((@set[0] - @x)*@inc).abs <= 0.00001*@constant
  end

  def delta; return Graphics.frame_rate/40.0; end
end

#===============================================================================
#  Curve calculation utility
#===============================================================================
def calculateCurve(x1, y1, x2, y2, x3, y3, frames = 10)
  output = []
  curve = [x1, y1, x2, y2, x3, y3, x3, y3]
  step = 1.0/frames
  t = 0.0
  frames.times do
    point = getCubicPoint2(curve, t)
    output.push([point[0], point[1]])
    t += step
  end
  return output
end

def singleDecInt?(number)
  number *= 10
  return (number%10 == 0)
end
