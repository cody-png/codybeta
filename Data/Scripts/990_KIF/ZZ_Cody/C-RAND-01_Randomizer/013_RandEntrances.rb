#===============================================================================
# C-RAND-01 – Randomizer: Entrances (Cody, 2026-10-07)
#   Doors between Kanto's outdoor maps and the places behind them are
#   shuffled (Johto's and the Sevii Islands' too with "And Johto?" / "And
#   Sevii?", mixed with Kanto's). The layout is built at Randomize now from Data/KIF/entrances.dat
#   (made by the KIF Test Kit's map tool: the world as regions and edges, the
#   switches/items/badges each place gives, and every shufflable door) and
#   only kept when the Hall of Fame can be reached from Pallet Town with what
#   the world gives along the way. One hook on Interpreter#command_201 sends
#   the player to the new destination; the door's own animation stays.
#===============================================================================
module KIF
  module Rand
    ENT_SETTINGS = [
      [:entrances, :enum, 3],     # Off / Simple / Full
      [:ent_doors, :enum, 3],     # Dungeons / Buildings / Everything
      [:ent_coupled, :enum, 2],   # Off / On (default On, DATA_DEFAULTS)
      [:ent_hints, :enum, 2],     # Off / On
      [:ent_start, :enum, 3],     # Pallet / Random town / Random map
      [:ent_levels, :enum, 3],    # Off / Trainers / Trainers + wild
      [:ent_johto, :enum, 2],     # Off / On: Johto's doors join the shuffle
      [:ent_sevii, :enum, 2]      # Off / On: the Sevii Islands' doors too
    ]
    ENT_SETTINGS.each { |st| DATA_SETTINGS << st unless DATA_KEYS.include?(st[0]) }
    ENT_SETTINGS.each { |st| DATA_KEYS << st[0] unless DATA_KEYS.include?(st[0]) }
    LABELS[:entrances] = ["Entrances", ["Off", "Simple", "Full"]]
    LABELS[:ent_doors] = ["Which doors", ["Dungeons", "Buildings", "Everything"]]
    LABELS[:ent_coupled] = ["Coupled", ["Off", "On"]]
    LABELS[:ent_hints] = ["Door hints", ["Off", "On"]]
    LABELS[:ent_start] = ["Start", ["Pallet", "Random town", "Random map"]]
    LABELS[:ent_levels] = ["Level scaling", ["Off", "Trainers", "Trainers + wild"]]
    LABELS[:ent_johto] = ["And Johto?", ["Off", "On"]]
    LABELS[:ent_sevii] = ["And Sevii?", ["Off", "On"]]

    DATA_DEFAULTS[:ent_coupled] = 1   # Coupled unless switched off

    module ER
      DATA_PATH = "Data/KIF/entrances.dat"
      RETRIES = 100      # most layouts are found in 1-3 tries (~0.2 s each)
      RETRIES_HERE = 40  # Randomize now mid-run: if nothing works from where you stand by then, the old doors stay
      BADGE_PREFIX = "badge_"
      OAK_LABS = [77, 551, 552, 593, 659, 724, 740, 847]   # every variant of Oak's Lab
      NO_START = [303, 167]   # Indigo Plateau, Crimson City (nowhere to go without 8 badges)

      class << self
        attr_accessor :dat_cache, :dat_failed, :seed_changed
      end

      # The compiled world, loaded once per session
      # (a missing or unreadable file is tried once per session: the feature
      # just stays unavailable)
      def self.dat
        return @dat_cache if @dat_cache
        return nil if @dat_failed
        @dat_failed = true
        return nil unless FileTest.exist?(DATA_PATH)
        d = Marshal.load(File.binread(DATA_PATH))
        return nil unless d.is_a?(Hash) && d[:doors].is_a?(Array) && d[:edges].is_a?(Hash)
        d[:door_by_id] = {}
        d[:doors].each { |o| d[:door_by_id][o[:id]] = o }
        @dat_failed = false
        @dat_cache = d
        return d
      rescue => e
        KIF.log("Entrances data couldn't be read (#{e.class}: #{e.message})")
        return nil
      end

      def self.available?
        return !dat.nil?
      end

      # Town-map regions whose doors take part: Kanto always, Johto when
      # "And Johto?" is on (data files before Johto have Kanto doors only)
      REGION_NAMES = { 0 => "Kanto", 1 => "Johto", 2 => "Sevii" }
      def self.regions_on
        r = [0]
        r << 1 if Rand.dget(:ent_johto) == 1
        r << 2 if Rand.dget(:ent_sevii) == 1
        return r
      end

      def self.door_region(o)
        return o[:region] || 0
      end

      # Does a layout belong to this data file? Kanto's doors (and the maps)
      # have one signature, every other region its own
      def self.layout_current?(s, d = dat)
        return false unless s.is_a?(Hash) && d && s[:sig] == d[:signature]
        rs = d[:region_sigs] || {}
        return (s[:rsig] || {}).all? { |r, v| rs[r] == v }
      end

      def self.state
        return Rand.data[:ent_layout]
      end

      # The layout in use, if it belongs to this data file
      def self.active?
        s = state
        return false unless s.is_a?(Hash) && s[:in].is_a?(Hash) && !s[:in].empty?
        return layout_current?(s)
      end

      #-------------------------------------------------------------------------
      # Logic: what the world gives you, and where you can get to
      #-------------------------------------------------------------------------
      def self.abilities(have, badges)
        a = []
        a << :cut if (have.include?(:item_HM01) && badges >= 1) || have.include?(:item_MACHETE)
        a << :rocksmash if have.include?(:item_TM94) || have.include?(:item_PICKAXE)
        a << :strength if (have.include?(:item_HM04) && badges >= 5) || have.include?(:item_LEVER)
        a << :surf if (have.include?(:item_HM03) && badges >= 6) || have.include?(:item_SURFBOARD)
        a << :waterfall if (have.include?(:item_HM05) && badges >= 9) || have.include?(:item_JETPACK)
        a << :rockclimb if have.include?(:item_CLIMBINGGEAR)
        a << :dive if (have.include?(:item_HM08) && badges >= 9) || have.include?(:item_SCUBAGEAR)
        a << :pokeflute if have.include?(:item_POKEFLUTE)
        a << :bike if have.include?(:item_BICYCLE)
        return a
      end

      # Requirements and gate conditions are parsed once, then looked up.
      # `have` is a Hash of flags (fast lookups); badges = how many.
      def self.req_kind(r)
        (@req_kind ||= {})[r] ||= begin
          str = r.to_s
          if str =~ /\Abadges_(\d+)\z/ then [:badges, $1.to_i]
          elsif str.start_with?("npc_") then [:npc]
          else [:flag]
          end
        end
      end

      # One condition of a gate's lift set: a switch number, a flag, the
      # badge count, "varN>=V" (variable N set), "selfX" (the event's own
      # switch, set by the event itself) or :always
      def self.lift_kind(c)
        (@lift_kind ||= {})[c] ||= begin
          case c
          when Integer then [:flag, :"sw_#{c}"]
          when Symbol
            if c == :always then [:yes]
            elsif c.to_s =~ /\Abadges_(\d+)\z/ then [:badges, $1.to_i]
            else [:flag, c]
            end
          else
            c.to_s =~ /\Avar(\d+)>=/ ? [:flag, :"var_#{$1}"] : (c.to_s.start_with?("self") ? [:yes] : [:no])
          end
        end
      end

      def self.gate_open?(lifts, have, badges)
        return false unless lifts
        return lifts.any? { |set| !set.empty? && set.all? { |c|
          k = lift_kind(c)
          case k[0]
          when :flag then have.include?(k[1])
          when :badges then badges >= k[1]
          when :yes then true
          else false
          end } }
      end

      def self.satisfied?(req, have, gates, badges)
        return true if have.include?(req)
        k = req_kind(req)
        return badges >= k[1] if k[0] == :badges
        return gate_open?(gates[req], have, badges) if k[0] == :npc
        return false
      end

      def self.flag_hash(have, badges)
        h = {}
        have.each { |f| h[f] = true }
        abilities(h, badges).each { |f| h[f] = true }
        return h
      end

      def self.badge_flag?(f)
        (@badge_flag ||= {})[f] ||= (f.to_s.start_with?(BADGE_PREFIX) ? 1 : 0)
        return @badge_flag[f] == 1
      end

      def self.key_flag?(f)
        (@key_flag ||= {})[f] ||= (f.to_s.start_with?(BADGE_PREFIX, "item_") ? 1 : 0)
        return @key_flag[f] == 1
      end

      def self.node_map(n)
        (@node_map ||= {})[n] ||= n.split(":")[0]
      end

      # Repeat: reach what you can, collect what it gives, until nothing new.
      # Returns seen (node => sphere), order (node => reach order), have
      # (flags), all (flags + abilities, as a Hash), badges, spheres count.
      # `from` continues an earlier sweep of a graph that has only gained
      # edges since (the shuffler adds doors one batch at a time): what was
      # reached stays reached, and only the edges out of `touched` (the spots
      # that got new edges) and the ones that were waiting on flags are looked
      # at again. `record` keeps, per round, its flags and the spots first
      # reached in it.
      def self.sweep(d, edges, extra = [], from = nil, start = nil, stop_at = nil, record = false, touched = nil)
        gates = d[:gates]
        have = from ? from[:have].dup : (d[:start_with] + extra).uniq
        have_h = {}
        have.each { |f| have_h[f] = true }
        seen = from ? from[:seen].dup : {}
        order = from ? from[:order].dup : {}   # node => how many nodes were reached before it
        maps = {}                              # map => reached
        if from
          if from[:maps] then maps = from[:maps].dup
          else from[:seen].each_key { |k| maps[node_map(k)] = true }
          end
        end
        # edges out of reached spots still waiting on a flag: to => [[from, req], ...]
        waiting = {}
        ((from && from[:waiting]) || {}).each { |k, v| waiting[k] = v.dup }
        sphere = from ? from[:spheres] - 1 : 0
        first = start || d[:start]
        queue = []
        unless seen[first]
          seen[first] = sphere
          order[first] = order.length
          maps[node_map(first)] = true
        end
        queue = from ? ((from[:waiting] && touched) ? touched.select { |n| seen[n] } : seen.keys) : [first]
        badges = have.count { |f| badge_flag?(f) }
        rounds = record ? [] : nil   # [flags this round, badges, nodes first reached in it]
        fresh = record ? (from ? [] : [first]) : nil
        recheck = from ? true : false
        loop do
          break if stop_at && have_h[stop_at]
          rb = badges   # what this round's checks see; gains count from the next round
          all = flag_hash(have, rb)
          if recheck
            waiting.keys.each do |to|
              if seen[to]
                waiting.delete(to)
                next
              end
              next unless waiting[to].any? { |_n, req| req.all? { |r| satisfied?(r, all, gates, rb) } }
              waiting.delete(to)
              seen[to] = sphere
              order[to] = order.length
              maps[node_map(to)] = true
              fresh << to if record
              queue << to
            end
          end
          until queue.empty?
            n = queue.shift
            (edges[n] || []).each do |to, req|
              next if seen[to]
              if req.all? { |r| satisfied?(r, all, gates, rb) }
                seen[to] = sphere
                order[to] = order.length
                maps[node_map(to)] = true
                fresh << to if record
                waiting.delete(to)
                queue << to
              else
                w = (waiting[to] ||= [])
                w << [n, req] unless w.any? { |a, b| a == n && b.equal?(req) }
              end
            end
          end
          if record
            rounds << [all, rb, fresh]
            fresh = []
          end
          gained = false
          key = false   # a badge or a key item: what makes a new sphere
          d[:providers].each do |flag, where, needs|
            next if have_h[flag]
            if where.is_a?(Symbol)
              next unless maps[where.to_s[1..-1]]
            else
              next unless where.any? { |x| seen[x] }
            end
            next unless needs.all? { |f| satisfied?(f, all, gates, rb) }
            have << flag
            have_h[flag] = true
            badges += 1 if badge_flag?(flag)
            gained = true
            key = true if key_flag?(flag)
          end
          break unless gained
          # Spheres as in Archipelago: sphere 0 is what you reach with nothing;
          # sphere N+1 opens with the badges/key items found in sphere N.
          # Story events (talking to the right person) widen the same sphere.
          sphere += 1 if key
          recheck = true
        end
        out = { seen: seen, order: order, have: have, all: flag_hash(have, badges), badges: badges, spheres: sphere + 1,
                maps: maps, waiting: waiting }
        out[:rounds] = rounds if record
        return out
      end

      # The graph for a layout: map_in (door => door whose place it leads
      # into), map_out (door => door on whose doorstep its exit comes out).
      # Doors missing from a map keep their own ends.
      # `pending`: doors being shuffled; while unplaced they lead nowhere.
      def self.edges_for(d, map_in, map_out, pending = nil)
        edges = {}
        d[:edges].each { |k, v| edges[k] = v.dup }
        byid = d[:door_by_id]
        d[:doors].each do |o|
          wait = pending && pending[o[:id]]
          unless wait && !map_in.key?(o[:id])
            i = byid[map_in[o[:id]] || o[:id]]
            o[:out_edges].each { |src, needs| (edges[src] ||= []) << [i[:in_node], needs, 1] }
          end
          unless wait && !map_out.key?(o[:id])
            back = byid[map_out[o[:id]] || o[:id]]
            o[:exit_edges].each { |src, needs| (edges[src] ||= []) << [back[:exit_node], needs, 1] }
          end
        end
        return edges
      end

      def self.beatable?(d, seen)
        goal = "#{d[:goal_map]}:"
        return seen.keys.any? { |k| k.start_with?(goal) }
      end

      #-------------------------------------------------------------------------
      # Shuffler
      #-------------------------------------------------------------------------
      def self.doors_for(d, which, regions = regions_on)
        list = d[:doors].select { |x| regions.include?(door_region(x)) }
        case which
        when 0 then list.select { |x| x[:pool] == :dungeon }
        when 1 then list.select { |x| x[:pool] == :building }
        else list
        end
      end

      # Standing at the door with what the sweep gave (its own condition met)
      def self.door_reached?(o, res)
        seen = res[:seen]
        return o[:out_edges].any? { |src, needs| seen[src] && needs.all? { |r| satisfied?(r, res[:all], dat[:gates], res[:badges]) } }
      end

      def self.inside_reached?(o, seen)
        return seen[o[:in_node]] ? true : false
      end

      # Flags that would open something at the edge of what is reached:
      # unmet requirements on edges out of seen nodes, and the switches that
      # lift the NPC gates among them
      def self.wanted(d, edges, res)
        seen = res[:seen]; have = res[:all]; badges = res[:badges]
        want = {}
        seen.each_key do |n|
          (edges[n] || []).each do |to, req|
            next if seen[to]
            req.each do |r|
              next if satisfied?(r, have, d[:gates], badges)
              if r.to_s.start_with?("npc_")
                (d[:gates][r] || []).each { |set| set.each { |x| want[x.is_a?(Integer) ? :"sw_#{x}" : x] = true } }
              else
                want[r] = true
              end
            end
          end
        end
        # ...and what the reached givers of those flags still wait for (the
        # parcel for the switch the lab sets), a few steps deep
        maps_now = {}
        seen.each_key { |k| maps_now[k.split(":")[0]] = true }
        3.times do
          added = false
          d[:providers].each do |flag, where, needs|
            next unless want[flag]
            here = where.is_a?(Symbol) ? maps_now[where.to_s[1..-1]] : where.any? { |n| seen[n] }
            next unless here
            needs.each do |f|
              next if want[f] || satisfied?(f, have, d[:gates], badges)
              want[f] = true; added = true
            end
          end
          break unless added
        end
        return want
      end

      # Grow the world. Each entrance has two ends: the door outside and the
      # exit inside. From what is reached, send a reached door into a place
      # not yet reached, or a reached exit out to a doorstep not yet reached;
      # sweep; repeat. Coupled: the exit of the place you entered leads back
      # to the door you came through. Leftovers pair at random.
      # `groups` (Simple): door id => the doors of its place (a gate, a cave
      # with two ends), in tile order. A group only trades with a group of the
      # same size, all its doors at once; single doors trade with single doors.
      def self.grow(d, doors, rng, coupled, map_in = {}, map_out = {}, start = nil, extra = [], groups = nil)
        ids = doors.map { |x| x[:id] }
        groups ||= {}
        free_doors = ids - map_in.keys                   # doors without a place
        free_places = ids - map_in.values                # places nobody leads into
        free_exits = ids - map_out.keys                  # exits without a doorstep
        free_steps = ids - map_out.values                # doorsteps nobody comes out on
        byid = d[:door_by_id]
        pending = {}
        ids.each { |id| pending[id] = true }
        batch = 6
        res = nil
        size = ->(id) { (g = groups[id]) ? g.length : 1 }
        # pair a (door / exit) unit with a (place / doorstep) unit of the same size
        added_in = []; added_out = []   # links since the last sweep
        link_in = lambda do |o, p|
          go = groups[o] || [o]; gp = groups[p] || [p]
          go.zip(gp) do |x, y|
            map_in[x] = y
            added_in << x
            free_doors.delete(x); free_places.delete(y)
            if coupled
              map_out[y] = x
              added_out << y
              free_exits.delete(y); free_steps.delete(x)
            end
          end
        end
        link_out = lambda do |e, st|
          ge = groups[e] || [e]; gs = groups[st] || [st]
          ge.zip(gs) do |x, y|
            map_out[x] = y
            added_out << x
            free_exits.delete(x); free_steps.delete(y)
          end
        end
        # the graph, built once and given each new link's edges as it comes
        edges = edges_for(d, map_in, map_out, pending)
        # one id per unit (a group counts once, by its first door)
        heads = ->(list) { list.select { |id| (g = groups[id]).nil? || g[0] == id } }
        loop do
          break if free_doors.empty? && free_exits.empty?
          touched = []
          added_in.each do |o|
            i = byid[map_in[o]]
            byid[o][:out_edges].each { |src, needs| (edges[src] ||= []) << [i[:in_node], needs, 1]; touched << src }
          end
          added_out.each do |o|
            back = byid[map_out[o]]
            byid[o][:exit_edges].each { |src, needs| (edges[src] ||= []) << [back[:exit_node], needs, 1]; touched << src }
          end
          added_in.clear; added_out.clear
          res = sweep(d, edges, extra, res, start, nil, false, touched.uniq)
          seen = res[:seen]
          want = nil
          # a group is open when any of its doors / exits is reached, far while
          # none of its places / doorsteps is
          reached_door = ->(id) { (groups[id] || [id]).any? { |x| door_reached?(byid[x], res) } }
          reached_in = ->(id) { (groups[id] || [id]).any? { |x| inside_reached?(byid[x], seen) } }
          open_doors = heads.call(free_doors).select { |id| reached_door.call(id) }
          open_exits = heads.call(free_exits).select { |id| reached_in.call(id) }
          far_places = heads.call(free_places).reject { |id| reached_in.call(id) }
          far_steps = heads.call(free_steps).reject { |id| reached_door.call(id) }
          moves = open_doors.map { |id| [:door, id] } + open_exits.map { |id| [:exit, id] }
          # dead end: reached doors all used up, places still out of reach
          return nil if moves.empty? && !(far_places.empty? && far_steps.empty?)
          if far_places.empty? && far_steps.empty?
            # everything reached: the rest can go anywhere (same sizes together)
            heads.call(free_doors).group_by { |id| size.call(id) }.each do |n, list|
              places = heads.call(free_places).select { |id| size.call(id) == n }.shuffle(random: rng)
              list.shuffle(random: rng).zip(places) { |o, p| link_in.call(o, p) if p }
            end
            unless coupled
              heads.call(free_exits).group_by { |id| size.call(id) }.each do |n, list|
                steps = heads.call(free_steps).select { |id| size.call(id) == n }.shuffle(random: rng)
                list.shuffle(random: rng).zip(steps) { |e, st| link_out.call(e, st) if st }
              end
            end
            return nil unless free_doors.empty? && free_exits.empty?
            break
          end
          moves.shuffle(random: rng).first(batch).each do |kind, id|
            n = size.call(id)
            if kind == :door
              next unless free_doors.include?(id)
              free_p = heads.call(free_places).select { |pid| size.call(pid) == n }
              far_p = far_places.select { |pid| size.call(pid) == n && free_places.include?(pid) }
              pool = far_p.empty? ? free_p : far_p
              # few doors open: spend them on places that give something or
              # lead on (a mart with the parcel, a gate), not on dead ends
              if open_doors.length <= 4 && !far_p.empty?
                want ||= wanted(d, edges, res)
                useful = pool.select { |pid| (groups[pid] || [pid]).any? { |x| (byid[x][:flags] || []).any? { |f| want[f] } } }
                rich = useful.empty? ? pool.select { |pid| (groups[pid] || [pid]).any? { |x| byid[x][:gives].to_i > 0 || byid[x][:siblings].to_i > 0 } } : useful
                pool = rich unless rich.empty?
              end
              next if pool.empty?
              link_in.call(id, pool[rng.rand(pool.length)])
            else
              next unless free_exits.include?(id)
              if coupled
                # a reached exit's doorstep is fixed by whoever leads in; with
                # nobody yet, pick the door for this place instead
                next unless free_places.include?(id)
                free_o = heads.call(free_doors).select { |o| size.call(o) == n }
                pool = far_steps.select { |o| size.call(o) == n && free_doors.include?(o) }
                pool = free_o if pool.empty?
                next if pool.empty?
                link_in.call(pool[rng.rand(pool.length)], id)
              else
                free_s = heads.call(free_steps).select { |st| size.call(st) == n }
                far_s = far_steps.select { |st| size.call(st) == n && free_steps.include?(st) }
                pool = far_s.empty? ? free_s : far_s
                next if pool.empty?
                link_out.call(id, pool[rng.rand(pool.length)])
              end
            end
          end
        end
        return [map_in, map_out]
      end

      # Simple: the doors of a place with several (a gate, a cave with two
      # ends) move together, onto another such place with as many doors
      def self.simple_groups(doors)
        groups = {}
        doors.group_by { |x| x[:to][0] }.each_value do |ds|
          next if ds.length < 2
          g = ds.sort_by { |x| [x[:tiles][0][1], x[:tiles][0][0]] }.map { |x| x[:id] }
          g.each { |id| groups[id] = g }
        end
        return groups
      end

      # Everything the unshuffled game reaches is reached, and every shuffled
      # door has both its doorstep and its place in reach: no door is cut off
      def self.complete?(d, doors, res)
        seen = res[:seen]
        return false unless doors.all? { |o| o[:out_edges].any? { |src, _| seen[src] } && seen[o[:in_node]] }
        reached = {}
        seen.each_key { |k| reached[node_map(k)] = true }
        return vanilla_maps(d).all? { |m| reached[m] }
      end

      def self.vanilla_maps(d)
        return d[:vanilla_maps] if d[:vanilla_maps]
        res = sweep(d, edges_for(d, {}, {}))
        maps = {}
        res[:seen].each_key { |k| maps[node_map(k)] = true }
        d[:vanilla_maps] = maps.keys
        return d[:vanilla_maps]
      end

      # A layout for the current settings, or nil when none was found
      def self.generate(seed_parts = [:entrances], random_start: false, origin_door: nil)
        d = dat
        return nil unless d
        shape = Rand.dget(:entrances)
        return nil if shape == 0
        doors = doors_for(d, Rand.dget(:ent_doors))
        coupled = Rand.dget(:ent_coupled) == 1
        rng = Random.new(Rand.sub_seed(*seed_parts))
        # Random start: made at the hand-over (see handover_target), from the
        # chosen Center, with exactly what the save has at that moment
        start_door = nil; start = nil; extra = []; cands = []
        if random_start
          cands = start_candidates(d, Rand.dget(:ent_start) == 1).shuffle(random: rng)
          start_door = cands.first
          if start_door
            start = start_door[:in_node]
            extra = current_flags(d)
          end
        elsif origin_door
          # Randomize now on a random-start save: the world still grows from
          # the start Center (and is measured from there for level scaling);
          # where the player stands is checked as usual
          start = origin_door[:in_node]
          extra = current_flags(d)
        end
        tries = (start_door.nil? && mid_run?) ? RETRIES_HERE : RETRIES
        tries.times do |i|
          Rand.progress(_INTL("Shuffling entrances... (try {1})", i + 1), 0.1 + 0.8 * i / tries) if Rand.respond_to?(:progress)
          # a start that keeps failing gives way to the next candidate
          if start_door && i > 0 && i % 5 == 0 && cands.length > 1
            start_door = cands[(i / 5) % cands.length]
            start = start_door[:in_node]
          end
          map_in = {}; map_out = {}
          groups = shape == 1 ? simple_groups(doors) : nil
          next unless grow(d, doors, rng, coupled, map_in, map_out, start, extra, groups)   # nil: dead end, try again
          next unless map_in.length == doors.length && map_out.length == doors.length
          edges = edges_for(d, map_in, map_out)
          res = sweep(d, edges, extra, nil, start)
          next unless beatable?(d, res[:seen])
          next unless complete?(d, doors, res)
          # mid-game: the player isn't in Pallet Town; from wherever they
          # may stand on the current map the end, and every place, must be
          # reachable too, with what the save really has
          next unless start_door || beatable_from_here?(d, edges, res, doors)
          regions = regions_on
          rsig = {}
          regions.each { |r| rsig[r] = (d[:region_sigs] || {})[r] if r != 0 }
          first = start_door || origin_door
          return { in: map_in, out: map_out, sig: d[:signature], rsig: rsig, regions: regions, attempts: i + 1, seen: [],
                   shape: shape, doors: Rand.dget(:ent_doors), coupled: coupled, spheres: door_spheres(d, map_in, res[:seen]),
                   start_door: first && first[:id], start_done: !first.nil?, progress: map_progress(res), pv: d[:progress_version],
                   nv: NEAR_VERSION, seed: Rand.seed }.merge(near_for(d, edges, res, start, start_door.nil?))
        end
        return nil
      end

      # Where the player stands, as nodes of the model (mid-run only: once the
      # Pokédex is in hand and the intro is over)
      def self.mid_run?
        return $game_map && $Trainer && $Trainer.has_pokedex && !$game_switches[SWITCH_DURING_INTRO]
      end

      # Every region of the current map the model knows (not only the ones the
      # layout reaches from the start: you may be standing in another one)
      def self.here_nodes
        return [] unless mid_run?
        return (map_nodes(dat)[$game_map.map_id.to_s] || []).reject { |k| k.include?(":g") }
      end

      def self.map_nodes(d)
        return d[:map_nodes] if d[:map_nodes]
        idx = Hash.new { |h, k| h[k] = [] }
        add = ->(n) { m = node_map(n); idx[m] << n unless idx[m].include?(n) }
        d[:edges].each { |k, v| add.call(k); v.each { |to, _| add.call(to) } }
        d[:doors].each { |o| add.call(o[:in_node]); add.call(o[:exit_node]) if o[:exit_node] }
        d[:map_nodes] = {}.merge(idx)
        return d[:map_nodes]
      end

      # The near-start counts for a new layout. Mid-run (Randomize now while
      # playing) "near" is measured from where you stand, with what you have,
      # and starts at your strongest Pokémon's level: everything you can walk
      # to right away is sized to your party, rising with every door
      def self.near_for(d, edges, res, start, may_be_here)
        best = ($Trainer.party.reject { |pk| pk.egg? rescue false }.map(&:level).max rescue nil) if $Trainer
        if may_be_here && mid_run?
          base = [NEAR_LEVEL, best || 0].max
          nodes = here_strict(d)
          unless nodes.empty?
            mine = current_flags(d)
            near = {}
            nodes.each do |n|
              r = sweep(d, edges, mine, nil, n)
              near_start(d, edges, r, n).each { |m, h| near[m] = h if near[m].nil? || h < near[m] }
            end
            return { near: near, near_base: base, near_here: true } unless near.empty?
          end
          return { near: near_start(d, edges, res, start), near_base: base }
        end
        return { near: near_start(d, edges, res, start), near_base: NEAR_LEVEL }
      end

      # The regions of this map you could be standing in: the ones with real
      # room around them in the doors you have now (tiny pockets - a tile
      # behind a ledge, an NPC's spot - aren't where a player stands). Worked
      # out once per Randomize now.
      def self.here_strict(d)
        key = [$game_map.map_id, state.object_id]
        return @here_strict[1] if @here_strict && @here_strict[0] == key
        s = state
        edges = (s.is_a?(Hash) && layout_current?(s)) ? edges_for(d, s[:in], s[:out]) : edges_for(d, {}, {})
        mine = current_flags(d)
        list = here_nodes.select { |n| sweep(d, edges, mine, nil, n)[:seen].length >= 20 }
        @here_strict = [key, list]
        return list
      end

      def self.beatable_from_here?(d, edges, res, doors = nil)
        return true unless mid_run?
        nodes = here_strict(d)
        return true if nodes.empty?   # not a place the model knows (an interior stair, a cutscene map)
        mine = current_flags(d)
        nb = mine.count { |f| badge_flag?(f) }
        all = flag_hash((d[:start_with] + mine).uniq, nb)
        home = res[:order].keys.first
        # Walking back to where the layout's own check started is enough
        # (from there the world was already checked, with no more than you
        # have); otherwise a sweep from that spot has to finish the game and
        # reach every place
        return nodes.all? { |n|
          next true if walks_to?(d, edges, n, home, all, nb)
          r = sweep(d, edges, mine, nil, n)
          beatable?(d, r[:seen]) && (doors.nil? || complete?(d, doors, r))
        }
      end

      # Can you walk from a to b with these flags (no new ones picked up)?
      def self.walks_to?(d, edges, a, b, all, badges)
        return true if a == b
        gates = d[:gates]
        seen = { a => true }
        queue = [a]
        until queue.empty?
          n = queue.shift
          (edges[n] || []).each do |to, req|
            next if seen[to]
            next unless req.all? { |r| satisfied?(r, all, gates, badges) }
            return true if to == b
            seen[to] = true
            queue << to
          end
        end
        return false
      end

      # The flags this save really has, read from the game state
      def self.current_flags(d)
        flags = {}
        d[:providers].each { |f, _w, needs| flags[f] = true; needs.each { |x| flags[x] = true } }
        out = []
        flags.each_key do |f|
          case f.to_s
          when /\Asw_(\d+)\z/ then out << f if $game_switches[$1.to_i]
          when /\Avar_(\d+)\z/ then v = $game_variables[$1.to_i]; out << f if v && v != 0 && v != ""
          when /\Abadge_(\d+)\z/ then out << f if $Trainer.badges[$1.to_i]
          when /\Aitem_(\w+)\z/
            sym = $1.to_sym
            out << f if $PokemonBag && GameData::Item.exists?(sym) && $PokemonBag.pbHasItem?(sym)
          end
        end
        return out
      rescue => e
        KIF.log("Entrances: current flags failed (#{e.class}: #{e.message})")
        return []
      end

      # Pokémon Center doors to start from: in a town, or on any outdoor map
      def self.start_candidates(d, towns_only)
        regions = regions_on
        d[:doors].select { |o|
          next false unless o[:pool] == :building && !NO_START.include?(o[:map])
          next false unless regions.include?(door_region(o))
          next false unless d[:names][o[:to][0]].to_s =~ /Pok[eé]mon Center/i
          !towns_only || d[:names][o[:map]].to_s =~ /City|Town|Island/
        }.sort_by { |o| o[:id] }
      end

      # How far into the game each map is: the share of all reached nodes
      # that came before its first node, in PROGRESS_BINS steps (0 = the
      # start, PROGRESS_BINS - 1 = the last places reached)
      PROGRESS_BINS = 40
      def self.map_progress(res)
        order = res[:order]
        total = [order.length, 1].max
        out = {}
        order.each do |node, k|
          mid = node.split(":")[0].to_i
          bin = (k * PROGRESS_BINS / total).to_i.clamp(0, PROGRESS_BINS - 1)
          out[mid] = bin if out[mid].nil? || bin < out[mid]
        end
        return out
      end

      # How many doors from the start each map is, for the maps you can reach
      # with nothing (sphere 0): fewest doors walked through on the way there.
      # Places that need a badge or key item first aren't counted (you get
      # there stronger anyway).
      NEAR_VERSION = 1
      NEAR_MAX = 30
      def self.near_start(d, edges, res, start = nil)
        seen = res[:seen]; all = res[:all]; gates = d[:gates]; badges = res[:badges]
        from = start || d[:start]
        hops = { from => 0 }
        front = [from]; back = []
        until front.empty? && back.empty?
          n = front.empty? ? back.shift : front.shift
          h = hops[n]
          next if h > NEAR_MAX
          (edges[n] || []).each do |to, req, door|
            next unless seen[to] == 0
            nh = h + (door ? 1 : 0)
            next if hops[to] && hops[to] <= nh
            next unless req.all? { |r| satisfied?(r, all, gates, badges) }
            hops[to] = nh
            door ? back << to : front.unshift(to)
          end
        end
        out = {}
        hops.each do |node, h|
          m = node.split(":")[0].to_i
          out[m] = h if out[m].nil? || h < out[m]
        end
        return out
      end

      # Sphere of each door: when its doorstep first comes into reach
      def self.door_spheres(d, map_in, seen)
        out = {}
        d[:doors].each do |o|
          s = o[:out_edges].map { |src, _n| seen[src] }.compact.min
          out[o[:id]] = s if s
        end
        return out
      end

      #-------------------------------------------------------------------------
      # Randomize now
      #-------------------------------------------------------------------------
      def self.randomize
        if Rand.dget(:entrances) == 0 || !available?
          # turning Entrances off mid-run: only where the normal doors can
          # still take you to the end
          if available? && active? && mid_run?
            d = dat
            edges = edges_for(d, {}, {})
            unless beatable_from_here?(d, edges, sweep(d, edges))
              pbMessage(_INTL("The normal doors can't get you to the end from here, so your doors stay shuffled. Try again somewhere else.")) if defined?(pbMessage)
              return
            end
          end
          Rand.data.delete(:ent_layout)
          return
        end
        if waiting_for_handover?
          # the layout is made when the starter is in hand (see handover_target)
          Rand.data.delete(:ent_layout)
          @targets = nil
          return
        end
        old = state
        new_seed = @seed_changed
        @seed_changed = false
        if !new_seed && same_layout?(old)
          old[:seed] ||= Rand.seed
          # nothing about the doors changed: keep them (and what you found)
          Rand.data[:ent_done] = true
          return
        end
        origin = old.is_a?(Hash) ? start_origin(old) : nil
        layout = generate([:entrances], origin_door: origin)
        Rand.progress_done if Rand.respond_to?(:progress_done)
        Rand.data[:ent_done] = true
        if layout
          Rand.data[:ent_layout] = layout
          @targets = nil
        elsif mid_run? && old.is_a?(Hash) && layout_current?(old)
          # nothing works from where you stand: keep the doors you have
          # (levels around you sized to your party all the same)
          begin
            d = dat
            e = edges_for(d, old[:in], old[:out])
            o = start_origin(old)
            st = o && o[:in_node]
            old.merge!(near_for(d, e, sweep(d, e, current_flags(d), nil, st), st, true))
          rescue => ex
            KIF.log("Entrance levels around you couldn't be redone (#{ex.class}: #{ex.message})")
          end
          pbMessage(_INTL("No new door layout works from where you're standing, so your doors stay as they are. Try again somewhere else.")) if defined?(pbMessage)
          KIF.log("Entrances: no layout from here after #{RETRIES_HERE} tries (seed #{Rand.seed}); kept the old one")
        else
          Rand.data.delete(:ent_layout)
          pbMessage(_INTL("No beatable entrance layout was found for this seed; entrances stay as they are.")) if defined?(pbMessage)
          KIF.log("Entrances: no beatable layout after #{RETRIES} tries (seed #{Rand.seed})")
        end
      end

      # Would a new shuffle give these same doors? (same data, seed and door
      # settings). Layouts from before the seed was stored count as the same seed.
      def self.same_layout?(s)
        return false unless s.is_a?(Hash) && dat && layout_current?(s)
        return false unless s[:shape] == Rand.dget(:entrances) && s[:doors] == Rand.dget(:ent_doors)
        return false unless s[:coupled] == (Rand.dget(:ent_coupled) == 1)
        return false unless (s[:regions] || [0]).sort == regions_on.sort
        return false if s[:seed] && s[:seed] != Rand.seed
        return true
      end

      # Where the journey started: the random start Center, or (saves whose
      # start got lost to an earlier Randomize now) the Center that is home
      def self.start_origin(s)
        d = dat
        return d[:door_by_id][s[:start_door]] if s[:start_door] && d[:door_by_id][s[:start_door]]
        return nil unless Rand.data[:ent_start_done] && $PokemonGlobal
        home = $PokemonGlobal.pokecenterMapId rescue nil
        return nil unless home && home > 0
        return d[:doors].find { |o| o[:to][0] == home && o[:pool] == :building }
      end

      # A new game picks its settings in the intro, where nothing is shuffled
      # yet: the layout is made at the first warp after it. Done once; later
      # changes go through Randomize now.
      def self.ensure_layout
        return if !$game_switches || $game_switches[SWITCH_DURING_INTRO]
        s = Rand.data[:ent_layout]
        if s.is_a?(Hash) && dat && !layout_current?(s) && !@sig_warned
          @sig_warned = true
          pbMessage(_INTL("The entrance data changed since this save's doors were shuffled. Doors are back to normal until you Randomize now."))
          return
        end
        # saves from the first version made a random-start layout before the
        # Pokédex and waited for it; that layout assumed the errand was done
        if s.is_a?(Hash) && s[:start_door] && !s[:start_done] && waiting_for_handover?
          Rand.data.delete(:ent_layout)
          @targets = nil
          return
        end
        return if Rand.data[:ent_done] || s
        return unless Rand.dget(:entrances) > 0 && available?
        return if waiting_for_handover?
        Rand.data[:ent_done] = true
        randomize
      rescue => e
        KIF.log("Entrance layout at intro end failed (#{e.class}: #{e.message})")
      end

      #-------------------------------------------------------------------------
      # Runtime
      #-------------------------------------------------------------------------
      # [map, event] => [map, x, y, dir, door id, :in/:out]
      def self.targets
        return @targets if @targets && @targets_sig == state.object_id
        @targets = {}
        @targets_sig = state.object_id
        return @targets unless active?
        d = dat; byid = d[:door_by_id]; s = state
        d[:doors].each do |o|
          i = byid[s[:in][o[:id]] || o[:id]] || o
          if i[:id] != o[:id]
            o[:events].each { |e| @targets[[o[:map], e]] = [i[:to][0], i[:to][1], i[:to][2], i[:to_dir], o[:id], :in, o[:to]] }
          end
          back = byid[s[:out][o[:id]] || o[:id]] || o
          if back[:id] != o[:id]
            o[:exit_events].each { |e| @targets[[o[:exit_map], e]] = [back[:exit_to][0], back[:exit_to][1], back[:exit_to][2], back[:exit_dir], o[:id], :out, o[:exit_to]] }
          end
        end
        return @targets
      end

      # Only the door's own transfer is redirected: an event can hold other
      # transfers too (a common event it calls, a page for a story scene),
      # so the transfer must go where this door always went
      def self.target(map_id, event_id, params = nil)
        return nil unless active?
        t = targets[[map_id, event_id]]
        return nil unless t
        return nil if params && params[1, 3] != t[6]
        return t
      end

      #-------------------------------------------------------------------------
      # Random start. Oak's errand (the parcel from the Viridian Mart) can't be
      # counted on once doors are shuffled, so it is skipped: with the starter
      # in hand, the next door the player takes hands over the Pokédex and
      # five Poké Balls the way Oak would, the layout is made from the start
      # Center with exactly what the save has then, and the door leads there.
      #-------------------------------------------------------------------------
      def self.waiting_for_handover?
        return false unless Rand.dget(:entrances) > 0 && Rand.dget(:ent_start) > 0
        return false if Rand.data[:ent_start_done]
        return false unless $Trainer && !$Trainer.has_pokedex
        return true
      end

      # Oak's parcel scene, as its switches leave the game: parcel received
      # (220), Pokédex given (988, 59), Oak on his after-Pokédex page (self B)
      OAK_EVENT = 7
      def self.give_pokedex
        $game_switches[220] = true
        $game_switches[988] = true
        $game_switches[59] = true
        OAK_LABS.each { |lab| $game_self_switches[[lab, OAK_EVENT, "B"]] = true }
        $PokemonBag.pbDeleteItem(:OAKSPARCEL) if $PokemonBag.pbHasItem?(:OAKSPARCEL)
        $PokemonBag.pbStoreItem(:POKEBALL, 5)
        $Trainer.has_pokedex = true
        pbUnlockDex rescue nil
        $game_map.need_refresh = true if $game_map
      end

      def self.handover_target(map_id, params)
        return nil unless params[0] == 0 && params[1] != map_id && waiting_for_handover? && available?
        return nil if $game_switches[SWITCH_DURING_INTRO]
        return nil if $Trainer.party.empty?
        give_pokedex
        Rand.data[:ent_start_done] = true
        Rand.data[:ent_done] = true
        layout = generate([:entrances], random_start: true)
        Rand.progress_done if Rand.respond_to?(:progress_done)
        unless layout && layout[:start_door]
          # no start Center worked: shuffle as usual from where the player is
          layout = generate
          Rand.progress_done if Rand.respond_to?(:progress_done)
          if layout
            Rand.data[:ent_layout] = layout
            @targets = nil
          end
          @handover_msg = [:dex_only]
          return nil
        end
        Rand.data[:ent_layout] = layout
        @targets = nil
        o = dat[:door_by_id][layout[:start_door]]
        @new_home = [o[:to][0], o[:to][1], o[:to][2], o[:to_dir]]
        @handover_msg = [:start, dat[:names][o[:map]]]
        return [o[:to][0], o[:to][1], o[:to][2], o[:to_dir], nil, :start]
      rescue => e
        KIF.log("Random start hand-over failed (#{e.class}: #{e.message})")
        # doors get shuffled the usual way at this warp instead
        Rand.data[:ent_done] = nil
        @handover_msg = [:dex_only] if $Trainer && $Trainer.has_pokedex
        return nil
      end

      def self.show_handover_message
        m = @handover_msg
        return unless m
        @handover_msg = nil
        pbMessage(_INTL("\\me[Key item get]Professor Oak sent you the Pokédex and 5 Poké Balls!"))
        pbMessage(_INTL("Your journey starts in {1}.", m[1])) if m[0] == :start
      end

      class << self
        attr_accessor :new_home, :handover_msg
      end

      # After arriving: the Center becomes home (where you wake up after a loss)
      def self.settle_home
        h = @new_home
        return unless h
        @new_home = nil
        $PokemonGlobal.pokecenterMapId = h[0]
        $PokemonGlobal.pokecenterX = h[1]
        $PokemonGlobal.pokecenterY = h[2]
        $PokemonGlobal.pokecenterDirection = h[3] == 0 ? 2 : h[3]
      rescue => e
        KIF.log("Random start home failed (#{e.class}: #{e.message})")
      end

      #-------------------------------------------------------------------------
      # Level scaling: trainers are as strong as vanilla trainers met at the
      # same point of the game. Progress = how far into the reachable world a
      # map is (see map_progress); the data file carries each map's vanilla
      # progress and the vanilla level curve over progress.
      #-------------------------------------------------------------------------
      def self.scaling?
        return active? && Rand.dget(:ent_levels) >= 1 && state[:progress].is_a?(Hash) && dat[:level_curve]
      end

      def self.wild_scaling?
        return scaling? && Rand.dget(:ent_levels) == 2
      end

      # One Pokémon to a new level by the map's factor; moves picked by level
      # follow it unless `keep_moves`
      def self.rescale(pkmn, f, keep_moves = false, cap = nil)
        old = pkmn.level
        lv = (old * f).round.clamp(1, GameData::GrowthRate.max_level)
        lv = [lv, cap].min if cap
        return if lv == old
        natural = keep_moves ? nil : (pkmn.getMoveList.select { |m| m[0] <= old }.map { |m| m[1] }.last(4) rescue nil)
        pkmn.level = lv
        pkmn.calc_stats
        pkmn.reset_moves if natural && pkmn.moves.map(&:id).sort == natural.uniq.sort
      end

      def self.scale_wild(pkmn, map_id = nil)
        return unless pkmn && wild_scaling?
        map_id ||= $game_map ? $game_map.map_id : nil
        return unless map_id
        f = level_factor(map_id)
        cap = level_cap(map_id)
        return if (f - 1.0).abs < 0.02 && !(cap && pkmn.level > cap)
        rescale(pkmn, f, false, cap)
      rescue => e
        KIF.log("Wild level scaling failed (#{e.class}: #{e.message})")
      end

      # How far into the game each map sits in this layout. The bins depend on
      # the data file's model of the world; a layout made with an older one
      # gets them worked out again, once, so its levels match the new curve
      def self.layout_progress
        s = state; d = dat
        return s[:progress] if (d[:progress_version].nil? || s[:pv] == d[:progress_version]) && s[:nv] == NEAR_VERSION
        start = nil; extra = []
        if (o = start_origin(s))
          start = o[:in_node]
          extra = current_flags(d)
          s[:start_door] ||= o[:id]
        end
        edges = edges_for(d, s[:in], s[:out])
        res = sweep(d, edges, extra, nil, start)
        s[:progress] = map_progress(res)
        s[:near] = near_start(d, edges, res, start) unless s[:near_here]
        s[:pv] = d[:progress_version]
        s[:nv] = NEAR_VERSION
        return s[:progress]
      rescue => e
        KIF.log("Entrance level bins couldn't be updated (#{e.class}: #{e.message})")
        return s[:progress] || {}
      end

      def self.level_factor(map_id)
        return 1.0 unless scaling?
        van = dat[:map_progress][map_id]
        now = layout_progress[map_id]
        return 1.0 unless van && now && van != now
        curve = dat[:level_curve]
        a = curve[van]; b = curve[now]
        return 1.0 unless a && b && a > 0
        return (b / a.to_f).clamp(0.05, 3.0)
      end

      # Near the start nothing outlevels a fresh starter: on the maps you can
      # reach with nothing, no Pokémon is above NEAR_LEVEL at the start and one
      # door out, plus NEAR_STEP for every door after that. Trainers there are
      # also never above your strongest Pokémon (the start Center's way out
      # can lead straight into a trainer who won't let you pass)
      NEAR_LEVEL = 6
      NEAR_STEP  = 2
      NEAR_PARTY = 1   # doors from the start where your party's level caps trainers too
      def self.near_hops(map_id)
        return nil unless scaling?
        layout_progress
        return (state[:near] || {})[map_id]
      end

      def self.level_cap(map_id)
        h = near_hops(map_id)
        return nil unless h
        return (state[:near_base] || NEAR_LEVEL) + NEAR_STEP * [h - 1, 0].max
      end

      def self.trainer_cap(map_id)
        cap = level_cap(map_id)
        return nil unless cap
        if near_hops(map_id) <= NEAR_PARTY && $Trainer
          best = $Trainer.party.reject { |pk| pk.egg? rescue false }.map(&:level).max
          cap = [cap, best].min if best
        end
        return cap
      end

      def self.scale_trainer(trainer, map_id = nil)
        return trainer unless trainer && scaling?
        # Endgame Challenge teams are already tuned to your party (Lv100)
        return trainer if defined?(KIF::Endgame) && KIF::Endgame.on? && KIF::Endgame.challenge_map?
        map_id ||= $game_map ? $game_map.map_id : nil
        return trainer unless map_id
        f = level_factor(map_id)
        cap = trainer_cap(map_id)
        return trainer if (f - 1.0).abs < 0.02 && !(cap && trainer.party.any? { |pk| pk.level > cap })
        # moves picked by level follow it; a hand-written set stays
        trainer.party.each { |pkmn| rescale(pkmn, f, false, cap) }
        return trainer
      rescue => e
        KIF.log("Level scaling failed (#{e.class}: #{e.message})")
        return trainer
      end

      def self.start_name
        s = state
        return nil unless s && s[:start_door]
        o = dat[:door_by_id][s[:start_door]]
        return o && dat[:names][o[:map]]
      end

      # Remember a door the player used (for the Entrance log)
      def self.note(door_id, kind)
        s = state
        return unless s
        s[:seen] ||= []
        key = [door_id, kind]
        s[:seen] << key unless s[:seen].include?(key)
      end

      def self.door_name(o)
        return "#{dat[:names][o[:map]]} - #{o[:label]}"
      end

      def self.place_name(o)
        return dat[:names][o[:to][0]].to_s
      end

      # "Viridian City - Gym -> Pewter City - Museum (door 1)"
      def self.describe(door_id, kind = :in)
        d = dat; s = state
        return "" unless d && s
        o = d[:door_by_id][door_id]
        return "" unless o
        if kind == :in
          i = d[:door_by_id][s[:in][door_id] || door_id]
          return _INTL("{1} -> inside {2}", door_name(o), door_name(i))
        else
          back = d[:door_by_id][s[:out][door_id] || door_id]
          return _INTL("leaving {1} -> {2}", door_name(o), door_name(back))
        end
      end

      # Lines for the spoiler log, by sphere
      def self.log_lines
        d = dat; s = state
        return [] unless d && s
        out = []
        out << _INTL("Settings: {1}, {2}, {3}", LABELS[:entrances][1][s[:shape] || 2], LABELS[:ent_doors][1][s[:doors] || 2],
                     s[:coupled] ? _INTL("coupled") : _INTL("decoupled"))
        regions = (s[:regions] || [0]).map { |r| REGION_NAMES[r] || r.to_s }
        out << _INTL("Regions: {1}", regions.join(" + ")) if regions.length > 1
        out << _INTL("Start: {1}", start_name) if start_name
        out << (wild_scaling? ? _INTL("Level scaling: trainers and wild Pokémon follow how far into the game their map is") :
                                _INTL("Level scaling: trainers follow how far into the game their map is")) if scaling?
        out << _INTL("Found so far: {1} of {2} doors", (s[:seen] || []).map(&:first).uniq.length, s[:in].length)
        sph = s[:spheres] || {}
        d[:doors].sort_by { |o| [sph[o[:id]] || 99, d[:names][o[:map]].to_s, o[:tiles][0][1], o[:tiles][0][0]] }.each do |o|
          next unless s[:in].key?(o[:id])
          i = d[:door_by_id][s[:in][o[:id]]]
          back = d[:door_by_id][s[:out][i[:id]] || i[:id]]
          line = "#{sph[o[:id]] ? "Sphere #{sph[o[:id]]}: " : "Unreached: "}#{door_name(o)} -> #{door_name(i)}"
          line << " (back: #{door_name(back)})" unless back[:id] == o[:id]
          out << line
        end
        return out
      end
    end
  end
end

#-------------------------------------------------------------------------------
# The warp hook
#-------------------------------------------------------------------------------
class Interpreter
  alias kif_ent_command_201 command_201 unless method_defined?(:kif_ent_command_201)

  def command_201
    t = nil
    begin
      if @parameters[0] == 0 && $PokemonGlobal && !$game_temp.in_battle
        t = KIF::Rand::ER.handover_target(@map_id, @parameters)
        KIF::Rand::ER.ensure_layout unless t
        t ||= KIF::Rand::ER.target(@map_id, @event_id, @parameters)
      end
    rescue => e
      KIF.log("Entrance lookup failed (#{e.class}: #{e.message})")
      t = nil
    end
    return kif_ent_command_201 unless t
    saved = @parameters
    @parameters = [0, t[0], t[1], t[2], t[3], saved[5]]
    begin
      r = kif_ent_command_201
    ensure
      @parameters = saved
    end
    begin
      KIF::Rand::ER.note(t[4], t[5]) if $game_temp.player_transferring && t[4]
    rescue => e
      KIF.log("Entrance log note failed (#{e.class}: #{e.message})")
    end
    return r
  end
end

#-------------------------------------------------------------------------------
# Randomize now runs the shuffle after everything else
#-------------------------------------------------------------------------------
module KIF
  module Rand
    class << self
      alias kif_ent_randomize_now randomize_now unless method_defined?(:kif_ent_randomize_now)
      def randomize_now
        ER.seed_changed = (changed?(:__seed) rescue false)
        kif_ent_randomize_now
      ensure
        begin
          had = !data[:ent_layout].nil?
          ER.randomize
          write_log if had || data[:ent_layout]   # the log written above has no entrances yet
        rescue => e
          KIF.log("Entrance shuffle failed (#{e.class}: #{e.message})")
        end
      end
    end
  end
end

#-------------------------------------------------------------------------------
# Level scaling: every trainer loaded for a battle
#-------------------------------------------------------------------------------
class Object
  alias kif_ent_pbLoadTrainer pbLoadTrainer unless method_defined?(:kif_ent_pbLoadTrainer) || private_method_defined?(:kif_ent_pbLoadTrainer)

  def pbLoadTrainer(tr_type, tr_name, tr_version = 0)
    trainer = kif_ent_pbLoadTrainer(tr_type, tr_name, tr_version)
    return KIF::Rand::ER.scale_trainer(trainer)
  end
end

#-------------------------------------------------------------------------------
# Level scaling: wild Pokémon (grass, water, statics - every wild battle)
#-------------------------------------------------------------------------------
Events.onWildPokemonCreate += proc { |_sender, e|
  KIF::Rand::ER.scale_wild(e[0]) if e.is_a?(Array)
}
