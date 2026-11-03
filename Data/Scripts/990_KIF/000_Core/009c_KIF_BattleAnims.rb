#===============================================================================
# Battle animations, read when played (2026-11-01, PERF-BOOT)
#
# Data/PkmnAnimations.rxdata is 12.8 MB: 1,456 animations, 270,000 objects.
# 6.8.2 loads all of it at every start (Game.initialize ->
# pbLoadBattleAnimations): ~1.5 s on a PC, much more on a phone, and ~35 MB of
# memory for a game in which one battle plays a handful of them. EBDX loaded
# a second copy (660_EBDX/002_EBDX_Module.rb, removed).
#
# Here each animation is kept in the cache (Cache/KIFBoot/battle_anims.kbc)
# as its own small deflated Marshal string, and $PokemonTemp.battleAnims is a
# PBAnimations whose list (AnimList, an Array) makes an animation the first
# time it is asked for with [] or each. Everything else an Array can do first
# makes all of them, so the answers are the same. The first start after the
# data file changes loads it whole, as before, and writes the cache. In debug
# mode (the animation editor saves this list back to the file) nothing
# changes at all; when debug mode is switched on later (Options > DEBUG) the
# lazy list is dropped and the file is read whole the next time it is asked for.
#===============================================================================
module KIF
  module Perf
    module AnimCache
      NAME = "battle_anims"

      # PBAnimations for the file, or nil (the game's own loader runs)
      def self.lazy(path)
        return nil if $DEBUG || !defined?(::PBAnimations)
        st = BootCache.stamp(path)
        return nil unless st
        data = BootCache.read(NAME, st)
        if data.is_a?(Array) && data.length == 2 && data[1].is_a?(Array)
          anims = ::PBAnimations.allocate
          anims.instance_variable_set(:@array, AnimList.new(path, data[1]))
          anims.instance_variable_set(:@selected, data[0])
          return anims
        end
        full = load_data(path)
        if full.is_a?(::PBAnimations) && full.array.instance_of?(Array)
          blobs = full.array.map { |a| a.nil? ? nil : Zlib::Deflate.deflate(Marshal.dump(a), Zlib::BEST_SPEED) }
          BootCache.write(NAME, st, [full.selected, blobs])
        end
        return full
      rescue StandardError => e
        KIF.log("Battle animations: cache not used (#{e.class}: #{e.message})") if KIF.respond_to?(:log)
        return nil
      end

      # the list inside a PBAnimations: an Array whose places hold nil until
      # the animation is asked for
      class AnimList < Array
        FAST = [:[], :each, :length, :size]

        def initialize(path, blobs)
          super(blobs.length)
          @path = path
          @blobs = blobs   # place => deflated Marshal string, or nil once made (or never an animation)
        end

        def make(i)
          b = @blobs[i]
          return nil unless b
          obj = Marshal.load(Zlib::Inflate.inflate(b))
          Array.instance_method(:[]=).bind_call(self, i, obj)
          @blobs[i] = nil
          return obj
        rescue StandardError => e
          return recover(i, e)
        end

        # a cache that can't be read: the data file, whole
        def recover(i, error)
          KIF.log("Battle animations: cache unreadable (#{error.class}: #{error.message}), reading #{@path}") if KIF.respond_to?(:log)
          full = load_data(@path).array
          full.each_with_index { |a, j| Array.instance_method(:[]=).bind_call(self, j, a) if @blobs[j] }
          @blobs = Array.new(full.length)
          return Array.instance_method(:[]).bind_call(self, i)
        end

        def fill_all
          return unless @blobs
          i = 0
          n = Array.instance_method(:length).bind_call(self)
          while i < n
            make(i) if @blobs[i]
            i += 1
          end
          @blobs = nil
        end

        def [](i, *rest)
          return super(i, *rest) unless @blobs
          return fill_all_and { super(i, *rest) } unless rest.empty? && i.is_a?(Integer)
          n = super_length
          j = i < 0 ? i + n : i
          return nil if j < 0 || j >= n
          return @blobs[j] ? make(j) : Array.instance_method(:[]).bind_call(self, j)
        end

        def super_length
          return Array.instance_method(:length).bind_call(self)
        end
        private :super_length

        def fill_all_and
          fill_all
          return yield
        end
        private :fill_all_and

        def each
          return to_enum(:each) { super_length } unless block_given?
          i = 0
          while i < super_length
            yield self[i]
            i += 1
          end
          return self
        end

        def length
          return super_length
        end
        alias size length

        (Array.public_instance_methods(false) - FAST).each do |m|
          define_method(m) { |*args, &blk| fill_all; super(*args, &blk) }
          ruby2_keywords(m)
        end
      end
    end
  end
end

class Object
  was_private = private_method_defined?(:pbLoadBattleAnimations)
  alias kif_perf_pbLoadBattleAnimations pbLoadBattleAnimations unless method_defined?(:kif_perf_pbLoadBattleAnimations) || private_method_defined?(:kif_perf_pbLoadBattleAnimations)

  def pbLoadBattleAnimations
    $PokemonTemp = PokemonTemp.new if !$PokemonTemp
    cur = $PokemonTemp.battleAnims
    # the editors save this list back to the file, so they never get the lazy one (unmade places would be saved as nil)
    $PokemonTemp.battleAnims = nil if $DEBUG && cur && cur.instance_variable_get(:@array).is_a?(KIF::Perf::AnimCache::AnimList)
    if !$PokemonTemp.battleAnims && pbRgssExists?("Data/PkmnAnimations.rxdata")
      anims = KIF::Perf::AnimCache.lazy("Data/PkmnAnimations.rxdata")
      $PokemonTemp.battleAnims = anims if anims
    end
    return kif_perf_pbLoadBattleAnimations
  end
  private :pbLoadBattleAnimations if was_private
end
