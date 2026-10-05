#===============================================================================
# F-SHINY-01 – KIF shiny colour engine: options and pixel transform
# Source: KIF 0.20.7 007_Objects and windows/008_AnimatedBitmap.rb
#   pbGiveFinaleColor (:498-744, "Modified by ChatGPT"), krsapply (:746-771),
#   getChannelGradient (:928-1209)
#
# KIF's "mashup": every shiny goes through one pipeline that combines PIF's
# (Anthony's) Improved Shinies palette with KIF's own colour shifting.
#
#   1. Decide per Pokémon (option "PIF's Improved Shinies", per-save):
#        roll = shinyimprovpif? (0..3, fixed per Pokémon)
#        Hybrid (0): roll 0 -> KIF only; 1..3 -> PIF palette, then KIF on top
#        Split  (1): roll 0 -> KIF only; 1 -> PIF then KIF; 2..3 -> PIF only
#        Vanilla(2): PIF only (KIF engine off)
#        Off    (3): KIF only
#   2. If PIF is used: PIF 6.8.2's own palette (AnimatedBitmap#shiftAllColors).
#      If KIF is used: hue shift by shinyValue (-180..180).
#   3. "Shiny Colors" (per-save): Simple stops here. Normal / Advanced then
#      rebuild every opaque pixel's R, G, B from the shinyR/G/B codes:
#        0 R   1 G   2 B   3 (R+G)/2   4 (R+B)/2   5 (G+B)/2
#        6-11 = 255 - (0-5)
#      Advanced also has 12 grey, 13 inverted grey, 14-19 3:1 blends
#      (Citrine, Violet, Marine, Orange, Pink, Jade), 20-25 their inverses,
#      adds shinyKRS[0..2] to each source channel (clamped), applies the
#      "semi-inverted" step shinyKRS[3..5] first, and "timid black"
#      shinyKRS[6..8] keeps dark pixels (<=16 or <=42) from being inverted.
#
# Differences from KIF (see port notes):
#   * KIF reloaded the sprite file with a hue; 6.8.2 sprites come from
#     spritesheets, so the same steps run on the already-loaded bitmap.
#   * The PIF step uses PIF 6.8.2's newer Improved Shinies code instead of the
#     older copy KIF shipped (same system, current data).
#   * KIF's Simple mode returned before applying the PIF palette, so a
#     PIF-rolled shiny looked normal in Simple mode. Here Simple = PIF
#     palette and/or hue.
#   * The transform is computed once per distinct colour of the sprite
#     (identical result, much faster) and cached (option "Shiny Cache").
#   * New option "Shiny Polish" (default On): keeps outlines/shading readable,
#     see KIF::Shiny::Polish. Off = exact KIF colours.
#===============================================================================
KIF::Options.define(:shinyadvanced, 1, :save)        # 0 Simple, 1 Normal, 2 Advanced
KIF::Options.define(:pifimprovedshinies, 0, :save)   # 0 Hybrid, 1 Split, 2 Vanilla, 3 Off
KIF::Options.define(:shiny_cache, 0, :global)        # 0 Permanent, 1 Per Session, 2 Off
KIF::Options.define(:shiny_icons_kuray, 0, :global)  # 0 Off, 1 On
KIF::Options.define(:kurayshinyanim, 0, :global)     # 0 On, 1 Off, 2 All
KIF::Options.define(:shinypolish, 1, :global)        # 0 Off, 1 On (port addition)

KIF::Options.add(:shinies, :global) {
  EnumOption.new(_INTL("Shiny Animation"), [_INTL("On"), _INTL("Off"), _INTL("All")],
                 proc { $PokemonSystem.kurayshinyanim },
                 proc { |value| $PokemonSystem.kurayshinyanim = value },
                 [_INTL("Display the shiny animations in battles"),
                  _INTL("Don't display the shiny animations in battles"),
                  _INTL("Display shiny animations on non-shiny as well")])
}
KIF::Options.add(:shinies, :global) {
  EnumOption.new(_INTL("Shiny Icons"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.shiny_icons_kuray },
                 proc { |value| $PokemonSystem.shiny_icons_kuray = value },
                 [_INTL("Shiny icons use PIF's shiny icons only"),
                  _INTL("Shiny icons also get KIF colours (reduces performances!)")])
}
KIF::Options.add(:shinies, :global) {
  EnumOption.new(_INTL("Shiny Cache"), [_INTL("Permanent"), _INTL("Per Session"), _INTL("Off")],
                 proc { $PokemonSystem.shiny_cache },
                 proc { |value| $PokemonSystem.shiny_cache = value },
                 [_INTL("Shinies are cached permanently"),
                  _INTL("Shinies are cached per session"),
                  _INTL("Shinies are not cached")])
}
KIF::Options.add(:shinies, :global) {
  EnumOption.new(_INTL("Shiny Polish"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.shinypolish },
                 proc { |value| $PokemonSystem.shinypolish = value },
                 [_INTL("KIF colours exactly as in KIF 0.20.7"),
                  _INTL("Keep outlines and shading readable (fixes most odd-looking shinies)")])
}
KIF::Options.add(:shinies, :save) {
  EnumOption.new(_INTL("Shiny Colors"), [_INTL("Simple"), _INTL("Normal"), _INTL("Advanced")],
                 proc { $PokemonSystem.shinyadvanced },
                 proc { |value| $PokemonSystem.shinyadvanced = value },
                 [_INTL("Shinies only have hue shifting (best performances)"),
                  _INTL("Shinies have hue and channels shifting (mid performances)"),
                  _INTL("Most powerful shiny system (low performances)")])
}
KIF::Options.add(:shinies, :save) {
  EnumOption.new(_INTL("PIF's Improved Shinies"), [_INTL("Hybrid"), _INTL("Split"), _INTL("Vanilla"), _INTL("Off")],
                 proc { $PokemonSystem.pifimprovedshinies },
                 proc { |value| $PokemonSystem.pifimprovedshinies = value },
                 [_INTL("All shinies use KIF system but most are also PIF shinies (best)"),
                  _INTL("Some shinies are PIF shinies, others KIF shinies, some both (split)"),
                  _INTL("KIF's shiny system is disabled"),
                  _INTL("PIF's shiny system is disabled")])
}

module KIF
  module Shiny
    CACHE_DIR = "Cache/KIFShiny"
    MEMORY_LIMIT = 150
    @memory = {}

    #---------------------------------------------------------------------------
    # Decision (KIF pbGiveFinaleColor :515-588)
    #---------------------------------------------------------------------------
    # Returns [use_pif, use_kif] as booleans for a Pokémon.
    def self.decide(pkmn)
      mode = $PokemonSystem ? $PokemonSystem.pifimprovedshinies : 0
      roll = pkmn.shinyimprovpif?
      use_pif = roll >= 1
      force_split = (roll == 1)
      use_kif = true
      case mode
      when 1 then use_kif = !(use_pif && !force_split)
      when 2 then use_pif = true;  use_kif = false
      when 3 then use_pif = false; use_kif = true
      end
      use_pif = true unless use_kif
      return [use_pif, use_kif]
    end

    # True when this Pokémon's sprite must go through the KIF engine (the PIF-
    # only case is left to PIF's own code).
    def self.kif_render?(pkmn)
      return false unless pkmn && !pkmn.egg? && pkmn.shiny?
      return decide(pkmn)[1]
    rescue
      return false
    end

    # Runs the block with the Pokémon temporarily not shiny (so PIF's loaders
    # return the plain sprite/icon); everything is restored afterwards.
    def self.without_shiny(pkmn)
      saved = [pkmn.instance_variable_get(:@shiny), pkmn.instance_variable_get(:@head_shiny),
               pkmn.instance_variable_get(:@body_shiny)]
      pkmn.instance_variable_set(:@shiny, false)
      pkmn.instance_variable_set(:@head_shiny, false)
      pkmn.instance_variable_set(:@body_shiny, false)
      begin
        return yield
      ensure
        pkmn.instance_variable_set(:@shiny, saved[0])
        pkmn.instance_variable_set(:@head_shiny, saved[1])
        pkmn.instance_variable_set(:@body_shiny, saved[2])
      end
    end

    #---------------------------------------------------------------------------
    # Per-pixel maths (KIF krsapply / getChannelGradient)
    #---------------------------------------------------------------------------
    def self.timid_invert(v, timidblack)
      if (timidblack == 1 && v > 16) || (timidblack == 2 && v > 42) || timidblack == 0
        return 255.0 - v
      end
      return v
    end

    def self.krsapply(v, condif, idcol, krs)
      timidblack = krs[idcol + 6]
      case condif
      when 1 then return v >= 127 ? v - 127.0 : v                       # 127->0 / 255->127
      when 2                                                             # 0->127 / 127->255
        ok = (timidblack == 1 && v > 16) || (timidblack == 2 && v > 42) || timidblack == 0
        return (ok && v <= 127) ? v + 127.0 : v
      when 3 then return v >= 127 ? 255.0 - (v - 127.0) : v             # 127->255 / 255->127
      when 4                                                             # 0->127 / 127->0
        ok = (timidblack == 1 && v > 16) || (timidblack == 2 && v > 42) || timidblack == 0
        return (ok && v <= 127) ? 127.0 - v : v
      end
      return v
    end

    def self.gradient_normal(code, r, g, b)
      case code
      when 0  then return r
      when 1  then return g
      when 2  then return b
      when 3  then return (r + g) / 2
      when 4  then return (r + b) / 2
      when 5  then return (g + b) / 2
      when 6  then return 255.0 - r
      when 7  then return 255.0 - g
      when 8  then return 255.0 - b
      when 9  then return 255.0 - (r + g) / 2
      when 10 then return 255.0 - (r + b) / 2
      when 11 then return 255.0 - (g + b) / 2
      end
      return r
    end

    def self.gradient_advanced(code, r, g, b, krs, idcol)
      tb = krs[idcol + 6]
      ri = (r + krs[0].to_f).clamp(0, 255)
      gi = (g + krs[1].to_f).clamp(0, 255)
      bi = (b + krs[2].to_f).clamp(0, 255)
      case code
      when 0  then return ri
      when 1  then return gi
      when 2  then return bi
      when 3  then return (ri + gi) / 2
      when 4  then return (ri + bi) / 2
      when 5  then return (gi + bi) / 2
      when 6  then return timid_invert(ri, tb)
      when 7  then return timid_invert(gi, tb)
      when 8  then return timid_invert(bi, tb)
      when 9  then return timid_invert((ri + gi) / 2, tb)
      when 10 then return timid_invert((ri + bi) / 2, tb)
      when 11 then return timid_invert((gi + bi) / 2, tb)
      when 12 then return (gi + bi + ri) / 3
      when 13 then return timid_invert((gi + bi + ri) / 3, tb)
      when 14 then return (ri + gi * 3) / 4   # Citrine
      when 15 then return (ri + bi * 3) / 4   # Violet
      when 16 then return (gi + bi * 3) / 4   # Marine
      when 17 then return (gi + ri * 3) / 4   # Orange
      when 18 then return (bi + ri * 3) / 4   # Pink
      when 19 then return (bi + gi * 3) / 4   # Jade
      when 20 then return timid_invert((ri + gi * 3) / 4, tb)
      when 21 then return timid_invert((ri + bi * 3) / 4, tb)
      when 22 then return timid_invert((gi + bi * 3) / 4, tb)
      when 23 then return timid_invert((gi + ri * 3) / 4, tb)
      when 24 then return timid_invert((bi + ri * 3) / 4, tb)
      when 25 then return timid_invert((bi + gi * 3) / 4, tb)
      end
      return r
    end

    def self.to_byte(v)
      v = v.to_f
      return 0 if v.nan? || v < 0
      return 255 if v > 255
      return v.to_i
    end

    # New [r, g, b] for one opaque pixel (KIF pbGiveFinaleColor :626-680).
    def self.map_color(r, g, b, codes, krs, adv)
      r = r.to_f; g = g.to_f; b = b.to_f
      if adv == 2
        r = krsapply(r, krs[3], 0, krs) if krs[3] > 0
        g = krsapply(g, krs[4], 1, krs) if krs[4] > 0
        b = krsapply(b, krs[5], 2, krs) if krs[5] > 0
        return [to_byte(gradient_advanced(codes[0], r, g, b, krs, 0)),
                to_byte(gradient_advanced(codes[1], r, g, b, krs, 1)),
                to_byte(gradient_advanced(codes[2], r, g, b, krs, 2))]
      end
      return [to_byte(gradient_normal(codes[0], r, g, b)),
              to_byte(gradient_normal(codes[1], r, g, b)),
              to_byte(gradient_normal(codes[2], r, g, b))]
    end

    # Applies the channel step to every opaque pixel of a Bitmap, in place.
    # Works per distinct colour: the result only depends on a pixel's RGB.
    # With "Shiny Polish" on, the colour table is then cleaned up (see
    # KIF::Shiny::Polish) before being written back.
    def self.channel_shift!(bmp, codes, krs, adv, polish = false)
      fast = bmp.respond_to?(:raw_data) && bmp.respond_to?(:raw_data=)
      px = nil
      if fast
        begin
          px = bmp.raw_data.unpack("N*")   # 0xRRGGBBAA per pixel
        rescue
          fast = false
        end
      end
      unless fast
        px = []
        for y in 0...bmp.height
          for x in 0...bmp.width
            c = bmp.get_pixel(x, y)
            px << ((c.red.to_i << 24) | (c.green.to_i << 16) | (c.blue.to_i << 8) | c.alpha.to_i)
          end
        end
      end
      hist = Hash.new(0)
      px.each { |p| hist[p >> 8] += 1 if (p & 0xFF) != 0 }
      return if hist.empty?
      map = {}
      hist.each_key do |rgb|
        map[rgb] = map_color((rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF, codes, krs, adv)
      end
      map = Polish.polish(hist, map) if polish
      packed = {}
      map.each { |rgb, c| packed[rgb] = (c[0] << 16) | (c[1] << 8) | c[2] }
      if fast
        px.map! { |p| (p & 0xFF) == 0 ? p : ((packed[p >> 8] << 8) | (p & 0xFF)) }
        bmp.raw_data = px.pack("N*")
      else
        i = 0
        for y in 0...bmp.height
          for x in 0...bmp.width
            p = px[i]; i += 1
            next if (p & 0xFF) == 0
            c = map[p >> 8]
            bmp.set_pixel(x, y, Color.new(c[0], c[1], c[2], p & 0xFF))
          end
        end
      end
    end

    #---------------------------------------------------------------------------
    # Shiny Polish (new in the port, option "Shiny Polish", default On)
    #
    # KIF's channel step can flip a sprite's light/dark structure: inverted
    # codes (black and cyan stars) turn outlines and shadows bright, which is
    # why most of them look bad. Pixel art reads by its value (light/dark)
    # structure, so the polish keeps that structure and only lets KIF change
    # the colours. Working in OKLab (a perceptual colour space), over the
    # sprite's colour table weighted by pixel count:
    #   1. If the lightness of the shifted colours correlates with the
    #      original lightness below 0.6 (structure broken/inverted), every
    #      colour keeps KIF's hue and colourfulness but gets back its original
    #      lightness.
    #   2. Otherwise only outlines are protected: originally dark colours
    #      (L < 0.32) may get at most 0.08 lighter.
    #   3. If the result is almost identical to the original (average
    #      difference < 0.04), the hue is turned to its opposite so the shiny
    #      is actually visible.
    # Colours that don't fit in sRGB lose colourfulness, not lightness.
    #---------------------------------------------------------------------------
    module Polish
      CORR_MIN     = 0.6
      OUTLINE_L    = 0.32
      OUTLINE_RISE = 0.08
      DE_MIN       = 0.04

      module_function

      def lin(c)
        c /= 255.0
        return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4
      end

      def unlin(c)
        return c <= 0.0031308 ? 12.92 * c : 1.055 * c**(1 / 2.4) - 0.055
      end

      def to_oklab(r, g, b)
        r = lin(r); g = lin(g); b = lin(b)
        l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)**(1.0 / 3)
        m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)**(1.0 / 3)
        s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)**(1.0 / 3)
        return [0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s]
      end

      def from_oklab_linear(lv, a, b)
        l = (lv + 0.3963377774 * a + 0.2158037573 * b)**3
        m = (lv - 0.1055613458 * a - 0.0638541728 * b)**3
        s = (lv - 0.0894841775 * a - 1.2914855480 * b)**3
        return [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s]
      end

      def to_rgb(lv, a, b)
        k = 1.0
        12.times do
          c = from_oklab_linear(lv, a * k, b * k)
          if c.all? { |v| v >= -0.0005 && v <= 1.0005 }
            return c.map { |v| (unlin(v.clamp(0.0, 1.0)) * 255).round.clamp(0, 255) }
          end
          k *= 0.85
        end
        c = from_oklab_linear(lv, 0, 0)
        return c.map { |v| (unlin(v.clamp(0.0, 1.0)) * 255).round.clamp(0, 255) }
      end

      # hist: {rgb_int => pixel count}; map: {rgb_int => [r, g, b]}
      def polish(hist, map)
        labs_in = {}
        labs_k = {}
        hist.each_key do |p|
          labs_in[p] = to_oklab((p >> 16) & 255, (p >> 8) & 255, p & 255)
          k = map[p]
          labs_k[p] = to_oklab(k[0], k[1], k[2])
        end
        n = hist.values.sum.to_f
        mi = hist.sum { |p, c| labs_in[p][0] * c } / n
        mk = hist.sum { |p, c| labs_k[p][0] * c } / n
        cov = hist.sum { |p, c| (labs_in[p][0] - mi) * (labs_k[p][0] - mk) * c }
        vi = hist.sum { |p, c| (labs_in[p][0] - mi)**2 * c }
        vk = hist.sum { |p, c| (labs_k[p][0] - mk)**2 * c }
        corr = (vi > 0 && vk > 0) ? cov / Math.sqrt(vi * vk) : 1.0
        relight = corr < CORR_MIN
        out = {}
        hist.each_key do |p|
          li = labs_in[p][0]
          l, a, b = labs_k[p]
          if relight
            l = li
          elsif li < OUTLINE_L && l > li + OUTLINE_RISE
            l = li + OUTLINE_RISE
          end
          out[p] = [l, a, b]
        end
        de = hist.sum do |p, c|
          li, ai, bi = labs_in[p]
          lo, ao, bo = out[p]
          Math.sqrt((li - lo)**2 + (ai - ao)**2 + (bi - bo)**2) * c
        end / n
        flip = de < DE_MIN
        res = {}
        out.each { |p, (l, a, b)| res[p] = flip ? to_rgb(l, -a, -b) : to_rgb(l, a, b) }
        return res
      end
    end

    #---------------------------------------------------------------------------
    # Cache
    #---------------------------------------------------------------------------
    def self.cache_mode
      return $PokemonSystem ? $PokemonSystem.shiny_cache : 2
    end

    def self.copy_bitmap(src)
      dst = Bitmap.new(src.width, src.height)
      dst.blt(0, 0, src, Rect.new(0, 0, src.width, src.height))
      return dst
    end

    def self.content_id(bmp)
      if bmp.respond_to?(:raw_data)
        return Zlib.crc32(bmp.raw_data).to_s(16) rescue nil
      end
      return nil
    end

    def self.disk_path(key)
      return "#{CACHE_DIR}/#{Settings::GAME_VERSION_NUMBER}/#{key}.png"
    end

    def self.cache_get(key)
      return nil if key.nil? || cache_mode == 2
      if (bmp = @memory[key]) && !bmp.disposed?
        return copy_bitmap(bmp)
      end
      if cache_mode == 0
        path = disk_path(key)
        if File.exist?(path)
          bmp = Bitmap.new(path) rescue nil
          if bmp
            cache_put_memory(key, bmp)
            return copy_bitmap(bmp)
          end
        end
      end
      return nil
    end

    def self.cache_put_memory(key, bmp)
      if @memory.length >= MEMORY_LIMIT
        old_key, old = @memory.first
        @memory.delete(old_key)
        old.dispose if old && !old.disposed?
      end
      @memory[key] = bmp
    end

    def self.cache_put(key, bmp)
      return if key.nil? || cache_mode == 2
      cache_put_memory(key, copy_bitmap(bmp))
      if cache_mode == 0
        begin
          dir = "#{CACHE_DIR}/#{Settings::GAME_VERSION_NUMBER}"
          [CACHE_DIR, dir].each { |d| Dir.mkdir(d) unless File.directory?(d) }
          bmp.save_to_png(disk_path(key)) unless File.exist?(disk_path(key))
        rescue
          nil
        end
      end
    end

    #---------------------------------------------------------------------------
    # Pipeline
    #---------------------------------------------------------------------------
    # anim: AnimatedBitmap holding the plain (non-shiny) image, already a
    # private copy. kind: :sprite (battler) or :icon.
    # For :icon with PIF palette, the caller passes PIF's shiny icon instead
    # and pif_done = true.
    def self.colorize!(anim, pkmn, kind = :sprite, pif_done = false)
      use_pif, use_kif = decide(pkmn)
      return anim unless use_kif
      adv = $PokemonSystem ? $PokemonSystem.shinyadvanced : 1
      polish = $PokemonSystem ? $PokemonSystem.shinypolish == 1 : false
      hue = pkmn.shinyValue?
      codes = (adv == 0) ? [0, 1, 2] : [pkmn.shinyR?, pkmn.shinyG?, pkmn.shinyB?]
      krs = pkmn.shinyKRS?
      dex = getDexNumberForSpecies(pkmn.species) rescue 0
      base = anim.bitmap
      id = content_id(base)
      key = nil
      if id
        key = [kind, id, base.width, base.height, dex, use_pif ? 1 : 0,
               pkmn.body_shiny ? 1 : 0, pkmn.head_shiny ? 1 : 0, adv, polish ? 1 : 0, hue,
               codes.join("."), krs.join(".")].join("_").gsub("-", "m")
      end
      if (hit = cache_get(key))
        anim.bitmap = hit
        return anim
      end
      if use_pif && !pif_done
        anim.shiftAllColors(dex, pkmn.body_shiny, pkmn.head_shiny)
      end
      anim.bitmap.hue_change(hue) if hue != 0
      channel_shift!(anim.bitmap, codes, krs, adv, polish) if adv != 0
      cache_put(key, anim.bitmap)
      return anim
    end

    # Replaces anim's bitmap by a private copy (spritesheet and RPG::Cache
    # bitmaps are shared, so they must never be recoloured in place).
    def self.privatize(anim)
      anim.bitmap = copy_bitmap(anim.bitmap)
      return anim
    end

    def self.clear_memory_cache
      @memory.each_value { |b| b.dispose if b && !b.disposed? }
      @memory.clear
    end
  end
end
