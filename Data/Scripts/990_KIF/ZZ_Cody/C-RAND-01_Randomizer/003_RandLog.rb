#===============================================================================
# C-RAND-01 – spoiler log: "Randomizer Log - <seed>.txt" next to Game.exe,
# rewritten after every shuffle (when Spoiler log is On), and an in-game
# viewer (Randomizer > View spoiler log, asks first).
#===============================================================================
module KIF
  module Rand
    LABELS = {
      :wild_mode => ["Wild encounters", ["Off", "Swap", "Route", "Dynamic"]],
      :starters => ["Starters", ["Off", "1st stage", "Any"]],
      :statics => ["Static encounters", ["Off", "On"]],
      :gifts => ["Gift Pokémon", ["Off", "On"]],
      :trades => ["Trades", ["Off", "On"]],
      :wild_bst => ["Strength range (Pokémon)", nil],
      :wild_legend => ["Legendaries", ["Off", "On"]],
      :wild_custom => ["Custom sprites only", ["Off", "On"]],
      :fuse_all => ["Fuse everything", ["Off", "On"]],
      :trainers => ["Trainers", ["Off", "On"]],
      :trainer_bst => ["Strength range (trainers)", nil],
      :trainer_custom => ["Trainer custom sprites only", ["Off", "On"]],
      :gyms => ["Gym trainers", ["Off", "On"]],
      :gym_custom => ["Gym custom sprites only", ["Off", "On"]],
      :gym_types => ["Gym types", ["Off", "On"]],
      :gym_each => ["Rerandomize each battle", ["Off", "On"]],
      :found_items => ["Found items", ["Off", "On"]],
      :found_tms => ["Found TMs", ["Off", "On"]],
      :given_items => ["Given items", ["Off", "On"]],
      :given_tms => ["Given TMs", ["Off", "On"]],
      :shop_items => ["Shop items", ["Off", "On"]],
      :held_items => ["Trainer held items", ["Off", "On"]]
    }

    def self.log_path
      return "#{LOG_DIR}/#{LOG_PREFIX}#{format_seed}.txt"
    end

    # Triple fusions have dex numbers from 999999; GameData::Species.get reads
    # such a number as a (broken) fusion and PIF pops up "species with error"
    @triples = nil
    def self.triple_names
      unless @triples
        @triples = {}
        GameData::Species.each { |sp| @triples[sp.id_number] = sp.real_name if sp.id_number >= Settings::ZAPMOLCUNO_NB } rescue nil
      end
      return @triples
    end

    def self.species_name(dex)
      if dex.is_a?(Integer)
        return triple_names[dex] || dex.to_s if dex >= Settings::ZAPMOLCUNO_NB
        if dex > NB_POKEMON
          body = getBodyID(dex)
          head = getHeadID(dex, body)
          return dex.to_s if body > NB_POKEMON || head > NB_POKEMON || body < 1 || head < 1
        end
      end
      return GameData::Species.get(dex).real_name rescue dex.to_s
    end

    def self.item_name(id)
      return GameData::Item.get(id).name rescue id.to_s
    end

    def self.type_name(id)
      return GameData::Type.get(id).name rescue id.to_s
    end

    # [[section title, [lines]], ...]
    def self.build_log
      out = []
      head = []
      head << "Seed: #{format_seed}"
      head << "Settings code: #{settings_code}"
      head << "Made: #{Time.now.strftime('%Y-%m-%d %H:%M')}"
      count = (File.foreach(Settings::CUSTOM_SPRITES_FILE_PATH).count rescue 0)
      head << "Custom sprite list: #{count} entries (same seed = same game on the same KIF Beta version and sprite pack)"
      out << ["General", head]
      out << ["Settings", SETTINGS.map { |key, _k, _m|
        name, vals = LABELS[key]
        v = get(key)
        "#{name}: #{vals ? vals[v] : v}"
      }]
      hash = $PokemonGlobal.psuedoBSTHash
      if pokemon_parts_on? && hash && !identity_dex?(hash)
        whole = get(:wild_mode) == 1 || get(:statics) == 1 || get(:gifts) == 1 || get(:trades) == 1
        lines = []
        (1..NB_POKEMON).each do |i|
          next unless hash[i]
          lines << sprintf("#%03d %s -> %s", i, species_name(i), species_name(hash[i]))
        end
        out << ["Pokémon swaps", lines] if whole
        if get(:starters) > 0
          out << ["Starters", [1, 4, 7].map { |d|
            to = (obtainRandomizedStarter([1, 4, 7].index(d)) rescue hash[d])
            "#{species_name(d)} -> #{species_name(to)}"
          }]
        end
      end
      if pokemon_parts_on? && sw(SWITCH_RANDOM_WILD_AREA)
        lines = []
        begin
          GameData::EncounterRandom.each do |enc|
            map = (pbGetMapNameFromId(enc.map) rescue enc.map.to_s)
            enc.types.each do |type, list|
              names = list.map { |e| species_name(e[1]) }.uniq
              lines << "#{map} (#{type}): #{names.join(', ')}"
            end
          end
        rescue => e
          lines << "(routes unavailable: #{e.message})"
        end
        out << ["Routes", lines]
      end
      th = $PokemonGlobal.randomTrainersHash
      if sw(SWITCH_RANDOM_TRAINERS) && th
        lines = []
        begin
          seen = {}
          getTrainersDataMode.list_all.each do |_key, tr|
            next if seen[tr.id]   # PIF's trainer data lists each trainer under two keys
            seen[tr.id] = true
            team = th[tr.id]
            next unless team
            tname = (GameData::TrainerType.get(tr.trainer_type).name rescue tr.trainer_type.to_s)
            old = tr.pokemon.map { |p| species_name(p[:species]) }.join(", ")
            new = team.map { |d| species_name(d) }.join(", ")
            lines << "#{tname} #{tr.real_name}: #{old} -> #{new}"
          end
        rescue => e
          lines << "(trainers unavailable: #{e.message})"
        end
        out << ["Trainers", lines]
      end
      if sw(SWITCH_RANDOMIZED_GYM_TYPES) && $game_variables[VAR_GYM_TYPES_ARRAY].is_a?(Array)
        base = (GYM_TYPES_ARRAY rescue [])
        lines = []
        $game_variables[VAR_GYM_TYPES_ARRAY].each_with_index do |t, i|
          from = base[i] ? type_name(base[i]) : "?"
          lines << "Gym #{i + 1}: #{from} -> #{type_name(t)}"
        end
        out << ["Gym types", lines]
      end
      ih = $PokemonGlobal.randomItemsHash
      if ih && !ih.empty? && (sw(SWITCH_RANDOM_ITEMS) || sw(SWITCH_RANDOM_SHOP_ITEMS))
        out << ["Items", ih.map { |a, b| "#{item_name(a)} -> #{item_name(b)}" }]
      end
      tm = $PokemonGlobal.randomTMsHash
      if tm && !tm.empty? && sw(SWITCH_RANDOM_TMS)
        out << ["TMs", tm.map { |a, b| "#{item_name(a)} -> #{item_name(b)}" }]
      end
      return out
    end

    def self.write_log
      return unless log_on? && $PokemonGlobal && $game_switches
      sections = build_log
      make_dir(LOG_DIR)
      File.open(log_path, "wb") do |f|
        f.write("KIF Beta - Randomizer spoiler log\r\n")
        sections.each do |title, lines|
          f.write("\r\n== #{title} ==\r\n")
          lines.each { |l| f.write(l + "\r\n") }
        end
      end
    rescue => e
      KIF.log("Spoiler log failed: #{e.message}")
    end

    def self.view_log
      return unless pbConfirmMessage(_INTL("The spoiler log shows everything that was randomized. View it?"))
      sections = build_log
      loop do
        titles = sections.map { |t, l| "#{t} (#{l.length})" }
        pick = pbMessage(_INTL("Which part?"), titles + [_INTL("Close")], titles.length + 1)
        break if pick < 0 || pick >= titles.length
        show_lines(sections[pick][0], sections[pick][1])
      end
    end

    def self.show_lines(title, lines)
      lines = [_INTL("(nothing)")] if lines.empty?
      vp = Viewport.new(0, 0, Graphics.width, Graphics.height)
      vp.z = 999999
      head = Window_UnformattedTextPokemon.newWithSize(title, 0, 0, Graphics.width, 64, vp)
      win = Window_CommandPokemon.newWithSize(lines, 0, 64, Graphics.width, Graphics.height - 64, vp)
      pbSetSmallFont(win.contents) rescue nil
      win.index = 0
      loop do
        Graphics.update
        Input.update
        win.update
        break if Input.trigger?(Input::BACK) || Input.trigger?(Input::USE)
      end
      pbPlayCancelSE
      win.dispose
      head.dispose
      vp.dispose
    end
  end
end
