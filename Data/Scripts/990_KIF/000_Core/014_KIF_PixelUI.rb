#===============================================================================
# KIF pixel UI (2026-10-16): crisp text and simple shapes for KIF's own
# screens (Battle Info; the new KIF Settings later).
# * Text uses KIF::PixelFont (013_KIF_PixelFont.rb): each glyph is built once
#   per colour as a tiny bitmap and copied with blt, so letters are never
#   smoothed, squeezed or broken the way the engine's draw_text draws Power
#   Green at in-between sizes.
# * Shapes are made of fill_rect strips. fill_rect replaces pixels (no
#   blending), so every colour here is solid.
#===============================================================================
module KIF
  module PixelFont
    @cache = {}

    # The fonts KIF screens use (only these sizes are in the data)
    TITLE = [:system, 26]
    ROW   = [:narrow, 26]
    TEXT  = [:small, 22]
    TINY  = [:system, 13]

    module_function

    def data(font)
      return FONTS[font] || FONTS[ROW]
    end

    # game data strings can come in as raw bytes; read them as UTF-8
    def utf8(str)
      s = str.to_s
      return s if s.encoding == Encoding::UTF_8 && s.valid_encoding?
      s = s.dup.force_encoding(Encoding::UTF_8)
      return s.valid_encoding? ? s : s.scrub("?")
    end

    def glyph(f, ch)
      return f[:glyphs][ch.ord] || f[:glyphs][63]   # unknown: "?"
    end

    def width(font, str)
      f = data(font)
      return utf8(str).each_char.sum { |c| (glyph(f, c) || [0])[0] }
    end

    def height(font)
      return data(font)[:height]
    end

    def glyph_bitmap(font, code, g, color)
      key = [font, code, color.red.to_i, color.green.to_i, color.blue.to_i, color.alpha.to_i]
      bmp = @cache[key]
      return bmp if bmp && !bmp.disposed?
      w = g[3]
      h = g[4]
      bytes = g[5].unpack1("m").bytes
      bmp = Bitmap.new(w, h)
      h.times do |yy|
        run = nil
        w.times do |xx|
          i = yy * w + xx
          if (bytes[i >> 3] >> (7 - (i & 7))) & 1 == 1
            run ||= xx
          elsif run
            bmp.fill_rect(run, yy, xx - run, 1, color)
            run = nil
          end
        end
        bmp.fill_rect(run, yy, w - run, 1, color) if run
      end
      @cache[key] = bmp
      return bmp
    end

    # top-left of the text at (x, y)
    def draw(bitmap, x, y, str, font, color)
      f = data(font)
      utf8(str).each_char do |c|
        g = glyph(f, c)
        next unless g
        if g[3] > 0
          gb = glyph_bitmap(font, c.ord, g, color)
          bitmap.blt(x + g[1], y + g[2], gb, gb.rect)
        end
        x += g[0]
      end
    end

    # shortened with "..." to fit max_w
    def fit(font, str, max_w)
      s = utf8(str)
      return s if width(font, s) <= max_w
      s = s[0...-1] while s.length > 1 && width(font, s + "...") > max_w
      return s + "..."
    end
  end

  module PixelUI
    BG      = Color.new(28, 36, 48)
    PANEL   = Color.new(46, 55, 68)
    PANEL2  = Color.new(38, 46, 58)
    LINE    = Color.new(70, 82, 98)
    TXT     = Color.new(248, 248, 248)
    DIM     = Color.new(150, 160, 175)
    SHADOW  = Color.new(16, 20, 28)
    SEL     = Color.new(58, 92, 132)
    SELB    = Color.new(130, 190, 250)
    ACC     = Color.new(110, 170, 235)
    DARK    = Color.new(30, 36, 46)
    KEY     = Color.new(80, 92, 110)
    PILL    = Color.new(70, 84, 104)
    UP      = Color.new(112, 216, 112)
    DOWN    = Color.new(240, 112, 96)
    WARN    = Color.new(232, 160, 48)
    OWN     = Color.new(90, 170, 120)
    FOE     = Color.new(210, 100, 100)
    INNATE  = Color.new(170, 140, 230)

    module_function

    def rrect(b, x0, y0, x1, y1, r, color)
      w = x1 - x0 + 1
      h = y1 - y0 + 1
      return if w <= 0 || h <= 0
      r = [r, w / 2, h / 2].min
      b.fill_rect(x0, y0 + r, w, h - 2 * r, color)
      r.times do |i|
        d = r - i - 0.5
        inset = (r - Math.sqrt([r * r - d * d, 0].max)).round
        b.fill_rect(x0 + inset, y0 + i, w - 2 * inset, 1, color)
        b.fill_rect(x0 + inset, y1 - i, w - 2 * inset, 1, color)
      end
    end

    def rbox(b, x0, y0, x1, y1, r, fill, outline = nil)
      if outline
        rrect(b, x0, y0, x1, y1, r, outline)
        rrect(b, x0 + 1, y0 + 1, x1 - 1, y1 - 1, [r - 1, 0].max, fill)
      else
        rrect(b, x0, y0, x1, y1, r, fill)
      end
    end

    def tri(b, x, y, dir, color, sz = 5)
      (sz + 1).times do |i|
        case dir
        when :l then b.fill_rect(x + i, y + sz - i, 1, 2 * i + 1, color)
        when :r then b.fill_rect(x + sz - i, y + sz - i, 1, 2 * i + 1, color)
        when :u then b.fill_rect(x + sz - i, y + i, 2 * i + 1, 1, color)
        when :d then b.fill_rect(x + sz - i, y + sz - i, 2 * i + 1, 1, color)
        end
      end
    end

    # text in a box, centred vertically; align 0 left, 1 right, 2 centre
    def text(b, x, y, w, h, str, color, font = PixelFont::TEXT, align = 0, shadow = false)
      str = str.to_s
      sw = PixelFont.width(font, str)
      tx = case align
           when 1 then x + w - sw
           when 2 then x + (w - sw) / 2
           else x
           end
      ty = y + (h - PixelFont.height(font)) / 2
      PixelFont.draw(b, tx + 1, ty + 1, str, font, SHADOW) if shadow
      PixelFont.draw(b, tx, ty, str, font, color)
      return sw
    end

    # a small label; right-aligned at x when right is true. Returns its width.
    def pill(b, x, y, label, color, right = false)
      w = PixelFont.width(PixelFont::TINY, label) + 12
      x -= w if right
      rbox(b, x, y, x + w, y + 15, 4, color)
      text(b, x, y + 1, w, 15, label, TXT, PixelFont::TINY, 2)
      return w
    end

    def key(b, x, y, label)
      w = [PixelFont.width(PixelFont::TINY, label) + 8, 16].max
      rbox(b, x, y, x + w, y + 15, 3, KEY)
      text(b, x, y + 1, w + 1, 15, label, TXT, PixelFont::TINY, 2)
      return w
    end

    # A heading in small capitals with a line after it
    def heading(b, x, x1, y, label)
      label = label.to_s.upcase
      w = text(b, x, y, 300, 13, label, ACC, PixelFont::TINY)
      b.fill_rect(x + w + 6, y + 6, x1 - (x + w + 6), 1, LINE)
    end

    # Bottom key bar: [[:ud / :lr / "Esc", "label"], ...]
    def footer(b, hints)
      w = b.width
      h = b.height
      b.fill_rect(0, h - 25, w, 25, PANEL2)
      b.fill_rect(0, h - 25, w, 1, LINE)
      x = 8
      hints.each do |k, label|
        if k.is_a?(Symbol)
          rbox(b, x, h - 20, x + 26, h - 6, 3, KEY)
          if k == :ud
            tri(b, x + 3, h - 17, :u, TXT, 4); tri(b, x + 14, h - 16, :d, TXT, 4)
          else
            tri(b, x + 5, h - 17, :l, TXT, 4); tri(b, x + 16, h - 17, :r, TXT, 4)
          end
          x += 30
        elsif k
          x += key(b, x, h - 20, k) + 4
        end
        x += text(b, x, h - 24, 300, 22, label, DIM) + 12
      end
    end
  end
end
