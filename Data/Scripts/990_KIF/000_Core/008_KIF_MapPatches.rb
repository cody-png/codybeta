#===============================================================================
# KIF::MapPatches – add or change map events when a map is loaded, without
# touching the Data/MapNNN.rxdata files (port framework, Cody 2026-10-05:
# "Let the scripts add the events when the map loads. Modularity is
# important.").
#
#   KIF::MapPatches.add(314, "Dem NPC") { |map| ... change map.events ... }
#
# Patches run on the RPG::Map returned by load_data, before the game builds
# its Game_Events from it, so added pages and events behave exactly like
# ones saved in the map (self switches, page conditions, move routes).
# Event data is written as plain arrays/hashes (see KIF::MapPatches.page /
# .event) so it can be read and diffed.
#===============================================================================
module KIF
  module MapPatches
    @patches = Hash.new { |h, k| h[k] = [] }

    def self.add(map_id, name, &block)
      @patches[map_id] << [name, block]
    end

    def self.apply(map_id, map)
      return map unless @patches.key?(map_id)
      return map unless map.respond_to?(:events) && map.events
      return map if map.instance_variable_get(:@kif_patched)
      map.instance_variable_set(:@kif_patched, true)
      @patches[map_id].each do |name, block|
        begin
          block.call(map)
        rescue => e
          KIF.log("Map #{map_id} patch '#{name}' failed: #{e.class}: #{e.message}")
        end
      end
      return map
    end

    #---------------------------------------------------------------------------
    # Builders: encoded values -> RPG objects
    #   [:tone, r, g, b, gray]  [:color, r, g, b, a]  [:audio, name, vol, pitch]
    #   [:route, repeat, skippable, [[code, params], ...]]
    #---------------------------------------------------------------------------
    def self.value(v)
      if v.is_a?(Array) && v[0].is_a?(Symbol)
        case v[0]
        when :tone  then return Tone.new(*v[1, 4])
        when :color then return Color.new(*v[1, 4])
        when :audio then return RPG::AudioFile.new(v[1], v[2], v[3])
        when :route
          r = RPG::MoveRoute.new
          r.repeat    = v[1]
          r.skippable = v[2]
          r.list      = v[3].map { |code, params| RPG::MoveCommand.new(code, value(params)) }
          return r
        when :mc then return RPG::MoveCommand.new(v[1], value(v[2]))
        end
      end
      return v.map { |x| value(x) } if v.is_a?(Array)
      return v.dup if v.is_a?(String)
      return v
    end

    def self.command(code, indent, params)
      return RPG::EventCommand.new(code, indent, value(params))
    end

    def self.commands(list)
      return list.map { |c| command(c[0], c[1], c[2]) }
    end

    def self.page(h)
      pg = RPG::Event::Page.new
      h[:cond].each { |k, v| pg.condition.send("#{k}=", v) }
      h[:gfx].each { |k, v| pg.graphic.send("#{k}=", v) }
      [:move_type, :move_speed, :move_frequency, :walk_anime, :step_anime,
       :direction_fix, :through, :always_on_top, :trigger].each do |k|
        pg.send("#{k}=", h[k]) if h.key?(k)
      end
      pg.move_route = value(h[:move_route]) if h[:move_route]
      pg.list = commands(h[:list])
      return pg
    end

    def self.event(id, h)
      ev = RPG::Event.new(h[:x], h[:y])
      ev.id    = id
      ev.name  = h[:name].dup
      ev.pages = h[:pages].map { |p| page(p) }
      return ev
    end

    #---------------------------------------------------------------------------
    # Helpers
    #---------------------------------------------------------------------------
    # Event whose first page uses this character graphic (ids differ between
    # PIF versions; the graphic doesn't)
    def self.find_by_graphic(map, graphic, id_hint = nil)
      hinted = map.events[id_hint] if id_hint
      return hinted if hinted && hinted.pages[0].graphic.character_name == graphic
      map.events.keys.sort.each do |id|
        ev = map.events[id]
        return ev if ev.pages[0] && ev.pages[0].graphic.character_name == graphic
      end
      return nil
    end

    def self.free_id(map, wanted)
      id = wanted
      id += 1 while map.events[id]
      return id
    end

    # Insert a page before the first page matching the block (else append)
    def self.insert_page(ev, pg, &before)
      idx = before ? ev.pages.index { |p| before.call(p) } : nil
      if idx
        ev.pages.insert(idx, pg)
      else
        ev.pages.push(pg)
      end
    end

    # Text of a Show Text command (101) without the encoding fuss
    def self.text_of(cmd)
      return nil unless cmd && [101, 401].include?(cmd.code)
      return cmd.parameters[0].to_s.dup.force_encoding("UTF-8")
    end
  end
end

alias kif_mp_load_data load_data unless defined?(kif_mp_load_data)

def load_data(filename, *args)
  ret = kif_mp_load_data(filename, *args)
  if filename.is_a?(String) && filename =~ /Map(\d+)\.rxdata\z/
    ret = KIF::MapPatches.apply($1.to_i, ret)
  end
  return ret
end
