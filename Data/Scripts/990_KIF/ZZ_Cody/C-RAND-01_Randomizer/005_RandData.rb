#===============================================================================
# C-RAND-01 – Randomizer chunk 3: Pokémon data (Cody, 2026-10-06)
# Types, moves that follow the new type, TM compatibility, abilities, base
# stats, evolutions and exclusion lists. Only the base Pokémon (dex 1-576)
# are changed; fusions are built from their two parts, so they follow.
#
# The changes are made once (Randomize now, or when the randomizer screen
# closes during the intro), kept in the save ($PokemonGlobal.kif_rand
# [:species]) and put onto the game data on load; a save without them gets
# the original data back. Pokémon you already have keep their moves; their
# stats are recalculated.
#
# Rules (Cody):
#   * Types follow the evolution family: each original type gets one new
#     type in the family (Charmander Fire->Ice, Charizard Fire/Flying ->
#     Ice/X). "Dual" gives single-type families a second type.
#     "Original type: Never" never keeps a species' own original types.
#   * Moves follow type: level-up and egg moves of an old own type become a
#     move of the matching new type, same kind (physical/special/status),
#     closest power; other moves (Scratch...) stay. TMs: same for TM/tutor
#     compatibility.
#   * Abilities: Random / Type-flavoured (themed table below) / Type-bound
#     (abilities Pokémon of that type have in the base game). "No self-harm":
#     never Truant, Slow Start, Defeatist, Klutz, Stall; never weather that
#     hurts the Pokémon's own type.
#   * Base stats: Shuffle (same numbers, new order, same order per family) /
#     Total (random spread, same total) / Chaos (each 1-255) with Chaos safety
#     Off / Total (an evolution's total is never lower) / Each stat.
#   * Evolutions (only Pokémon that already evolve): the new evolution is a
#     Final (doesn't evolve) or a higher stage; same level/item/method.
#     Type-themed: it shares a type.
#   * Exclusions: banned Pokémon/moves/abilities are never picked by any part
#     of the randomizer.
#===============================================================================
module KIF
  module Rand
    DATA_SETTINGS = [
      [:types, :enum, 3],        # Same / Random / Dual
      [:type_orig, :enum, 2],    # Allowed / Never
      [:moves_follow, :enum, 2],
      [:tms_follow, :enum, 2],
      [:abilities, :enum, 4],    # Same / Random / Type-flavoured / Type-bound
      [:no_selfharm, :enum, 2],
      [:stats, :enum, 4],        # Same / Shuffle / Total / Chaos
      [:chaos_safety, :enum, 3], # Off / Total / Each stat
      [:evolutions, :enum, 2],   # Same / Random
      [:evo_typed, :enum, 2]
    ]
    DATA_DEFAULTS = { :chaos_safety => 1 }
    DATA_KEYS = DATA_SETTINGS.map(&:first)

    ALWAYS_BAD = [:TRUANT, :SLOWSTART, :DEFEATIST, :KLUTZ, :STALL]

    FLAVOUR = {
      :NORMAL   => [:SCRAPPY, :ADAPTABILITY, :THICKFAT, :GUTS, :RUNAWAY, :PICKUP, :SERENEGRACE, :SKILLLINK,
                    :TECHNICIAN, :SIMPLE, :UNAWARE, :CUTECHARM, :FRIENDGUARD, :NORMALIZE, :OWNTEMPO, :TOUGHCLAWS],
      :FIGHTING => [:GUTS, :IRONFIST, :INNERFOCUS, :STEADFAST, :JUSTIFIED, :SCRAPPY, :NOGUARD, :DEFIANT, :HUGEPOWER, :RECKLESS],
      :FLYING   => [:GALEWINGS, :AERILATE, :BIGPECKS, :KEENEYE, :EARLYBIRD, :TANGLEDFEET, :AIRLOCK, :SUPERLUCK, :LEVITATE],
      :POISON   => [:POISONPOINT, :POISONTOUCH, :STENCH, :LIQUIDOOZE, :MERCILESS, :CORROSION, :TOXICBOOST, :IMMUNITY],
      :GROUND   => [:SANDVEIL, :SANDRUSH, :SANDFORCE, :SANDSTREAM, :ARENATRAP, :EARTHEATER],
      :ROCK     => [:STURDY, :ROCKHEAD, :SOLIDROCK, :SANDSTREAM, :SANDFORCE, :WEAKARMOR, :MAGNETPULL],
      :BUG      => [:SWARM, :COMPOUNDEYES, :SHIELDDUST, :TINTEDLENS, :SHEDSKIN, :SPEEDBOOST, :HONEYGATHER],
      :GHOST    => [:CURSEDBODY, :LEVITATE, :FRISK, :PICKPOCKET, :INFILTRATOR, :PERISHBODY, :WANDERINGSPIRIT, :DISGUISE],
      :STEEL    => [:HEAVYMETAL, :LIGHTMETAL, :CLEARBODY, :MAGNETPULL, :STURDY, :STEELWORKER, :FULLMETALBODY, :FILTER],
      :FIRE     => [:BLAZE, :FLASHFIRE, :FLAMEBODY, :DROUGHT, :SOLARPOWER, :MAGMAARMOR, :WHITESMOKE, :FLAREBOOST],
      :WATER    => [:TORRENT, :SWIFTSWIM, :WATERABSORB, :RAINDISH, :DRIZZLE, :HYDRATION, :STORMDRAIN, :WATERVEIL, :DAMP],
      :GRASS    => [:OVERGROW, :CHLOROPHYLL, :LEAFGUARD, :SAPSIPPER, :EFFECTSPORE, :HARVEST, :GRASSPELT, :NATURALCURE],
      :ELECTRIC => [:STATIC, :VOLTABSORB, :LIGHTNINGROD, :MOTORDRIVE, :PLUS, :MINUS, :ELECTRICSURGE, :GALVANIZE],
      :PSYCHIC  => [:SYNCHRONIZE, :MAGICGUARD, :TELEPATHY, :FOREWARN, :MAGICBOUNCE, :PSYCHICSURGE, :ANTICIPATION, :TRACE],
      :ICE      => [:ICEBODY, :SNOWCLOAK, :SNOWWARNING, :THICKFAT, :REFRIGERATE, :SLUSHRUSH, :ICESCALES],
      :DRAGON   => [:ROUGHSKIN, :MULTISCALE, :MARVELSCALE, :PRESSURE, :SHEERFORCE, :INTIMIDATE],
      :DARK     => [:INTIMIDATE, :PRESSURE, :PRANKSTER, :MOXIE, :SUPERLUCK, :PICKPOCKET, :DARKAURA, :UNNERVE],
      :FAIRY    => [:CUTECHARM, :PIXILATE, :MISTYSURGE, :FLOWERVEIL, :SWEETVEIL, :AROMAVEIL, :MAGICGUARD, :FRIENDGUARD]
    }

    def self.dget(key)
      default = DATA_DEFAULTS[key] || 0
      v = as_int(data[key], default)
      max = setting_max(key)
      return default if v < 0 || (max && v > max)
      return v
    end

    def self.dset(key, v); data[key] = v; end

    def self.data_on?
      return dget(:types) > 0 || dget(:moves_follow) == 1 || dget(:tms_follow) == 1 ||
             dget(:abilities) > 0 || dget(:stats) > 0 || dget(:evolutions) > 0
    end

    def self.bans(kind)
      return item_bans if kind == :items
      data[:"ban_#{kind}"] ||= []
      return data[:"ban_#{kind}"]
    end

    def self.banned?(kind, id)
      list = data[:"ban_#{kind}"]
      return list && list.include?(id)
    end

    # A species (or either part of a fusion) is banned
    def self.species_banned?(dex)
      list = data[:ban_pokemon]
      return false if !list || list.empty?
      n = dex.is_a?(Integer) ? dex : (getDexNumberForSpecies(dex) rescue nil)
      return false unless n
      if n > NB_POKEMON && n < Settings::ZAPMOLCUNO_NB
        body = getBodyID(n)
        head = getHeadID(n, body)
        return species_banned?(body) || species_banned?(head)
      end
      sp = (GameData::Species.get(n).species rescue nil)
      return sp && list.include?(sp)
    end

    #---------------------------------------------------------------------------
    # Original data (taken once from the loaded game data)
    #---------------------------------------------------------------------------
    FIELDS = [:@type1, :@type2, :@abilities, :@hidden_abilities, :@base_stats, :@moves,
              :@egg_moves, :@tutor_moves, :@evolutions]
    @orig = nil

    def self.base_species
      return (1..NB_POKEMON).map { |i| GameData::Species.get(i) rescue nil }.compact.uniq
    end

    def self.originals
      if !@orig || @orig_for != GameData::Species.get(1).object_id
        @orig = {}
        base_species.each do |sp|
          @orig[sp.species] = FIELDS.map { |f| [f, Marshal.load(Marshal.dump(sp.instance_variable_get(f)))] }.to_h
        end
        @orig_for = GameData::Species.get(1).object_id
      end
      return @orig
    end

    def self.orig(sp, field); return originals[sp][field]; end

    # Original families: species => [base form, stage, final?]
    def self.family_info
      return @family if @family && @family_for == @orig_for
      @family = {}
      originals.each_key do |s|
        stage = 1
        cur = GameData::Species.get(s)
        seen = [s]
        loop do
          prev = cur.get_previous_species
          break if prev.nil? || seen.include?(prev) || !originals[prev]
          seen << prev
          cur = GameData::Species.get(prev)
          stage += 1
        end
        evos = orig(s, :@evolutions).reject { |e| e[3] }
        @family[s] = [cur.species, stage, evos.empty?]
      end
      @family_for = @orig_for
      return @family
    end

    #---------------------------------------------------------------------------
    # Putting a save's changes on the game data
    #---------------------------------------------------------------------------
    def self.apply_data(changes = nil)
      changes ||= (data[:species] || {})
      originals.each do |s, fields|
        sp = GameData::Species.get(s)
        ch = changes[s] || {}
        fields.each do |f, v|
          val = ch.key?(f) ? ch[f] : v
          next if sp.instance_variable_get(f) == val   # already right: no copy
          sp.instance_variable_set(f, Marshal.load(Marshal.dump(val)))
        end
      end
      KIF::Perf.bump_token if defined?(KIF::Perf)
      recalc_owned
    end

    def self.recalc_owned
      list = []
      list.concat($Trainer.party) if $Trainer && $Trainer.party
      if $PokemonGlobal && $PokemonGlobal.respond_to?(:daycare) && $PokemonGlobal.daycare.is_a?(Array)
        $PokemonGlobal.daycare.each { |slot| list << slot[0] if slot.is_a?(Array) && slot[0].is_a?(Pokemon) }
      end
      if $PokemonStorage
        $PokemonStorage.maxBoxes.times do |b|
          $PokemonStorage.maxPokemon(b).times { |i| list << $PokemonStorage[b, i] }
        end rescue nil
      end
      list.compact.each { |pk| pk.calc_stats rescue nil }
    end

    #---------------------------------------------------------------------------
    # Making the changes
    #---------------------------------------------------------------------------
    def self.randomize_data
      ch = {}
      types = with_seed(:types) { roll_types }
      evos  = with_seed(:evolutions) { roll_evolutions(types) }
      moves = with_seed(:moves) { roll_moves(types) }
      abil  = with_seed(:abilities) { roll_abilities(types) }
      stats = with_seed(:stats) { roll_stats(evos) }
      [types, evos, moves, abil, stats].each do |part|
        part.each { |s, fields| (ch[s] ||= {}).merge!(fields) }
      end
      data[:species] = ch
      apply_data(ch)
      return ch
    end

    def self.new_types_of(s, types)
      t = types[s]
      return t ? [t[:@type1], t[:@type2]] : [orig(s, :@type1), orig(s, :@type2)]
    end

    def self.type_pool
      return GameData::Type.each.to_a.reject { |t| t.pseudo_type || t.id == :QMARKS || t.id == :SHADOW }.map(&:id) rescue
             [:NORMAL, :FIGHTING, :FLYING, :POISON, :GROUND, :ROCK, :BUG, :GHOST, :STEEL, :FIRE, :WATER,
              :GRASS, :ELECTRIC, :PSYCHIC, :ICE, :DRAGON, :DARK, :FAIRY]
    end

    def self.roll_types
      out = {}
      mode = dget(:types)
      return out if mode == 0
      pool = type_pool
      never = dget(:type_orig) == 1
      fams = family_info.group_by { |_s, info| info[0] }
      fams.keys.sort_by { |b| GameData::Species.get(b).id_number }.each do |base|
        members = fams[base].map(&:first).sort_by { |s| GameData::Species.get(s).id_number }
        map = {}
        members.each do |s|
          olds = [orig(s, :@type1), orig(s, :@type2)].uniq
          olds.each do |ot|
            next if map[ot]
            cands = pool - map.values
            cands -= members.flat_map { |m| [orig(m, :@type1), orig(m, :@type2)] } if never
            cands = pool - map.values if cands.empty?
            map[ot] = cands.sample
          end
        end
        extra = nil
        members.each do |s|
          t1 = map[orig(s, :@type1)]
          t2 = map[orig(s, :@type2)]
          if mode == 2 && t1 == t2
            extra ||= (pool - map.values - [t1]).sample
            t2 = extra
          end
          out[s] = { :@type1 => t1, :@type2 => t2 }
        end
      end
      return out
    end

    def self.roll_evolutions(types)
      out = {}
      return out if dget(:evolutions) == 0
      fam = family_info
      typed = dget(:evo_typed) == 1
      all = fam.keys.sort_by { |s| GameData::Species.get(s).id_number }
      all.each do |s|
        evos = orig(s, :@evolutions)
        fwd = evos.reject { |e| e[3] }
        next if fwd.empty?
        stage = fam[s][1]
        used = []
        my_types = new_types_of(s, types)
        new_evos = evos.map do |e|
          next e.dup if e[3]
          cands = all.select do |t|
            next false if t == s || used.include?(t) || species_banned?(t)
            next false unless fam[t][2] || fam[t][1] > stage
            next false if typed && (new_types_of(t, types) & my_types).empty?
            true
          end
          if cands.empty? && typed
            cands = all.select { |t| t != s && !used.include?(t) && !species_banned?(t) && (fam[t][2] || fam[t][1] > stage) }
          end
          to = cands.empty? ? e[0] : cands.sample
          used << to
          [to, e[1], e[2], false]
        end
        out[s] = { :@evolutions => new_evos }
      end
      return out
    end

    #---------------------------------------------------------------------------
    # Moves
    #---------------------------------------------------------------------------
    def self.move_kind(m)
      return :status if m.base_damage == 0
      return m.category == 0 ? :physical : :special
    end

    def self.move_pool
      @move_pool ||= begin
        list = []
        GameData::Move.each do |m|
          next if m.type == :SHADOW || m.id == :STRUGGLE
          list << m
        end
        list.sort_by(&:id_number)
      end
      return @move_pool
    end

    # The new-type move closest to the old one (same kind, power +-10 widening)
    def self.match_move(move_id, new_type, avoid)
      m = GameData::Move.get(move_id)
      kind = move_kind(m)
      cands = move_pool.select { |x| x.type == new_type && move_kind(x) == kind && !banned?(:moves, x.id) }
      return move_id if cands.empty?
      fresh = cands.reject { |x| avoid.include?(x.id) }
      cands = fresh unless fresh.empty?
      return cands.sample.id if kind == :status
      range = 10
      loop do
        near = cands.select { |x| (x.base_damage - m.base_damage).abs <= range }
        return near.sample.id unless near.empty?
        range += 10
        return cands.sample.id if range > 250
      end
    end

    def self.type_map_for(s, types)
      t = types[s]
      return nil unless t
      o1, o2 = orig(s, :@type1), orig(s, :@type2)
      map = { o1 => t[:@type1] }
      map[o2] = (o2 == o1) ? t[:@type1] : t[:@type2]
      return map
    end

    def self.roll_moves(types)
      out = {}
      follow = dget(:moves_follow) == 1
      tms = dget(:tms_follow) == 1
      return out unless follow || tms
      originals.keys.sort_by { |s| GameData::Species.get(s).id_number }.each do |s|
        map = type_map_for(s, types)
        next unless map
        ch = {}
        if follow
          used = []
          ch[:@moves] = orig(s, :@moves).map do |lv, mv|
            mt = (GameData::Move.get(mv).type rescue nil)
            nt = map[mt]
            if nt && nt != mt
              nm = match_move(mv, nt, used)
              used << nm
              [lv, nm]
            else
              [lv, mv]
            end
          end
          ch[:@egg_moves] = orig(s, :@egg_moves).map do |mv|
            mt = (GameData::Move.get(mv).type rescue nil)
            nt = map[mt]
            (nt && nt != mt) ? match_move(mv, nt, used) : mv
          end.uniq
        end
        if tms
          used = []
          ch[:@tutor_moves] = orig(s, :@tutor_moves).map do |mv|
            mt = (GameData::Move.get(mv).type rescue nil)
            nt = map[mt]
            if nt && nt != mt
              nm = match_move(mv, nt, used)
              used << nm
              nm
            else
              mv
            end
          end.uniq
        end
        out[s] = ch
      end
      return out
    end

    #---------------------------------------------------------------------------
    # Abilities
    #---------------------------------------------------------------------------
    def self.ability_ok?(ab, my_types)
      return false if banned?(:abilities, ab)
      return false unless GameData::Ability.exists?(ab)
      if dget(:no_selfharm) == 1
        return false if ALWAYS_BAD.include?(ab)
        return false if ab == :DROUGHT && my_types.include?(:WATER)
        return false if ab == :DRIZZLE && my_types.include?(:FIRE)
        return false if ab == :SANDSTREAM && (my_types & [:ROCK, :GROUND, :STEEL]).empty?
        return false if ab == :SNOWWARNING && !my_types.include?(:ICE)
      end
      return true
    end

    def self.all_abilities
      @all_abilities ||= begin
        list = []
        GameData::Ability.each { |a| list << a.id }
        list.sort_by { |a| GameData::Ability.get(a).id_number }
      end
    end

    def self.bound_table
      @bound ||= begin
        t = Hash.new { |h, k| h[k] = [] }
        originals.each_key do |s|
          abs = (orig(s, :@abilities) || []) + (orig(s, :@hidden_abilities) || [])
          [orig(s, :@type1), orig(s, :@type2)].uniq.each { |ty| t[ty].concat(abs) }
        end
        t.each_value(&:uniq!)
        t
      end
    end

    def self.ability_pool(my_types)
      case dget(:abilities)
      when 1 then pool = all_abilities
      when 2 then pool = my_types.flat_map { |t| FLAVOUR[t] || [] }.uniq
      when 3 then pool = my_types.flat_map { |t| bound_table[t] }.uniq
      else return []
      end
      pool = pool.select { |a| ability_ok?(a, my_types) }
      pool = all_abilities.select { |a| ability_ok?(a, my_types) } if pool.length < 2
      return pool.sort_by { |a| GameData::Ability.get(a).id_number }
    end

    def self.roll_abilities(types)
      out = {}
      return out if dget(:abilities) == 0
      fams = family_info.group_by { |_s, info| info[0] }
      fams.keys.sort_by { |b| GameData::Species.get(b).id_number }.each do |base|
        members = fams[base].map(&:first).sort_by { |s| family_info[s][1] * 10000 + GameData::Species.get(s).id_number }
        rolled = {}   # types => [abilities, hidden]
        members.each do |s|
          my = new_types_of(s, types).compact.uniq
          key = my.sort
          unless rolled[key]
            pool = ability_pool(my)
            n = [orig(s, :@abilities).length, 1].max
            abs = pool.sample(n)
            hid = (orig(s, :@hidden_abilities) || []).map { (pool - abs).sample || pool.sample }
            rolled[key] = [abs, hid]
          end
          out[s] = { :@abilities => rolled[key][0], :@hidden_abilities => rolled[key][1] }
        end
      end
      return out
    end

    #---------------------------------------------------------------------------
    # Base stats
    #---------------------------------------------------------------------------
    STAT_ORDER = [:HP, :ATTACK, :DEFENSE, :SPECIAL_ATTACK, :SPECIAL_DEFENSE, :SPEED]

    def self.spread(total)
      total = [[total, 6].max, 1530].min
      w = STAT_ORDER.map { rand + 0.05 }
      sum = w.sum
      v = w.map { |x| [[(x / sum * total).round, 1].max, 255].min }
      # fix rounding/caps so the total stays the same
      guard = 0
      while v.sum != total && guard < 5000
        i = rand(6)
        if v.sum < total && v[i] < 255 then v[i] += 1
        elsif v.sum > total && v[i] > 1 then v[i] -= 1 end
        guard += 1
      end
      return v
    end

    def self.roll_stats(evos)
      out = {}
      mode = dget(:stats)
      return out if mode == 0
      fam = family_info
      order = originals.keys.sort_by { |s| fam[s][1] * 10000 + GameData::Species.get(s).id_number }
      # predecessors in the (possibly randomized) evolution graph
      preds = Hash.new { |h, k| h[k] = [] }
      originals.each_key do |s|
        list = evos[s] ? evos[s][:@evolutions] : orig(s, :@evolutions)
        list.each { |e| preds[e[0]] << s unless e[3] }
      end
      perms = {}
      done = {}
      # pre-evolutions first (repeat while something gets done; whatever is
      # left after that - only possible with an evolution loop - is done
      # without a floor)
      pending = order.dup
      strict = true
      loop do
        before = pending.length
        pend_set = {}
        pending.each { |x| pend_set[x] = true }
        pending = pending.reject do |s|
          next false if strict && preds[s].any? { |p| !done[p] && pend_set[p] && p != s }
          old = STAT_ORDER.map { |k| orig(s, :@base_stats)[k] }
          case mode
          when 1
            perms[fam[s][0]] ||= (0...6).to_a.shuffle
            v = perms[fam[s][0]].map { |i| old[i] }
          when 2
            v = spread(old.sum)
          else
            v = STAT_ORDER.map { rand(255) + 1 }
            safety = dget(:chaos_safety)
            floors = preds[s].map { |p| done[p] }.compact
            if safety == 2 && !floors.empty?
              lo = (0...6).map { |i| floors.map { |f| f[i] }.max }
              v = (0...6).map { |i| lo[i] + rand(256 - lo[i]) }
            elsif safety == 1 && !floors.empty?
              need = floors.map(&:sum).max
              guard = 0
              while v.sum < need && guard < 3000
                i = rand(6)
                v[i] += 1 if v[i] < 255
                guard += 1
              end
            end
          end
          done[s] = v
          out[s] = { :@base_stats => STAT_ORDER.each_with_index.map { |k, i| [k, v[i]] }.to_h }
          true
        end
        break if pending.empty?
        if pending.length == before
          break unless strict
          strict = false
        end
      end
      return out
    end
  end
end

#-------------------------------------------------------------------------------
# Loading, new games and data reloads
#-------------------------------------------------------------------------------
module Game
  class << self
    alias kif_rand_load load unless method_defined?(:kif_rand_load)
    alias kif_rand_start_new start_new unless method_defined?(:kif_rand_start_new)

    def load(*args)
      ret = kif_rand_load(*args)
      begin
        KIF::Rand.sanitize_tables if $PokemonGlobal
        KIF::Rand.apply_data
      rescue => e
        KIF.log("Randomizer data failed to load: #{e.class}: #{e.message}")
      end
      return ret
    end

    def start_new(*args)
      begin
        KIF::Rand.apply_data({}) if KIF::Rand.instance_variable_get(:@orig)
      rescue => e
        KIF.log("Randomizer data reset failed: #{e.message}")
      end
      return kif_rand_start_new(*args)
    end
  end
end

KIF::DataLoad.after_load_all("Randomizer Pokémon data") do
  KIF::Rand.instance_variable_set(:@orig, nil)
  KIF::Rand.instance_variable_set(:@move_pool, nil)
  KIF::Rand.instance_variable_set(:@bound, nil)
  KIF::Rand.apply_data if $PokemonGlobal && $PokemonGlobal.kif_rand[:species]
end

# Banned Pokémon are never picked: every PIF pick (swaps, routes, trainers,
# gyms, Dynamic) checks legendaryOk(old, new, ...) in its loop
class Object
  alias kif_rand_legendaryOk legendaryOk unless method_defined?(:kif_rand_legendaryOk) || private_method_defined?(:kif_rand_legendaryOk)

  def legendaryOk(oldspecies, newspecies, includeLegendaries)
    return false if $PokemonGlobal && KIF::Rand.species_banned?(newspecies)
    return kif_rand_legendaryOk(oldspecies, newspecies, includeLegendaries)
  end
end
