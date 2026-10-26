#===============================================================================
# F-CORE-09 – ModSettingsMenu for mods (mods round 2, 2026-10-10)
#   Many catalog mods keep their settings in "ModSettingsMenu", the settings
#   API of an older community mod (Ghost QoL, GhostItem Splicers, GhostBattle
#   Classic+, GhostNPC Buddy / Wandering Trainers, Poké-Broker, Player
#   Housing, Overworld Encounters, Alpha Encounters). Only Kanto Reloaded
#   provides it in KIF, so without Kanto Reloaded those settings could
#   not be changed, and Ghost QoL even crashed (it reads ModSettingsMenu
#   without checking for it).
#   When no Kanto Reloaded is installed, KIF provides the same API before the
#   Mods folder loads, keeps the values in KIF_ModSettings.kro in the save
#   folder (all saves) and lists them under Options > KIF Settings > Mods.
#   With Kanto Reloaded installed nothing here runs: it has its own.
#===============================================================================
module KIF
  module ModSettings
    FILE = "KIF_ModSettings.kro"
    DEFAULT_CATEGORIES = [
      ["Interface", 10, "UI, menus and visuals"],
      ["Major Systems", 20, "Major gameplay systems"],
      ["Quality of Life", 30, "Convenience features and shortcuts"],
      ["Battle Mechanics", 40, "Battle mechanics and move behavior"],
      ["Economy", 50, "Money, shops, loot and prizes"],
      ["Difficulty", 60, "Difficulty and challenge settings"],
      ["Encounters", 70, "Wild encounters and spawn rates"],
      ["Training & Stats", 80, "Experience, EVs, IVs and stats"],
      ["Uncategorized", 900, "Settings without a category"],
      ["Debug & Developer", 999, "Testing and developer options"]
    ]
    @active = false
    @registry = []
    @categories = nil
    @values = nil
    @callbacks = {}

    class << self
      attr_reader :registry
    end

    def self.active?; return @active; end

    def self.categories
      return @categories if @categories
      @categories = DEFAULT_CATEGORIES.map { |n, p, d| { :name => n, :priority => p, :description => d, :collapsed => true } }
      return @categories
    end

    # Kanto Reloaded installed and not switched off in Mod Manager?
    # A Mod Manager mod (Mods/<x>/mod.json or Mods/ModDev/<x>/mod.json) with
    # this id, unless Mod Manager has it disabled
    def self.mm_mod_installed?(id, dir = "Mods")
      found = (Dir[File.join(dir, "*", "mod.json")] + Dir[File.join(dir, "ModDev", "*", "mod.json")]).any? do |f|
        (File.read(f) rescue "") =~ /"id"\s*:\s*"#{Regexp.escape(id)}"/
      end
      return false unless found
      state = File.join(dir, "mod_manager_state.json")
      if File.exist?(state)
        s = (File.read(state) rescue "")
        return false if s =~ /"#{Regexp.escape(id)}"\s*:\s*\{[^}]*"enabled"\s*:\s*false/
      end
      return true
    rescue StandardError
      return true   # when unsure, leave the API to the mod
    end

    def self.kanto_reloaded_installed?(dir = "Mods")
      return mm_mod_installed?("KantoReloaded", dir)
    end

    # Called before the Mods folder loads
    def self.install(dir = "Mods")
      # KIF's own, still defined after an F12 in the same game (phones, Linux, macOS), is used again
      ours = defined?(::ModSettingsMenu) && ::ModSettingsMenu.singleton_class.include?(API)
      return false if defined?(::ModSettingsMenu) && !ours
      return false if kanto_reloaded_installed?(dir)
      return false if mm_mod_installed?("mod_settings_menu", dir)   # the original Mod Settings Menu mod
      unless ours
        Object.const_set(:ModSettingsMenu, Module.new)
        ::ModSettingsMenu.const_set(:NOCATEGORY, "__nocategory__")
        ::ModSettingsMenu.extend(API)
      end
      @active = true
      drain_pending
      return true
    end

    # Mods loaded before the API existed queue their registration here
    def self.drain_pending
      return unless @active
      list = $MOD_SETTINGS_PENDING_REGISTRATIONS
      return unless list.is_a?(Array) && !list.empty?
      pending = list.dup
      list.clear
      pending.each do |pr|
        begin
          pr.call
        rescue StandardError => e
          KIF.log("Mod setting registration failed: #{e.class}: #{e.message}") if KIF.respond_to?(:log)
        end
      end
    end

    #---------------------------------------------------------------------------
    # Values (all saves)
    #---------------------------------------------------------------------------
    def self.path; return File.join(KIF.save_dir, FILE); end

    def self.values
      return @values if @values
      @values = {}
      begin
        d = File.open(path, "rb") { |f| Marshal.load(f) } if File.exist?(path)
        @values = d if d.is_a?(Hash)
      rescue StandardError => e
        KIF.set_aside(path, "Mod settings file", e)
      end
      return @values
    end

    def self.write
      tmp = path + ".tmp"
      File.open(tmp, "wb") { |f| Marshal.dump(values, f) }   # whole file or nothing
      File.rename(tmp, path)
    rescue StandardError => e
      KIF.log("Mod settings file not written (#{e.class}: #{e.message})") if KIF.respond_to?(:log)
    end

    def self.key(k); return k.to_s.to_sym; end

    #---------------------------------------------------------------------------
    # Settings of an uninstalled mod (Cody, 2026-10-20): moved into a file of
    # their own that nothing reads, so a leftover value can't reach a save or
    # another mod. They come back only when the same mod registers the same
    # setting again and the value still fits it (a choice that still exists,
    # a number still in range).
    #---------------------------------------------------------------------------
    UNINSTALLED_FILE = "KIF_ModSettings_uninstalled.kro"

    def self.uninstalled_path; return File.join(KIF.save_dir, UNINSTALLED_FILE); end

    def self.uninstalled
      return @uninstalled if @uninstalled
      d = File.open(uninstalled_path, "rb") { |f| Marshal.load(f) } if File.exist?(uninstalled_path)
      return @uninstalled = (d.is_a?(Hash) ? d : {})
    rescue StandardError => e
      KIF.set_aside(uninstalled_path, "Uninstalled mods' settings file", e)
      return @uninstalled = {}
    end

    def self.write_uninstalled
      tmp = uninstalled_path + ".tmp"
      File.open(tmp, "wb") { |f| Marshal.dump(uninstalled, f) }
      File.rename(tmp, uninstalled_path)
      return true
    rescue StandardError => e
      KIF.log("Uninstalled mods' settings not written (#{e.class}: #{e.message})") if KIF.respond_to?(:log)
      return false
    end

    # Moves mod_id's saved values out. Returns how many.
    def self.stash(mod_id)
      id = mod_id.to_s
      keys = @registry.select { |e| e[:mod].to_s == id }.map { |e| e[:key] }.select { |k| values.has_key?(k) }
      return 0 if keys.empty?
      box = (uninstalled[id] ||= {})
      keys.each { |k| box[k] = values[k] }
      return 0 unless write_uninstalled   # kept where they were if that failed
      keys.each { |k| values.delete(k) }
      write
      return keys.length
    end

    # v still a value e's row can show
    def self.fits?(e, v)
      return false unless v.nil? || v == true || v == false || v.is_a?(Numeric) || v.is_a?(String)
      case e[:type]
      when :enum
        n = Array(e[:values]).length
        n = 2 if n == 0
        return v.is_a?(Integer) && v >= 0 && v < n
      when :number, :slider
        lo = num(e[:min] || e[:minimum], 0)
        hi = num(e[:max] || e[:maximum], 100)
        return v.is_a?(Numeric) && v >= lo && v <= hi
      when :button
        return false
      else
        return v == true || v == false || v == 0 || v == 1
      end
    end

    def self.restore_stashed(e)
      return if e[:mod].nil? || values.has_key?(e[:key])
      box = uninstalled[e[:mod].to_s]
      return unless box && box.has_key?(e[:key])
      v = box.delete(e[:key])
      uninstalled.delete(e[:mod].to_s) if box.empty?
      write_uninstalled
      return unless fits?(e, v)
      values[e[:key]] = v
      write
    end

    def self.entry(k)
      kk = key(k)
      return @registry.find { |e| e[:key] == kk }
    end

    def self.get(k)
      kk = key(k)
      return values[kk] if values.has_key?(kk)
      e = entry(kk)
      return e ? e[:default] : nil
    end

    def self.set(k, v)
      kk = key(k)
      stored = values.has_key?(kk)
      old = stored ? values[kk] : get(kk)   # what the mod saw before (its default when unsaved)
      return v if stored && old == v
      values[kk] = v
      changed = (old != v)
      write if changed || !stored
      invoke(kk, v) if changed
      return v
    end

    def self.invoke(k, v)
      Array(@callbacks[key(k)]).each do |cb|
        begin
          cb.call(v)
        rescue StandardError => e
          KIF.log("Mod setting #{k} callback failed: #{e.class}: #{e.message}") if KIF.respond_to?(:log)
        end
      end
      e = entry(k)
      if e && e[:on_change].respond_to?(:call)
        begin
          e[:on_change].call(v)
        rescue StandardError => ex
          KIF.log("Mod setting #{k} on_change failed: #{ex.class}: #{ex.message}") if KIF.respond_to?(:log)
        end
      end
    end

    def self.on_change(k, &block)
      (@callbacks[key(k)] ||= []) << block if block
    end

    def self.register(k, opts = {})
      opts = {} unless opts.is_a?(Hash)
      h = {}
      opts.each { |ok, ov| h[ok.to_s.to_sym] = ov }
      h[:key] = key(k)
      h[:mod] ||= KIF::Mods.current if defined?(KIF::Mods) && KIF::Mods.respond_to?(:current)
      h[:type] = (h[:type] || :toggle).to_s.to_sym
      h[:name] ||= k.to_s
      h[:category] = "Uncategorized" if h[:category].nil? || h[:category].to_s.empty? ||
                                        h[:category] == "__nocategory__"
      @registry.delete_if { |e| e[:key] == h[:key] }
      @registry << h
      begin
        restore_stashed(h)   # a reinstalled mod gets its settings back
      rescue StandardError => ex
        KIF.log("Mod setting #{h[:key]}: couldn't bring back its saved value (#{ex.class}: #{ex.message})") if KIF.respond_to?(:log)
      end
      return true
    end

    # Categories that have settings, in priority order
    def self.used_categories
      names = @registry.map { |e| e[:category].to_s }.uniq
      cats = categories.select { |c| names.include?(c[:name].to_s) }
      (names - cats.map { |c| c[:name].to_s }).each { |n| cats << { :name => n, :priority => 500, :description => "" } }
      return cats.sort_by { |c| [c[:priority].to_i, c[:name].to_s] }
    end

    def self.entries_in(category)
      return @registry.select { |e| e[:category].to_s == category.to_s }
    end

    #---------------------------------------------------------------------------
    # The API mods call (same names as the old mod / Kanto Reloaded's shim)
    #---------------------------------------------------------------------------
    module API
      def kif_mod_settings?; true; end
      def registry; KIF::ModSettings.registry; end
      def categories; KIF::ModSettings.categories; end
      def register(key, options = {}); KIF::ModSettings.register(key, options); end
      def register_toggle(key, name, description = "", default = 0, category = nil)
        register(key, :name => name, :description => description, :type => :toggle, :default => default, :category => category)
      end
      def register_enum(key, name, values, default_index = 0, description = "", category = nil)
        register(key, :name => name, :description => description, :type => :enum, :values => values,
                      :default => default_index, :category => category)
      end
      def register_number(key, name, start_value, end_value, default, description = "", category = nil)
        register(key, :name => name, :description => description, :type => :number, :min => start_value,
                      :max => end_value, :default => default, :category => category)
      end
      def register_slider(key, name, start_value, end_value, interval, default, description = "", category = nil)
        register(key, :name => name, :description => description, :type => :slider, :min => start_value,
                      :max => end_value, :interval => interval, :default => default, :category => category)
      end
      def register_pending(key, options = {})
        register(key, options)
      end
      # Kanto Reloaded's shim form: an Option object with a key
      def register_option(option, key = nil, category = nil, _scene = nil)
        k = key || "legacy_option_#{option.object_id}"
        register(k, :name => (option.respond_to?(:name) ? option.name : k.to_s), :category => category)
      end
      def get(key); KIF::ModSettings.get(key); end
      def set(key, value); KIF::ModSettings.set(key, value); end
      def storage; KIF::ModSettings.values.dup; end
      def fallback_storage; storage; end
      def ensure_storage; true; end
      def set_storage(values)
        (values || {}).each { |k, v| KIF::ModSettings.set(k, v) }
      end
      def register_on_change(key, &block); KIF::ModSettings.on_change(key, &block); end
      def invoke_on_change(key, value); KIF::ModSettings.invoke(key, value); end
      def on_change_registry; {}; end
      def valid_category?(name); categories.any? { |c| c[:name].to_s == name.to_s }; end
      def toggle_category(_name); nil; end
      def category_collapsed?(_name); false; end
      def restore_category_states; nil; end
      def debug_log(message); KIF.verbose("[Mod] #{message}") if KIF.respond_to?(:verbose); end
    end

    #---------------------------------------------------------------------------
    # Options rows
    #---------------------------------------------------------------------------
    def self.num(v, fallback = 0)
      return (v ? 1 : 0) if v == true || v == false
      return v if v.is_a?(Numeric)
      begin
        return Integer(v.to_s)
      rescue ArgumentError, TypeError
        begin
          return Float(v.to_s)
        rescue ArgumentError, TypeError
          return fallback
        end
      end
    end

    def self.option_for(e)
      k = e[:key]
      name = _INTL(e[:name].to_s)
      desc = e[:description].to_s
      case e[:type]
      when :button
        pr = e[:on_press]
        return ButtonOption.new(name, proc { pr.call if pr.respond_to?(:call) }, desc)
      when :enum
        vals = Array(e[:values]).map { |v| _INTL(v.to_s) }
        vals = [_INTL("Off"), _INTL("On")] if vals.empty?
        return EnumOption.new(name, vals,
                              proc { [[num(get(k)).to_i, 0].max, vals.length - 1].min },
                              proc { |v| set(k, v) }, desc)
      when :number, :slider
        lo = num(e[:min] || e[:minimum], 0)
        hi = num(e[:max] || e[:maximum], 100)
        hi = lo if hi < lo
        step = num(e[:interval] || e[:step], 1)
        step = 1 if step <= 0
        step = [step, KIF::Options.slider_step].max if hi - lo > 200
        getter = proc { [[num(get(k), lo), lo].max, hi].min - lo }
        setter = proc { |v| set(k, (lo.is_a?(Integer) && step.is_a?(Integer)) ? (v + lo).to_i : v + lo) }
        if e[:type] == :number && hi - lo <= 200 && step == 1
          return NumberOption.new(name, lo, hi, getter, setter, desc)
        end
        return SliderOption.new(name, lo, hi, step, getter, setter, desc)
      else # :toggle and anything unknown
        return EnumOption.new(name, [_INTL("Off"), _INTL("On")],
                              proc { num(get(k)) == 0 ? 0 : 1 },
                              proc { |v| set(k, v) }, desc)
      end
    end
  end
end

# Rows for the settings screen: one category's settings, or a list of
# registry entries (one mod's)
module KIF
  module ModSettings
    def self.options_for(list)
      return list.map do |e|
        begin
          option_for(e)
        rescue StandardError => ex
          KIF.log("Mod setting #{e[:key]} has no row: #{ex.class}: #{ex.message}") if KIF.respond_to?(:log)
          nil
        end
      end.compact
    end

    def self.options_in(category)
      return options_for(entries_in(category))
    end
  end
end
