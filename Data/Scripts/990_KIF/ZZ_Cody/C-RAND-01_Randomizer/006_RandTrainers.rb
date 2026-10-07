#===============================================================================
# C-RAND-01 – Randomizer, chunk 4: trainers (Cody, 2026-10-06)
#   * Trainers: Off / Random / Follow wild (trainer Pokémon use the wild swap
#     table, fusions part by part).
#   * Class themes: Off / On – every Pokémon of a themed class has the class's
#     type: Bug Catchers use Bug types, Swimmers Water types, ... (CLASS_THEMES).
#     Uses the save's types, so it follows randomized Pokémon data. Gym
#     leaders keep using the Gyms page.
#   * Shuffle themes: each class gets a random type instead (per seed; Type
#     Experts keep theirs, their name says it).
#   * Rival keeps his team: each Pokémon line in a rival's team gets one
#     replacement line for every battle with him, at the same stage.
#   * Team size: Same / +1 / +2 / Full – extra Pokémon join at the team's
#     average level.
#   * Fuse everything: every trainer Pokémon is a fusion.
#   (Double battles are KIF's Battle Format option, not part of this.)
# Everything is made when the trainers are shuffled (seeded) and kept in
# $PokemonGlobal.randomTrainersHash like PIF's own shuffle; with none of the
# new settings on, PIF's shuffle runs unchanged.
#===============================================================================
module KIF
  module Rand
    TRAINER_SETTINGS = [
      [:class_themes, :enum, 2],
      [:theme_shuffle, :enum, 2],
      [:rival_team, :enum, 2],
      [:team_size, :enum, 4],     # Same / +1 / +2 / Full
      [:trainer_fuse, :enum, 2],
      [:extra_themes, :enum, 2]   # themes for the less obvious classes
    ]
    # Added after the data settings, so older settings codes still line up
    DATA_SETTINGS.concat(TRAINER_SETTINGS)
    DATA_KEYS.concat(TRAINER_SETTINGS.map(&:first))
    DATA_DEFAULTS[:class_themes] = 1
    DATA_DEFAULTS[:extra_themes] = 1

    # Extra class themes (Cody: a toggle of their own); picked from their
    # FireRed/LeafGreen teams
    EXTRA_THEMES = [:SCIENTIST, :ROBOT, :JUGGLER, :BURGLAR, :BIKER, :ROUGHNECK,
                    :CUEBALL, :AROMALADY, :PAINTER, :TUBER_F]

    RIVAL_TYPES = [:RIVAL1, :RIVAL2, :CHAMPION]

    CLASS_THEMES = {
      :BUGCATCHER => [:BUG], :BUGCATCHER_F => [:BUG],
      :SWIMMER_M => [:WATER], :SWIMMER_F => [:WATER], :FISHERMAN => [:WATER],
      :SAILOR => [:WATER], :TUBER_F => [:WATER],
      :HIKER => [:ROCK, :GROUND],
      :BIRDKEEPER => [:FLYING],
      :CHANNELER => [:GHOST], :HAUNTEDGIRL => [:GHOST], :HAUNTEDGIRL_YOUNG => [:GHOST],
      :BLACKBELT => [:FIGHTING], :CRUSHGIRL => [:FIGHTING], :CRUSHKIN => [:FIGHTING],
      :CUEBALL => [:FIGHTING],
      :PSYCHIC_M => [:PSYCHIC], :PSYCHIC_F => [:PSYCHIC], :SAGE => [:PSYCHIC], :JUGGLER => [:PSYCHIC],
      :PYROMANIAC => [:FIRE], :BURGLAR => [:FIRE],
      :ENGINEER => [:ELECTRIC], :SCIENTIST => [:ELECTRIC, :POISON], :ROBOT => [:STEEL],
      :SKIER_F => [:ICE],
      :TEAMROCKET_M => [:POISON, :DARK], :TEAMROCKET_F => [:POISON, :DARK],
      :ROCKETEXEC_F => [:POISON, :DARK], :ROCKETEXEC_Archer => [:POISON, :DARK],
      :ROCKETEXEC_Ariana => [:POISON, :DARK],
      :BIKER => [:POISON], :ROUGHNECK => [:DARK],
      :AROMALADY => [:GRASS], :PAINTER => [:NORMAL],
      :ELITEFOUR_Lorelei => [:ICE], :ELITEFOUR_Bruno => [:FIGHTING],
      :ELITEFOUR_Agatha => [:GHOST], :ELITEFOUR_Lance => [:DRAGON]
    }

    # The class's usual theme (nil = any type)
    def self.base_theme(tr_type)
      return nil unless tr_type.is_a?(Symbol) || tr_type.is_a?(String)
      t = tr_type.to_s
      if t.start_with?("TYPE_EXPERT_")
        type = t.sub("TYPE_EXPERT_", "").to_sym
        return GameData::Type.exists?(type) ? [type] : nil
      end
      return nil if dget(:extra_themes) == 0 && EXTRA_THEMES.include?(tr_type.to_sym)
      return CLASS_THEMES[tr_type.to_sym]
    end

    # The theme this save uses (shuffled when Shuffle themes is On)
    def self.class_theme(tr_type)
      th = base_theme(tr_type)
      return th unless th && dget(:theme_shuffle) == 1 && !tr_type.to_s.start_with?("TYPE_EXPERT_")
      map = data[:theme_map]
      return (map && map[theme_key(tr_type)]) || th
    end

    # Classes that share a name and usual type share one shuffled type
    # (Swimmer M/F); the Elite Four etc. stay separate
    def self.theme_key(tr_type)
      return "#{class_label(tr_type)}|#{base_theme(tr_type).inspect}"
    end

    # "Elite Four Lorelei", "Swimmer", ...
    def self.class_label(tr_type)
      name = (GameData::TrainerType.get(tr_type).name rescue tr_type.to_s)
      name = "#{name} #{$1}" if tr_type.to_s =~ /_([A-Z][a-z]+)\z/
      return name
    end

    # The 18 normal types (PIF also has ??? and the triple-fusion types,
    # which no regular Pokémon has)
    def self.real_types
      return GameData::Type.keys.select { |k|
        k.is_a?(Symbol) && (t = GameData::Type.get(k)) && !t.pseudo_type &&
          themed_bases([k]).length >= 10
      }.uniq
    end

    # One random type set per class name (Swimmer M/F share one); seeded,
    # made with the trainers
    def self.make_theme_map
      map = {}
      types = real_types
      trainer_type_keys.each do |k|
        th = base_theme(k)
        next if !th || k.to_s.start_with?("TYPE_EXPERT_")
        map[theme_key(k)] ||= types.shuffle.first(th.length)
      end
      data[:theme_map] = map
    end

    def self.trainer_type_keys
      return (GameData::TrainerType.keys rescue CLASS_THEMES.keys).select { |k| k.is_a?(Symbol) }.sort_by(&:to_s)
    end

    # Read-only list for the Trainers page
    def self.class_theme_lines
      seen = {}
      lines = []
      if dget(:theme_shuffle) == 1 && !data[:theme_map]
        return [_INTL("Shuffle themes is On: each class gets its type when the trainers are randomized.")]
      end
      trainer_type_keys.each do |k|
        th = class_theme(k)
        next unless th
        name = class_label(k)
        label = th.map { |x| type_name(x) }.join(" / ")
        next if seen[[name, label]]
        seen[[name, label]] = true
        lines << "#{name}: #{label}"
      end
      return lines.sort
    end

    def self.trainer_mode
      return get(:trainers)
    end

    def self.trainer_features?
      return trainer_mode == 2 || dget(:class_themes) > 0 || dget(:rival_team) == 1 ||
             dget(:team_size) > 0 || dget(:trainer_fuse) == 1
    end

    #---------------------------------------------------------------------------
    # Picking
    #---------------------------------------------------------------------------
    def self.fused?(dex)
      return dex > NB_POKEMON && dex < Settings::ZAPMOLCUNO_NB
    end

    def self.parts_of(dex)
      body = getBodyID(dex)
      return [body, getHeadID(dex, body)]
    end

    def self.fuse(body, head)
      return body * NB_POKEMON + head
    end

    # A number the game can make a Pokémon from
    def self.valid_dex?(d)
      return false unless d.is_a?(Integer) && d > 0
      return true if d <= NB_POKEMON
      return false if d >= Settings::ZAPMOLCUNO_NB   # triple fusions are kept as they were, never picked
      b, h = parts_of(d)
      return b.between?(1, NB_POKEMON) && h.between?(1, NB_POKEMON)
    end

    def self.theme_ok?(dex, theme)
      sp = (GameData::Species.get(dex) rescue nil)
      return false unless sp
      return theme.any? { |t| sp.type1 == t || sp.type2 == t }
    end

    def self.pick_ok?(old, cand, bst)
      return false if cand <= 0 || cand >= Settings::ZAPMOLCUNO_NB
      return false if species_banned?(cand)
      return false if bst < 999 && bstNotOk(cand, old, bst)
      return legendaryOk(old, cand, true)
    end

    def self.random_dex(customs)
      return dex_of(customs[rand(customs.length)]) if customs && !customs.empty?
      return rand(PBSpecies.maxValue - 1) + 1
    end

    # Base Pokémon with a theme type (this save's types); fusions are built
    # from these so most tries hit the theme. Reset with each shuffle.
    def self.themed_bases(theme)
      @themed_bases ||= {}
      @themed_bases[theme] ||= (1..NB_POKEMON).select { |d| theme_ok?(d, theme) && !species_banned?(d) }
    end

    # Custom-sprite fusions whose head or body has a theme type (checked
    # properly afterwards)
    def self.themed_customs(theme, customs)
      @themed_customs ||= {}
      @themed_customs[theme] ||= begin
        ok = {}
        themed_bases(theme).each { |d| ok[d] = true }
        customs.map { |c| dex_of(c) }.select { |d| fused?(d) ? parts_of(d).any? { |x| ok[x] } : ok[d] }
      end
    end

    def self.reset_theme_cache
      @themed_bases = {}
      @themed_customs = {}
    end

    def self.themed_candidate(theme, customs)
      if customs && !customs.empty?
        list = themed_customs(theme, customs)
        return list.empty? ? random_dex(customs) : list[rand(list.length)]
      end
      bases = themed_bases(theme)
      return random_dex(nil) if bases.empty?
      b = bases[rand(bases.length)]
      r = rand(20)
      return b if r == 0                                 # unfused now and then
      return r < 11 ? fuse(rand(NB_POKEMON) + 1, b) : fuse(b, rand(NB_POKEMON) + 1)
    end

    # One Pokémon for a trainer: like PIF's pick, plus the theme
    def self.trainer_pick(old, theme, customs)
      bst = get(:trainer_bst)
      unless theme
        return dex_of(customs ? getNewCustomSpecies(old, customs, bst) : getNewSpecies(old, bst))
      end
      3000.times do |i|
        bst += 5 if i > 0 && i % 25 == 0
        cand = themed_candidate(theme, customs)
        next unless theme_ok?(cand, theme)
        return cand if pick_ok?(old, cand, bst)
      end
      # Nothing in range: any unbanned Pokémon of the type
      list = themed_bases(theme)
      return list.empty? ? getNewSpecies(old, 999) : list[rand(list.length)]
    end

    # first_stage: only the first Pokémon of a line (for the rival's lines,
    # so they can evolve along with his team)
    def self.random_base(old = nil, first_stage = false)
      bst = get(:trainer_bst)
      2000.times do |i|
        bst += 5 if i > 0 && i % 25 == 0
        cand = rand(NB_POKEMON) + 1
        next if species_banned?(cand)
        next if first_stage && family_of(cand)[1] != 1
        next if old && bst < 999 && bstNotOk(cand, old, bst)
        next if old && !legendaryOk(old, cand, false)
        return cand
      end
      return rand(NB_POKEMON) + 1
    end

    # Follow wild: the swap table, fusions part by part
    def self.follow_wild(old)
      h = $PokemonGlobal.psuedoBSTHash || {}
      return old if old >= Settings::ZAPMOLCUNO_NB
      if fused?(old)
        b, hd = parts_of(old)
        # With wild Fuse everything the table holds fusions; a fusion's
        # body part stands in for the body, its head for the head
        nb = dex_of(h[b] || b)
        nh = dex_of(h[hd] || hd)
        nb = parts_of(nb)[0] if fused?(nb)
        nh = parts_of(nh)[1] if fused?(nh)
        return fuse(nb, nh)
      end
      return dex_of(h[old] || old)
    end

    # Fuse everything: an unfused pick gets a partner; with a theme the
    # fusion keeps a themed type when it can
    def self.fuse_pick(dex, theme)
      return dex if fused?(dex) || dex >= Settings::ZAPMOLCUNO_NB || dex <= 0
      partner = random_base(dex)
      a = fuse(partner, dex)
      b = fuse(dex, partner)
      first, second = rand(2) == 0 ? [a, b] : [b, a]
      return first unless theme
      return first if theme_ok?(first, theme)
      return second if theme_ok?(second, theme)
      return first
    end

    #---------------------------------------------------------------------------
    # Rival: one replacement line per original line, same stage
    #---------------------------------------------------------------------------
    def self.family_of(dex)
      sp = (GameData::Species.get(dex).species rescue nil)
      info = sp && family_info[sp]
      return [dex, 1] unless info
      return [dex_of(info[0]), info[1]]
    end

    def self.evolve_n(dex, n)
      cur = dex
      n.times do
        evos = (GameData::Species.get(cur).get_evolutions(true) rescue [])
        break if evos.empty?
        nxt = dex_of(evos.first[0])
        break if nxt <= 0 || nxt > NB_POKEMON
        cur = nxt
      end
      return cur
    end

    def self.rival_part(map, part)
      base, stage = family_of(part)
      map[base] ||= random_base(base, true)
      return evolve_n(map[base], stage - 1)
    end

    def self.rival_pick(map, old)
      return old if old == Settings::RIVAL_STARTER_PLACEHOLDER_SPECIES || old >= Settings::ZAPMOLCUNO_NB
      if fused?(old)
        b, hd = parts_of(old)
        return fuse(rival_part(map, b), rival_part(map, hd))
      end
      new = rival_part(map, old)
      if dget(:trainer_fuse) == 1
        # The partner is a line too, at the same stage
        base, stage = family_of(old)
        key = "partner#{base}"
        map[key] ||= random_base(base, true)
        new = fuse(evolve_n(map[key], stage - 1), new)
      end
      return new
    end

    #---------------------------------------------------------------------------
    # The shuffle
    #---------------------------------------------------------------------------
    def self.extra_count(n)
      case dget(:team_size)
      when 1 then return [n + 1, 6].min - n
      when 2 then return [n + 2, 6].min - n
      when 3 then return 6 - n
      end
      return 0
    end

    # Follow wild needs the swap table even when no wild part is randomized;
    # made on its own seed (before the trainers' one) so it's the same table
    # either way
    def self.ensure_trainer_dex
      return unless trainer_mode == 2
      h = $PokemonGlobal.psuedoBSTHash
      return if h && !identity_dex?(h)
      Kernel.pbShuffleDex($game_variables[VAR_RANDOMIZER_WILD_POKE_BST])
    end

    def self.shuffle_trainers(customs = nil)
      customs = customs.map { |c| dex_of(c) }.select { |d| d > 0 } if customs
      customs = nil if customs && customs.empty?
      hash = {}
      rival_maps = {}
      themes_on = dget(:class_themes) > 0
      reset_theme_cache
      if themes_on && dget(:theme_shuffle) == 1
        make_theme_map
      else
        data[:theme_map] = nil
      end
      list = getTrainersDataMode.list_all.values.uniq { |t| t.id }
      list.each_with_index do |tr, ti|
        progress(_INTL("Shuffling trainers..."), ti.to_f / list.length) if ti % 40 == 0
        olds = tr.pokemon.map { |p| dex_of(p[:species]) }
        rival = dget(:rival_team) == 1 && RIVAL_TYPES.include?(tr.trainer_type)
        theme = themes_on ? class_theme(tr.trainer_type) : nil
        n = olds.length + extra_count(olds.length)
        team = []
        n.times do |i|
          old = olds[i] || olds[rand(olds.length)] || 1
          if rival
            map = (rival_maps[tr.real_name] ||= {})
            if i >= olds.length
              stage = olds.map { |o| family_of(fused?(o) ? parts_of(o)[1] : o)[1] }.max || 1
              key = "extra#{i}"
              map[key] ||= random_base(nil, true)
              dex = evolve_n(map[key], stage - 1)
              dex = fuse_pick(dex, nil) if dget(:trainer_fuse) == 1
            else
              dex = rival_pick(map, old)
            end
          else
            th = theme
            if i < olds.length && (old == Settings::RIVAL_STARTER_PLACEHOLDER_SPECIES || old >= Settings::ZAPMOLCUNO_NB)
              dex = old
            elsif trainer_mode == 2
              dex = follow_wild(old)
              dex = trainer_pick(old, th, customs) if th && !theme_ok?(dex, th)
            else
              dex = trainer_pick(old, th, customs)
            end
            dex = fuse_pick(dex, th) if dget(:trainer_fuse) == 1 && dex != Settings::RIVAL_STARTER_PLACEHOLDER_SPECIES
          end
          dex = dex_of(dex)
          unless valid_dex?(dex) || dex == old
            KIF.log("Randomizer: bad trainer Pokémon #{dex} for #{tr.real_name}, re-rolled")
            dex = dex_of(getNewSpecies(old, 999))
          end
          team << dex
        end
        hash[tr.id] = team
      end
      $PokemonGlobal.randomTrainersHash = hash
      return hash
    end

  end
end

#-------------------------------------------------------------------------------
# Extra team members (Team size)
#-------------------------------------------------------------------------------
module GameData
  class Trainer
    alias kif_rand_to_trainer to_trainer unless method_defined?(:kif_rand_to_trainer)

    def to_trainer
      trainer = kif_rand_to_trainer
      begin
        kif_add_extras(trainer)
      rescue => e
        KIF.log("Randomizer extra trainer Pokémon failed: #{e.message}")
      end
      return trainer
    end

    def kif_add_extras(trainer)
      return unless trainer && $game_switches && $game_switches[SWITCH_RANDOM_TRAINERS]
      return if $game_switches[SWITCH_FIRST_RIVAL_BATTLE]
      return if KIF::Rand.dget(:team_size) == 0
      th = $PokemonGlobal.randomTrainersHash
      team = th && th[self.id]
      return unless team && team.length > @pokemon.length
      party = trainer.party
      return if party.empty?
      level = (party.sum { |p| p.level }.to_f / party.length).round
      (@pokemon.length...team.length).each do |i|
        break if party.length >= Settings::MAX_PARTY_SIZE
        species = getSpecies(team[i])
        next unless species
        species = replace_species_to_randomized(species, self.id, i)
        species = replaceSingleSpeciesModeIfApplicable(species)
        species = reverseFusionSpecies(species) if $game_switches[SWITCH_REVERSED_MODE]
        sp = species.is_a?(GameData::Species) ? species.id : species
        pkmn = Pokemon.new(sp, level, trainer)
        pkmn.item = pbGetRandomHeldItem.id if $game_switches[SWITCH_RANDOM_HELD_ITEMS]
        pkmn.calc_stats
        party.push(pkmn)
      end
    end
  end
end
