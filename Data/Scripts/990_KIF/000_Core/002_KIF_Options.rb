#===============================================================================
# F-CORE-01 – KIF Options framework (port)
#
# KIF stored ~105 extra attributes directly on PokemonSystem and built seven
# hand-written option scenes (015_UI_Options.rb:1439-3100 in KIF 0.20.7).
# Here every setting is declared once:
#
#   KIF::Options.define(:shinyodds, 16, :save)
#   KIF::Options.add(:shinies, :save) {
#     SliderOption.new(_INTL("Wild Shiny Odds"), 0, 65536, KIF::Options.slider_step,
#                      proc { $PokemonSystem.shinyodds },
#                      proc { |v| $PokemonSystem.shinyodds = [v, 1].max },
#                      _INTL("<x> out of 65536 | Choose the Shiny Odds"))
#   }
#
# * The attribute keeps KIF's original name, so ported code can keep using
#   `$PokemonSystem.<name>` unchanged.
# * Old saves (or vanilla saves) that lack the instance variable read the
#   default instead of nil.
# * Scope :global  -> lives on $PokemonSystem only (saved under :pokemon_system,
#                     loaded at boot: shared by every save file, like KIF).
#   Scope :save    -> also copied into the :kif_save_settings save key and
#                     restored when that save file is loaded; reset to the
#                     default on New Game. (KIF used :kuray_pokemon_system_file
#                     holding a whole PokemonSystem; a Hash is used here so a
#                     vanilla PIF can still Marshal.load the save.)
#===============================================================================
module KIF
  module Options
    # id => [title, menu-button description, name colour, shadow colour]
    # Order and colours follow KIF's KurayOptionsScene / KurayOptSc_1..6.
    MENUS = {
      :shinies    => ["Shiny settings",                "Customize shinies features",       [200, 200, 35], [115, 115, 20]],
      :battles    => ["Battles & Pokemons settings",   "Customize battles & pokemons features", [200, 35, 35], [115, 20, 20]],
      :graphics   => ["Graphics settings",             "Customize graphics features",      [35, 200, 35], [20, 115, 20]],
      :selfbattle => ["Self-Battle & Import settings", "Self-battling & import features",  [200, 35, 200], [115, 20, 115]],
      :challenges => ["Challenges settings",           "Challenges",                       [35, 35, 200], [20, 20, 115]],
      :others     => ["Others settings",               "Customize others features",        [35, 200, 200], [20, 115, 115]]
    }
    MENU_BUTTON_LABELS = {
      :shinies => "Shinies", :battles => "Battles & Pokemons", :graphics => "Graphics",
      :selfbattle => "Self-Battle & Import", :challenges => "Challenges", :others => "Others"
    }
    # Values for "Increment Slider by" (KIF: raiserb index -> raiser step)
    SLIDER_STEPS = [1, 10, 100, 1000, 10000]

    @defaults = {}     # key => default
    @scopes   = {}     # key => :global / :save
    @entries  = {}     # menu => [[scope, builder_proc], ...]

    def self.defaults; @defaults; end

    # Menus added by other settings roots (e.g. Cody Settings):
    # id => [title, menu-button description, name colour, shadow colour, button label]
    @extra_menus = {}

    def self.register_menu(id, title, description, base, shadow, label)
      @extra_menus[id] = [title, description, base, shadow, label]
    end

    def self.menu_info(menu)
      return MENUS[menu] || @extra_menus[menu]
    end

    def self.menu_label(menu)
      return MENU_BUTTON_LABELS[menu] if MENU_BUTTON_LABELS[menu]
      info = @extra_menus[menu]
      return info ? info[4] : menu.to_s
    end

    def self.define(key, default, scope = :save)
      key = key.to_sym
      @defaults[key] = default
      @scopes[key] = scope
      ivar = :"@#{key}"
      if PokemonSystem.method_defined?(key) && !PokemonSystem.method_defined?(:"kif_defined_#{key}")
        # the getter below replaces it, so KIF's default does apply when unset
        KIF.log("PokemonSystem##{key} is also defined outside KIF; KIF's default (#{default.inspect}) applies when it's unset")
      end
      PokemonSystem.class_eval do
        define_method(:"kif_defined_#{key}") { true }
        define_method(key) do
          t = KIF::Options.tracing
          t << key if t
          lock = KIF::Locks.table[key]
          return lock[0] if lock
          val = instance_variable_get(ivar)
          if val.nil?
            val = KIF::Options.copy_default(key)
            instance_variable_set(ivar, val)
          end
          val
        end
        define_method(:"#{key}=") { |v| instance_variable_set(ivar, v) }
      end
    end

    # The player's own value (a mod's lock doesn't count): what saves keep
    def self.raw(key, sys = $PokemonSystem)
      return nil unless sys
      key = key.to_sym
      ivar = :"@#{key}"
      return sys.instance_variable_get(ivar) if sys.instance_variable_defined?(ivar) && !sys.instance_variable_get(ivar).nil?
      return copy_default(key) if @defaults.has_key?(key)
      plain = :"kif_unlocked_#{key}"
      return sys.respond_to?(plain) ? sys.send(plain) : sys.send(key)
    end

    # The settings a block reads ([:shinyodds]); the settings screen uses it
    # to find which rows a mod locked
    @tracing = nil
    def self.tracing; @tracing; end

    def self.keys_read
      old = @tracing
      @tracing = []
      begin
        yield
      rescue StandardError
      end
      return @tracing.uniq
    ensure
      @tracing = old
    end

    def self.copy_default(key)
      d = @defaults[key]
      return (d.is_a?(Hash) || d.is_a?(Array) || d.is_a?(String)) ? Marshal.load(Marshal.dump(d)) : d
    end

    def self.scope(key);  @scopes[key.to_sym]; end
    def self.save_keys;   @scopes.select { |_k, s| s == :save }.keys; end

    # Register a menu entry. The block must return an Option (built each time
    # the menu opens, so slider steps etc. are current).
    def self.add(menu, scope = :save, &builder)
      raise ArgumentError, "Unknown KIF menu #{menu}" unless menu_info(menu)
      (@entries[menu] ||= []) << [scope, builder]
    end

    def self.entries(menu); @entries[menu] || []; end
    def self.menu_used?(menu); !entries(menu).empty?; end

    def self.slider_step
      return SLIDER_STEPS[$PokemonSystem.raiserb] || 1
    end

    #---------------------------------------------------------------------------
    # Per-save persistence
    #---------------------------------------------------------------------------
    # Entries of the loaded :kif_save_settings hash that no ported feature
    # defines (yet). Kept and written back so nothing from an old KIF save is
    # lost before its feature is ported.
    @carry = {}

    def self.export_save_scope
      hash = {}
      @carry.each { |k, v| hash[k] = Marshal.load(Marshal.dump(v)) }
      return hash unless $PokemonSystem
      # the player's values, not a mod's locks
      save_keys.each { |k| hash[k] = Marshal.load(Marshal.dump(raw(k))) }
      return hash
    end

    def self.import_save_scope(hash)
      hash = {} unless hash.is_a?(Hash)
      @carry = {}
      hash.each { |k, v| @carry[k] = v unless save_keys.include?(k) }
      return unless $PokemonSystem
      save_keys.each do |k|
        if hash.has_key?(k)
          $PokemonSystem.send(:"#{k}=", hash[k])
        else
          $PokemonSystem.send(:"#{k}=", copy_default(k))
        end
      end
    end
  end
end

#===============================================================================
# Locks (2026-10-16): a mod sets some settings or modules for as long as it's
# On ("Experiences": a hardcore mod pins shiny odds, turns Auto Battle off).
#   mod.json   "locks":   { "shinyodds": 16, "levelcap": 1 }
#              "modules": { "auto_battle": "off", "randomizer": "on" }
#   Ruby       KIF::Locks.set(:shinyodds, 16)
#              KIF::Locks.set_module(:auto_battle, :off)
# The game reads the locked value; the settings screen shows the row with a
# LOCKED badge ("Set by <mod>") and won't change it. The player's own value
# is kept (and saved) underneath, so it's back once the mod is Off.
# Any KIF setting (KIF::Options.define) or PIF one on PokemonSystem
# (textspeed, battlestyle...) can be locked. Mod Settings can't be locked
# Off (the player must always be able to switch a mod Off).
#===============================================================================
module KIF
  module Locks
    @table = {}     # setting => [value, mod name, mod id]
    @modules = {}   # module id => [state, mod name, mod id]
    @wrapped = {}
    MODULE_STATES = { "off" => 0, "on" => 1, "hidden" => 2 }

    class << self
      attr_reader :table
    end

    def self.any?; return !@table.empty? || !@modules.empty?; end

    def self.owner_name(by, owner)
      owner ||= (KIF::Mods.current if defined?(KIF::Mods) && KIF::Mods.respond_to?(:current))
      by ||= (KIF::Mods.display_name(owner) if owner && defined?(KIF::Mods) && KIF::Mods.respond_to?(:display_name)) || owner || "A mod"
      return [by.to_s, owner]
    end

    # the value as the setting stores it (true -> 1 for On/Off settings...)
    def self.fit(key, value)
      d = KIF::Options.defaults[key]
      # mods lock settings at load, before $PokemonSystem exists: read a fresh one
      cur = d.nil? ? (($PokemonSystem || PokemonSystem.new).send(key) rescue nil) : d
      if cur.is_a?(Integer)
        return 1 if value == true
        return 0 if value == false
        return value.round if value.is_a?(Float)
        return value if value.is_a?(Integer)
        return nil
      end
      return value if cur.nil? || [true, false].include?(cur) && [true, false].include?(value)
      return value.to_f if cur.is_a?(Float) && value.is_a?(Numeric)
      return value if value.class == cur.class && !value.is_a?(Hash) && !value.is_a?(Array)
      return nil
    end

    def self.set(key, value, by: nil, owner: nil)
      key = key.to_sym
      by, owner = owner_name(by, owner)
      unless KIF::Options.defaults.has_key?(key) || wrap(key)
        KIF.log("#{by}: can't lock \"#{key}\" - no setting by that name")
        return false
      end
      if key == :kif_modules
        KIF.log("#{by}: modules are locked with \"modules\", not \"locks\"")
        return false
      end
      v = fit(key, value)
      if v.nil?
        KIF.log("#{by}: can't lock #{key} to #{value.inspect} (it holds #{KIF::Options.defaults[key].class})")
        return false
      end
      if @table[key] && @table[key][2] != owner
        KIF.log("#{by}: #{key} is already locked by #{@table[key][1]} - left to it")
        return false
      end
      @table[key] = [v, by, owner]
      return true
    end

    def self.set_module(id, state, by: nil, owner: nil)
      by, owner = owner_name(by, owner)
      id = id.to_s.to_sym
      st = state.is_a?(Integer) ? state : MODULE_STATES[state.to_s.downcase]
      unless KIF::Modules::MODULES.has_key?(id) && st && st.between?(0, 2)
        KIF.log("#{by}: can't set module #{id} to #{state.inspect}")
        return false
      end
      if id == :mod_settings && st != KIF::Modules::ON
        KIF.log("#{by}: Mod Settings can't be locked #{state} (players need it to switch mods Off)")
        return false
      end
      if @modules[id] && @modules[id][2] != owner
        KIF.log("#{by}: module #{id} is already set by #{@modules[id][1]} - left to it")
        return false
      end
      @modules[id] = [st, by, owner]
      KIF::Modules.poll if KIF::Modules.respond_to?(:poll) && $PokemonSystem
      return true
    end

    def self.get(key); return @table[key.to_sym]; end
    def self.module_lock(id); return @modules[id]; end

    def self.module_state(id)
      return nil if @modules.empty?
      l = @modules[id]
      return l ? l[0] : nil
    end

    # undo every lock of a mod (one that failed to load)
    def self.release(owner)
      @table.delete_if { |_k, v| v[2] == owner }
      @modules.delete_if { |_k, v| v[2] == owner }
    end

    def self.reset!
      @table = {}
      @modules = {}
    end

    # PIF's own settings (plain attributes): the getter learns about locks
    def self.wrap(key)
      return true if @wrapped[key]
      return false unless PokemonSystem.method_defined?(key) && PokemonSystem.method_defined?(:"#{key}=")
      plain = :"kif_unlocked_#{key}"
      PokemonSystem.send(:alias_method, plain, key) unless PokemonSystem.method_defined?(plain)
      PokemonSystem.send(:define_method, key) do
        t = KIF::Options.tracing
        t << key if t
        lock = KIF::Locks.table[key]
        lock ? lock[0] : __send__(plain)
      end
      @wrapped[key] = true
      return true
    end
  end
end

# No ensure_class: SaveData.valid? checks every registered value, and a save
# without this key (vanilla PIF, PIF 6.4.5, KIF) would be rejected as
# "corrupt". import_save_scope accepts nil / non-Hash values instead.
SaveData.register(:kif_save_settings) do
  save_value { KIF::Options.export_save_scope }
  load_value { |value| KIF::Options.import_save_scope(value) }
  new_game_value { {} }
end

# Settings that belong to the framework itself
KIF::Options.define(:raiserb, 0, :global)  # index into SLIDER_STEPS
KIF::Options.define(:debug, 0, :global)    # KIF "DEBUG": force $DEBUG on

#===============================================================================
# Entry point: the "KIF Settings" button in PIF's Options list (Options
# itself opens the settings screen; mods read this list)
#===============================================================================
class PokemonGameOption_Scene < PokemonOption_Scene
  alias kif_pbGetOptions pbGetOptions unless method_defined?(:kif_pbGetOptions)

  def pbGetOptions(inloadscreen = false)
    options = kif_pbGetOptions(inloadscreen)
    # One button since 2026-10-16: the new KIF Settings screen also holds
    # Modules, Mods and Presets (016_KIF_SettingsScreen.rb)
    options << ButtonOption.new(_INTL("KIF Settings"),
                                proc { pbFadeOutIn { KifSettingsScreen.new.main } },
                                _INTL("KIF's settings, modules, mods and presets"))
    KIF::ModCompat.add_root_mod_options(self, options, inloadscreen) if defined?(KIF::ModCompat)
    return options
  end

end


#===============================================================================
# KIF "DEBUG" option: "Force debug to be activated" – turns on PIF's real
# debug mode ($DEBUG), so every debug entry (pause menu, Pokémon/PC
# context menus, F9) appears. Turning it off restores $DEBUG only if KIF
# was the one that turned it on.
#===============================================================================
module KIF
  @debug_forced = false

  def self.sync_debug
    want = $PokemonSystem && $PokemonSystem.debug == 1
    if want && !$DEBUG
      $DEBUG = true
      @debug_forced = true
    elsif !want && @debug_forced
      $DEBUG = false
      @debug_forced = false
    end
  end
end

class Scene_Map
  alias kif_debug_update update unless method_defined?(:kif_debug_update)

  def update
    KIF.sync_debug
    kif_debug_update
  end
end
