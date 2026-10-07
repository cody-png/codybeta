#===============================================================================
# C-RAND-01 – Randomizer: Entrances (Cody, 2026-10-07)
#   Doors between Kanto's outdoor maps and the places behind them are
#   shuffled. The layout is built at Randomize now from Data/KIF/entrances.dat
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
      [:ent_coupled, :enum, 2],   # Off / On (default On, see dget below)
      [:ent_hints, :enum, 2],     # Off / On
      [:ent_start, :enum, 3]      # Pallet / Random town / Random map
    ]
    ENT_SETTINGS.each { |st| DATA_SETTINGS << st unless DATA_KEYS.include?(st[0]) }
    ENT_SETTINGS.each { |st| DATA_KEYS << st[0] unless DATA_KEYS.include?(st[0]) }
    LABELS[:entrances] = ["Entrances", ["Off", "Simple", "Full"]]
    LABELS[:ent_doors] = ["Which doors", ["Dungeons", "Buildings", "Everything"]]
    LABELS[:ent_coupled] = ["Coupled", ["Off", "On"]]
    LABELS[:ent_hints] = ["Door hints", ["Off", "On"]]
    LABELS[:ent_start] = ["Start", ["Pallet", "Random town", "Random map"]]

    DATA_DEFAULTS[:ent_coupled] = 1   # Coupled unless switched off

    module ER
      DATA_PATH = "Data/KIF/entrances.dat"
      RETRIES = 40
      BADGE_PREFIX = "badge_"
      POKEDEX_FLAG = :sw_988           # set by Oak when he hands over the Pokédex
      OAK_LABS = [77, 551, 552, 593, 659, 724, 740, 847]
      PALLET = 42
      INDIGO = 303
      NO_START = [303, 167]   # Indigo Plateau, Crimson City (nowhere to go without 8 badges)

      class << self
        attr_accessor :dat_cache
      end

      # The compiled world, loaded once per session
      def self.dat
        return @dat_cache if @dat_cache
        return nil unless FileTest.exist?(DATA_PATH)
        @dat_cache = Marshal.load(File.binread(DATA_PATH))
        @dat_cache[:door_by_id] = {}
        @dat_cache[:doors].each { |d| @dat_cache[:door_by_id][d[:id]] = d }
        return @dat_cache
      rescue => e
        KIF.log("Entrances data couldn't be read (#{e.class}: #{e.message})")
        return nil
      end

      def self.available?
        return !dat.nil?
      end

      def self.state
        return Rand.data[:ent_layout]
      end

      # The layout in use, if it belongs to this data file
      def self.active?
        s = state
        return false unless s.is_a?(Hash) && s[:in].is_a?(Hash) && !s[:in].empty?
        return false unless dat && s[:sig] == dat[:signature]
        return true
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

      # `have` is a Hash of flags (fast lookups); badges = how many
      def self.gate_open?(lifts, have, badges)
        return false unless lifts
        return lifts.any? { |set| !set.empty? && set.all? { |s|
          case s
          when Integer then have.include?(:"sw_#{s}")
          when Symbol then have.include?(s) || (s.to_s =~ /\Abadges_(\d+)\z/ && badges >= $1.to_i)
          else s.to_s =~ /\Avar(\d+)>=/ ? have.include?(:"var_#{$1}") : s.to_s.start_with?("self")
          end } }
      end

      def self.satisfied?(req, have, gates, badges)
        return true if have.include?(req)
        return badges >= $1.to_i if req.to_s =~ /\Abadges_(\d+)\z/
        return gate_open?(gates[req], have, badges) if req.to_s.start_with?("npc_")
        return false
      end

      def self.flag_hash(have, badges)
        h = {}
        have.each { |f| h[f] = true }
        abilities(have, badges).each { |f| h[f] = true }
        return h
      end

      # Repeat: reach what you can, collect what it gives, until nothing new.
      # Returns seen (node => sphere), have (flags), spheres count.
      # `from` continues an earlier sweep of a graph that has only gained
      # edges since (the shuffler adds doors one batch at a time): what was
      # reached stays reached, so only the new edges need following.
      def self.sweep(d, edges, extra = [], from = nil, start = nil, stop_at = nil)
        gates = d[:gates]
        have = from ? from[:have].dup : (d[:start_with] + extra).uniq
        seen = from ? from[:seen].dup : {}
        sphere = from ? from[:spheres] - 1 : 0
        seen[start || d[:start]] ||= sphere
        loop do
          break if stop_at && have.include?(stop_at)
          badges = have.count { |f| f.to_s.start_with?(BADGE_PREFIX) }
          all = flag_hash(have, badges)
          queue = seen.keys
          now = {}
          queue.each { |k| now[k] = true }
          until queue.empty?
            n = queue.shift
            (edges[n] || []).each do |to, req|
              next if now[to]
              next unless req.all? { |r| satisfied?(r, all, gates, badges) }
              now[to] = true
              seen[to] ||= sphere
              queue << to
            end
          end
          gained = false
          maps_now = {}
          now.each_key { |k| maps_now[k.split(":")[0]] = true }
          d[:providers].each do |flag, where, needs|
            next if have.include?(flag)
            if where.is_a?(Symbol)
              next unless maps_now[where.to_s[1..-1]]
            else
              next unless where.any? { |n| now[n] }
            end
            next unless needs.all? { |f| satisfied?(f, all, gates, badges) }
            have << flag
            gained = true
          end
          break unless gained
          sphere += 1
        end
        badges = have.count { |f| f.to_s.start_with?(BADGE_PREFIX) }
        return { seen: seen, have: have, all: flag_hash(have, badges), badges: badges, spheres: sphere + 1 }
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
      def self.doors_for(d, which)
        case which
        when 0 then d[:doors].select { |x| x[:pool] == :dungeon }
        when 1 then d[:doors].select { |x| x[:pool] == :building }
        else d[:doors]
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
      def self.generate(seed_parts = [:entrances])
        d = dat
        return nil unless d
        shape = Rand.dget(:entrances)
        return nil if shape == 0
        doors = doors_for(d, Rand.dget(:ent_doors))
        coupled = Rand.dget(:ent_coupled) == 1
        rng = Random.new(Rand.sub_seed(*seed_parts))
        # Random start: picked once per seed; only for a game that hasn't got
        # its Pokédex yet (the move happens when Oak hands it over)
        start_door = nil; start = nil; extra = []; cands = []
        if Rand.dget(:ent_start) > 0 && !($Trainer && $Trainer.has_pokedex)
          cands = start_candidates(d, Rand.dget(:ent_start) == 1).shuffle(random: rng)
          start_door = cands.first
          if start_door
            start = start_door[:in_node]
            extra = pre_dex_flags(d)
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
          res = sweep(d, edges_for(d, map_in, map_out), extra, nil, start)
          next unless beatable?(d, res[:seen])
          return { in: map_in, out: map_out, sig: d[:signature], attempts: i + 1, seen: [],
                   shape: shape, doors: Rand.dget(:ent_doors), coupled: coupled, spheres: door_spheres(d, map_in, res[:seen]),
                   start_door: start_door && start_door[:id], start_done: false }
        end
        return nil
      end

      # Pokémon Center doors to start from: in a town, or on any outdoor map
      def self.start_candidates(d, towns_only)
        d[:doors].select { |o|
          next false unless o[:pool] == :building && !NO_START.include?(o[:map])
          next false unless d[:names][o[:to][0]].to_s =~ /Pok[eé]mon Center/i
          !towns_only || d[:names][o[:map]].to_s =~ /City|Town|Island/
        }.sort_by { |o| o[:id] }
      end

      # What the start of the game gives before the Pokédex (Pallet, Route 1,
      # Viridian): a game that starts elsewhere has been through that
      def self.pre_dex_flags(d)
        res = sweep(d, edges_for(d, {}, {}), [], nil, nil, POKEDEX_FLAG)
        return res[:have]
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
        if s.is_a?(Hash) && dat && s[:sig] != dat[:signature] && !@sig_warned
          @sig_warned = true
          pbMessage(_INTL("The entrance data changed since this save's doors were shuffled. Doors are back to normal until you Randomize now."))
          return
        end
        return if Rand.data[:ent_done] || s
        return unless Rand.dget(:entrances) > 0 && available?
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
          i = byid[s[:in][o[:id]] || o[:id]]
          if i[:id] != o[:id]
            o[:events].each { |e| @targets[[o[:map], e]] = [i[:to][0], i[:to][1], i[:to][2], i[:to_dir], o[:id], :in] }
          end
          back = byid[s[:out][o[:id]] || o[:id]]
          if back[:id] != o[:id]
            o[:exit_events].each { |e| @targets[[o[:exit_map], e]] = [back[:exit_to][0], back[:exit_to][1], back[:exit_to][2], back[:exit_dir], o[:id], :out] }
          end
        end
        return @targets
      end

      def self.target(map_id, event_id)
        return nil unless active?
        return targets[[map_id, event_id]]
      end

      # Random start: Oak has handed over the Pokédex and the player leaves
      # the lab - that door leads into the start town's Pokémon Center once
      def self.start_target(map_id, params)
        s = state
        return nil unless active? && s[:start_door] && s[:start_pending] && !s[:start_done]
        return nil unless OAK_LABS.include?(map_id) && params[1] == PALLET
        o = dat[:door_by_id][s[:start_door]]
        return nil unless o
        s[:start_done] = true
        s[:start_pending] = false
        @new_home = [o[:to][0], o[:to][1], o[:to][2], o[:to_dir]]
        return [o[:to][0], o[:to][1], o[:to][2], o[:to_dir]]
      end

      class << self
        attr_accessor :new_home
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
        o = dat[:door_by_id][state[:start_door]]
        pbMessage(_INTL("Your journey starts in {1}.", dat[:names][o[:map]])) if o
      rescue => e
        KIF.log("Random start home failed (#{e.class}: #{e.message})")
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
        out << _INTL("Start: {1}", start_name) if start_name
        out << _INTL("Found so far: {1} of {2} doors", (s[:seen] || []).length, s[:in].length)
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
    KIF::Rand::ER.ensure_layout if @parameters[0] == 0 && $PokemonGlobal
    return kif_ent_command_201 unless @parameters[0] == 0 && KIF::Rand::ER.active?
    t = KIF::Rand::ER.start_target(@map_id, @parameters) || KIF::Rand::ER.target(@map_id, @event_id)
    return kif_ent_command_201 unless t
    saved = @parameters
    @parameters = [0, t[0], t[1], t[2], t[3], saved[5]]
    begin
      r = kif_ent_command_201
      # @index moved on: the transfer is set up
      KIF::Rand::ER.note(t[4], t[5]) if $game_temp.player_transferring && t[4]
      return r
    ensure
      @parameters = saved
    end
  rescue => e
    KIF.log("Entrance warp failed (#{e.class}: #{e.message})")
    @parameters = saved if saved
    return kif_ent_command_201
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
# Random start: the Pokédex is the signal
#-------------------------------------------------------------------------------
class Player
  alias kif_ent_has_pokedex= has_pokedex= unless method_defined?(:"kif_ent_has_pokedex=")

  def has_pokedex=(value)
    before = @has_pokedex
    self.kif_ent_has_pokedex = value
    if value && !before && KIF::Rand::ER.active?
      s = KIF::Rand::ER.state
      s[:start_pending] = true if s[:start_door] && !s[:start_done]
    end
  rescue => e
    KIF.log("Random start flag failed (#{e.class}: #{e.message})")
  end
end
