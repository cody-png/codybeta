#===============================================================================
# C-SYS-03 – Disposed sprites let go (2026-10-09)
#   mkxp-z keeps every sprite made on a viewport in a hidden list on that
#   viewport, and doesn't take it out of the list when the sprite is
#   disposed. The map's viewports (Spriteset_Map's @@viewport0/1/3) live for
#   the whole session, so every tile and event sprite of every map ever
#   loaded stayed in memory - and through each sprite its event, its map
#   and the map's ~110 common events. After a few hours (a door crawl) that
#   was 20,000+ dead sprites holding 300+ old maps: more memory, and every
#   full garbage collection (the occasional 80-300 ms stutter) had more to
#   go through.
#   Here, each time a map's sprites are disposed, disposed sprites are taken
#   out of those lists. Only disposed ones: anything still on screen stays.
#===============================================================================
begin
  require "objspace"
rescue LoadError, StandardError
  nil
end

module KIF
  module ViewportLeak
    @viewports = ObjectSpace::WeakMap.new   # every viewport made after load
    @seeded = false

    class << self
      def available?
        return ObjectSpace.respond_to?(:reachable_objects_from)
      end

      def track(vp)
        @viewports[vp] = true
      end

      # the hidden lists the engine keeps on the viewport (Arrays only it holds)
      # (Ruby-side @variables of a Viewport subclass are left alone)
      # (a tester's game logged "wrong number of arguments (given 0, expected
      # 1..4)" here - Kernel#select's message - so the result is checked to be
      # an Array and walked without .select; failures now log where they were)
      def lists(vp)
        found = ObjectSpace.reachable_objects_from(vp)
        return [] unless found.is_a?(Array)
        named = vp.instance_variables.map { |iv| vp.instance_variable_get(iv) }
        ret = []
        found.each do |x|
          next unless x.is_a?(Array)
          next if named.any? { |v| v.equal?(x) }
          ret << x
        end
        return ret
      end

      # One viewport's lists; a problem with one viewport doesn't stop the others
      def prune_viewport(vp)
        n = 0
        lists(vp).each do |l|
          next if l.frozen? || l.empty?
          before = l.length
          l.reject! { |s| s.respond_to?(:disposed?) && s.disposed? }
          n += before - l.length
        end
        return n
      rescue StandardError => e
        failed(e, vp)
        return 0
      end

      def failed(e, vp = nil)
        @failures = (@failures || 0) + 1
        return if @failures > 3
        where = (e.backtrace || [])[0, 3].map { |l| l.to_s.sub(/\A.*[\/\\]/, "") }.join(" < ")
        what = vp ? " on #{vp.class}" : ""
        KIF.log("Viewport cleanup failed#{what} (#{e.class}: #{e.message}) at #{where}") if defined?(KIF.log)
      end

      # Removes disposed sprites from every live viewport's list; returns how many
      def prune
        return 0 unless available?
        unless @seeded   # viewports made before this file (Spriteset_Map's, at load)
          @seeded = true
          ObjectSpace.each_object(Viewport) { |v| @viewports[v] = true }
        end
        n = 0
        @viewports.each_key do |vp|
          next if vp.disposed?
          n += prune_viewport(vp)
        end
        return n
      rescue StandardError => e
        failed(e)
        return 0
      end
    end

    module ViewportHook
      def initialize(*args)
        super
        KIF::ViewportLeak.track(self)
      end
    end

    module SpritesetHook
      def dispose(*args)
        super
      ensure
        KIF::ViewportLeak.prune
      end
    end
  end
end

Viewport.prepend(KIF::ViewportLeak::ViewportHook)
Spriteset_Map.prepend(KIF::ViewportLeak::SpritesetHook)
