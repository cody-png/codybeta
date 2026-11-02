#===============================================================================
# F-CORE-10 Mod API - data a mod keeps (survives the mod's removal)
#
#   store = KIF::API.data(:save)     # this save file's data of the calling mod
#   store = KIF::API.data(:global)   # this install's data of the calling mod
#   store["gold"] = 5; store.fetch("gold", 0); store.update("a" => 1, "b" => [1, 2])
#   store.delete("gold"); store.key?("a"); store.keys; store.to_h; store.clear
#   store.version; store.migrate(to: 2) { |old| old.merge("new" => 1) }
#   KIF::API.data(:save, mod: "other_mod")   # another mod's data: a frozen copy, read only
#
# Plain data only: nil, true, false, Integer, finite Float, String (UTF-8, at
# most 64 KB), Array, Hash (keys become Strings, Symbols become Strings), depth
# at most 8. A mod may hold 256 KB in all; all mods 2 MB in saves and 4 MB
# global. Anything else is not stored, logged once, and raised as
# KIF::API::PlainDataError in Mod Dev mode. Nothing a mod stores is evaluated or
# loaded with Marshal. Values you get back are the live objects: change a nested
# Array or Hash and the change is saved too, but anything that is not plain is
# dropped when the game saves.
#
# :save lives in the save file under ONE key, :kif_mod_data, plain core types
# only, so the save loads in vanilla PIF and without this mod. Data of a mod that
# is not installed stays in the save (it comes back if the mod is installed
# again); KIF::API.data_orphans lists it, KIF::API.data_forget(key, scope)
# removes it, nothing is removed by itself.
# :global is a JSON file (KIF_ModData/<mod>/data.json in the save folder), written
# whole or not at all (temporary file, then rename) when the game saves, every
# 30 seconds while something changed, and when a mod is unloaded. A file that
# can not be read is kept aside (.bad) and the store starts empty.
#===============================================================================
module KIF
  module API
    module Data
      MAX_DEPTH   = 8                 unless const_defined?(:MAX_DEPTH)
      MAX_STRING  = 65_536            unless const_defined?(:MAX_STRING)
      MAX_MOD     = 262_144           unless const_defined?(:MAX_MOD)
      MAX_SAVE    = 2 * 1024 * 1024   unless const_defined?(:MAX_SAVE)
      MAX_GLOBAL  = 4 * 1024 * 1024   unless const_defined?(:MAX_GLOBAL)
      VERSION_KEY = "__kif_version"   unless const_defined?(:VERSION_KEY)
      FILE        = "data.json"       unless const_defined?(:FILE)
      FLUSH_TICKS = 1200              unless const_defined?(:FLUSH_TICKS)   # 30 s of logic steps

      class Bad < StandardError; end

      @save    ||= {}   # mod key => { String => plain }
      @global  ||= {}
      @sizes   ||= { :save => {}, :global => {} }   # scope => mod => { key => bytes }
      @dirty   ||= {}   # mod key => true (global only)
      @hooks   ||= false
      @ticks   ||= 0

      class << self
        attr_reader :save, :global, :dirty
      end

      #-------------------------------------------------------------------------
      # Plain data
      #-------------------------------------------------------------------------
      # A deep copy of value made only of plain data (Hash keys as Strings), or raises Bad.
      def self.convert(v, depth = 0)
        raise Bad, "nested deeper than #{MAX_DEPTH}" if depth > MAX_DEPTH
        case v
        when nil, true, false then return v
        when Integer
          raise Bad, "integer too large" unless v.abs < 2**63
          return v
        when Float
          raise Bad, "number is not finite" unless v.finite?
          return v
        when Symbol then return convert(v.to_s, depth)
        when String
          s = v.encoding.name == "UTF-8" ? v : v.dup.force_encoding("UTF-8") # not Encoding::UTF_8: JoiPlay rewrites that constant
          raise Bad, "text is not valid UTF-8" unless s.valid_encoding?
          raise Bad, "text longer than #{MAX_STRING} bytes" if s.bytesize > MAX_STRING
          return s.dup
        when Array then return v.map { |x| convert(x, depth + 1) }
        when Hash
          out = {}
          v.each do |k, x|
            raise Bad, "hash key #{k.class} (use a String)" unless k.is_a?(String) || k.is_a?(Symbol)
            out[k.to_s] = convert(x, depth + 1)
          end
          return out
        else
          raise Bad, "#{v.class} is not plain data"
        end
      end

      # compact JSON of plain data (KIF::Mods::MiniJSON reads it back)
      def self.dump(v)
        case v
        when nil then return "null"
        when true then return "true"
        when false then return "false"
        when Integer, Float then return v.to_s
        when String then return dump_str(v)
        when Array then return "[" + v.map { |x| dump(x) }.join(",") + "]"
        when Hash then return "{" + v.map { |k, x| dump_str(k.to_s) + ":" + dump(x) }.join(",") + "}"
        end
        return "null"
      end

      def self.dump_str(s)
        return '"' + s.gsub(/["\\\x00-\x1f]/) do |c|
          case c
          when '"' then '\\"'
          when "\\" then "\\\\"
          when "\n" then "\\n"
          when "\r" then "\\r"
          when "\t" then "\\t"
          else format("\\u%04x", c.ord)
          end
        end + '"'
      end

      def self.bytes_of(key, value); return dump(value).bytesize + key.to_s.bytesize + 6; end

      def self.json_parse(text)
        h = KIF::Mods::MiniJSON.parse(text)
        return h.is_a?(Hash) ? h : nil
      end

      #-------------------------------------------------------------------------
      # The tables
      #-------------------------------------------------------------------------
      def self.table(scope); return scope == :global ? @global : @save; end

      def self.hash_for(scope, mod)
        load_global(mod) if scope == :global && !@global.key?(mod)
        return table(scope)[mod] ||= {}
      end

      def self.total(scope)
        return @sizes[scope].values.inject(0) { |s, h| s + h.values.inject(0, :+) }
      end

      # one write, checked: returns true, or false (not stored)
      def self.write(scope, mod, key, value)
        k = key.to_s
        if k.empty? || k.bytesize > 200 || k.start_with?("__kif")
          return refuse(scope, mod, "key #{k[0, 40].inspect} is empty, too long or reserved")
        end
        begin
          v = convert(value)
        rescue Bad => e
          return refuse(scope, mod, "#{k}: #{e.message}")
        end
        sz = bytes_of(k, v)
        mine = (@sizes[scope][mod] ||= {})
        mod_total = mine.reject { |kk, _| kk == k }.values.inject(0, :+) + sz
        return refuse(scope, mod, "#{k}: over #{MAX_MOD / 1024} KB for this mod") if mod_total > MAX_MOD
        cap = scope == :global ? MAX_GLOBAL : MAX_SAVE
        if total(scope) - (mine[k] || 0) + sz > cap
          return refuse(scope, mod, "#{k}: all mods together would pass #{cap / (1024 * 1024)} MB")
        end
        hash_for(scope, mod)[k] = v
        mine[k] = sz
        mark_dirty(mod) if scope == :global
        return true
      end

      def self.refuse(scope, mod, why)
        msg = "mod data (#{scope}): #{why}"
        raise PlainDataError, msg if API.dev?
        API.say("data:#{mod}:#{why[0, 40]}", "Mod \"#{Attribution.display(mod)}\" #{msg}; not stored")
        return false
      end

      def self.forget_key(scope, mod, key)
        h = table(scope)[mod]
        h.delete(key) if h
        (@sizes[scope][mod] || {}).delete(key)
        mark_dirty(mod) if scope == :global
      end

      #-------------------------------------------------------------------------
      # What a mod holds
      #-------------------------------------------------------------------------
      class Store
        attr_reader :scope, :mod

        def initialize(scope, mod, snapshot = nil)
          @scope = scope
          @mod = mod
          @snapshot = snapshot
        end

        def readonly?; return !@snapshot.nil?; end
        def h; return @snapshot || API::Data.hash_for(@scope, @mod); end
        private :h

        def [](key); return h[key.to_s]; end
        def key?(key); return h.key?(key.to_s); end
        def keys; return h.keys.reject { |k| k.start_with?("__kif") }; end
        def fetch(key, default = nil)
          return h[key.to_s] if h.key?(key.to_s)
          return block_given? ? yield(key.to_s) : default
        end
        def to_h; return h.reject { |k, _| k.start_with?("__kif") }; end

        def []=(key, value)
          return value if guard_write
          API::Data.write(@scope, @mod, key, value)
          return value
        end

        def update(hash)
          return self if guard_write
          hash.each { |k, v| API::Data.write(@scope, @mod, k, v) }
          return self
        end

        def delete(key)
          return nil if guard_write
          old = h[key.to_s]
          API::Data.forget_key(@scope, @mod, key.to_s)
          return old
        end

        def clear
          return self if guard_write
          keys.each { |k| API::Data.forget_key(@scope, @mod, k) }
          return self
        end

        # the version of the mod's own data layout (0 until set)
        def version; return h[VERSION_KEY].is_a?(Integer) ? h[VERSION_KEY] : 0; end

        # store.migrate(to: 2) { |old_hash| new_hash } runs once when the stored
        # version is lower; the block gets a copy and returns the new contents
        def migrate(to:)
          return false if guard_write || version >= to
          nh = yield(to_h)
          return false unless nh.is_a?(Hash)
          clean = {}
          begin
            nh.each { |k, v| clean[k.to_s] = API::Data.convert(v) }
          rescue Bad, NoMethodError => e
            API::Data.refuse(@scope, @mod, "migrate: #{e.message}")
            return false
          end
          keys.each { |k| API::Data.forget_key(@scope, @mod, k) }
          clean.each { |k, v| API::Data.write(@scope, @mod, k, v) }
          API::Data.table(@scope)[@mod][VERSION_KEY] = to
          API::Data.mark_dirty(@mod) if @scope == :global
          return true
        end

        private

        def guard_write
          return false unless readonly?
          API.say("datareadonly:#{@mod}", "Mod data of \"#{API::Attribution.display(@mod)}\" is read only here")
          return true
        end
      end

      # a frozen deep copy of another mod's data (read only)
      def self.snapshot(scope, mod)
        h = (hash_for(scope, mod) rescue {})
        copy = (convert(h) rescue {})
        deep_freeze(copy)
        return copy
      end

      def self.deep_freeze(v)
        case v
        when Hash then v.each { |k, x| deep_freeze(x) }
        when Array then v.each { |x| deep_freeze(x) }
        end
        v.freeze
      end

      #-------------------------------------------------------------------------
      # The save (one key, :kif_mod_data)
      #-------------------------------------------------------------------------
      # sanitised copy of a whole { mod => { key => value } }; what does not fit is dropped and logged
      def self.clean_all(raw, scope, what)
        out = {}
        sizes = {}
        return [out, sizes] unless raw.is_a?(Hash)
        raw.each do |mk, h|
          next unless h.is_a?(Hash)
          mod = mk.to_s
          mine = {}
          msz = {}
          h.each do |k, v|
            ks = k.to_s
            begin
              c = convert(v)
            rescue Bad => e
              KIF.log("Mod data (#{what}): #{mod}/#{ks[0, 40]} dropped (#{e.message})")
              next
            end
            msz[ks] = bytes_of(ks, c)
            mine[ks] = c
          end
          if msz.values.inject(0, :+) > MAX_MOD
            KIF.log("Mod data (#{what}): #{mod} is over #{MAX_MOD / 1024} KB and was dropped")
            next
          end
          out[mod] = mine
          sizes[mod] = msz
        end
        cap = scope == :global ? MAX_GLOBAL : MAX_SAVE
        sum = lambda { sizes.values.inject(0) { |s, m| s + m.values.inject(0, :+) } }
        if sum.call > cap
          installed = (API.mods.map(&:key) rescue [])
          # data of mods that are not installed goes first, oldest (first in the hash) first
          out.keys.reject { |m| installed.include?(m) }.each do |m|
            break if sum.call <= cap
            KIF.log("Mod data (#{what}): #{m} (not installed) dropped to fit #{cap / (1024 * 1024)} MB")
            out.delete(m); sizes.delete(m)
          end
          while sum.call > cap && !out.empty?
            m = sizes.max_by { |_, mm| mm.values.inject(0, :+) }[0]
            KIF.log("Mod data (#{what}): #{m} dropped to fit #{cap / (1024 * 1024)} MB")
            out.delete(m); sizes.delete(m)
          end
        end
        return [out, sizes]
      end

      # what the save file holds: a deep copy, plain core types only. What does
      # not fit is dropped from the live data too (objects a mod holds stay live).
      def self.export_save
        out, sizes = clean_all(@save, :save, "saving")
        @save.keys.each { |m| @save.delete(m) unless out.key?(m) }
        @save.each { |m, h| h.keys.each { |k| h.delete(k) unless k.start_with?("__kif") || out[m].key?(k) } }
        @sizes[:save] = sizes
        return out.reject { |_, h| h.empty? }
      end

      # a save without the key, a non-Hash, or hostile content: sanitised, never raises
      def self.import_save(value)
        out, sizes = clean_all(value, :save, "loading")
        @save = out
        @sizes[:save] = sizes
        return true
      end

      #-------------------------------------------------------------------------
      # The global file
      #-------------------------------------------------------------------------
      def self.path_for(mod); return File.join(KIF::ModContract.data_dir(mod), FILE); end

      def self.read_file(mod)
        return KIF::Safe.read_mod_file(mod, FILE) if defined?(KIF::Safe) && KIF::Safe.respond_to?(:read_mod_file)
        p = path_for(mod)
        return File.file?(p) ? File.binread(p) : nil
      end

      def self.write_file(mod, text)
        if defined?(KIF::Safe) && KIF::Safe.respond_to?(:write_mod_file)
          KIF::Safe.write_mod_file(mod, FILE, text)
          return true
        end
        p = path_for(mod)
        KIF.mkdir_p(File.dirname(p))
        tmp = "#{p}.#{$$}.tmp"
        File.binwrite(tmp, text)
        File.rename(tmp, p)
        return true
      end

      def self.load_global(mod)
        @global[mod] = {}
        @sizes[:global][mod] = {}
        text = read_file(mod)
        return if text.nil? || text.empty?
        h = json_parse(text.dup.force_encoding("UTF-8"))
        if h.nil?
          p = path_for(mod)
          KIF.set_aside(p, "Mod data of #{Attribution.display(mod)}") if File.file?(p)
          return
        end
        out, sizes = clean_all({ mod => h }, :global, "reading")
        @global[mod] = out[mod] || {}
        @sizes[:global][mod] = sizes[mod] || {}
      rescue StandardError => e
        KIF.log("Mod data of #{mod}: could not be read (#{e.class}: #{e.message[0, 100]})")
        @global[mod] = {}
        @sizes[:global][mod] ||= {}
      end

      def self.mark_dirty(mod)
        @dirty[mod] = true
        ensure_hooks
      end

      # writes the changed files; mod = one mod only
      def self.flush(mod = nil)
        (mod ? [mod] : @dirty.keys).each do |m|
          next unless @dirty[m]
          begin
            write_file(m, dump(@global[m] || {}))
            @dirty.delete(m)
          rescue StandardError => e
            API.say("dataflush:#{m}", "Mod data of \"#{Attribution.display(m)}\" could not be written (#{e.class}: #{e.message[0, 100]})")
          end
        end
        drop_hooks if @dirty.empty?
      end

      def self.ensure_hooks
        return if @hooks
        @hooks = true
        @ticks = 0
        API.on(:game_saved, "modapi_data_flush", mod: :kif) { |c| Data.flush }
        API.on(:tick, "modapi_data_tick", mod: :kif) { |c| Data.tick }
      end

      def self.drop_hooks
        return unless @hooks
        @hooks = false
        API.subscribers(:game_saved).each { |s| s.off if s.id == "modapi_data_flush" }
        API.subscribers(:tick).each { |s| s.off if s.id == "modapi_data_tick" }
      end

      def self.tick
        @ticks += 1
        return if @ticks < FLUSH_TICKS
        @ticks = 0
        flush
      end

      #-------------------------------------------------------------------------
      # Mods that are gone
      #-------------------------------------------------------------------------
      def self.orphans
        installed = (API.mods.map(&:key) rescue [])
        safe = installed.map { |k| KIF::ModContract.safe_id(k) }
        out = []
        @save.each { |k, h| out << { :scope => :save, :key => k, :bytes => (@sizes[:save][k] || {}).values.inject(0, :+) } unless installed.include?(k) }
        dir = File.join(KIF.save_dir, "KIF_ModData")
        if File.directory?(dir)
          Dir.children(dir).sort.each do |c|
            next if safe.include?(c) || !File.file?(File.join(dir, c, FILE))
            out << { :scope => :global, :key => c, :bytes => File.size(File.join(dir, c, FILE)) }
          end
        end
        return out
      end

      def self.forget(key, scope)
        if scope == :save
          @save.delete(key.to_s)
          @sizes[:save].delete(key.to_s)
          return true
        end
        @global.delete(key.to_s)
        @sizes[:global].delete(key.to_s)
        @dirty.delete(key.to_s)
        dir = File.join(KIF.save_dir, "KIF_ModData", KIF::ModContract.safe_id(key))
        File.delete(File.join(dir, FILE)) if File.file?(File.join(dir, FILE))
        Dir.rmdir(dir) rescue nil
        return true
      end
    end

    #---------------------------------------------------------------------------
    # KIF::API.data(scope = :save, mod: nil) -> Store
    #---------------------------------------------------------------------------
    def self.data(scope = :save, mod: nil)
      scope = scope.to_sym
      raise ArgumentError, "scope must be :save or :global" unless [:save, :global].include?(scope)
      key = Attribution.key_from_caller(caller_locations(1, 40))
      if key.nil? && mod.nil?
        raise ArgumentError, "KIF::API.data needs to be called from a mod (or pass mod: \"name\" for a read-only copy)"
      end
      return Data::Store.new(scope, key) if mod.nil? || mod.to_s == key.to_s
      return Data::Store.new(scope, mod.to_s, Data.snapshot(scope, mod.to_s))
    end

    def self.data_orphans; return Data.orphans; end
    def self.data_forget(key, scope = :save); return Data.forget(key, scope); end

    on_unload(:data) { |key| Data.flush(key) }
  end
end

# ONE save key, no ensure_class: a save without it (vanilla PIF, an older KIF)
# must load, and import_save_scope accepts nil and non-Hash values.
unless (SaveData.instance_variable_get(:@values) || []).any? { |v| v.id == :kif_mod_data }
  SaveData.register(:kif_mod_data) do
    save_value { KIF::API::Data.export_save }
    load_value { |value| KIF::API::Data.import_save(value) }
    new_game_value { {} }
  end
end
