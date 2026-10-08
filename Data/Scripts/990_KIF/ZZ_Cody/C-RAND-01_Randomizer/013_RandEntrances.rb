#===============================================================================
# C-RAND-01 – Randomizer: Entrances (Cody, 2026-10-07)
#   Doors between Kanto's outdoor maps and the places behind them are
#   shuffled (Johto's too with "And Johto?", mixed with Kanto's). The layout is built at Randomize now from Data/KIF/entrances.dat
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
      [:ent_johto, :enum, 2]      # Off / On: Johto's doors join the shuffle
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

    DATA_DEFAULTS[:ent_coupled] = 1   # Coupled unless switched off

    module ER
      DATA_PATH = "Data/KIF/entrances.dat"
      RETRIES = 100   # a try takes ~0.05 s; Simple needs ~5 on average
      BADGE_PREFIX = "badge_"
      OAK_LABS = [77, 551, 552, 593, 659, 724, 740, 847]   # every variant of Oak's Lab
      NO_START = [303, 167]   # Indigo Plateau, Crimson City (nowhere to go without 8 badges)

      class << self
        attr_accessor :dat_cache, :dat_failed
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
      # reached stays reached, so only the new edges need following.
      def self.sweep(d, edges, extra = [], from = nil, start = nil, stop_at = nil)
        gates = d[:gates]
        have = from ? from[:have].dup : (d[:start_with] + extra).uniq
        have_h = {}
        have.each { |f| have_h[f] = true }
        seen = from ? from[:seen].dup : {}
        order = from ? from[:order].dup : {}   # node => how many nodes were reached before it
        sphere = from ? from[:spheres] - 1 : 0
        seen[start || d[:start]] ||= sphere
        order[start || d[:start]] ||= 0
        badges = have.count { |f| badge_flag?(f) }
        loop do
          break if stop_at && have_h[stop_at]
          rb = badges   # what this round's checks see; gains count from the next round
          all = flag_hash(have, rb)
          queue = seen.keys
          now = {}
          queue.each { |k| now[k] = true }
          until queue.empty?
            n = queue.shift
            (edges[n] || []).each do |to, req|
              next if now[to]
              next unless req.all? { |r| satisfied?(r, all, gates, rb) }
              now[to] = true
              seen[to] ||= sphere
              order[to] ||= order.length
              queue << to
            end
          end
          gained = false
          key = false   # a badge or a key item: what makes a new sphere
          maps_now = {}
          now.each_key { |k| maps_now[node_map(k)] = true }
          d[:providers].each do |flag, where, needs|
            next if have_h[flag]
            if where.is_a?(Symbol)
              next unless maps_now[where.to_s[1..-1]]
            else
              next unless where.any? { |n| now[n] }
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
        end
        return { seen: seen, order: order, have: have, all: flag_hash(have, badges), badges: badges, spheres: sphere + 1 }
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
            o[:out_edges].each { |src, needs| (edges[src] ||= []) << [i[:in_node], needs] }
          end
          unless wait && !map_out.key?(o[:id])
            back = byid[map_out[o[:id]] || o[:id]]
            o[:exit_edges].each { |src, needs| (edges[src] ||= []) << [back[:exit_node], needs] }
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
      def self.grow(d, doors, rng, coupled, map_in = {}, map_out = {}, start = nil, extra = [])
        ids = doors.map { |x| x[:id] }
        free_doors = ids - map_in.keys                   # doors without a place
        free_places = ids - map_in.values                # places nobody leads into
        free_exits = ids - map_out.keys                  # exits without a doorstep
        free_steps = ids - map_out.values                # doorsteps nobody comes out on
        byid = d[:door_by_id]
        pending = {}
        ids.each { |id| pending[id] = true }
        batch = 6
        res = nil
        loop do
          break if free_doors.empty? && free_exits.empty?
          edges = edges_for(d, map_in, map_out, pending)
          res = sweep(d, edges, extra, res, start)
          seen = res[:seen]
          want = nil
          open_doors = free_doors.select { |id| door_reached?(byid[id], res) }
          open_exits = free_exits.select { |id| inside_reached?(byid[id], seen) }
          far_places = free_places.reject { |id| inside_reached?(byid[id], seen) }
          far_steps = free_steps.reject { |id| door_reached?(byid[id], res) }
          moves = open_doors.map { |id| [:door, id] } + open_exits.map { |id| [:exit, id] }
          # dead end: reached doors all used up, places still out of reach
          return nil if moves.empty? && !(far_places.empty? && far_steps.empty?)
          if far_places.empty? && far_steps.empty?
            # everything reached: the rest can go anywhere
            free_doors.shuffle(random: rng).zip(free_places.shuffle(random: rng)) do |o, p|
              map_in[o] = p
              map_out[p] = o if coupled
            end
            unless coupled
              free_exits.shuffle(random: rng).zip(free_steps.shuffle(random: rng)) { |e, s| map_out[e] = s }
            end
            break
          end
          moves.shuffle(random: rng).first(batch).each do |kind, id|
            if kind == :door
              next unless free_doors.include?(id)
              pool = far_places.empty? ? free_places : far_places
              # few doors open: spend them on places that give something or
              # lead on (a mart with the parcel, a gate), not on dead ends
              if open_doors.length <= 4 && !far_places.empty?
                want ||= wanted(d, edges, res)
                useful = pool.select { |pid| (byid[pid][:flags] || []).any? { |f| want[f] } }
                rich = useful.empty? ? pool.select { |pid| byid[pid][:gives].to_i > 0 || byid[pid][:siblings].to_i > 0 } : useful
                pool = rich unless rich.empty?
              end
              next if pool.empty?
              p = pool[rng.rand(pool.length)]
              map_in[id] = p
              free_doors.delete(id); free_places.delete(p); far_places.delete(p)
              if coupled
                map_out[p] = id
                free_exits.delete(p); free_steps.delete(id); far_steps.delete(id)
              end
            else
              next unless free_exits.include?(id)
              if coupled
                # a reached exit's doorstep is fixed by whoever leads in; with
                # nobody yet, pick the door for this place instead
                next unless free_places.include?(id)
                pool = far_steps.empty? ? free_doors : (far_steps & free_doors)
                pool = free_doors if pool.empty?
                next if pool.empty?
                o = pool[rng.rand(pool.length)]
                map_in[o] = id; map_out[id] = o
                free_doors.delete(o); free_places.delete(id); far_places.delete(id)
                free_exits.delete(id); free_steps.delete(o); far_steps.delete(o)
              else
                pool = far_steps.empty? ? free_steps : far_steps
                next if pool.empty?
                s = pool[rng.rand(pool.length)]
                map_out[id] = s
                free_exits.delete(id); free_steps.delete(s); far_steps.delete(s)
              end
            end
          end
        end
        return [map_in, map_out]
      end

      # Simple: a place with several doors (a gate, a cave with two ends)
      # trades all its doors with another place that has as many. These are
      # fixed first, at random; the single doors then grow around them.
      def self.simple_places(d, doors, rng, coupled)
        map_in = {}; map_out = {}
        places = doors.group_by { |x| x[:to][0] }.values.select { |ds| ds.length > 1 }
        places.group_by(&:length).each_value do |same|
          perm = same.shuffle(random: rng)
          same.zip(perm) do |from, to|
            from = from.sort_by { |x| [x[:tiles][0][1], x[:tiles][0][0]] }
            to = to.sort_by { |x| [x[:tiles][0][1], x[:tiles][0][0]] }
            from.zip(to) do |o, p|
              map_in[o[:id]] = p[:id]
              map_out[p[:id]] = o[:id] if coupled
            end
          end
          unless coupled
            exits = same.flatten.map { |x| x[:id] }
            exits.zip(exits.shuffle(random: rng)) { |e, s| map_out[e] = s }
          end
        end
        return [map_in, map_out]
      end

      # A layout for the current settings, or nil when none was found
      def self.generate(seed_parts = [:entrances], random_start: false)
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
        end
        RETRIES.times do |i|
          Rand.progress(_INTL("Shuffling entrances... (try {1})", i + 1), 0.1 + 0.8 * i / RETRIES) if Rand.respond_to?(:progress)
          # a start that keeps failing gives way to the next candidate
          if start_door && i > 0 && i % 5 == 0 && cands.length > 1
            start_door = cands[(i / 5) % cands.length]
            start = start_door[:in_node]
          end
          map_in, map_out = shape == 1 ? simple_places(d, doors, rng, coupled) : [{}, {}]
          next unless grow(d, doors, rng, coupled, map_in, map_out, start, extra)   # nil: dead end, try again
          next unless map_in.length == doors.length && map_out.length == doors.length
          edges = edges_for(d, map_in, map_out)
          res = sweep(d, edges, extra, nil, start)
          next unless beatable?(d, res[:seen])
          # mid-game: the player isn't in Pallet Town; from wherever they
          # stand on the current map the end must be reachable too (every
          # region of that map the layout reaches, with everything gathered
          # so far assumed from scratch - conservative)
          next unless start_door || beatable_from_here?(d, edges, res)
          regions = regions_on
          rsig = {}
          regions.each { |r| rsig[r] = (d[:region_sigs] || {})[r] if r != 0 }
          return { in: map_in, out: map_out, sig: d[:signature], rsig: rsig, regions: regions, attempts: i + 1, seen: [],
                   shape: shape, doors: Rand.dget(:ent_doors), coupled: coupled, spheres: door_spheres(d, map_in, res[:seen]),
                   start_door: start_door && start_door[:id], start_done: !start_door.nil?, progress: map_progress(res) }
        end
        return nil
      end

      def self.beatable_from_here?(d, edges, res)
        return true unless $game_map && $Trainer && $Trainer.has_pokedex && !$game_switches[SWITCH_DURING_INTRO]
        here = "#{$game_map.map_id}:"
        nodes = res[:seen].keys.select { |k| k.start_with?(here) && !k.include?(":g") }.first(12)
        return true if nodes.empty?   # not a place the model knows (an interior stair, a cutscene map)
        mine = current_flags(d)
        # tiny pockets (a tile behind a ledge, an NPC's spot) aren't where the
        # player is; every region with some reach of its own must get there
        return nodes.all? { |n| r = sweep(d, edges, mine, nil, n); r[:seen].length < 20 || beatable?(d, r[:seen]) }
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
          Rand.data.delete(:ent_layout)
          return
        end
        if waiting_for_handover?
          # the layout is made when the starter is in hand (see handover_target)
          Rand.data.delete(:ent_layout)
          @targets = nil
          return
        end
        layout = generate
        Rand.progress_done if Rand.respond_to?(:progress_done)
        Rand.data[:ent_done] = true
        if layout
          Rand.data[:ent_layout] = layout
          @targets = nil
        else
          Rand.data.delete(:ent_layout)
          pbMessage(_INTL("No beatable entrance layout was found for this seed; entrances stay as they are.")) if defined?(pbMessage)
          KIF.log("Entrances: no beatable layout after #{RETRIES} tries (seed #{Rand.seed})")
        end
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
      def self.rescale(pkmn, f, keep_moves = false)
        old = pkmn.level
        lv = (old * f).round.clamp(1, GameData::GrowthRate.max_level)
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
        return if (f - 1.0).abs < 0.02
        rescale(pkmn, f)
      rescue => e
        KIF.log("Wild level scaling failed (#{e.class}: #{e.message})")
      end

      def self.level_factor(map_id)
        return 1.0 unless scaling?
        van = dat[:map_progress][map_id]
        now = state[:progress][map_id]
        return 1.0 unless van && now && van != now
        curve = dat[:level_curve]
        a = curve[van]; b = curve[now]
        return 1.0 unless a && b && a > 0
        return (b / a.to_f).clamp(0.3, 3.0)
      end

      def self.scale_trainer(trainer, map_id = nil)
        return trainer unless trainer && scaling?
        map_id ||= $game_map ? $game_map.map_id : nil
        return trainer unless map_id
        f = level_factor(map_id)
        return trainer if (f - 1.0).abs < 0.02
        # moves picked by level follow it; a hand-written set stays
        trainer.party.each { |pkmn| rescale(pkmn, f) }
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
