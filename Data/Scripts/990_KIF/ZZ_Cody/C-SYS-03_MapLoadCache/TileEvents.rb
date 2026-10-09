#===============================================================================
# C-SYS-03 – Tile events without the tileset reload (2026-10-09)
#   An event drawn with a tile instead of a character (fake roofs, rocks,
#   signs, plenty of invisible-looking events) gets its picture from
#   pbGetTileBitmap (007_Objects and windows/008_AnimatedBitmap.rb:372) via
#   RPG::Cache.tileEx (001_RPG_Cache.rb:96), which decodes the WHOLE tileset
#   PNG for every tile it hasn't cut yet (~80 ms for Outdoor) and throws it
#   away again. RPG::Cache is emptied often (100 entries), so walking into
#   Cerulean / Route 24 / through a door paid ~80 ms per such event: the
#   one-step stutters in Cody's frame logs.
#   Here the tile is cut from the tileset picture the map renderer already
#   has in memory (it loads it before the map's events, wrapped mega
#   tilesets included), and each cut tile is kept so a later visit doesn't
#   need the tileset at all. Same pixels as PIF's way (hue applied after).
#===============================================================================
module KIF
  module TileEvents
    KEEP = 400   # cut tiles kept (32x32 each, ~4 KB)

    @tiles = {}  # [filename, tile_id, hue, width, height] => Bitmap (ours)

    class << self
      attr_reader :tiles

      # The tileset picture the map renderer holds for this file, and whether
      # it's a wrapped mega tileset; nil if it has none
      def source(filename)
        sc = $scene
        return nil unless sc && sc.respond_to?(:map_renderer)
        r = sc.map_renderer
        return nil if r.nil? || (r.respond_to?(:disposed?) && r.disposed?)
        ts = r.instance_variable_get(:@tilesets)
        return nil unless ts
        bmp = ts[filename]
        if bmp && !bmp.disposed?
          return [bmp, !!ts.instance_variable_get(:@bitmap_wraps)[filename]]
        end
        if ts.respond_to?(:kif_spare) && (kept = ts.kif_spare[filename])
          return [kept[0], !!kept[1]] if kept[0] && !kept[0].disposed?
        end
        return nil
      rescue StandardError
        return nil
      end

      # Where tile_id sits in the picture (TilesetBitmaps#set_src_rect)
      def spot(id, height, wraps)
        n = id - 384
        x = (n % 8) * 32
        y = (n / 8) * 32
        if wraps
          col = n * 32 / (8 * height)
          x += col * 8 * 32
          y -= col * height
        end
        return [x, y]
      end

      # A tile picture cut from the renderer's tileset, or nil
      def cut(filename, tile_id, hue, width, height)
        src = source(filename)
        return nil unless src
        bmp, wraps = src
        top = tile_id - (height - 1) * 8     # tileEx: the event's tile is the bottom row
        return nil if top < 384
        out = Bitmap.new(32 * width, 32 * height)
        height.times do |r|
          x, y = spot(top + r * 8, bmp.height, wraps)
          out.blt(0, r * 32, bmp, Rect.new(x, y, 32 * width, 32))
        end
        out.hue_change(hue) if hue != 0
        return out
      rescue StandardError
        out.dispose if out && !out.disposed?
        return nil
      end

      def keep(key, bitmap)
        if @tiles.length >= KEEP
          old_key, old = @tiles.first
          @tiles.delete(old_key)
          old.dispose if old && !old.disposed?
        end
        @tiles[key] = bitmap
      end

      def copy(bitmap)
        b = Bitmap.new(bitmap.width, bitmap.height)
        b.blt(0, 0, bitmap, Rect.new(0, 0, bitmap.width, bitmap.height))
        return b
      end
    end
  end
end

class Object
  unless private_method_defined?(:kif_tiles_pbGetTileBitmap)
    alias kif_tiles_pbGetTileBitmap pbGetTileBitmap
  end
  private

  def pbGetTileBitmap(filename, tile_id, hue, width = 1, height = 1)
    key = [filename, tile_id, hue, width, height]
    if (ret = RPG::Cache.fromCache(key))
      ret.addRef
      return ret
    end
    te = KIF::TileEvents
    mine = te.tiles[key]
    mine = nil if mine && mine.disposed?
    unless mine
      mine = te.cut(filename, tile_id, hue, width, height)
      te.keep(key, mine) if mine
    end
    unless mine
      # PIF's way (decodes the tileset); keep a copy of what it cut
      ret = kif_tiles_pbGetTileBitmap(filename, tile_id, hue, width, height)
      (te.keep(key, te.copy(ret)) rescue nil) if ret && !ret.disposed?
      return ret
    end
    ret = BitmapWrapper.new(mine.width, mine.height)
    ret.blt(0, 0, mine, Rect.new(0, 0, mine.width, mine.height))
    RPG::Cache.setKey(key, ret)
    return ret
  end
end
