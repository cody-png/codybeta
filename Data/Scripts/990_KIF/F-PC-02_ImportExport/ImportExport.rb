#===============================================================================
# F-PC-02 – Pokémon Import / Export (.json + .png)
# Source: KIF 0.20.7 (Reïzod)
#   016_UI/017_UI_PokemonStorage.rb
#     :2468-2528 pbExport, :2529-2564 logic_png, :2565-2663 pbExportBox /
#     pbExportAll, :3971-4087 build_tree / build_jsons / navigationSystem,
#     :4387-4418 pbExportSelected, :4813-4830 box menu, :5265-5520 Import /
#     Import Randomly, :1846-1866 Kuray Actions "Export" / "Export All Pokemons",
#     :3265-3283 multi-select "Export"
#   014_Pokemon/001_Pokemon.rb:2235-2480  as_json / to_json / load_json
#   014_Pokemon/004_Pokemon_Move.rb, 005_Pokemon_Owner.rb  as_json / load_json
#   016_UI/015_UI_Options.rb:2958-3005 options, :2725 "Debug Exclusive"
#
# Files go to the "ExportedPokemons" folder in the game folder, named
#   <Species>-<Nickname>-<personalID>-<gender>-<level>.json (+ .png)
# PC box menu: Export this Box, Export All (skips export-locked boxes, also
#   exports the party), Import (pick a folder: <This Folder>, <This
#   Folder+Sub-Folders>, <Random Sub-Folder> or browse), Import Randomly
#   (one random file). Imports fill the current box, then Box 1 onwards.
# Kuray Actions: Export, Export All Pokemons. Multi-select: Export.
# Options (Self-Battle & Import): Import Level, Import De-Evolve, Import as
#   Egg, Import Without Deletion, Delete on Export, Export Sprite on Export
#   (On / Off / Shiny), Import Sprite on Import (On / Read-Only / Off).
# "Debug Exclusive" (Others, global): when On, export/import need Debug mode.
#
# 6.8.2 adaptations / safety:
#   * The files use KIF's format (a Ruby hash literal, despite the .json
#     name), so KIF exports and the KIF Pokémon Bank import here and these
#     exports import in KIF. KIF read them with eval, which runs any code a
#     shared file contains; here they are read by a small parser that only
#     accepts plain data (hashes, arrays, strings, symbols, numbers,
#     true/false/nil). Real JSON is accepted too.
#   * Data that 6.8.2 adds (hats, chosen sprite, original head/body of a
#     fusion, ...) is saved under "pif_extra"; KIF ignores that key.
#   * Unknown species skip the file; unknown moves, items, abilities and
#     natures are dropped (KIF crashed on them). The import ends with how many
#     files could not be read.
#   * PNG export: 6.8.2 keeps sprites in spritesheets, so the Pokémon's current
#     sprite is saved (plain colours for "On"; with its shiny colours for
#     "Shiny", the .json then being un-shinied as in KIF). PNG import stores
#     the path like KIF (kuraycustomfile); it is only shown once Individual
#     Custom Sprites (F-POKE-07) is ported.
#   * The party is never emptied: Export All and the party menu don't delete
#     party Pokémon (KIF's Export All deleted the wrong slots there).
#   * Nothing is imported into the Hoenn transfer box.
#===============================================================================
KIF::Options.define(:importlvl, 0, :save)
KIF::Options.define(:importdevolve, 0, :save)
KIF::Options.define(:importegg, 0, :save)
KIF::Options.define(:importnodelete, 0, :save)
KIF::Options.define(:exportdelete, 0, :save)
KIF::Options.define(:nopngexport, 0, :save)
KIF::Options.define(:nopngimport, 0, :save)
KIF::Options.define(:debugfeature, 0, :global)

KIF::Options.add(:selfbattle, :save) {
  EnumOption.new(_INTL("Import Level"), [_INTL("Default"), _INTL("1"), _INTL("5"), _INTL("50"), _INTL("100")],
                 proc { $PokemonSystem.importlvl },
                 proc { |value| $PokemonSystem.importlvl = value },
                 [_INTL("Imported Pokemons keep their original level."),
                  _INTL("Imported Pokemons are set to level 1."),
                  _INTL("Imported Pokemons are set to level 5."),
                  _INTL("Imported Pokemons are set to level 50."),
                  _INTL("Imported Pokemons are set to level 100.")])
}
KIF::Options.add(:selfbattle, :save) {
  EnumOption.new(_INTL("Import De-Evolve"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.importdevolve },
                 proc { |value| $PokemonSystem.importdevolve = value },
                 [_INTL("Imported Pokemons remain intact."),
                  _INTL("Imported Pokemons are de-evolved into babies.")])
}
KIF::Options.add(:selfbattle, :save) {
  EnumOption.new(_INTL("Import as Egg"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.importegg },
                 proc { |value| $PokemonSystem.importegg = value },
                 [_INTL("Imported Pokemons remain intact."),
                  _INTL("Imported Pokemons are turned into eggs.")])
}
KIF::Options.add(:selfbattle, :save) {
  EnumOption.new(_INTL("Import Without Deletion"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.importnodelete },
                 proc { |value| $PokemonSystem.importnodelete = value },
                 [_INTL("Imported Pokemons will have their .json deleted."),
                  _INTL("Imported Pokemons will remain as .json in Import folder.")])
}
KIF::Options.add(:selfbattle, :save) {
  EnumOption.new(_INTL("Delete on Export"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.exportdelete },
                 proc { |value| $PokemonSystem.exportdelete = value },
                 [_INTL("Exported Pokemons will not be deleted."),
                  _INTL("Exported Pokemons will be deleted.")])
}
KIF::Options.add(:selfbattle, :save) {
  EnumOption.new(_INTL("Export Sprite on Export"), [_INTL("On"), _INTL("Off"), _INTL("Shiny")],
                 proc { $PokemonSystem.nopngexport },
                 proc { |value| $PokemonSystem.nopngexport = value },
                 [_INTL("The .png of the Pokemon will also be exported."),
                  _INTL("The .png (appearence) of the Pokemon will not be exported."),
                  _INTL(".png exported as shiny, shiny appearence but pokemon un-shinified.")])
}
KIF::Options.add(:selfbattle, :save) {
  EnumOption.new(_INTL("Import Sprite on Import"), [_INTL("On"), _INTL("Read-Only"), _INTL("Off")],
                 proc { $PokemonSystem.nopngimport },
                 proc { |value| $PokemonSystem.nopngimport = value },
                 [_INTL("The .png of the Pokemon will also be imported."),
                  _INTL("The .png of the Pokemon will be read from the folder but not imported."),
                  _INTL("The .png (appearence) of the Pokemon will not be imported.")])
}
KIF::Options.add(:others, :global) {
  EnumOption.new(_INTL("Debug Exclusive"), [_INTL("Off"), _INTL("On")],
                 proc { $PokemonSystem.debugfeature },
                 proc { |value| $PokemonSystem.debugfeature = value },
                 [_INTL("Some debug features are available without debug (magic boots)"),
                  _INTL("All debug features requires debug (magic boots)")])
}

module KIF
  #-----------------------------------------------------------------------------
  # Reads KIF's export files without eval: plain data only.
  #-----------------------------------------------------------------------------
  module DataLiteral
    class ParseError < StandardError; end

    def self.parse(text)
      text = text.to_s.dup.force_encoding("UTF-8")
      text = text[1..-1] if text.start_with?("\uFEFF")
      p = Parser.new(text)
      v = p.value
      p.skip_ws
      raise ParseError, "trailing data" unless p.eof?
      return v
    end

    class Parser
      def initialize(s)
        @s = s.dup.force_encoding("UTF-8")
        @i = 0
        @depth = 0
      end

      def eof?; @i >= @s.length; end
      def peek; @s[@i]; end

      def skip_ws
        @i += 1 while @i < @s.length && " \t\r\n".include?(@s[@i])
      end

      def expect(str)
        skip_ws
        raise ParseError, "expected #{str} at #{@i}" unless @s[@i, str.length] == str
        @i += str.length
      end

      def value
        skip_ws
        raise ParseError, "unexpected end" if eof?
        @depth += 1
        raise ParseError, "too deep" if @depth > 64
        begin
          c = peek
          return hash  if c == "{"
          return array if c == "["
          return string(c) if c == '"' || c == "'"
          return symbol if c == ":"
          return number if c =~ /[-+0-9]/
          word = @s[@i..-1][/\A[A-Za-z_]+/]
          case word
          when "nil", "null" then @i += word.length; return nil
          when "true"        then @i += 4; return true
          when "false"       then @i += 5; return false
          end
          raise ParseError, "unexpected '#{c}' at #{@i}"
        ensure
          @depth -= 1
        end
      end

      def hash
        expect("{")
        ret = {}
        skip_ws
        if peek == "}"
          @i += 1
          return ret
        end
        loop do
          skip_ws
          key = nil
          label = @s[@i..-1][/\A[A-Za-z_][A-Za-z0-9_]*[?!]?:(?!:)/]
          if label                       # {HP: 1} (newer Ruby inspect)
            @i += label.length
            key = label[0..-2].to_sym
          else
            key = value
            skip_ws
            if @s[@i, 2] == "=>"
              @i += 2
            elsif peek == ":"
              @i += 1                    # JSON
            else
              raise ParseError, "expected => at #{@i}"
            end
          end
          ret[key] = value
          skip_ws
          if peek == ","
            @i += 1
            next
          end
          expect("}")
          return ret
        end
      end

      def array
        expect("[")
        ret = []
        skip_ws
        if peek == "]"
          @i += 1
          return ret
        end
        loop do
          ret << value
          skip_ws
          if peek == ","
            @i += 1
            next
          end
          expect("]")
          return ret
        end
      end

      ESCAPES = { "n" => "\n", "t" => "\t", "r" => "\r", "e" => "\e", "s" => " ",
                  "0" => "\0", "a" => "\a", "b" => "\b", "f" => "\f", "v" => "\v" }

      def string(q)
        @i += 1
        out = +""
        loop do
          raise ParseError, "unterminated string" if eof?
          c = @s[@i]
          @i += 1
          return out if c == q
          if c != "\\"
            out << c
            next
          end
          e = @s[@i]
          @i += 1
          if q == "'"
            out << ((e == "'" || e == "\\") ? e : "\\" + e.to_s)
          elsif e == "u"
            if @s[@i] == "{"
              close = @s.index("}", @i)
              raise ParseError, "bad \\u" unless close
              @s[(@i + 1)...close].split.each { |h| out << h.to_i(16).chr(Encoding::UTF_8) }
              @i = close + 1
            else
              out << @s[@i, 4].to_i(16).chr(Encoding::UTF_8)
              @i += 4
            end
          elsif e == "x"
            hex = @s[@i..-1][/\A[0-9a-fA-F]{1,2}/]
            out << hex.to_i(16).chr
            @i += hex.length
          else
            out << (ESCAPES[e] || e.to_s)
          end
        end
      end

      def symbol
        @i += 1
        return string(@s[@i]).to_sym if @s[@i] == '"'
        name = @s[@i..-1][/\A[A-Za-z_][A-Za-z0-9_]*(?:[?!]|=(?!>))?/]
        raise ParseError, "bad symbol at #{@i}" unless name
        @i += name.length
        return name.to_sym
      end

      def number
        num = @s[@i..-1][/\A[-+]?\d[\d_]*(\.\d+)?([eE][-+]?\d+)?/]
        raise ParseError, "bad number at #{@i}" unless num
        @i += num.length
        return (num.include?(".") || num =~ /[eE]/) ? num.to_f : num.delete("_").to_i
      end
    end

    # Writes plain data in KIF's format (Ruby inspect style)
    def self.dump(v)
      case v
      when Hash   then return "{" + v.map { |k, x| "#{dump(k)}=>#{dump(x)}" }.join(", ") + "}"
      when Array  then return "[" + v.map { |x| dump(x) }.join(", ") + "]"
      when String then return v.inspect
      when Symbol then return v.inspect
      when Integer, Float, TrueClass, FalseClass, NilClass then return v.inspect
      else return v.to_s.inspect
      end
    end
  end

  #-----------------------------------------------------------------------------
  # Pokémon <-> KIF export hash
  #-----------------------------------------------------------------------------
  module PokeIO
    FOLDER = "ExportedPokemons"
    JSON_VERSION = "0.9"
    # KIF as_json keys (same names as the instance variables)
    KIF_KEYS = %w[
      species form forced_form time_form_set exp level steps_to_hatch heal_status gender
      shiny fakeshiny kuraygender shinyValue veryunique kuraycustomfile oldkuraycustomfile
      shinyimprovpif head_shinyimprovpif body_shinyimprovpif shinyR shinyG shinyB shinyKRS
      ability_index ability ability2_index ability2 nature nature_for_stats item mail
      cool beauty cute smart tough sheen pokerus name happiness poke_ball markings iv ivMaxed
      ev hiddenPowerType glitter obtain_method obtain_map obtain_level obtain_text
      hatched_map timeReceived timeEggHatched fused personalID hp totalhp first_moves
      head_gender head_nickname head_shiny head_shinyhue head_shinyr head_shinyg head_shinyb
      head_shinykrs body_shiny body_shinyhue body_shinyr body_shinyg body_shinyb body_shinykrs
      kuray_no_evo ribbons spriteform_body spriteform_head type1kuray type2kuray typeoverwrite
      sprite_scale size_category
    ]
    SPECIAL_KEYS = %w[species exp level owner moves mail heal_status pif_extra json_version]
    SKIP_EXTRA = [:@species_data, :@moves, :@owner, :@mail, :@kif_banked_exp]
    OBJECT_CLASSES = ["PIFSprite", "Pokemon::Move", "Pokemon::Owner"]

    def self.allowed?
      return true if $DEBUG
      return !($PokemonSystem && $PokemonSystem.debugfeature.to_i == 1)
    end

    def self.ensure_folder(dir = FOLDER)
      Dir.mkdir(dir) unless File.directory?(dir)
    end

    #--- export ----------------------------------------------------------------
    def self.plain?(v)
      case v
      when nil, true, false, Integer, Float, String, Symbol then return true
      when Array then return v.all? { |x| plain?(x) }
      when Hash  then return v.all? { |k, x| plain?(k) && plain?(x) }
      end
      return false
    end

    # Plain data, or an exported object (Pokémon or whitelisted class)
    def self.extra_value(v, depth)
      return v if plain?(v)
      return nil if depth > 3
      if v.is_a?(Pokemon)
        return { "__pokemon" => to_hash(v, depth + 1) }
      end
      if OBJECT_CLASSES.include?(v.class.name)
        h = { "__class" => v.class.name }
        v.instance_variables.each do |iv|
          x = extra_value(v.instance_variable_get(iv), depth + 1)
          h[iv.to_s[1..-1]] = x unless x.nil? && !v.instance_variable_get(iv).nil?
        end
        return h
      end
      if v.is_a?(Array)
        return v.map { |x| extra_value(x, depth + 1) }
      end
      return nil
    end

    def self.to_hash(pkmn, depth = 0)
      h = { "json_version" => JSON_VERSION }
      KIF_KEYS.each do |k|
        h[k] = (k == "heal_status" || k == "mail") ? (k == "mail" ? nil : 0) : pkmn.instance_variable_get("@#{k}")
        h[k] = h[k].clone if h[k].is_a?(Array) || h[k].is_a?(Hash)
      end
      h["species"] = pkmn.species
      h["exp"] = pkmn.exp
      h["level"] = pkmn.level
      h["timeReceived"] = pkmn.instance_variable_get(:@timeReceived).to_i
      o = pkmn.owner
      h["owner"] = o ? { "id" => o.id, "name" => o.name, "gender" => o.gender, "language" => o.language } : nil
      h["moves"] = pkmn.moves.map { |m| { "id" => m.id, "pp" => m.pp, "ppup" => m.ppup } }
      extra = {}
      pkmn.instance_variables.each do |iv|
        name = iv.to_s[1..-1]
        next if KIF_KEYS.include?(name) || SKIP_EXTRA.include?(iv)
        v = extra_value(pkmn.instance_variable_get(iv), depth)
        extra[name] = v unless v.nil?
      end
      h["pif_extra"] = extra unless extra.empty?
      return h
    end

    def self.file_base(pkmn, dir = FOLDER)
      clean = proc { |s| s.to_s.gsub(/[^a-zA-Z0-9]/, "_") }
      base = "#{dir}/#{clean.call(pkmn.speciesName)}-#{clean.call(pkmn.name)}-#{pkmn.personalID}-#{pkmn.gender}-#{pkmn.level}"
      name = base
      n = 0
      while File.file?(name + ".json") || File.file?(name + ".png")
        name = base + "(#{n})"
        n += 1
        break if n > 9999
      end
      return name
    end

    # Writes one Pokémon; returns true on success
    def self.export(pkmn)
      ensure_folder
      name = file_base(pkmn)
      h = to_hash(pkmn)
      mode = $PokemonSystem.nopngexport.to_i
      if mode == 2 && pkmn.shiny?   # KIF: shiny .png, Pokémon un-shinied
        h["shiny"] = false
        h["fakeshiny"] = true
      end
      File.open(name + ".json", "w") { |f| f.write(DataLiteral.dump(h)) }
      export_png(pkmn, name + ".png", mode)
      return true
    rescue => e
      KIF.log("Export failed: #{e.message}")
      return false
    end

    def self.export_png(pkmn, path, mode)
      return if mode == 1
      anim = nil
      if mode == 2
        anim = GameData::Species.sprite_bitmap_from_pokemon(pkmn)
      else
        anim = KIF::Shiny.without_shiny(pkmn) { GameData::Species.sprite_bitmap_from_pokemon(pkmn) }
      end
      return unless anim && anim.bitmap
      anim.bitmap.save_to_png(path)
    rescue => e
      KIF.log("PNG export failed: #{e.message}")
    ensure
      anim.dispose if anim && anim.respond_to?(:dispose) && !(anim.respond_to?(:disposed?) && anim.disposed?)
    end

    #--- import ----------------------------------------------------------------
    def self.species_of(v)
      return nil if v.nil?
      d = GameData::Species.get(v.is_a?(String) ? v.to_sym : v)
      return d ? d.id : nil
    rescue
      return nil
    end

    def self.valid?(mod, v)
      return false if v.nil?
      return mod.exists?(v.is_a?(String) ? v.to_sym : v)
    rescue
      return false
    end

    def self.sym(v)
      return v.is_a?(String) ? v.to_sym : v
    end

    def self.stat_hash(v, default)
      ret = {}
      GameData::Stat.each_main { |s| ret[s.id] = default }
      return ret unless v.is_a?(Hash)
      v.each { |k, x| ret[sym(k)] = x.to_i if ret.has_key?(sym(k)) && x.is_a?(Numeric) }
      return ret
    end

    def self.object_from(v, depth)
      return nil if depth > 4
      if v.is_a?(Hash) && v["__pokemon"].is_a?(Hash)
        return from_hash(v["__pokemon"], depth + 1)
      end
      if v.is_a?(Hash) && OBJECT_CLASSES.include?(v["__class"])
        cls = v["__class"].split("::").inject(Object) { |m, c| m.const_get(c) }
        obj = cls.allocate
        v.each do |k, x|
          next if k == "__class" || !k.is_a?(String) || k !~ /\A[A-Za-z_]\w*\z/
          obj.instance_variable_set("@#{k}", object_from(x, depth + 1))
        end
        return obj
      end
      return v.map { |x| object_from(x, depth + 1) } if v.is_a?(Array)
      return v
    rescue
      return nil
    end

    # Builds a Pokémon from a KIF export hash; nil when it can't be used.
    def self.from_hash(h, depth = 0)
      return nil unless h.is_a?(Hash)
      species = species_of(h["species"])
      return nil unless species
      level = h["level"].is_a?(Integer) ? h["level"].clamp(1, GameData::GrowthRate.max_level) : 5
      pkmn = Pokemon.new(species, level)
      plain_ok = proc { |v| v.nil? || plain?(v) }
      KIF_KEYS.each do |k|
        next unless h.has_key?(k)
        next if %w[species level exp].include?(k)
        v = h[k]
        case k
        when "ability", "ability2" then v = valid?(GameData::Ability, v) ? sym(v) : nil
        when "nature", "nature_for_stats" then v = valid?(GameData::Nature, v) ? sym(v) : nil
        when "item"      then v = valid?(GameData::Item, v) ? sym(v) : nil
        when "poke_ball" then v = valid?(GameData::Item, v) ? sym(v) : :POKEBALL
        when "iv"        then v = stat_hash(v, 0)
        when "ev"        then v = stat_hash(v, 0)
        when "ivMaxed"   then v = v.is_a?(Hash) ? v.each_with_object({}) { |(a, b), r| r[sym(a)] = b } : {}
        when "first_moves" then v = Array(v).map { |m| sym(m) }.select { |m| valid?(GameData::Move, m) }
        when "ribbons"   then v = Array(v).map { |m| sym(m) }
        when "timeReceived", "timeEggHatched", "personalID" then v = v.to_i
        when "name"      then v = v.is_a?(String) ? v : nil
        when "heal_status", "mail" then next
        end
        next unless plain_ok.call(v)
        pkmn.instance_variable_set("@#{k}", v)
      end
      pkmn.exp = h["exp"] if h["exp"].is_a?(Integer)
      if h["owner"].is_a?(Hash)
        o = h["owner"]
        pkmn.owner = Pokemon::Owner.new(o["id"].to_i, o["name"].to_s, o["gender"].to_i, o["language"].to_i)
      end
      moves = Array(h["moves"]).select { |m| m.is_a?(Hash) && valid?(GameData::Move, m["id"]) }
      unless moves.empty?
        pkmn.instance_variable_set(:@moves, [])
        moves.first(Pokemon::MAX_MOVES).each do |m|
          mv = Pokemon::Move.new(sym(m["id"]))
          mv.ppup = m["ppup"].to_i.clamp(0, 3) rescue nil
          mv.pp = m["pp"].to_i rescue nil
          pkmn.moves.push(mv)
        end
      end
      if h["pif_extra"].is_a?(Hash)
        h["pif_extra"].each do |k, v|
          next unless k.is_a?(String) && k =~ /\A[A-Za-z_]\w*\z/
          next if KIF_KEYS.include?(k) || SKIP_EXTRA.include?("@#{k}".to_sym)
          pkmn.instance_variable_set("@#{k}", object_from(v, depth))
        end
      end
      pkmn.instance_variable_set(:@imported, true)
      pkmn.calc_stats
      pkmn.hp = pkmn.totalhp if !h["hp"].is_a?(Integer) || pkmn.hp > pkmn.totalhp
      return pkmn
    rescue => e
      KIF.log("Import failed: #{e.message}")
      return nil
    end

    def self.read_file(file)
      return from_hash(DataLiteral.parse(File.read(file)))
    rescue => e
      KIF.log("Can't read #{file}: #{e.message}")
      return nil
    end

    # KIF import options + .png handling
    def self.prepare_import(pkmn, file)
      if $PokemonSystem.importdevolve.to_i == 1
        baby = (GameData::Species.get(pkmn.species).get_baby_species(false) rescue nil)
        pkmn.species = baby if baby && baby != pkmn.species
      end
      lvl = [0, 1, 5, 50, 100][$PokemonSystem.importlvl.to_i] || 0
      pkmn.level = [lvl, GameData::GrowthRate.max_level].min if lvl > 0
      if $PokemonSystem.importegg.to_i == 1
        pkmn.name           = _INTL("Egg")
        pkmn.steps_to_hatch = (pkmn.species_data.hatch_steps rescue 5120)
        pkmn.hatched_map    = 0
        pkmn.obtain_method  = 1
      end
      png = file.sub(/\.json\z/i, ".png")
      mode = $PokemonSystem.nopngimport.to_i
      if mode != 2 && File.file?(png)
        if mode == 0
          begin
            Dir.mkdir("Graphics/Imported") unless File.directory?("Graphics/Imported")
            dest = "Graphics/Imported/#{pkmn.personalID}_#{pkmn.owner ? pkmn.owner.id : 0}_#{pkmn.species}.png"
            File.open(dest, "wb") { |f| f.write(File.binread(png)) }
            pkmn.instance_variable_set(:@kuraycustomfile, dest)
          rescue
            pkmn.instance_variable_set(:@kuraycustomfile, png)
          end
        else
          pkmn.instance_variable_set(:@kuraycustomfile, png)
        end
      end
      pkmn.calc_stats
      pkmn.hp = pkmn.totalhp if pkmn.hp > pkmn.totalhp || pkmn.hp <= 0
    end

    #--- folders (KIF navigationSystem) ----------------------------------------
    def self.subdirs(dir)
      return Dir.entries(dir).reject { |e| e == "." || e == ".." }
                .select { |e| File.directory?(File.join(dir, e)) }.sort
    rescue
      return []
    end

    def self.jsons_in(dir, recursive)
      ret = []
      (Dir.entries(dir) rescue []).sort.each do |e|
        next if e == "." || e == ".."
        path = File.join(dir, e)
        if File.directory?(path)
          ret.concat(jsons_in(path, true)) if recursive
        elsif e.downcase.end_with?(".json")
          ret << path
        end
      end
      return ret
    end

    def self.dirs_with_jsons(dir, out = [])
      out << dir if jsons_in(dir, false).any?
      subdirs(dir).each { |d| dirs_with_jsons(File.join(dir, d), out) }
      return out
    end

    # KIF navigationSystem. Returns nil if cancelled, else a hash:
    #   :dir   folder used (nil for <This Folder+Sub-Folders>)
    #   :files .json files to use
    #   :random_root folder whose sub-folders are re-picked (Random Sub-Folder)
    def self.navigate(screen, message)
      ensure_folder
      dir = FOLDER
      loop do
        subs = subdirs(dir)
        cmds = []
        cmds << "<...>" if dir != FOLDER
        cmds << "<This Folder>" << "<This Folder+Sub-Folders>" << "<Random Sub-Folder>"
        fixed = cmds.length
        cmds.concat(subs)
        cmds << "<Cancel>"
        cmd = screen.pbShowCommands(_INTL(message), cmds)
        return nil if cmd < 0 || cmd == cmds.length - 1
        case cmds[cmd]
        when "<...>"
          dir = File.dirname(dir)
        when "<This Folder>"
          return { :dir => dir, :files => jsons_in(dir, false), :random_root => nil }
        when "<This Folder+Sub-Folders>"
          return { :dir => nil, :files => jsons_in(dir, true), :random_root => nil }
        when "<Random Sub-Folder>"
          if subs.empty?
            pbPlayBuzzerSE
            screen.pbDisplay(_INTL("No sub-folders to randomize from!"))
          else
            pick = dirs_with_jsons(dir).sample
            return { :dir => pick, :files => (pick ? jsons_in(pick, false) : []), :random_root => dir }
          end
        else
          dir = File.join(dir, cmds[cmd]) if cmd >= fixed
        end
      end
    end

    # Returns the list of .json files to use, or nil if cancelled.
    def self.choose_files(screen, message)
      nav = navigate(screen, message)
      return nav ? nav[:files] : nil
    end

    # Free slots: current box first, then Box 1 onwards (KIF), no transfer box
    def self.free_slots(storage)
      order = [storage.currentBox] + (0...storage.maxBoxes).to_a
      ret = []
      order.uniq.each do |b|
        next if storage[b].is_a?(StorageTransferBox)
        storage.maxPokemon(b).times { |i| ret << [b, i] unless storage[b, i] }
      end
      return ret
    end

    def self.import(screen, randomly)
      files = choose_files(screen, "Choose Import Sub-Directory.")
      return if files.nil?
      if files.empty?
        pbPlayBuzzerSE
        screen.pbDisplay(_INTL("No Pokemon to Import!"))
        return
      end
      files = [files.sample] if randomly
      storage = screen.storage
      slots = free_slots(storage)
      delete = $PokemonSystem.importnodelete.to_i != 1
      failed = 0
      out_of_space = false
      files.each do |file|
        if slots.empty?
          out_of_space = true
          break
        end
        pkmn = read_file(file)
        if pkmn.nil?
          failed += 1
          next
        end
        prepare_import(pkmn, file)
        b, i = slots.shift
        storage[b, i] = pkmn
        begin
          File.delete(file) if delete
        rescue
          nil
        end
      end
      screen.pbHardRefresh
      if out_of_space
        pbPlayBuzzerSE
        screen.pbDisplay(_INTL("Out of place!"))
      else
        screen.pbDisplay(_INTL("Pokemon(s) Imported!"))
      end
      screen.pbDisplay(_INTL("{1} file(s) could not be read.", failed)) if failed > 0
    end

    #--- export commands -------------------------------------------------------
    def self.delete_on_export?
      return $PokemonSystem.exportdelete.to_i == 1
    end

    def self.export_box(screen, box)
      storage = screen.storage
      if storage[box].empty?
        pbPlayBuzzerSE
        screen.pbDisplay(_INTL("Box is empty!"))
        return
      end
      storage.maxPokemon(box).times do |k|
        pkmn = storage[box, k]
        next unless pkmn
        storage.pbDelete(box, k) if export(pkmn) && delete_on_export?
      end
      screen.pbHardRefresh
      screen.pbDisplay(_INTL("Pokemon(s) Exported!"))
    end

    def self.export_all(screen_or_nil, display)
      storage = $PokemonStorage
      storage.maxBoxes.times do |j|
        box = storage[j]
        next if box.is_a?(StorageTransferBox) || box.empty? || box.exportlock?
        storage.maxPokemon(j).times do |k|
          pkmn = storage[j, k]
          next unless pkmn
          storage.pbDelete(j, k) if export(pkmn) && delete_on_export?
        end
      end
      $Trainer.party.each { |pkmn| export(pkmn) if pkmn }   # party is never deleted
      screen_or_nil.pbHardRefresh if screen_or_nil && screen_or_nil.respond_to?(:pbHardRefresh)
      display.call(_INTL("All Pokemons Exported!"))
    end

    def self.export_selected(screen, box)
      storage = screen.storage
      screen.getMultiSelection(box, nil).each do |index|
        pkmn = storage[box, index]
        export(pkmn) if pkmn
      end
      screen.pbDisplay(_INTL("Pokemon(s) Exported!"))
    end
  end
end

#-------------------------------------------------------------------------------
# Kuray Actions: Export / Export All Pokemons (PC and party)
#-------------------------------------------------------------------------------
module KIF::PCActionMethods
  def kif_export_one(pkmn, selected, heldpoke)
    unless KIF::PokeIO.export(pkmn)
      pbDisplay(_INTL("The Pokémon couldn't be exported."))
      return
    end
    if KIF::PokeIO.delete_on_export? && is_a?(PokemonStorageScreen)
      box, index = selected
      if box == -1 && !heldpoke && (pbAbleCount <= 1 && pbAble?(pkmn))
        # never remove the last Pokémon of the party
      else
        @scene.pbRelease(selected, heldpoke)
        if heldpoke
          @heldpkmn = nil
        else
          @storage.pbDelete(box, index)
        end
        @scene.pbRefresh
      end
    end
    pbDisplay(_INTL("Pokemon Exported!"))
  end
end

KIF::PCActions.add(:export,
  proc { |pkmn| KIF::PokeIO.allowed? ? _INTL("Export") : nil },
  proc { |host, pkmn, selected, heldpoke| host.kif_export_one(pkmn, selected, heldpoke) })
KIF::PCActions.add(:export_all,
  proc { |pkmn| KIF::PokeIO.allowed? ? _INTL("Export All Pokemons") : nil },
  proc { |host, pkmn, selected, heldpoke|
    KIF::PokeIO.export_all(host.is_a?(PokemonStorageScreen) ? host : nil, proc { |t| host.pbDisplay(t) })
  })

#-------------------------------------------------------------------------------
# Box menu and multi-select
#-------------------------------------------------------------------------------
KIF::BoxCommands.add(:export_box, proc { |_s| KIF::PokeIO.allowed? ? _INTL("Export this Box") : nil },
  proc { |s| KIF::PokeIO.export_box(s, s.storage.currentBox) }, order: 70)
KIF::BoxCommands.add(:export_all, proc { |_s| KIF::PokeIO.allowed? ? _INTL("Export All") : nil },
  proc { |s| KIF::PokeIO.export_all(s, proc { |t| s.pbDisplay(t) }) }, order: 80)
KIF::BoxCommands.add(:import, proc { |_s| KIF::PokeIO.allowed? ? _INTL("Import") : nil },
  proc { |s| KIF::PokeIO.import(s, false) }, order: 90)
KIF::BoxCommands.add(:import_random, proc { |_s| KIF::PokeIO.allowed? ? _INTL("Import Randomly") : nil },
  proc { |s| KIF::PokeIO.import(s, true) }, order: 100)

KIF::MultiCommands.add(:export, proc { |_s, _b| KIF::PokeIO.allowed? ? _INTL("Export") : nil },
  proc { |s, box| KIF::PokeIO.export_selected(s, box) }, order: 20)
