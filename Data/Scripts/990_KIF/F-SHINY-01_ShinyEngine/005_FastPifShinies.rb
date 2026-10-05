#===============================================================================
# F-SHINY-01 – speed-up for PIF 6.8.2's Improved Shinies palette step
#
# Bitmap#hue_customcolor (052_InfiniteFusion/ImprovedShinies/Shinies_Bitmap.rb)
# visits every pixel in Ruby with get_pixel/set_pixel and, for each one,
# searches every palette rule for the nearest colour. A 96x96 sprite with
# 70 rules is ~650,000 distance checks; that is the slow part of a Hybrid
# shiny's first display.
# The result for a pixel depends only on its RGB, so this version reads the
# whole image at once (Bitmap#raw_data, available in 6.8.2's mkxp-z), works
# each distinct colour out once, and writes the image back. Output is
# identical (checked offline against the original on real sprites and
# SHINY_COLOR_OFFSETS rules). If raw_data is unavailable it falls back to
# PIF's original method.
#===============================================================================
KIF.guard_base("052_InfiniteFusion/ImprovedShinies/Shinies_Bitmap.rb", 2682676885, "Bitmap#hue_customcolor")

class Bitmap
  alias kif_slow_hue_customcolor hue_customcolor unless method_defined?(:kif_slow_hue_customcolor)

  def hue_customcolor(rules_string)
    return if rules_string.nil? || rules_string == "nil"
    if rules_string.include?("&")
      rules_string.split("&").each do |part|
        part = part.strip
        next if part.empty?
        hue_customcolor(part)
      end
      return
    end
    return kif_slow_hue_customcolor(rules_string) unless respond_to?(:raw_data) && respond_to?(:raw_data=)
    rules = rules_string.split("|").map do |str|
      parts = str.split(".")
      from = parts[0].split.map(&:to_f)
      to = parts[1].split.map(&:to_f)
      from.map! { |v| v <= 10 ? 10.0 : v }   # PIF: avoid division by zero
      to.map! { |v| v <= 10 ? 10.0 : v }     # PIF: avoid multiplication by zero
      [from, to]
    end
    return if rules.empty?
    memo = {}
    px = raw_data.unpack("N*")
    px.map! do |p|
      a = p & 0xFF
      next p if a == 0
      rgb = p >> 8
      out = memo[rgb]
      if out.nil?
        r = ((rgb >> 16) & 0xFF).to_f
        g = ((rgb >> 8) & 0xFF).to_f
        b = (rgb & 0xFF).to_f
        r = 10.0 if r <= 10
        g = 10.0 if g <= 10
        b = 10.0 if b <= 10
        best = nil
        best_d = Float::INFINITY
        rules.each do |rule|
          f = rule[0]
          d = (r - f[0])**2 + (g - f[1])**2 + (b - f[2])**2
          if d < best_d
            best_d = d
            best = rule
          end
        end
        f, t = best
        nr = (t[0] * (r / f[0])).clamp(0, 255).to_i
        ng = (t[1] * (g / f[1])).clamp(0, 255).to_i
        nb = (t[2] * (b / f[2])).clamp(0, 255).to_i
        out = memo[rgb] = (nr << 16) | (ng << 8) | nb
      end
      (out << 8) | a
    end
    self.raw_data = px.pack("N*")
  rescue
    kif_slow_hue_customcolor(rules_string)
  end
end
