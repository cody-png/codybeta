#===============================================================================
#  EBDX Math Utilities
#===============================================================================
#  Helper functions for camera calculations, animations, and vector math.
#===============================================================================

module EBDXMath
  #=============================================================================
  #  Easing Functions
  #=============================================================================

  # Linear interpolation
  def self.lerp(start_val, end_val, t)
    start_val + (end_val - start_val) * t.clamp(0.0, 1.0)
  end

  # Ease in (slow start)
  def self.ease_in(t, power = 2)
    t.clamp(0.0, 1.0) ** power
  end

  # Ease out (slow end)
  def self.ease_out(t, power = 2)
    1.0 - ((1.0 - t.clamp(0.0, 1.0)) ** power)
  end

  # Ease in-out (slow start and end)
  def self.ease_in_out(t, power = 2)
    t = t.clamp(0.0, 1.0)
    if t < 0.5
      (2 ** (power - 1)) * (t ** power)
    else
      1.0 - (((-2 * t + 2) ** power) / 2.0)
    end
  end

  # Bounce ease out
  def self.bounce_out(t)
    t = t.clamp(0.0, 1.0)
    n1 = 7.5625
    d1 = 2.75

    if t < 1.0 / d1
      n1 * t * t
    elsif t < 2.0 / d1
      t -= 1.5 / d1
      n1 * t * t + 0.75
    elsif t < 2.5 / d1
      t -= 2.25 / d1
      n1 * t * t + 0.9375
    else
      t -= 2.625 / d1
      n1 * t * t + 0.984375
    end
  end

  # Elastic ease out
  def self.elastic_out(t)
    t = t.clamp(0.0, 1.0)
    return 0.0 if t == 0.0
    return 1.0 if t == 1.0

    p = 0.3
    s = p / 4.0
    (2.0 ** (-10.0 * t)) * Math.sin((t - s) * (2.0 * Math::PI) / p) + 1.0
  end

  #=============================================================================
  #  Vector Operations
  #=============================================================================

  # Distance between two points
  def self.distance(x1, y1, x2, y2)
    Math.sqrt((x2 - x1) ** 2 + (y2 - y1) ** 2)
  end

  # Angle between two points (in degrees)
  def self.angle(x1, y1, x2, y2)
    Math.atan2(y2 - y1, x2 - x1) * 180.0 / Math::PI
  end

  # Rotate point around origin
  def self.rotate_point(x, y, angle_degrees, ox = 0, oy = 0)
    angle_rad = angle_degrees * Math::PI / 180.0
    cos_a = Math.cos(angle_rad)
    sin_a = Math.sin(angle_rad)

    # Translate to origin
    tx = x - ox
    ty = y - oy

    # Rotate
    rx = tx * cos_a - ty * sin_a
    ry = tx * sin_a + ty * cos_a

    # Translate back
    [rx + ox, ry + oy]
  end

  #=============================================================================
  #  Camera/Zoom Calculations
  #=============================================================================

  # Calculate sprite position based on camera vector
  def self.apply_camera(sprite_x, sprite_y, camera_x, camera_y, zoom = 1.0)
    # Apply camera offset and zoom
    new_x = (sprite_x - camera_x) * zoom + (Graphics.width / 2)
    new_y = (sprite_y - camera_y) * zoom + (Graphics.height / 2)
    [new_x, new_y]
  end

  # Calculate zoom factor for depth effect
  def self.depth_zoom(base_zoom, y_position, horizon_y = 0)
    # Objects closer to horizon appear smaller
    depth_factor = 1.0 - ((y_position - horizon_y).abs / Graphics.height.to_f * 0.5)
    base_zoom * depth_factor.clamp(0.5, 1.5)
  end

  #=============================================================================
  #  Animation Timing
  #=============================================================================

  # Convert frames to seconds (assumes 60fps)
  def self.frames_to_seconds(frames)
    frames / 60.0
  end

  # Convert seconds to frames
  def self.seconds_to_frames(seconds)
    (seconds * 60).to_i
  end

  # Calculate animation progress (0.0 to 1.0)
  def self.animation_progress(current_frame, total_frames)
    return 1.0 if total_frames <= 0
    (current_frame.to_f / total_frames).clamp(0.0, 1.0)
  end

  #=============================================================================
  #  Color Blending
  #=============================================================================

  # Blend two colors
  def self.blend_colors(color1, color2, t)
    t = t.clamp(0.0, 1.0)
    Color.new(
      lerp(color1.red, color2.red, t).to_i,
      lerp(color1.green, color2.green, t).to_i,
      lerp(color1.blue, color2.blue, t).to_i,
      lerp(color1.alpha, color2.alpha, t).to_i
    )
  end

  # Create flash color with intensity
  def self.flash_color(base_color, intensity)
    Color.new(
      base_color.red,
      base_color.green,
      base_color.blue,
      (base_color.alpha * intensity).to_i.clamp(0, 255)
    )
  end

  #=============================================================================
  #  Shake/Wobble Effects
  #=============================================================================

  # Calculate shake offset
  def self.shake_offset(frame, intensity, decay = 0.9)
    offset = (rand - 0.5) * 2 * intensity * (decay ** frame)
    offset.round
  end

  # Calculate wobble (sinusoidal)
  def self.wobble(frame, amplitude, frequency)
    amplitude * Math.sin(frame * frequency * Math::PI / 180.0)
  end

  # Pulse effect (for selection highlighting)
  def self.pulse(frame, min_val, max_val, speed = 4)
    range = max_val - min_val
    t = (Math.sin(frame * speed * Math::PI / 180.0) + 1.0) / 2.0
    min_val + range * t
  end
end

#===============================================================================
#  Numeric Extensions (for convenience)
#===============================================================================
class Numeric
  def clamp(min, max)
    [[self, min].max, max].min
  end unless method_defined?(:clamp)
end
