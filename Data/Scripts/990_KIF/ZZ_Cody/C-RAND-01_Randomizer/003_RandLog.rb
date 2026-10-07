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
      :trainers => ["Trainers", ["Off", "Random", "Follow wild"]],
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
      :held_items => ["Trainer held items", ["Off", "Random", "Fixed"]],
      :types => ["Types", ["Same", "Random", "Dual"]],
      :type_orig => ["Original type", ["Allowed", "Never"]],
      :moves_follow => ["Moves follow type", ["Off", "On"]],
      :tms_follow => ["TMs follow type", ["Off", "On"]],
      :abilities => ["Abilities", ["Same", "Random", "Type-flavoured", "Type-bound"]],
      :no_selfharm => ["No self-harm", ["Off", "On"]],
      :stats => ["Base stats", ["Same", "Shuffle", "Total", "Chaos"]],
      :chaos_safety => ["Chaos safety", ["Off", "Total", "Each stat"]],
      :evolutions => ["Evolutions", ["Same", "Random"]],
      :evo_typed => ["Type-themed evolutions", ["Off", "On"]],
      :class_themes => ["Class themes", ["Off", "On"]],
      :theme_shuffle => ["Shuffle themes", ["Off", "On"]],
      :extra_themes => ["Extra class themes", ["Off", "On"]],
      :item_mode => ["Item mode", ["Mapped", "Dynamic"]],
      :keep_categories => ["Keep item categories", ["Off", "On"]],
      :shop_basics => ["Keep shop basics", ["Off", "On"]],
      :rival_team => ["Rival keeps his team", ["Off", "On"]],
      :team_size => ["Team size", ["Same", "+1", "+2", "Full"]],
      :trainer_fuse => ["Trainer fuse everything", ["Off", "On"]]
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
      dex = dex_of(dex) unless dex.is_a?(Symbol) || dex.is_a?(String)
      if dex.is_a?(Integer)
        return "?" if dex <= 0
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

    #---------------------------------------------------------------------------
    # Sections. Each is [title, proc] so the in-game viewer only builds the
    # part that is opened (the Pokémon data and trainer parts take seconds);
    # the file gets them all.
    #---------------------------------------------------------------------------
    def self.sections
      out = []
      out << ["General", method(:sec_general)]
      out << ["Settings", method(:sec_settings)]
      out << ["Exclusions", method(:sec_exclusions)] if [:pokemon, :moves, :abilities].any? { |k| !bans(k).empty? }
      out << ["Pokémon data", method(:sec_pokemon_data)] if data[:species] && !data[:species].empty?
      hash = $PokemonGlobal.psuedoBSTHash
      follow = sw(SWITCH_RANDOM_TRAINERS) && get(:trainers) == 2
      if (pokemon_parts_on? || follow) && hash && !identity_dex?(hash)
        # Trainers on Follow wild use the table too, even with wild Pokémon Off
        whole = get(:wild_mode) == 1 || get(:statics) == 1 || get(:gifts) == 1 || get(:trades) == 1 || follow
        out << ["Pokémon swaps", method(:sec_swaps)] if whole
        out << ["Starters", method(:sec_starters)] if pokemon_parts_on? && get(:starters) > 0
      end
      out << ["Routes", method(:sec_routes)] if pokemon_parts_on? && sw(SWITCH_RANDOM_WILD_AREA)
      if sw(SWITCH_RANDOM_TRAINERS) && $PokemonGlobal.randomTrainersHash
        out << ["Trainers", method(:sec_trainers)]
        out << ["Class themes", method(:class_theme_lines)] if dget(:class_themes) > 0
      end
      out << ["Gym types", method(:sec_gym_types)] if sw(SWITCH_RANDOMIZED_GYM_TYPES) && $game_variables[VAR_GYM_TYPES_ARRAY].is_a?(Array)
      if dynamic_items?
        out << ["Items and TMs (Dynamic, by spot)", method(:dynamic_item_lines)] if sw(SWITCH_RANDOM_ITEMS) || sw(SWITCH_RANDOM_TMS)
        out << ["Shops", proc { ["Dynamic: every shop rolls its own stock."] }] if sw(SWITCH_RANDOM_SHOP_ITEMS)
      else
        ih = $PokemonGlobal.randomItemsHash
        out << ["Items", method(:sec_items)] if ih && !ih.empty? && (sw(SWITCH_RANDOM_ITEMS) || sw(SWITCH_RANDOM_SHOP_ITEMS))
        tm = $PokemonGlobal.randomTMsHash
        out << ["TMs", method(:sec_tms)] if tm && !tm.empty? && sw(SWITCH_RANDOM_TMS)
      end
      out << ["Banned items", method(:sec_banned_items)] if sw(SWITCH_RANDOM_ITEMS_GENERAL) && !item_bans.empty?
      return out
    end

    # [[section title, [lines]], ...] – everything built (for the file)
    def self.build_log
      return sections.map { |title, body| [title, section_lines(body)] }
    end

    def self.section_lines(body)
      lines = body.call
      return lines.is_a?(Array) ? lines : [lines.to_s]
    rescue => e
      return ["(unavailable: #{e.message})"]
    end

    def self.sec_general
      head = []
      head << "Seed: #{format_seed}"
      head << "Settings code: #{settings_code}"
      head << "Made: #{Time.now.strftime('%Y-%m-%d %H:%M')}"
      count = (File.foreach(Settings::CUSTOM_SPRITES_FILE_PATH).count rescue 0)
      head << "Custom sprite list: #{count} entries (same seed = same game on the same KIF Beta version and sprite pack)"
      return head
    end

    def self.sec_settings
      return (SETTINGS + DATA_SETTINGS).map { |key, _k, _m|
        name, vals = LABELS[key]
        v = get(key)
        "#{name || key}: #{vals ? vals[v] : v}"
      }
    end

    def self.sec_exclusions
      bl = [:pokemon, :moves, :abilities].map { |k| [k, bans(k)] }.reject { |_k, l| l.empty? }
      return bl.map { |k, l|
        names = l.map { |id|
          case k
          when :pokemon then species_name(id)
          when :moves then (GameData::Move.get(id).name rescue id.to_s)
          else (GameData::Ability.get(id).name rescue id.to_s)
          end
        }
        "#{k.to_s.capitalize}: #{names.join(', ')}"
      }
    end

    def self.sec_pokemon_data
      sp = data[:species] || {}
      lines = []
      originals.keys.sort_by { |s| GameData::Species.get(s).id_number }.each do |s|
        ch = sp[s]
        next unless ch
        g = GameData::Species.get(s)
        bits = []
        bits << [type_name(g.type1), (g.type2 != g.type1 ? type_name(g.type2) : nil)].compact.join("/") if ch.key?(:@type1)
        if ch.key?(:@abilities)
          ab = g.abilities.map { |a| GameData::Ability.get(a).name rescue a.to_s }.join(", ")
          hid = (g.hidden_abilities || []).map { |a| GameData::Ability.get(a).name rescue a.to_s }.join(", ")
          bits << (hid.empty? ? ab : "#{ab} (hidden: #{hid})")
        end
        if ch.key?(:@base_stats)
          st = STAT_ORDER.map { |k| g.base_stats[k] }
          bits << "#{st.join('/')} (#{st.sum})"
        end
        if ch.key?(:@evolutions)
          ev = g.get_evolutions(true).map { |e| "#{species_name(e[0])} (#{e[1]}#{e[2] ? ' ' + e[2].to_s : ''})" }
          bits << "evolves into #{ev.join(', ')}" unless ev.empty?
        end
        if ch.key?(:@moves)
          diff = orig(s, :@moves).zip(g.moves).select { |a, b| a && b && a[1] != b[1] }
          bits << "moves: " + diff.map { |a, b| "Lv#{a[0]} #{GameData::Move.get(a[1]).name}->#{GameData::Move.get(b[1]).name}" }.join(", ") unless diff.empty?
        end
        lines << sprintf("#%03d %s: %s", g.id_number, g.real_name, bits.join(" | ")) unless bits.empty?
      end
      return lines
    end

    def self.sec_swaps
      hash = $PokemonGlobal.psuedoBSTHash || {}
      lines = []
      (1..NB_POKEMON).each do |i|
        next unless hash[i]
        lines << sprintf("#%03d %s -> %s", i, species_name(i), species_name(hash[i]))
      end
      return lines
    end

    def self.sec_starters
      hash = $PokemonGlobal.psuedoBSTHash || {}
      return [1, 4, 7].map { |d|
        to = (obtainRandomizedStarter([1, 4, 7].index(d)) rescue hash[d])
        "#{species_name(d)} -> #{species_name(to)}"
      }
    end

    def self.sec_routes
      lines = []
      GameData::EncounterRandom.each do |enc|
        map = (pbGetMapNameFromId(enc.map) rescue enc.map.to_s)
        enc.types.each do |type, list|
          names = list.map { |e| species_name(e[1]) }.uniq
          lines << "#{map} (#{type}): #{names.join(', ')}"
        end
      end
      return lines
    end

    def self.sec_trainers
      th = $PokemonGlobal.randomTrainersHash || {}
      lines = []
      seen = {}
      getTrainersDataMode.list_all.each do |_key, tr|
        next if seen[tr.id]   # PIF's trainer data lists each trainer under two keys
        seen[tr.id] = true
        team = th[tr.id]
        next unless team
        tname = (GameData::TrainerType.get(tr.trainer_type).name rescue tr.trainer_type.to_s)
        old = tr.pokemon.map { |p| species_name(p[:species]) }.join(", ")
        new = team.map { |d| species_name(d) }.join(", ")
        ct = dget(:class_themes) > 0 ? class_theme(tr.trainer_type) : nil
        tag = ct ? " [#{ct.map { |x| type_name(x) }.join('/')}]" : ""
        line = "#{tname} #{tr.real_name}#{tag}: #{old} -> #{new}"
        if get(:held_items) == 2
          held = (0...team.length).map { |i| item_name(fixed_held(tr.id, i)) }
          line += " | held: #{held.join(', ')}"
        end
        lines << line
      end
      return lines
    end

    def self.sec_gym_types
      base = (GYM_TYPES_ARRAY rescue [])
      lines = []
      $game_variables[VAR_GYM_TYPES_ARRAY].each_with_index do |t, i|
        from = base[i] ? type_name(base[i]) : "?"
        lines << "Gym #{i + 1}: #{from} -> #{type_name(t)}"
      end
      return lines
    end

    def self.sec_items
      return ($PokemonGlobal.randomItemsHash || {}).map { |a, b| "#{item_name(a)} -> #{item_name(b)}" }
    end

    def self.sec_tms
      return ($PokemonGlobal.randomTMsHash || {}).map { |a, b| "#{item_name(a)} -> #{item_name(b)}" }
    end

    def self.sec_banned_items
      return [item_bans.map { |i| item_name(i) }.join(", ")]
    end

    # Randomize now shuffles several parts in a row; the log is written once
    # at the end instead of after each part (each write builds every section)
    @log_suspended = false
    class << self
      attr_accessor :log_suspended
    end

    def self.write_log
      return if @log_suspended
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
      secs = sections
      loop do
        titles = secs.map { |t, _b| t }
        pick = pbMessage(_INTL("Which part?"), titles + [_INTL("Close")], titles.length + 1)
        break if pick < 0 || pick >= titles.length
        show_lines(secs[pick][0], section_lines(secs[pick][1]))
      end
    end

    # Word-wraps one log line to the reader's width. " | " parts (Pokémon
    # data) go on their own lines; wrapped parts are indented.
    def self.wrap_line(bmp, line, width)
      out = []
      parts = line.split(" | ")
      parts.each_with_index do |part, pi|
        indent = (pi > 0) ? "    " : ""
        cur = indent
        part.split(" ").each do |word|
          test = (cur.strip.empty?) ? cur + word : "#{cur} #{word}"
          if bmp.text_size(test).width > width && !cur.strip.empty?
            out << cur
            cur = "    #{word}"
          else
            cur = test
          end
        end
        out << cur
      end
      return out
    end

    # Reader for one log section: Up/Down scroll, Left/Right a page, B/A close
    def self.show_lines(title, lines)
      lines = [_INTL("(nothing)")] if lines.empty?
      vp = Viewport.new(0, 0, Graphics.width, Graphics.height)
      vp.z = 999999
      head = Window_UnformattedTextPokemon.newWithSize(title, 0, 0, Graphics.width, 64, vp)
      win = SpriteWindow_Base.new(0, 64, Graphics.width, Graphics.height - 64)
      win.viewport = vp
      win.setSkin(MessageConfig.pbGetSystemFrame) rescue nil
      # Solid windows, so the menu behind doesn't show through the text
      head.back_opacity = 255
      win.back_opacity = 255
      cw = win.width - win.borderX
      ch = win.height - win.borderY
      win.contents = Bitmap.new(cw, ch)
      pbSetSmallFont(win.contents) rescue nil
      base, shadow = (getDefaultTextColors(win.windowskin) rescue [Color.new(80, 80, 88), Color.new(160, 160, 168)])
      lh = 26
      rows = []
      lines.each { |l| rows.concat(wrap_line(win.contents, l, cw - 12)) }
      per = ch / lh
      maxtop = [rows.length - per, 0].max
      top = 0
      draw = proc {
        win.contents.clear
        rows[top, per].each_with_index do |r, k|
          pbDrawShadowText(win.contents, 4, k * lh, cw - 8, lh, r, base, shadow)
        end
        pos = rows.length > per ? "#{top + 1}-#{[top + per, rows.length].min}/#{rows.length}" : ""
        head.text = pos.empty? ? title : "#{title}  (#{pos})"
      }
      draw.call
      loop do
        Graphics.update
        Input.update
        old = top
        if Input.repeat?(Input::DOWN) then top += 1
        elsif Input.repeat?(Input::UP) then top -= 1
        elsif Input.repeat?(Input::RIGHT) || Input.repeat?(Input::JUMPDOWN) then top += per - 1
        elsif Input.repeat?(Input::LEFT) || Input.repeat?(Input::JUMPUP) then top -= per - 1
        elsif Input.trigger?(Input::BACK) || Input.trigger?(Input::USE) then break
        end
        top = top.clamp(0, maxtop)
        draw.call if top != old
      end
      pbPlayCancelSE
      win.contents.dispose
      win.dispose
      head.dispose
      vp.dispose
      eat_input
    end
  end
end
