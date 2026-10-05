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
#===============================================================================
KIF::Options.define(:shinyadvanced, 1, :save)        # 0 Simple, 1 Normal, 2 Advanced
KIF::Options.define(:pifimprovedshinies, 0, :save)   # 0 Hybrid, 1 Split, 2 Vanilla, 3 Off
KIF::Options.define(:shiny_cache, 0, :global)        # 0 Permanent, 1 Per Session, 2 Off
KIF::Options.define(:shiny_icons_kuray, 0, :global)  # 0 Off, 1 On
KIF::Options.define(:kurayshinyanim, 0, :global)     # 0 On, 1 Off, 2 All

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
    def self.channel_shift!(bmp, codes, krs, adv)
      memo = {}
      if bmp.respond_to?(:raw_data) && bmp.respond_to?(:raw_data=)
        begin
          px = bmp.raw_data.unpack("N*")   # 0xRRGGBBAA per pixel
          px.map! do |p|
            next p if (p & 0xFF) == 0
            memo[p] ||= begin
              c = map_color((p >> 24) & 0xFF, (p >> 16) & 0xFF, (p >> 8) & 0xFF, codes, krs, adv)
              (c[0] << 24) | (c[1] << 16) | (c[2] << 8) | (p & 0xFF)
            end
          end
          bmp.raw_data = px.pack("N*")
          return
        rescue
          memo.clear   # fall back to the slow path below
        end
      end
      for x in 0...bmp.width
        for y in 0...bmp.height
          c = bmp.get_pixel(x, y)
          next if c.alpha == 0
          key = [c.red.to_i, c.green.to_i, c.blue.to_i]
          n = (memo[key] ||= map_color(c.red, c.green, c.blue, codes, krs, adv))
          bmp.set_pixel(x, y, Color.new(n[0], n[1], n[2], c.alpha))
        end
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
      hue = pkmn.shinyValue?
      codes = (adv == 0) ? [0, 1, 2] : [pkmn.shinyR?, pkmn.shinyG?, pkmn.shinyB?]
      krs = pkmn.shinyKRS?
      dex = getDexNumberForSpecies(pkmn.species) rescue 0
      base = anim.bitmap
      id = content_id(base)
      key = nil
      if id
        key = [kind, id, base.width, base.height, dex, use_pif ? 1 : 0,
               pkmn.body_shiny ? 1 : 0, pkmn.head_shiny ? 1 : 0, adv, hue,
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
      channel_shift!(anim.bitmap, codes, krs, adv) if adv != 0
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
