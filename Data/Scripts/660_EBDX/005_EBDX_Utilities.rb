#===============================================================================
#  Luka's Scripting Utilities - required by EBDX
#  Only includes extensions not already present in KIF
#===============================================================================

#===============================================================================
#  Numeric delta extensions (frame rate independence)
#===============================================================================
class ::Numeric
  unless method_defined?(:delta_add)
    def delta(type = :add, round = true)
      d = Graphics.frame_rate/40.0
      a = round ? (self*d).to_i : (self*d)
      s = round ? (self/d).floor : (self/d)
      return type == :add ? a : s
    end
    def delta_add(round = true)
      return self.delta(:add, round)
    end
    def delta_sub(round = true)
      return self.delta(:sub, round)
    end
  end
end

#===============================================================================
#  Dir.create - creates nested directories
#===============================================================================
class Dir
  def self.create(path)
    path.gsub!("\\", "/")
    dirs = path.split("/"); full = ""
    for dir in dirs
      full += dir + "/"
      self.mkdir(full) if !self.safe?(full) rescue nil
    end
  end
end unless Dir.respond_to?(:create)

#===============================================================================
#  File.safeData?
#===============================================================================
class File
  def self.safeData?(file)
    ret = false
    ret = (load_data(file) ? true : false) rescue false
    return ret
  end
end unless File.respond_to?(:safeData?)

#===============================================================================
#  Array extensions
#===============================================================================
class ::Array
  unless method_defined?(:swap_at)
    def swap_at(index1, index2)
      val1 = self[index1].clone
      val2 = self[index2].clone
      self[index1] = val2
      self[index2] = val1
    end
  end
  unless method_defined?(:to_last)
    def to_last(val)
      self.delete(val) if self.include?(val)
      self.push(val)
    end
  end
  unless method_defined?(:string_include?)
    def string_include?(val)
      return false if !val.is_a?(String)
      ret = false
      for a in self
        ret = true if a.is_a?(String) && val.include?(a)
      end
      return ret
    end
  end
end

#===============================================================================
#  Hash extensions
#===============================================================================
class ::Hash
  unless method_defined?(:try_key?)
    def try_key?(*args)
      for key in args
        return false if !self.keys.include?(key) || !self[key]
      end
      return true
    end
  end
  unless method_defined?(:get_key)
    def get_key(key)
      return self.keys.include?(key) ? self[key] : nil
    end
  end
  unless method_defined?(:deep_merge!)
    def deep_merge!(hash)
      return if !hash.is_a?(Hash)
      for key in hash.keys
        if self[key].is_a?(Hash)
          self[key].deep_merge!(hash[key])
        else
          self[key] = hash[key]
        end
      end
    end
  end
end

#===============================================================================
#  String extensions
#===============================================================================
class ::String
  unless method_defined?(:is_numeric?)
    def is_numeric?
      for c in self.gsub('.', '').gsub('-', '').scan(/./)
        return false unless (0..9).to_a.map { |n| n.to_s }.include?(c)
      end
      return true
    end
  end
end

#===============================================================================
#  Viewport extensions
#===============================================================================
class Viewport
  unless method_defined?(:width)
    def width; return self.rect.width; end
  end
  unless method_defined?(:height)
    def height; return self.rect.height; end
  end
end

#===============================================================================
#  Sprite extensions for EBDX
#===============================================================================
class Sprite
  attr_reader :storedBitmap unless method_defined?(:storedBitmap)
  attr_accessor :direction unless method_defined?(:direction)
  attr_accessor :speed unless method_defined?(:speed)
  attr_accessor :toggle unless method_defined?(:toggle)
  attr_accessor :end_x, :end_y unless method_defined?(:end_x)
  attr_accessor :param, :skew_d unless method_defined?(:param)
  attr_accessor :ex, :ey unless method_defined?(:ex)
  attr_accessor :zx, :zy unless method_defined?(:zx)

  def id?(val); return nil; end unless method_defined?(:id?)

  unless method_defined?(:create_rect)
    def create_rect(width, height, color)
      self.bitmap = Bitmap.new(width, height)
      self.bitmap.fill_rect(0, 0, width, height, color)
    end
  end

  unless method_defined?(:full_rect)
    def full_rect(color)
      self.blank_screen if !self.bitmap
      self.bitmap.fill_rect(0, 0, self.bitmap.width, self.bitmap.height, color)
    end
  end

  unless method_defined?(:default!)
    def default!
      @speed = 1; @toggle = 1; @end_x = 0; @end_y = 0
      @ex = 0; @ey = 0; @zx = 1; @zy = 1; @param = 1; @direction = 1
    end
  end

  unless method_defined?(:center!)
    def center!(snap = false)
      self.ox = self.src_rect.width/2
      self.oy = self.src_rect.height/2
      if snap && self.viewport
        self.x = self.viewport.rect.width/2
        self.y = self.viewport.rect.height/2
      end
    end
  end

  unless method_defined?(:bottom!)
    def bottom!
      self.ox = self.src_rect.width/2
      self.oy = self.src_rect.height
    end
  end

  unless method_defined?(:snap_screen)
    def snap_screen
      bmp = Graphics.snap_to_bitmap
      width = self.viewport ? self.viewport.rect.width : Graphics.width
      height = self.viewport ? self.viewport.rect.height : Graphics.height
      x = self.viewport ? self.viewport.rect.x : 0
      y = self.viewport ? self.viewport.rect.y : 0
      self.bitmap = Bitmap.new(width, height)
      self.bitmap.blt(0, 0, bmp, Rect.new(x, y, width, height)); bmp.dispose
    end
    def screenshot; self.snap_screen; end
  end

  unless method_defined?(:stretch_screen)
    def stretch_screen(file)
      bmp = pbBitmap(file)
      self.bitmap = Bitmap.new(self.viewport.rect.width, self.viewport.rect.height)
      self.bitmap.stretch_blt(self.bitmap.rect, bmp, bmp.rect)
    end
  end

  unless method_defined?(:blur_sprite)
    def blur_sprite(blur_val = 2, opacity = 35)
      bitmap = self.bitmap
      self.bitmap = Bitmap.new(bitmap.width, bitmap.height)
      self.bitmap.blt(0, 0, bitmap, Rect.new(0, 0, bitmap.width, bitmap.height))
      x = 0; y = 0
      for i in 1...(8 * blur_val)
        dir = i % 8
        x += (1 + (i / 8))*([0,6,7].include?(dir) ? -1 : 1)*([1,5].include?(dir) ? 0 : 1)
        y += (1 + (i / 8))*([1,4,5,6].include?(dir) ? -1 : 1)*([3,7].include?(dir) ? 0 : 1)
        self.bitmap.blt(x-blur_val, y+(blur_val*2), bitmap, Rect.new(0, 0, bitmap.width, bitmap.height), opacity)
      end
    end
  end

  unless method_defined?(:memorize_bitmap)
    def memorize_bitmap(bitmap = nil)
      @storedBitmap = bitmap if !bitmap.nil?
      @storedBitmap = self.bitmap.clone if bitmap.nil?
    end
    def restore_bitmap
      self.bitmap = @storedBitmap.clone
    end
  end

  unless method_defined?(:blank_screen)
    def blank_screen
      self.bitmap = Bitmap.new(self.viewport.rect.width, self.viewport.rect.height)
    end
  end

  unless method_defined?(:x_mid)
    def x_mid
      return self.bitmap ? self.bitmap.width / 2 : 0
    end
  end

  unless method_defined?(:skew)
    # Skew effect (EBDX uses this for wind effects on grass/trees)
    # This simulates wind by applying a small rotation based on the wind angle
    # The wind angle oscillates around 90 degrees (80-100 range typically)
    # angle 90 = neutral, <90 = lean left, >90 = lean right
    def skew(angle)
      @skew_d = angle
      # Convert wind angle to a small rotation
      # Wind oscillates around 90, so (angle - 90) gives us -10 to +10 typically
      rotation = (angle - 90) * 0.3  # Scale down for subtle effect
      self.angle = rotation
    end
  end

  # Unified zoom setter (sets both zoom_x and zoom_y)
  unless method_defined?(:zoom=)
    def zoom=(val)
      self.zoom_x = val
      self.zoom_y = val
    end
  end

  # Colorize sprite - applies a color tint to the sprite
  # This is a simplified version that uses tone instead of raw pixel manipulation
  unless method_defined?(:colorize)
    def colorize(color, amt = 255)
      return false if !self.bitmap
      # Use color property for tinting (simpler than raw pixel manipulation)
      # The color property blends the sprite with the specified color
      alpha = [amt.to_i, 255].min

      if color.is_a?(Color)
        r, g, b = color.red, color.green, color.blue

        # At night/evening, darken the color to simulate night effect
        # This is more effective than using tone (which color overrides)
        if defined?(PBDayNight)
          isNight = PBDayNight.isNight? rescue false
          isEvening = (PBDayNight.isEvening? || PBDayNight.isMorning?) rescue false
          if isNight
            # Darken significantly and add blue tint for night
            r = (r * 0.35).to_i
            g = (g * 0.40).to_i
            b = (b * 0.55).to_i  # Less reduction = more blue = night feel
          elsif isEvening
            # Slight warm darkening for evening/morning
            r = (r * 0.70).to_i
            g = (g * 0.65).to_i
            b = (b * 0.60).to_i
          end
        end

        self.color = Color.new(r, g, b, alpha)
      elsif color.is_a?(Tone)
        # Convert tone to color-like tinting via tone property
        self.tone = Tone.new(color.red, color.green, color.blue, color.gray)
      end
      return true
    end
  end
end

#===============================================================================
#  Tone extensions
#===============================================================================
class Tone
  unless method_defined?(:all)
    def all
      return (self.red + self.green + self.blue)/3
    end
    def all=(val)
      self.red = val
      self.green = val
      self.blue = val
    end
  end
end

#===============================================================================
#  Bitmap extensions for EBDX
#===============================================================================
class Bitmap
  attr_accessor :storedPath unless method_defined?(:storedPath)

  unless method_defined?(:bmp_circle)
    def bmp_circle(color = Color.new(255,255,255), r = (self.width/2), tx = (self.width/2), ty = (self.height/2), hollow = false)
      for x in 0...self.width
        f = (r**2 - (x - tx)**2)
        next if f < 0
        y1 = -Math.sqrt(f).to_i + ty
        y2 =  Math.sqrt(f).to_i + ty
        if hollow
          self.set_pixel(x, y1, color)
          self.set_pixel(x, y2, color)
        else
          self.fill_rect(x, y1, 1, y2 - y1, color)
        end
      end
    end
    def draw_circle(*args); self.bmp_circle(*args); end
  end

  unless respond_to?(:smartWindow)
    def self.smartWindow(slice, rect, path = "img/window001.png")
      begin
        window = Bitmap.new(path)
      rescue
        window = Bitmap.new(32, 32)
      end
      output = Bitmap.new(rect.width, rect.height)
      x1 = [0, slice.x, slice.x + slice.width]
      y1 = [0, slice.y, slice.y + slice.height]
      w1 = [slice.x, slice.width, window.width - slice.x - slice.width]
      h1 = [slice.y, slice.height, window.height - slice.y - slice.height]
      x2 = [0, x1[1], rect.width - w1[2]]
      y2 = [0, y1[1], rect.height - h1[2]]
      w2 = [x1[1], rect.width - x1[1] - w1[2], w1[2]]
      h2 = [y1[1], rect.height - y1[1] - h1[2], h1[2]]
      slice_matrix = []; rect_matrix = []
      for y in 0...3
        for x in 0...3
          slice_matrix.push(Rect.new(x1[x], y1[y], w1[x], h1[y]))
          rect_matrix.push(Rect.new(x2[x], y2[y], w2[x], h2[y]))
        end
      end
      for i in 0...9
        output.stretch_blt(rect_matrix[i], window, slice_matrix[i])
      end
      window.dispose
      return output
    end
  end
end

#===============================================================================
#  Color extensions
#===============================================================================
class Color
  def self.red; return Color.new(255, 0, 0); end unless respond_to?(:red)
  def self.green; return Color.new(0, 255, 0); end unless respond_to?(:green)
  def self.blue; return Color.new(0, 0, 255); end unless respond_to?(:blue)
  def self.black; return Color.new(0, 0, 0); end unless respond_to?(:black)
  def self.white; return Color.new(255, 255, 255); end unless respond_to?(:white)
  def self.yellow; return Color.new(255, 255, 0); end unless respond_to?(:yellow)
  def self.orange; return Color.new(255, 155, 0); end unless respond_to?(:orange)
  def self.purple; return Color.new(155, 0, 255); end unless respond_to?(:purple)
  def self.brown; return Color.new(112, 72, 32); end unless respond_to?(:brown)
  def self.teal; return Color.new(0, 255, 255); end unless respond_to?(:teal)
  def self.magenta; return Color.new(255, 0, 255); end unless respond_to?(:magenta)

  unless method_defined?(:darken)
    def darken(amt = 0.2)
      red = self.red - self.red*amt
      green = self.green - self.green*amt
      blue = self.blue - self.blue*amt
      return Color.new(red, green, blue)
    end
  end
end

#===============================================================================
#  ScrollingSprite - scrolling background sprite
#===============================================================================
class ScrollingSprite < Sprite
  attr_accessor :speed, :direction, :vertical, :pulse, :min_o, :max_o

  def setBitmap(val, vertical = false, pulse = false)
    @vertical = vertical
    @pulse = pulse
    @direction = 1 if @direction.nil?
    @gopac = 1
    @frame = 0
    @speed = 32 if @speed.nil?
    @min_o = 0
    @max_o = 255
    val = pbBitmap(val) if val.is_a?(String)
    if @vertical
      bmp = Bitmap.new(val.width, val.height*2)
      2.times { |i| bmp.blt(0, val.height*i, val, val.rect) }
      self.bitmap = bmp
      y = @direction > 0 ? 0 : val.height
      self.src_rect.set(0, y, val.width, val.height)
    else
      bmp = Bitmap.new(val.width*2, val.height)
      2.times { |i| bmp.blt(val.width*i, 0, val, val.rect) }
      self.bitmap = bmp
      x = @direction > 0 ? 0 : val.width
      self.src_rect.set(x, 0, val.width, val.height)
    end
  end

  def update
    s = (1/@speed).to_i rescue 0
    @frame += 1
    return if s > 0 && @frame < s
    if @vertical
      self.src_rect.y += (@speed < 1 ? 1 : @speed)*@direction
      self.src_rect.y = 0 if @direction > 0 && self.src_rect.y >= self.src_rect.height
      self.src_rect.y = self.src_rect.height if @direction < 0 && self.src_rect.y <= 0
    else
      self.src_rect.x += (@speed < 1 ? 1 : @speed)*@direction
      self.src_rect.x = 0 if @direction > 0 && self.src_rect.x >= self.src_rect.width
      self.src_rect.x = self.src_rect.width if @direction < 0 && self.src_rect.x <= 0
    end
    if @pulse
      self.opacity -= @gopac*(@speed < 1 ? 1 : @speed)
      @gopac *= -1 if self.opacity == @max_o || self.opacity == @min_o
    end
    @frame = 0
  end
end

#===============================================================================
#  RainbowSprite - hue-cycling sprite
#===============================================================================
class RainbowSprite < Sprite
  attr_accessor :speed
  def setBitmap(val, speed = 1)
    @val = val
    @val = pbBitmap(val) if val.is_a?(String)
    @speed = speed
    self.bitmap = Bitmap.new(@val.width, @val.height)
    self.bitmap.blt(0, 0, @val, Rect.new(0, 0, @val.width, @val.height))
    @current_hue = 0
  end
  def update
    @current_hue += @speed
    @current_hue = 0 if @current_hue >= 360
    self.bitmap.clear
    self.bitmap.blt(0, 0, @val, Rect.new(0, 0, @val.width, @val.height))
    self.bitmap.hue_change(@current_hue)
  end
end

#===============================================================================
#  SpriteSheet - animated spritesheet
#===============================================================================
class SpriteSheet < Sprite
  attr_accessor :speed
  def initialize(viewport, frames = 1)
    @frames = frames
    @speed = 1
    @curFrame = 0
    @vertical = false
    super(viewport)
  end
  def setBitmap(file, vertical = false)
    self.bitmap = file.is_a?(Bitmap) ? file : pbBitmap(file)
    @vertical = vertical
    if @vertical
      self.src_rect.height /= @frames
    else
      self.src_rect.width /= @frames
    end
  end
  def update
    return if !self.bitmap
    if @curFrame >= @speed
      if @vertical
        self.src_rect.y += self.src_rect.height
        self.src_rect.y = 0 if self.src_rect.y >= self.bitmap.height
      else
        self.src_rect.x += self.src_rect.width
        self.src_rect.x = 0 if self.src_rect.x >= self.bitmap.width
      end
      @curFrame = 0
    end
    @curFrame += 1
  end
end

#===============================================================================
#  SelectorSprite - selection cursor spritesheet
#===============================================================================
class SelectorSprite < SpriteSheet
  attr_accessor :filename, :anchor
  def render(rect, file = nil, vertical = false)
    @filename = file if @filename.nil? && !file.nil?
    file = @filename if file.nil? && !@filename.nil?
    @curFrame = 0
    self.src_rect.x = 0
    self.src_rect.y = 0
    self.setBitmap(pbSelBitmap(@filename, rect), vertical)
    self.center!
    self.speed = 4
  end
  def target(sprite)
    return if !sprite || !sprite.is_a?(Sprite)
    self.render(Rect.new(0, 0, sprite.src_rect.width, sprite.src_rect.height))
    self.anchor = sprite
  end
  def update
    super
    if self.anchor
      self.x = self.anchor.x - self.anchor.ox + self.anchor.src_rect.width/2
      self.y = self.anchor.y - self.anchor.oy + self.anchor.src_rect.height/2
      self.opacity = self.anchor.opacity
      self.visible = self.anchor.visible
    end
  end
end

#===============================================================================
#  CallbackWrapper - block execution with params
#===============================================================================
class CallbackWrapper
  def initialize
    @params = {}
  end
  def execute(block, *args)
    @params.each do |key, value|
      args.instance_variable_set("@#{key.to_s}", value)
    end
    args.instance_eval(&block)
  end
  def set(params)
    @params = params
  end
end

#===============================================================================
#  ErrorLogger (only define if not already present)
#===============================================================================
unless defined?(ErrorLogger)
  class ErrorLogger
    def initialize(file = nil)
      file = "systemout.txt" if file.nil?
      @file = file
    end
    def log_msg(msg, type = "INFO", file = nil)
      file = @file if file.nil?
      echoln "#{type.upcase}: #{msg}"
    end
    def log(msg, file = nil); log_msg(msg, "INFO", file); end
    def info(msg, file = nil); log_msg(msg, "INFO", file); end
    def error(msg, file = nil); log_msg(msg, "ERROR", file); raise msg; end
    def warn(msg, file = nil); log_msg(msg, "WARN", file); end
    def debug(msg, file = nil); return if !$DEBUG; log_msg(msg, "DEBUG", file); end
  end
end

#===============================================================================
#  Env module (only define if not already present)
#===============================================================================
unless defined?(Env)
  module Env
    @logger = ErrorLogger.new
    def self.log; return @logger; end
    def self.directory; return Dir.pwd.gsub("/","\\"); end
    def self.interpret(filename)
      return {} if !safeExists?(filename)
      contents = File.open(filename, 'rb') {|f| f.read.gsub("\t", "  ") }
      data = {}
      return data if !contents || contents.empty?
      indexes = contents.scan(/(?<=\[)(.*?)(?=\])/i); indexes.push(indexes[-1])
      entries = []
      for j in 0...indexes.length
        i = indexes[j]
        if j == indexes.length - 1
          m = contents.split("[#{i[0]}]")[1]
          next if m.nil?
        else
          m = contents.split("[#{i[0]}]")[0]
          next if m.nil?
          contents.gsub!(m, "")
        end
        m.gsub!("[#{i[0]}]\r\n", "")
        entries.push(m.split("\r\n"))
      end
      entries.delete_at(0)
      for i in 0...entries.length
        d = {}; section = "__pk__"
        for e in entries[i]
          d[section] = {} if !d.keys.include?(section)
          e = e.split("#")[0]
          next if e.nil? || e == ""
          a = e.split("=")
          a[0] = a[0] ? a[0].strip : ""
          a[1] = a[1] ? a[1].strip : ""
          next section = a[0] if a[1].nil? || a[1] == "" || a[1].empty?
          a[1] = a[1].split(",")
          for q in 0...a[1].length
            begin
              if a[1][q].is_numeric? && a[1][q].include?('.')
                a[1][q] = a[1][q].to_f
              elsif a[1][q].is_numeric?
                a[1][q] = a[1][q].to_i
              elsif a[1][q].strip.downcase == "true" || a[1][q].strip.downcase == "false"
                a[1][q] = a[1][q].strip.downcase == "true"
              end
            rescue; end
          end
          d[section][a[0]] = a[1]
        end
        d.delete("__pk__") if d["__pk__"] && d["__pk__"].empty?
        data[indexes[i][0]] = d
      end
      return data
    end
  end
end

#===============================================================================
#  Safe bitmap loading
#===============================================================================
unless defined?(pbBitmap)
  def pbBitmap(name)
    begin
      dir = name.split("/")[0...-1].join("/") + "/"
      file = name.split("/")[-1]
      bmp = RPG::Cache.load_bitmap(dir, file)
      bmp.storedPath = name if bmp.respond_to?(:storedPath=)
    rescue
      bmp = Bitmap.new(2, 2)
    end
    return bmp
  end
end

#===============================================================================
#  Selection bitmap renderer
#===============================================================================
unless defined?(pbSelBitmap)
  def pbSelBitmap(name, rect)
    bmp = pbBitmap(name)
    qw = bmp.width/2
    qh = bmp.height/2
    max_w = rect.width + qw*2 - 8
    max_h = rect.height + qh*2 - 8
    full = Bitmap.new(max_w*4, max_h)
    for i in 0...4
      for j in 0...4
        m = (i < 3) ? i : (i-2)
        x = (j%2 == 0 ? 2 : -2)*m + max_w*i + (j%2 == 0 ? 0 : max_w-qw)
        y = (j/2 == 0 ? 2 : -2)*m + (j/2 == 0 ? 0 : max_h-qh)
        full.blt(x, y, bmp, Rect.new(qw*(j%2), qh*(j/2), qw, qh))
      end
    end
    return full
  end
end

#===============================================================================
#  Legacy utilities
#===============================================================================
unless defined?(isConst?)
  def isConst?(val, mod, constant)
    begin
      return false if !mod.const_defined?(constant.to_sym)
    rescue
      return false
    end
    return (val == mod.const_get(constant.to_sym))
  end
end
unless defined?(hasConst?)
  def hasConst?(mod, constant)
    return false if !mod || !constant || constant == ""
    return mod.const_defined?(constant.to_sym) rescue false
  end
end
unless defined?(getConst)
  def getConst(mod, constant)
    return nil if !mod || !constant || constant == ""
    return mod.const_get(constant.to_sym) rescue nil
  end
end

#===============================================================================
#  Mathematical utilities
#===============================================================================
def getPolygonPoints(n, rx = 50, ry = 50, a = 0, tx = Graphics.width/2, ty = Graphics.height/2)
  points = []
  ang = 360/n
  n.times do
    b = a*(Math::PI/180)
    r = rx*Math.cos(b).abs + ry*Math.sin(b).abs
    x = tx + r*Math.cos(b)
    y = ty - r*Math.sin(b)
    points.push([x, y])
    a += ang
  end
  return points
end

def randCircleCord(r, x = nil)
  x = rand(r*2) if x.nil?
  y1 = -Math.sqrt(r**2 - (x - r)**2)
  y2 =  Math.sqrt(r**2 - (x - r)**2)
  return x, (rand(2)==0 ? y1.to_i : y2.to_i) + r
end

#===============================================================================
#  SpriteEBDX - Animated sprite class for EBDX UI elements
#===============================================================================
class SpriteEBDX < Sprite
  attr_accessor :animatedBitmap

  def setBitmap(file, scale = EliteBattle::FRONT_SPRITE_SCALE, speed = 2)
    @animatedBitmap = BitmapEBDX.new(file, scale, speed)
    self.bitmap = @animatedBitmap.bitmap.clone rescue nil
  end

  def setSpeciesBitmap(species, female = false, form = 0, shiny = false, shadow = false, back = false, egg = false)
    if species.is_a?(Numeric) && species > 0
      @animatedBitmap = pbLoadSpeciesBitmap(species, female, form, shiny, shadow, back, egg) rescue nil
    end
    if @animatedBitmap.nil?
      @animatedBitmap = BitmapEBDX.new("Graphics/EBDX/Battlers/000")
    end
    self.bitmap = @animatedBitmap.bitmap.clone rescue nil
  end

  def play
    return unless @animatedBitmap
    @animatedBitmap.play
    self.bitmap = @animatedBitmap.bitmap.clone rescue nil
  end

  def speed=(val)
    return if !self.animatedBitmap
    self.animatedBitmap.setSpeed(val)
  end

  def finished?; return @animatedBitmap ? @animatedBitmap.finished? : true; end
  def animatedBitmap; return @animatedBitmap; end

  alias update_wrapper_ebdx update unless self.method_defined?(:update_wrapper_ebdx)
  def update
    update_wrapper_ebdx
    return if @animatedBitmap.nil?
    @animatedBitmap.update
    self.bitmap = @animatedBitmap.bitmap rescue nil
  end
end

#===============================================================================
#  TrailingSprite — leaves fading ghost copies behind a moving projectile.
#  Port of the original Luka's Scripting Utilities class; adapted for KIF
#  (uses center! instead of center, which matches 005_EBDX_Utilities.rb).
#===============================================================================
class TrailingSprite
  attr_accessor :x, :y, :z
  attr_accessor :color
  attr_accessor :keyFrame
  attr_accessor :zoom_x, :zoom_y
  attr_accessor :opacity

  def initialize(viewport, bmp)
    @viewport = viewport
    @bmp      = bmp
    @sprites  = {}
    @x = 0; @y = 0; @z = 0; @i = 0
    @frame    = 128
    @keyFrame = 0
    @color    = Color.new(0, 0, 0, 0)
    @zoom_x   = 1; @zoom_y = 1
    @opacity  = 255
  end

  def update
    @frame += 1
    if @frame > @keyFrame.delta_add(false)
      spr = Sprite.new(@viewport)
      spr.bitmap  = @bmp
      spr.center!
      spr.x       = @x
      spr.y       = @y
      spr.z       = @z
      spr.zoom_x  = @zoom_x
      spr.zoom_y  = @zoom_y
      spr.opacity = @opacity
      @sprites[@i.to_s] = spr
      @i    += 1
      @frame = 0
    end
    @sprites.each_value do |spr|
      next if spr.disposed?
      if spr.opacity > @keyFrame.delta_add(false)
        spr.opacity -= 24.delta_sub(false)
        spr.zoom_x  -= 0.035.delta_sub(false)
        spr.zoom_y  -= 0.035.delta_sub(false)
        spr.color    = @color
      end
    end
  end

  def visible=(val)
    @sprites.each_value { |spr| spr.visible = val rescue nil }
  end

  def dispose
    @sprites.each_value { |spr| spr.dispose rescue nil }
    @sprites.clear
  end

  def disposed?
    @sprites.empty?
  end
end
