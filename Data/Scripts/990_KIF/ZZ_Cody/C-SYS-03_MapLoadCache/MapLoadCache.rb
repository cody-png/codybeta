#===============================================================================
# C-SYS-03 – Map load cache (Cody, 2026-10-08)
#   Walking between connected maps (Cerulean <-> Route 5, Route 24...) PIF
#   loads the next map's tileset picture from disk every time it comes into
#   view (~60 ms, a visible hitch) and throws it away again as soon as it is
#   out of view. Here the last few pictures no longer in use are kept, so
#   going back and forth only loads them once.
#===============================================================================
module KIF
  module MapLoadCache
    SPARE_TILESETS  = 4    # tileset pictures kept after their map goes away
    SPARE_AUTOTILES = 40   # autotile pictures (small)

    def self.limit(store)
      return store.is_a?(TilemapRenderer::AutotileBitmaps) ? SPARE_AUTOTILES : SPARE_TILESETS
    end

    module Store
      def kif_spare
        @kif_spare ||= {}   # filename => [bitmap, wraps, frame duration]; oldest first
      end

      # Put a kept picture back instead of loading it again
      def kif_restore(filename)
        return false if nil_or_empty?(filename) || @bitmaps[filename]
        kept = kif_spare.delete(filename)
        return false unless kept
        bitmap, wraps, duration = kept
        return false if bitmap.disposed?
        @bitmaps[filename] = bitmap
        @bitmap_wraps[filename] = wraps
        @load_counts[filename] = 1
        @changed = true
        if @frame_durations
          @frame_durations[filename] = duration
          frame_count(filename, true)
          set_current_frame(filename)
        end
        return true
      end

      def add(filename)
        return if kif_restore(filename)
        super
      end

      def remove(filename)
        if !nil_or_empty?(filename) && @bitmaps[filename] && @load_counts[filename].to_i <= 1
          bitmap = @bitmaps[filename]
          unless bitmap.disposed?
            kif_spare.delete(filename)
            kif_spare[filename] = [bitmap, @bitmap_wraps[filename], @frame_durations ? @frame_durations[filename] : nil]
            @bitmaps.delete(filename)
            @bitmap_wraps.delete(filename)
            @load_counts.delete(filename)
            if @frame_durations      # (AutotileBitmaps#remove clears its own frame data after this)
              @frame_counts.delete(filename)
              @current_frames.delete(filename)
              @frame_durations.delete(filename)
            end
            while kif_spare.length > KIF::MapLoadCache.limit(self)
              _name, (old, *) = kif_spare.shift
              old.dispose unless old.disposed? || @bitmaps.value?(old)
            end
            return
          end
        end
        super
      end

      def kif_spare_dispose
        kif_spare.each_value { |b, *| b.dispose unless b.disposed? || @bitmaps.value?(b) }
        kif_spare.clear
      end
    end

    # AutotileBitmaps has its own add (it doesn't call TilesetBitmaps#add)
    module AutotileAdd
      def add(filename)
        return if kif_restore(filename)
        super
      end
    end
  end
end

if defined?(TilemapRenderer::TilesetBitmaps)
  TilemapRenderer::TilesetBitmaps.prepend(KIF::MapLoadCache::Store)
  TilemapRenderer::AutotileBitmaps.prepend(KIF::MapLoadCache::AutotileAdd) if defined?(TilemapRenderer::AutotileBitmaps)

  class TilemapRenderer
    alias kif_mlc_dispose dispose unless method_defined?(:kif_mlc_dispose)

    def dispose
      unless disposed?
        @tilesets.kif_spare_dispose if @tilesets.respond_to?(:kif_spare_dispose)
        @autotiles.kif_spare_dispose if @autotiles.respond_to?(:kif_spare_dispose)
      end
      kif_mlc_dispose
    end
  end
end
