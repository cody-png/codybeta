#===============================================================================
# F-CORE-09 – ModSettingsMenu for mods (mods round 2, 2026-10-10)
#   Many catalog mods keep their settings in "ModSettingsMenu", the settings
#   API of an older community mod (Ghost QoL, GhostItem Splicers, GhostBattle
#   Classic+, GhostNPC Buddy / Wandering Trainers, Poké-Broker, Player
#   Housing, Overworld Encounters, Alpha Encounters). Only Kanto Reloaded
#   provides it in KIF Beta, so without Kanto Reloaded those settings could
#   not be changed, and Ghost QoL even crashed (it reads ModSettingsMenu
#   without checking for it).
#   When no Kanto Reloaded is installed, KIF provides the same API before the
#   Mods folder loads, keeps the values in KIF_ModSettings.kro in the save
#   folder (all saves) and lists them under Options > Mod Settings.
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
    def self.kanto_reloaded_installed?(dir = "Mods")
      found = Dir[File.join(dir, "*", "mod.json")].any? do |f|
        (File.read(f) rescue "") =~ /"id"\s*:\s*"KantoReloaded"/
      end
      return false unless found
      state = File.join(dir, "mod_manager_state.json")
      if File.exist?(state)
        s = (File.read(state) rescue "")
        return false if s =~ /"KantoReloaded"\s*:\s*\{[^}]*"enabled"\s*:\s*false/
      end
      return true
    rescue StandardError
      return true   # when unsure, leave the API to Kanto Reloaded
    end

    # Called before the Mods folder loads
    def self.install(dir = "Mods")
      return false if defined?(::ModSettingsMenu)
      return false if kanto_reloaded_installed?(dir)
      Object.const_set(:ModSettingsMenu, Module.new)
      ::ModSettingsMenu.const_set(:NOCATEGORY, "__nocategory__")
      ::ModSettingsMenu.extend(API)
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
        KIF.log("Mod settings file unreadable (#{e.class}: #{e.message})") if KIF.respond_to?(:log)
      end
      return @values
    end

    def self.write
      File.open(path, "wb") { |f| Marshal.dump(values, f) }
    rescue StandardError => e
      KIF.log("Mod settings file not written (#{e.class}: #{e.message})") if KIF.respond_to?(:log)
    end

    def self.key(k); return k.to_s.to_sym; end

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
      old = values[kk]
      values[kk] = v
      write if old != v || !File.exist?(path)
      invoke(kk, v) if old != v
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
      h[:type] = (h[:type] || :toggle).to_s.to_sym
      h[:name] ||= k.to_s
      h[:category] = "Uncategorized" if h[:category].nil? || h[:category].to_s.empty? ||
                                        h[:category] == "__nocategory__"
      @registry.delete_if { |e| e[:key] == h[:key] }
      @registry << h
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
      def debug_log(message); KIF.log("[Mod] #{message}") if KIF.respond_to?(:log); end
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

class KifModSettingsScene < KifOptionsBaseScene
  def kif_title; "Mod Settings"; end
  def getDefaultDescription; return _INTL("Settings added by your mods"); end

  def pbGetOptions(inloadscreen = false)
    options = []
    KIF::ModSettings.used_categories.each do |c|
      name = c[:name].to_s
      options << ButtonOption.new(_INTL(name), proc { @kif_cat = name; kif_open_category },
                                  _INTL(c[:description].to_s))
    end
    return options
  end

  def kif_open_category
    cat = @kif_cat
    return unless cat
    pbFadeOutIn {
      scene = KifModSettingsCategoryScene.new(cat)
      PokemonOptionScreen.new(scene).pbStartScreen
    }
    @kif_cat = nil
  end
end

class KifModSettingsCategoryScene < KifOptionsBaseScene
  def initialize(category)
    super()
    @kif_category = category
  end

  def kif_title; @kif_category.to_s; end
  def getDefaultDescription; return _INTL("Settings added by your mods"); end

  def pbGetOptions(inloadscreen = false)
    return KIF::ModSettings.entries_in(@kif_category).map do |e|
      begin
        KIF::ModSettings.option_for(e)
      rescue StandardError => ex
        KIF.log("Mod setting #{e[:key]} has no row: #{ex.class}: #{ex.message}") if KIF.respond_to?(:log)
        nil
      end
    end.compact
  end
end
