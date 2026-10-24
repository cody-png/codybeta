#===============================================================================
# F-CORE-04 – Mods folder (DemICE)
# Source: KIF 0.20.7
#   999_Main/999_Main.rb:138-146   passModdedPokemon
#   999_Main/999_Main.rb:150, :154 queue reset; Dir["./Mods/*.rb"] loaded
#                                  right after PluginManager.runPlugins
#   201_Kuray/003_KurayPokemonRevamp.rb:2-9  kuray_modqueue (Species.register)
#   ChallengeMode.rb:457           queue applied in GameData.load_all
#
# Every .rb file in the game's Mods folder (next to InfiniteFusion.exe) is loaded once
# at boot, in name order, after all game and port scripts and before the
# game data loads – same moment as KIF. A mod can add or replace species with
#   passModdedPokemon({ :id => ..., :id_number => ..., ... })   # Species hash
# (applied every time the game data loads, after the port's own changes).
#
# Port additions:
#   * The Mods folder is created on first boot if missing (KIF shipped it).
#   * A mod that raises an error is skipped and the error is written to
#     KIF_errorlog.txt instead of stopping the game.
#   * 6.8.2's own scripts don't need KIF's alias guards: mods load once.
#   * 2026-10-14: a mod can also be a folder (Mods/<name>/ with its
#     .rb files, a mod.json when it has one) or a .zip (unpacked into
#     Mods/<name>/ at start-up, the zip moved to Mods/Imported). Folders with
#     a mod.json are left to Mod Manager when it is installed. Every mod can
#     be switched Off in Options > KIF Settings > Mods (KIF_Mods.kro in the
#     save folder); the list is built from "sources" (KIF::Mods.add_source) so
#     a future Mod Manager can list its own mods there.
#===============================================================================
$POKEMONDATA_QUEUEING ||= []

def passModdedPokemon(data = {})
  return if !data.is_a?(Hash) || data.empty?
  $POKEMONDATA_QUEUEING.push(data)
end

module KIF
  module Mods
    FOLDER    = "Mods"
    DONE_DIR  = "Imported"                       # unpacked .zip files go here
    SKIP_DIRS = [DONE_DIR, "ModDev", "Mods"]     # never mods themselves
    STATE     = "KIF_Mods.kro"                   # ids switched Off (save folder)
    @loaded = false
    @failed = []
    @sources = []
    @loaded_files = {}
    class << self
      attr_reader :failed
      attr_accessor :current   # id of the mod whose scripts are loading
    end

    # One installed mod. kind: :file (Mods/x.rb), :folder (Mods/x/), or a
    # source's own kind (:mod_manager...). settings: KIF Mod Settings rows it
    # registered while loading.
    class Entry
      attr_accessor :id, :name, :version, :author, :description, :kind, :path,
                    :source, :loaded, :error
      def initialize(h = {})
        h.each { |k, v| send("#{k}=", v) if respond_to?("#{k}=") }
        @name ||= @id.to_s
      end

      def enabled?; return @source ? @source.enabled?(self) : true; end
      # what happened when it loaded this session (KIF's own mods)
      def error; return @error || (KIF::Mods.status[@id] || {})[:error]; end
      def loaded; return @loaded.nil? ? (KIF::Mods.status[@id] || {})[:loaded] : @loaded; end
      # why it wasn't loaded (mod.json requires_kif / incompatible), or nil
      def blocked; return (KIF::Mods.status[@id] || {})[:blocked]; end
      def settings
        return [] unless defined?(KIF::ModSettings) && KIF::ModSettings.active?
        return KIF::ModSettings.registry.select { |e| e[:mod] == @id }
      end
    end

    # A read-only game folder (phones): <save folder>/Mods is read as well
    def self.extra_folders
      dir = KIF::Paths.extra_drop_dir(FOLDER)
      return dir ? [dir] : []
    end

    # file names loaded straight from the Mods folder this session
    def self.loaded_root; @loaded_root || []; end
    def self.loaded_dirs; @loaded_dirs || []; end

    # Uninstall (Cody, 2026-10-20): deletes a mod of KIF's own Mods folder
    # (its folder, or its loose .rb). Its settings move to the uninstalled
    # store first (KIF::ModSettings.stash). Code already loaded stays until
    # the game restarts. Mod Manager's mods are Mod Manager's to remove.
    def self.uninstall(e)
      return false unless e && e.source.is_a?(NativeSource)
      path = File.expand_path(e.path.to_s)
      roots = e.source.dirs.map { |d| File.expand_path(d.to_s) }
      return false unless roots.any? { |root| path.start_with?(root + "/") } && File.exist?(path)
      KIF::ModSettings.stash(e.id) if defined?(KIF::ModSettings) && KIF::ModSettings.active?
      File.directory?(path) ? KIF.rm_tree(path) : File.delete(path)
      set_disabled(e.id, false) if disabled.include?(e.id)
      e.source.instance_variable_set(:@entries, nil)
      KIF::ModCatalog.instance_variable_set(:@installed_index, nil) if defined?(KIF::ModCatalog)
      KIF.log("Mod uninstalled: #{e.name} (#{e.id})")
      return !File.exist?(path)
    rescue StandardError => ex
      KIF.log("Mod #{e && e.id} couldn't be uninstalled: #{ex.class}: #{ex.message}")
      return false
    end

    # f is the same script as one loaded loose from Mods/ (same name AND same
    # bytes): loading it again makes its aliases recurse. Only the name used
    # to count, so Mods/main.rb kept another mod's own main.rb from loading.
    def self.loose_copy?(f)
      name = File.basename(f)
      return false unless loaded_root.include?(name)
      (@loaded_root_paths || {}).fetch(name, []).any? do |p|
        File.size(p) == File.size(f) && File.binread(p) == File.binread(f)
      end
    rescue SystemCallError
      return false
    end

    def self.status; return @status ||= {}; end

    # a mod's name for messages ("Set by Kanto Reloaded")
    def self.display_name(id)
      return nil if id.nil?
      return (@names || {})[id] || id.to_s
    end

    def self.loaded_file?(path)
      return @loaded_files[File.expand_path(path)] ? true : false
    end

    #---------------------------------------------------------------------------
    # Sources of the Mods list: KIF's own (files, folders, zips) and Mod
    # Manager's. Another manager adds itself with KIF::Mods.add_source(obj);
    # obj answers entries -> [Entry], enabled?(entry), set_enabled(entry, bool)
    # and optionally open_settings(entry).
    #---------------------------------------------------------------------------
    def self.add_source(src)
      @sources.delete_if { |s| s.class == src.class }
      @sources << src
    end

    def self.sources; return @sources; end

    def self.entries
      list = []
      add_source(NativeSource.new(File.join(".", FOLDER), extra_folders)) if @sources.empty?
      @sources.each do |s|
        begin
          list.concat(Array(s.entries))
        rescue StandardError => e
          KIF.log("Mods list: #{s.class} failed (#{e.class}: #{e.message})")
        end
      end
      return list
    end

    # KIF's switched-off list
    def self.state_path; return File.join(KIF.save_dir, STATE); end

    def self.disabled
      return @disabled if @disabled
      @disabled = []
      if File.file?(state_path)
        @disabled = File.read(state_path).force_encoding("UTF-8").split(/\r?\n/).map(&:strip).reject(&:empty?)
      end
      return @disabled
    rescue StandardError
      return @disabled = []
    end

    def self.set_disabled(id, off)
      list = disabled
      off ? (list << id unless list.include?(id)) : list.delete(id)
      File.open(state_path, "wb") { |f| f.write(list.join("\r\n")) }
    rescue StandardError => e
      KIF.log("Mods: couldn't save the On/Off list (#{e.message})")
    end

    #---------------------------------------------------------------------------
    # mod.json (a small reader: the engine's JSON isn't in every build)
    #---------------------------------------------------------------------------
    module MiniJSON
      module_function

      def parse(text)
        @s = text.to_s.sub(/\A\xEF\xBB\xBF/, "")
        @i = 0
        v = value
        return v
      rescue StandardError
        return nil
      end

      def ws; @i += 1 while @i < @s.length && @s[@i] =~ /\s/; end

      def value
        ws
        c = @s[@i]
        case c
        when "{"
          @i += 1; h = {}; ws
          (@i += 1; return h) if @s[@i] == "}"
          loop do
            ws; k = value; ws
            raise "colon" unless @s[@i] == ":"
            @i += 1
            h[k.to_s] = value; ws
            if @s[@i] == ","
              @i += 1
            elsif @s[@i] == "}"
              @i += 1; return h
            else
              raise "object"
            end
          end
        when "["
          @i += 1; a = []; ws
          (@i += 1; return a) if @s[@i] == "]"
          loop do
            a << value; ws
            if @s[@i] == ","
              @i += 1
            elsif @s[@i] == "]"
              @i += 1; return a
            else
              raise "array"
            end
          end
        when '"'
          @i += 1; out = +""
          while @i < @s.length && @s[@i] != '"'
            if @s[@i] == "\\"
              @i += 1
              e = @s[@i]
              out << ({ "n" => "\n", "t" => "\t", "r" => "\r", "b" => "\b", "f" => "\f" }[e] ||
                      (e == "u" ? [@s[@i + 1, 4].hex].pack("U").tap { @i += 4 } : e))
            else
              out << @s[@i]
            end
            @i += 1
          end
          @i += 1
          return out
        else
          lit = @s[@i..-1][/\A(true|false|null|-?\d+(\.\d+)?([eE][+-]?\d+)?)/]
          raise "value" unless lit
          @i += lit.length
          return true if lit == "true"
          return false if lit == "false"
          return nil if lit == "null"
          return lit.include?(".") || lit =~ /e/i ? lit.to_f : lit.to_i
        end
      end
    end

    def self.read_json(path)
      h = MiniJSON.parse(File.read(path, encoding: "UTF-8"))
      return h.is_a?(Hash) ? h : nil
    rescue StandardError
      return nil
    end

    #---------------------------------------------------------------------------
    # .zip mods: unpacked into Mods/<name>/ (a zip holding one folder gives
    # that folder's contents), then moved to Mods/Imported
    #---------------------------------------------------------------------------
    def self.mkdir_p(dir); KIF.mkdir_p(dir); end

    def self.unpack_zips(dir)
      Dir.children(dir).sort.each do |c|
        next unless c =~ /\.zip\z/i
        zip = File.join(dir, c)
        next unless File.file?(zip)
        name = File.basename(c, ".*")
        into = File.join(dir, name)
        if File.exist?(into)
          KIF.log("Mod zip #{c}: Mods/#{name} already exists - the zip is left alone (delete one of them)")
          next
        end
        begin
          n = unzip(zip, into)
          done = File.join(dir, DONE_DIR)
          mkdir_p(done)
          dest = File.join(done, c); k = 2
          while File.exist?(dest)
            dest = File.join(done, "#{name} (#{k})#{File.extname(c)}"); k += 1
          end
          File.rename(zip, dest)
          KIF.log("Mod zip #{c}: #{n} files unpacked into Mods/#{name} (zip moved to Mods/#{DONE_DIR})")
        rescue StandardError => e
          KIF.log("Mod zip #{c} couldn't be unpacked (#{e.class}: #{e.message})")
          @failed << c
          (rm_tree(into) rescue nil)
        end
      end
    end

    def self.unzip(zip, into)
      require "zlib"
      raise "no zip reader" unless defined?(KIF::SpriteImport::Zip)
      written = 0
      File.open(zip, "rb") do |f|
        list = KIF::SpriteImport::Zip.entries(f)
        names = list.map { |e| e[0].tr("\\", "/").split("/").reject { |p| p.empty? || p == "." || p == ".." } }
        files = names.each_with_index.reject { |n, i| n.empty? || list[i][0].end_with?("/") }
        # one folder around everything: drop it
        tops = files.map { |n, _| n.length > 1 ? n[0] : nil }.uniq
        strip = (tops.length == 1 && tops[0]) ? 1 : 0
        files.each do |parts, i|
          _name, method, csize, offset = list[i]
          rel = parts[strip..-1]
          next if rel.nil? || rel.empty?
          raise "unsupported packing (method #{method})" unless method == 0 || method == 8
          f.seek(offset)
          h = f.read(30)
          raise "damaged entry #{parts.join('/')}" unless h && h[0, 4] == "PK\x03\x04".b
          nlen, xlen = h[26, 4].unpack("vv")
          f.seek(offset + 30 + nlen + xlen)
          data = f.read(csize)
          data = Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(data) if method == 8
          dest = File.join(into, *rel)
          mkdir_p(File.dirname(dest))
          File.open(dest, "wb") { |o| o.write(data) }
          written += 1
        end
      end
      mkdir_p(into)
      return written
    end

    def self.rm_tree(path); KIF.rm_tree(path); end

    #---------------------------------------------------------------------------
    # KIF's own mods: Mods/*.rb and Mods/<folder>/
    #---------------------------------------------------------------------------
    class NativeSource
      attr_reader :dir
      # extra: more Mods folders (the save folder's on phones); a mod in a
      # later folder replaces one of the same name in an earlier one: a
      # read-only game folder's mod can only be updated by hand there
      def initialize(dir, extra = []); @dir = dir; @extra = extra; @entries = nil; end
      def dirs; return [@dir] + @extra; end

      def mod_manager_folders?
        return defined?(::ModManager) ? true : false
      end

      # folders and files KIF loads (Mod Manager's own mod.json folders excluded)
      def entries
        return @entries if @entries
        list = []
        dirs.each do |d|
          next unless File.directory?(d)
          entries_in(d).each do |e|
            i = list.index { |o| o.id == e.id }
            i ? list[i] = e : list << e   # keeps its place in the load order
          end
        end
        return @entries = list
      end

      def entries_in(dir)
        list = []
        Dir.children(dir).sort.each do |c|
          path = File.join(dir, c)
          if File.file?(path) && c =~ /\.rb\z/i
            list << Entry.new(:id => c, :name => File.basename(c, ".*").sub(/\A\d+[_ -]*/, "").tr("_", " "),
                              :kind => :file, :path => path, :source => self)
          elsif File.directory?(path)
            next if c.start_with?(".", "_") || SKIP_DIRS.include?(c)
            json = File.join(path, "mod.json")
            if File.file?(json)
              next if mod_manager_folders?
              h = KIF::Mods.read_json(json) || {}
              desc = h["description"].is_a?(Array) ? h["description"].join(" ") : h["description"].to_s
              list << Entry.new(:id => c, :name => (h["name"] || c).to_s, :version => h["version"]&.to_s,
                                :author => h["author"]&.to_s, :description => desc, :kind => :folder,
                                :path => path, :source => self)
            else
              # a folder with only pictures / sounds is a mod too (KIF::ModAssets)
              next if Dir[File.join(path, "**", "*.rb")].empty? &&
                      KIF::ModAssets::DIRS.none? { |d| File.directory?(File.join(path, d)) }
              list << Entry.new(:id => c, :name => c, :kind => :folder, :path => path, :source => self)
            end
          end
        end
        return list
      end

      def enabled?(e); return !KIF::Mods.disabled.include?(e.id); end
      def set_enabled(e, on); KIF::Mods.set_disabled(e.id, !on); end

      # the scripts of a folder mod, in load order
      def scripts(e)
        return [e.path] if e.kind == :file
        json = File.join(e.path, "mod.json")
        h = File.file?(json) ? (KIF::Mods.read_json(json) || {}) : nil
        if h && h["scripts"].is_a?(Array) && !h["scripts"].empty?
          listed = h["scripts"].map { |s| File.join(e.path, s.to_s) }.select { |f| File.file?(f) }
          return listed unless listed.empty?
          KIF.log("Mod #{e.name}: mod.json lists #{h['scripts'].join(', ')} (missing) - loading its .rb files instead")
        end
        return KIF::Mods.folder_scripts(e.path)
      end

      # mod.json "dependencies" and "load_after" first. load_after (2026-10-18)
      # is only an order: a named mod that isn't installed is skipped, nothing
      # is required. Otherwise folder-name order. A loop is logged and cut
      # where it closes.
      def order(list)
        ids = list.map(&:id)
        jsons = {}
        list.each do |e|
          json = File.join(e.path.to_s, "mod.json")
          jsons[e.id] = (e.kind == :folder && File.file?(json)) ? (KIF::Mods.read_json(json) || {}) : {}
        end
        deps = {}
        list.each do |e|
          h = jsons[e.id]
          d = KIF::ModRules.ids_in(h["dependencies"]) + KIF::ModRules.ids_in(h["load_after"])
          # both name mod.json ids; match them to folders by id or name
          deps[e.id] = list.select { |o| o != e && d.any? { |x| x == o.id || x == jsons[o.id]["id"].to_s } }.map(&:id)
        end
        out = []
        visit = lambda do |id, stack|
          return if out.include?(id)
          if stack.include?(id)
            KIF.log("Mods: load order loop #{(stack[stack.index(id)..-1] + [id]).join(' -> ')} (mod.json dependencies / load_after) - cut at #{id}")
            return
          end
          (deps[id] || []).each { |d| visit.call(d, stack + [id]) }
          out << id
        end
        ids.each { |id| visit.call(id, []) }
        return out.map { |id| list.find { |e| e.id == id } }
      end
    end

    # like the game's script loader: files by name, then sub-folders
    def self.folder_scripts(dir)
      files = []; folders = []
      Dir.children(dir).sort.each do |c|
        next if c.start_with?(".")
        p = File.join(dir, c)
        if File.directory?(p)
          folders << p
        elsif c =~ /\.rb\z/i
          files << p
        end
      end
      return files + folders.flat_map { |f| folder_scripts(f) }
    end

    # Mod Manager's mods (it loads them itself; KIF lists them and uses its
    # own On/Off)
    class ModManagerSource
      def entries
        return [] unless defined?(::ModManager) && ::ModManager.respond_to?(:registry)
        return ::ModManager.registry.map do |id, info|
          Entry.new(:id => "mm:#{id}", :name => info.name.to_s, :version => info.version.to_s,
                    :author => info.author.to_s, :description => info.description.to_s,
                    :kind => :mod_manager, :path => info.folder_path.to_s, :source => self,
                    :loaded => ::ModManager.load_order.include?(id))
        end
      end

      def mm_id(e); return e.id.sub(/\Amm:/, ""); end
      def enabled?(e); return ::ModManager.enabled?(mm_id(e)); end

      def set_enabled(e, on)
        ::ModManager.toggle(mm_id(e)) if enabled?(e) != on
      end
    end

    def self.load_file(file, id)
      @current = id
      load File.expand_path(file)
      @loaded_files[File.expand_path(file)] = true
      return true
    rescue Exception => e
      raise if e.is_a?(SystemExit) || (defined?(Reset) && e.is_a?(Reset))
      @failed << id unless @failed.include?(id)
      KIF::CrashLog.write("Mod skipped: #{file}\r\n" + KIF::CrashLog.describe(e)) if defined?(KIF::CrashLog)
      KIF.log("Mod failed: #{id} (#{File.basename(file)}): #{e.class}: #{e.message}")
      return e
    ensure
      @current = nil
    end

    # Everything in one Mods folder (the game's, or a test's)
    def self.load_dir(dir, extra = [])
      @loaded_root = []
      @loaded_root_paths = {}
      @loaded_dirs = []   # folder mods that loaded, in order (their pictures / sounds)
      @disabled = nil
      @status = {}
      @names = {}
      KIF::Features.reset! if defined?(KIF::Features)
      KIF::Locks.reset! if defined?(KIF::Locks)
      native = NativeSource.new(dir, extra)
      add_source(native)
      add_source(ModManagerSource.new)
      native.dirs.each { |d| unpack_zips(d) if File.directory?(d) }
      off = []
      on = mods_on(native)
      # loose .rb files first, in name order (as KIF 0.20.7)
      native.entries.select { |e| e.kind == :file }.each do |e|
        (off << e.id; next) unless e.enabled?
        @names[e.id] = e.name.to_s
        r = load_file(e.path, e.id)
        status[e.id] = { :loaded => r == true, :error => (r == true ? nil : r) }
        KIF::ModRules.release(e.id) unless r == true
        next unless r == true
        @loaded_root << e.id
        (@loaded_root_paths[File.basename(e.path)] ||= []) << e.path
        KIF.log("Mod loaded: #{e.id}")
      end
      # then folders (Mod Manager's own are loaded by Mod Manager); the source
      # is asked again, as Mod Manager may have loaded by now
      native.instance_variable_set(:@entries, nil)
      folders = native.order(native.entries.select { |e| e.kind == :folder })
      blocked = {}
      folders.each do |e|
        (off << e.id; next) unless e.enabled?
        json = KIF::ModRules.json_for(e)
        why = KIF::ModRules.blocked_reason(e, json, on, blocked)
        if why
          status[e.id] = { :loaded => false, :error => nil, :blocked => why }
          blocked[e.id] = e.name.to_s
          blocked[json["id"].to_s] = e.name.to_s if json && json["id"]
          KIF.log("Mod not loaded: #{e.name} - #{why}")
          next
        end
        @names[e.id] = e.name.to_s
        KIF::ModRules.apply(e.id, e.name.to_s, json)
        # a script also dropped loose into Mods/ is already loaded (twice
        # makes its aliases recurse)
        scripts = native.scripts(e).reject { |f| loaded_file?(f) || loose_copy?(f) }
        results = scripts.map { |f| load_file(f, e.id) }
        bad = results.find { |r| r != true }
        status[e.id] = { :loaded => bad.nil?, :error => bad }
        if bad.nil?
          @loaded_dirs << e.path.to_s
          ver = json && json["version"] ? " #{json['version']}" : ""
          KIF.log("Mod loaded: #{e.name}#{ver} (folder #{e.id}, #{scripts.length} scripts)")
        else
          KIF::ModRules.release(e.id)
          blocked[e.id] = e.name.to_s
          blocked[json["id"].to_s] = e.name.to_s if json && json["id"]
        end
      end
      KIF::ModRules.apply_mod_manager
      KIF.log("Mods switched Off: #{off.join(', ')}") unless off.empty?
    end

    # every mod that is On: id / folder => name (for "incompatible")
    def self.mods_on(native)
      on = {}
      native.entries.each do |e|
        next unless e.enabled?
        on[e.id] = e.name.to_s
        on[File.basename(e.id, ".*")] = e.name.to_s if e.kind == :file
        json = e.kind == :folder ? KIF::ModRules.json_for(e) : nil
        on[json["id"].to_s] = e.name.to_s if json && json["id"]
      end
      ModManagerSource.new.entries.each do |e|
        on[e.id.sub(/\Amm:/, "")] = e.name.to_s if (e.enabled? rescue false)
      end
      return on
    rescue StandardError => e
      KIF.log("Mods: couldn't list the mods that are On (#{e.class}: #{e.message})")
      return on || {}
    end

    def self.load_all
      return if @loaded
      @loaded = true
      # Registered here (after every port script) so modded species are
      # applied after the port's own data changes.
      KIF::DataLoad.after_load_all("Modded Pokémon (Mods folder)") { KIF::Mods.apply_species }
      KIF::ModCompat.patch_mod_manager if defined?(KIF::ModCompat)
      KIF::ModCompat.before_mods_load if defined?(KIF::ModCompat) && KIF::ModCompat.respond_to?(:before_mods_load)
      (Dir.mkdir(FOLDER) rescue nil) unless File.directory?(FOLDER)   # a read-only game folder still loads its mods
      KIF::ModSettings.install(FOLDER) if defined?(KIF::ModSettings)
      KIF::ModCatalog.migrate_copied_assets(FOLDER) if defined?(KIF::ModCatalog)   # once: files older KIF copied into the game
      load_dir(File.join(".", FOLDER), extra_folders)
      KIF::ModAssets.build(@loaded_dirs || []) if defined?(KIF::ModAssets)
      KIF::ModCompat.after_mods_loaded if defined?(KIF::ModCompat) && KIF::ModCompat.respond_to?(:after_mods_loaded)
      KIF::AbilityText.install if defined?(KIF::AbilityText)   # outside mods' own ability-text aliases
      KIF::MoveText.install if defined?(KIF::MoveText)
    rescue => e
      KIF.log("Mods folder failed: #{e.message}")
    end

    # KIF kuray_modqueue
    def self.apply_species
      return if $POKEMONDATA_QUEUEING.nil? || $POKEMONDATA_QUEUEING.empty?
      $POKEMONDATA_QUEUEING.each do |data|
        begin
          GameData::Species.register(data)
        rescue => e
          KIF.log("Modded Pokémon #{data[:id].inspect} failed: #{e.message}")
        end
      end
    end
  end
end

module PluginManager
  class << self
    alias kif_mods_runPlugins runPlugins unless method_defined?(:kif_mods_runPlugins)

    def runPlugins(*args)
      ret = kif_mods_runPlugins(*args)
      KIF::Mods.load_all
      return ret
    end
  end
end

