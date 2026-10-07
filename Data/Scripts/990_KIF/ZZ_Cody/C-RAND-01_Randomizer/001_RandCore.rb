#===============================================================================
# C-RAND-01 – Randomizer, chunk 1: foundation (Cody, 2026-10-06)
#
# PIF's randomizer (025-Randomizer + Common Events 15 "SET RANDOMIZER OPTIONS"
# and 28 "APPLY randomizer options") keeps working; this layer adds:
#   * a seed (8 characters, ~1.1 trillion values). Every shuffle (Pokédex
#     swap, routes, trainers, gym teams, gym types, items, TMs) runs on its
#     own sub-seed (seed + part), so the same seed and settings give the same
#     game and changing one part doesn't reshuffle the others. The rest of the
#     game's randomness is untouched (the global RNG is re-seeded after).
#   * every part has its own switch (wild encounters Off/Swap/Route/Dynamic,
#     starters, static encounters, gifts, trades, ...); the Pokédex swap is
#     made whenever any part needs it.
#   * Dynamic wild encounters (any Pokémon, rolled on each encounter) and
#     randomized in-game trades (new).
#   * settings code (clipboard), presets (files), spoiler log (file + viewer),
#     "Randomize now" (see 002 / 003).
#   * route randomization is kept per save: PIF writes it to one shared file
#     (Data/encounters_randomized.dat); it's re-made from the save's seed when
#     another save changed it.
# PIF's own switches/variables stay the source of truth for its options.
#===============================================================================
class PokemonGlobalMetadata
  attr_writer :kif_rand
  def kif_rand
    @kif_rand ||= {}
    return @kif_rand
  end
end

module KIF
  module Rand
    ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"   # no I/O/0/1
    CODE_PREFIX = "KIFR2"
    LOG_PREFIX = "Randomizer Log - "
    RAND_DIR = "Randomizer"
    LOG_DIR = "Randomizer/Logs"
    PRESET_DIR = "Randomizer/Presets"
    ROUTE_SIG_FILE = "Data/encounters_randomized_kif.txt"

    # [key, kind, getter, setter, choices/range]
    #   :enum values are indices; :int is a number
    def self.sw(id);      return $game_switches[id] ? true : false; end
    def self.setsw(id, v); $game_switches[id] = v ? true : false; end

    SETTINGS = [
      # Pokémon
      [:wild_mode, :enum, 4],
      [:starters, :enum, 3],
      [:statics, :enum, 2],
      [:gifts, :enum, 2],
      [:trades, :enum, 2],
      [:wild_bst, :int, 999],
      [:wild_legend, :enum, 2],
      [:wild_custom, :enum, 2],
      [:fuse_all, :enum, 2],
      # Trainers
      [:trainers, :enum, 3],   # Off / Random / Follow wild
      [:trainer_bst, :int, 999],
      [:trainer_custom, :enum, 2],
      # Gyms
      [:gyms, :enum, 2],
      [:gym_custom, :enum, 2],
      [:gym_types, :enum, 2],
      [:gym_each, :enum, 2],
      # Items
      [:found_items, :enum, 2],
      [:found_tms, :enum, 2],
      [:given_items, :enum, 2],
      [:given_tms, :enum, 2],
      [:shop_items, :enum, 2],
      [:held_items, :enum, 3]  # Off / Random / Fixed
    ]

    def self.data
      return {} unless $PokemonGlobal
      return $PokemonGlobal.kif_rand
    end

    #---------------------------------------------------------------------------
    # Settings (PIF switches / variables where PIF has them)
    #---------------------------------------------------------------------------
    def self.get(key)
      return dget(key) if DATA_KEYS.include?(key)
      case key
      when :wild_mode
        return 0 unless sw(SWITCH_RANDOM_WILD) || data[:wild_mode]
        return 3 if data[:wild_mode] == 3
        return 2 if sw(SWITCH_RANDOM_WILD_AREA)
        return 1 if sw(SWITCH_WILD_RANDOM_GLOBAL)
        return 0
      when :starters
        return 0 unless sw(SWITCH_RANDOM_STARTERS)
        return sw(SWITCH_RANDOM_STARTER_FIRST_STAGE) ? 1 : 2
      when :statics      then return sw(SWITCH_RANDOM_STATIC_ENCOUNTERS) ? 1 : 0
      when :gifts        then return sw(SWITCH_RANDOM_GIFT_POKEMON) ? 1 : 0
      when :trades       then return data[:trades] ? 1 : 0
      when :wild_bst     then return $game_variables[VAR_RANDOMIZER_WILD_POKE_BST].to_i
      when :wild_legend  then return sw(SWITCH_RANDOM_WILD_LEGENDARIES) ? 1 : 0
      when :wild_custom  then return sw(SWITCH_RANDOM_WILD_ONLY_CUSTOMS) ? 1 : 0
      when :fuse_all     then return sw(SWITCH_RANDOM_WILD_TO_FUSION) ? 1 : 0
      when :trainers     then return 0 unless sw(SWITCH_RANDOM_TRAINERS)
                              return data[:trainer_follow] ? 2 : 1
      when :trainer_bst  then return $game_variables[VAR_RANDOMIZER_TRAINER_BST].to_i
      when :trainer_custom then return sw(600) ? 1 : 0
      when :gyms         then return sw(SWITCH_RANDOMIZE_GYMS_SEPARATELY) ? 1 : 0
      when :gym_custom   then return sw(SWITCH_RANDOM_GYM_CUSTOMS) ? 1 : 0
      when :gym_types    then return sw(SWITCH_RANDOMIZED_GYM_TYPES) ? 1 : 0
      when :gym_each     then return sw(SWITCH_GYM_RANDOM_EACH_BATTLE) ? 1 : 0
      when :found_items  then return sw(SWITCH_RANDOM_FOUND_ITEMS) ? 1 : 0
      when :found_tms    then return sw(SWITCH_RANDOM_FOUND_TMS) ? 1 : 0
      when :given_items  then return sw(SWITCH_RANDOM_GIVEN_ITEMS) ? 1 : 0
      when :given_tms    then return sw(SWITCH_RANDOM_GIVEN_TMS) ? 1 : 0
      when :shop_items   then return sw(SWITCH_RANDOM_SHOP_ITEMS) ? 1 : 0
      when :held_items   then return 0 unless sw(SWITCH_RANDOM_HELD_ITEMS)
                              return data[:held_fixed] ? 2 : 1
      end
      return 0
    end

    def self.set(key, v)
      return dset(key, v) if DATA_KEYS.include?(key)
      case key
      when :wild_mode
        data[:wild_mode] = v
        setsw(SWITCH_WILD_RANDOM_GLOBAL, v == 1)
        setsw(SWITCH_RANDOM_WILD_AREA, v == 2)
      when :starters
        setsw(SWITCH_RANDOM_STARTERS, v > 0)
        setsw(SWITCH_RANDOM_STARTER_FIRST_STAGE, v == 1)
      when :statics      then setsw(SWITCH_RANDOM_STATIC_ENCOUNTERS, v == 1)
      when :gifts        then setsw(SWITCH_RANDOM_GIFT_POKEMON, v == 1)
      when :trades       then data[:trades] = (v == 1)
      when :wild_bst     then $game_variables[VAR_RANDOMIZER_WILD_POKE_BST] = v.to_i
      when :wild_legend  then setsw(SWITCH_RANDOM_WILD_LEGENDARIES, v == 1)
      when :wild_custom  then setsw(SWITCH_RANDOM_WILD_ONLY_CUSTOMS, v == 1)
      when :fuse_all     then setsw(SWITCH_RANDOM_WILD_TO_FUSION, v == 1)
      when :trainers
        setsw(SWITCH_RANDOM_TRAINERS, v > 0)
        data[:trainer_follow] = (v == 2)
      when :trainer_bst  then $game_variables[VAR_RANDOMIZER_TRAINER_BST] = v.to_i
      when :trainer_custom then setsw(600, v == 1)
      when :gyms         then setsw(SWITCH_RANDOMIZE_GYMS_SEPARATELY, v == 1)
      when :gym_custom   then setsw(SWITCH_RANDOM_GYM_CUSTOMS, v == 1)
      when :gym_types    then setsw(SWITCH_RANDOMIZED_GYM_TYPES, v == 1)
      when :gym_each
        setsw(SWITCH_GYM_RANDOM_EACH_BATTLE, v == 1)
        setsw(SWITCH_RANDOM_GYM_PERSIST_TEAMS, v != 1)
      when :found_items
        setsw(SWITCH_RANDOM_FOUND_ITEMS, v == 1)
        setsw(SWITCH_RANDOM_ITEMS_MAPPED, v == 1)
      when :found_tms    then setsw(SWITCH_RANDOM_FOUND_TMS, v == 1)
      when :given_items  then setsw(SWITCH_RANDOM_GIVEN_ITEMS, v == 1)
      when :given_tms    then setsw(SWITCH_RANDOM_GIVEN_TMS, v == 1)
      when :shop_items   then setsw(SWITCH_RANDOM_SHOP_ITEMS, v == 1)
      when :held_items
        setsw(SWITCH_RANDOM_HELD_ITEMS, v > 0)
        data[:held_fixed] = (v == 2)
      end
      sync_masters
    end

    # PIF's "master" switches follow the parts
    def self.sync_masters
      return unless $game_switches
      poke = get(:wild_mode) > 0 || get(:starters) > 0 || get(:statics) == 1 ||
             get(:gifts) == 1 || get(:trades) == 1
      setsw(SWITCH_RANDOM_WILD, poke)
      setsw(SWITCH_RANDOM_ITEMS, sw(SWITCH_RANDOM_FOUND_ITEMS) || sw(SWITCH_RANDOM_GIVEN_ITEMS))
      setsw(SWITCH_RANDOM_TMS, sw(SWITCH_RANDOM_FOUND_TMS) || sw(SWITCH_RANDOM_GIVEN_TMS))
      setsw(SWITCH_RANDOM_ITEMS_GENERAL, sw(SWITCH_RANDOM_ITEMS) || sw(SWITCH_RANDOM_TMS) ||
                                         sw(SWITCH_RANDOM_SHOP_ITEMS) || sw(SWITCH_RANDOM_HELD_ITEMS))
    end

    def self.pokemon_parts_on?
      return $game_switches && sw(SWITCH_RANDOM_WILD)
    end

    # Randomizer button in Cody Settings: saves started as randomized saves
    def self.available?
      return $game_switches && $PokemonGlobal && sw(SWITCH_RANDOMIZED_AT_LEAST_ONCE)
    end

    def self.log_on?
      return data[:log] != false
    end

    #---------------------------------------------------------------------------
    # Seed
    #---------------------------------------------------------------------------
    def self.new_seed
      return Array.new(8) { ALPHABET[Random.new_seed % ALPHABET.length] }.join
    end

    def self.seed
      data[:seed] ||= new_seed
      return data[:seed]
    end

    def self.seed=(s)
      data[:seed] = s
    end

    def self.format_seed(s = seed)
      return "#{s[0, 4]}-#{s[4, 4]}"
    end

    # "k7q2 9xma" -> "K7Q29XMA" or nil
    def self.parse_seed(text)
      s = text.to_s.upcase.gsub(/[^A-Z0-9]/, "")
      return nil unless s.length == 8 && s.chars.all? { |c| ALPHABET.include?(c) }
      return s
    end

    def self.sub_seed(*parts)
      str = ([seed] + parts).map(&:to_s).join("|")
      return (Zlib.crc32(str) << 32) | Zlib.crc32(str.reverse + "kif")
    end

    @seeded = 0
    class << self
      attr_reader :seeded
    end

    # Runs the block on the seed's own random numbers for this part
    def self.with_seed(*parts)
      return yield if @seeded > 0
      @seeded += 1
      srand(sub_seed(*parts))
      memo_clear
      begin
        return yield
      ensure
        @seeded -= 1
        memo_clear
        srand(Random.new_seed)
      end
    end

    # While a seeded shuffle runs, base stat totals and legendary checks are
    # remembered per Pokémon: every candidate PIF tries builds a whole
    # FusedSpecies for them otherwise (and the "old" Pokémon is looked up
    # again on every try). Nothing about a Pokémon changes during a shuffle.
    @memo_bst = {}
    @memo_legend = {}
    def self.memo_clear
      @memo_bst = {}
      @memo_legend = {}
    end

    def self.memo_bst(dex)
      return nil unless @seeded > 0 && dex.is_a?(Integer)
      return @memo_bst[dex] if @memo_bst.key?(dex)
      return nil
    end

    def self.memo_bst_set(dex, v)
      @memo_bst[dex] = v if @seeded > 0 && dex.is_a?(Integer)
      return v
    end

    # (PIF's Pokédex shuffle asks with species symbols, the others with numbers)
    def self.memo_legend(dex)
      return nil unless @seeded > 0 && (dex.is_a?(Integer) || dex.is_a?(Symbol))
      return @memo_legend.key?(dex) ? @memo_legend[dex] : nil
    end

    def self.memo_legend_set(dex, v)
      @memo_legend[dex] = v if @seeded > 0 && (dex.is_a?(Integer) || dex.is_a?(Symbol))
      return v
    end

    # Dex number of a species, symbol, number or PIFSprite. PIF's swap table
    # and custom sprite lists can hold PIFSprites (seen in Cody's saves), and
    # getDexNumberForSpecies passes those through untouched.
    def self.dex_of(sp)
      return sp if sp.is_a?(Integer)
      return 0 if sp.nil?
      if sp.respond_to?(:head_id) && sp.respond_to?(:body_id)
        h = sp.head_id.to_i
        b = sp.body_id.to_i
        return b > 0 ? b * NB_POKEMON + h : h
      end
      return (GameData::Species.get(sp).id_number rescue 0)
    end

    #---------------------------------------------------------------------------
    # Settings code:
    #   KIFR2-SEED-<one character per setting>-<wild BST>-<trainer BST>-<bans>
    #   bans = "P" + Pokémon dex numbers, "M" + move numbers, "A" + ability
    #   numbers (base 36, dot-separated), joined by "~"
    #   KIFR1 codes (chunk 1, no data settings or bans) are still read.
    #---------------------------------------------------------------------------
    CODE_PREFIX_V1 = "KIFR1"

    def self.code_enums
      return SETTINGS.select { |s| s[1] == :enum } + DATA_SETTINGS
    end

    # GameData::Move.get doesn't take numbers; look them up once
    def self.by_number(gd, n)
      @by_number ||= {}
      unless @by_number[gd]
        h = {}
        gd.each { |o| h[o.id_number] ||= o }
        @by_number[gd] = h
      end
      return @by_number[gd][n]
    end

    BAN_TAGS = { "P" => [:pokemon, GameData::Species], "M" => [:moves, GameData::Move],
                 "A" => [:abilities, GameData::Ability], "I" => [:items, GameData::Item] }

    def self.bans_code
      parts = []
      BAN_TAGS.each do |tag, (kind, gd)|
        ids = bans(kind).map { |id| (gd.get(id).id_number rescue nil) }.compact.sort
        parts << tag + ids.map { |n| n.to_s(36) }.join(".")
      end
      return parts.join("~")
    end

    def self.settings_code
      flags = code_enums.map { |s| get(s[0]).to_s(36) }.join
      return [CODE_PREFIX, seed, flags, get(:wild_bst), get(:trainer_bst), bans_code].join("-")
    end

    # Returns [seed, {key => value}, bans or nil] or nil
    def self.parse_code(code)
      parts = code.to_s.strip.split("-")
      v1 = parts[0] == CODE_PREFIX_V1
      return nil unless (v1 && parts.length == 5) || (parts[0] == CODE_PREFIX && parts.length == 6)
      s = parse_seed(parts[1])
      enums = v1 ? SETTINGS.select { |x| x[1] == :enum } : code_enums
      # Codes from before newer settings existed are shorter; the rest keep
      # their defaults
      return nil unless s && (v1 ? parts[2].length == enums.length : parts[2].length.between?(1, enums.length))
      vals = {}
      enums.each_with_index do |(key, _k, max), i|
        if i >= parts[2].length
          vals[key] = (DATA_DEFAULTS[key] || 0)
          next
        end
        v = parts[2][i].to_i(36)
        return nil if v >= max
        vals[key] = v
      end
      return nil unless parts[3] =~ /\A\d+\z/ && parts[4] =~ /\A\d+\z/
      vals[:wild_bst] = [parts[3].to_i, 999].min
      vals[:trainer_bst] = [parts[4].to_i, 999].min
      bans = nil
      unless v1
        bans = { :pokemon => [], :moves => [], :abilities => [] }
        parts[5].split("~").each do |seg|
          kind, gd = BAN_TAGS[seg[0]]
          bans[kind] ||= []
          return nil unless kind
          seg[1..-1].split(".").each do |n|
            obj = by_number(gd, n.to_i(36))
            return nil unless obj
            bans[kind] << (kind == :pokemon ? obj.species : obj.id)
          end
        end
      end
      # Codes from before banned items existed: the default list
      bans[:items] ||= :default if bans
      return [s, vals, bans]
    end

    def self.apply_code(code)
      res = parse_code(code)
      return false unless res
      self.seed = res[0]
      res[1].each { |k, v| set(k, v) }
      if res[2]
        res[2].each { |kind, list| data[:"ban_#{kind}"] = (list == :default ? nil : list) }
      end
      return true
    end

    def self.make_dir(path)
      Dir.mkdir(RAND_DIR) unless Dir.exist?(RAND_DIR)
      Dir.mkdir(path) unless Dir.exist?(path)
    end

    #---------------------------------------------------------------------------
    # Presets: "Randomizer Presets/<name>.txt", first line = settings code
    #---------------------------------------------------------------------------
    def self.preset_names
      return [] unless Dir.exist?(PRESET_DIR)
      return Dir.glob("#{PRESET_DIR}/*.txt").map { |f| File.basename(f, ".txt") }.sort
    end

    def self.save_preset(name)
      clean = name.to_s.gsub(/[\\\/:*?"<>|]/, "").strip
      return false if clean.empty?
      make_dir(PRESET_DIR)
      File.open("#{PRESET_DIR}/#{clean}.txt", "wb") do |f|
        f.write(settings_code + "\r\n")
        f.write("# KIF Beta randomizer preset. The first line is the settings code;\r\n")
        f.write("# paste it in Randomizer > Presets & sharing > Paste settings code.\r\n")
      end
      return true
    end

    def self.load_preset(name)
      path = "#{PRESET_DIR}/#{name}.txt"
      return false unless File.exist?(path)
      line = File.readlines(path).map(&:strip).find { |l| l.start_with?(CODE_PREFIX) || l.start_with?(CODE_PREFIX_V1) }
      return line ? apply_code(line) : false
    end

    #---------------------------------------------------------------------------
    # Pokédex swap: made once whenever a Pokémon part needs it
    #---------------------------------------------------------------------------
    def self.identity_dex?(h)
      return true unless h
      h.each { |k, v| return false if k != v }
      return true
    end

    def self.ensure_dex
      return unless pokemon_parts_on?
      return if data[:dex_ok]
      if $PokemonGlobal.psuedoBSTHash && !identity_dex?($PokemonGlobal.psuedoBSTHash)
        data[:dex_ok] = true   # randomized before this layer existed
        return
      end
      Kernel.pbShuffleDex($game_variables[VAR_RANDOMIZER_WILD_POKE_BST])
    end

    # PIF's tables sometimes hold PIFSprite objects instead of dex numbers
    # (older saves). PIF's own code crashes on those (GameData::Species.get
    # refuses them), so they're turned into the numbers they stand for when a
    # save is loaded and after each shuffle. Same Pokémon, plain numbers.
    def self.sanitize_tables
      h = $PokemonGlobal.psuedoBSTHash
      if h.is_a?(Hash)
        h.each { |k, v| h[k] = dex_of(v) unless v.is_a?(Integer) }
      end
      t = $PokemonGlobal.randomTrainersHash
      if t.is_a?(Hash)
        t.each_value { |team| team.map! { |v| v.is_a?(Integer) ? v : dex_of(v) } if team.is_a?(Array) }
      end
    rescue => e
      KIF.log("Randomizer table clean-up failed: #{e.message}")
    end

    #---------------------------------------------------------------------------
    # Dynamic wild encounters
    #---------------------------------------------------------------------------
    def self.dynamic?
      return pokemon_parts_on? && data[:wild_mode] == 3
    end

    @custom_list = nil
    def self.custom_list
      path = Settings::CUSTOM_SPRITES_FILE_PATH
      mtime = File.exist?(path) ? File.mtime(path) : nil
      if !@custom_list || @custom_list[0] != mtime
        list = getCustomSpeciesList rescue []
        @custom_list = [mtime, list || []]
      end
      return @custom_list[1]
    end

    def self.dynamic_species(old_species)
      fusions = sw(SWITCH_RANDOM_WILD_TO_FUSION)
      pool = (fusions && sw(SWITCH_RANDOM_WILD_ONLY_CUSTOMS)) ? custom_list : nil
      pool = nil if pool && pool.length < 50
      max = fusions ? PBSpecies.maxValue : NB_POKEMON
      legend = sw(SWITCH_RANDOM_WILD_LEGENDARIES)
      old_dex = getDexNumberForSpecies(old_species) rescue nil
      # Strength range applies to Dynamic too (Cody): the pick stays within
      # range of the usual Pokémon, widening a little when nothing fits
      bst = get(:wild_bst)
      300.times do |i|
        bst += 5 if i > 0 && i % 20 == 0 && bst < 999
        pick = dex_of(pool ? pool.sample : rand(max) + 1)
        next if pick <= 0 || pick >= Settings::ZAPMOLCUNO_NB
        next unless (GameData::Species.exists?(pick) rescue false)
        next if species_banned?(pick)
        next unless old_dex.nil? || legendaryOk(old_dex, pick, legend)
        next if old_dex && bst < 999 && bstNotOk(pick, old_dex, bst)
        return GameData::Species.get(pick).species
      end
      return old_species   # nothing allowed came up: the usual Pokémon
    rescue => e
      KIF.log("Dynamic encounter failed: #{e.message}")
      return old_species
    end

    #---------------------------------------------------------------------------
    # Route randomization belongs to a save
    #---------------------------------------------------------------------------
    def self.route_signature
      return [seed, get(:wild_bst), get(:wild_legend), get(:wild_custom), get(:fuse_all)].join("|")
    end

    def self.file_route_signature
      return File.exist?(ROUTE_SIG_FILE) ? File.read(ROUTE_SIG_FILE).strip : nil
    end

    def self.mark_routes
      File.open(ROUTE_SIG_FILE, "wb") { |f| f.write(route_signature) } rescue nil
      data[:route_sig] = route_signature
    end

    def self.ensure_routes
      return unless pokemon_parts_on? && sw(SWITCH_RANDOM_WILD_AREA)
      file = file_route_signature
      if data[:route_sig].nil?
        # Randomized before this layer: the file is assumed to be this save's
        if file
          data[:route_sig] = file
        else
          mark_routes
        end
        return
      end
      return if file == data[:route_sig]
      Kernel.randomizeWildPokemonByRoute
    end

    #---------------------------------------------------------------------------
    # Lightweight progress (no map updates, so seeded shuffles stay exact)
    #---------------------------------------------------------------------------
    @progress = nil
    def self.progress(text, frac)
      unless @progress && !@progress.disposed?
        vp = Viewport.new(0, Graphics.height - 64, Graphics.width, 64)
        vp.z = 999999
        @progress = BitmapSprite.new(Graphics.width, 64, vp)
        @progress_vp = vp
      end
      bmp = @progress.bitmap
      bmp.clear
      bmp.fill_rect(0, 0, bmp.width, 64, Color.new(16, 16, 24, 220))
      bmp.fill_rect(16, 44, ((bmp.width - 32) * [[frac, 0].max, 1].min).round, 8, Color.new(120, 200, 120))
      pbSetSystemFont(bmp)
      pbDrawTextPositions(bmp, [[text, 16, 6, 0, Color.new(248, 248, 248), Color.new(64, 64, 64)]])
      Graphics.update
    end

    def self.progress_done
      @progress.dispose if @progress && !@progress.disposed?
      @progress_vp.dispose if @progress_vp && !@progress_vp.disposed?
      @progress = @progress_vp = nil
    end
  end
end
