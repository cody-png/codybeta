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
        KIF.log("PokemonSystem##{key} already exists in base PIF; KIF default not applied")
      end
      PokemonSystem.class_eval do
        define_method(:"kif_defined_#{key}") { true }
        define_method(key) do
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
      save_keys.each { |k| hash[k] = Marshal.load(Marshal.dump($PokemonSystem.send(k))) }
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
# Scenes
#===============================================================================
class KifOptionsBaseScene < PokemonOption_Scene
  def initialize
    super
    @changedColor = false
  end

  def kif_title; "KIF Settings"; end
  def kif_colors; [[35, 130, 200], [20, 75, 115]]; end

  def getDefaultDescription
    return _INTL("Customize modded features")
  end

  def pbStartScene(inloadscreen = false)
    super
    base, shadow = kif_colors
    @sprites["option"].nameBaseColor = Color.new(*base)
    @sprites["option"].nameShadowColor = Color.new(*shadow)
    @changedColor = true
    for i in 0...@PokemonOptions.length
      @sprites["option"][i] = (@PokemonOptions[i].get || 0)
    end
    @sprites["textbox"].text = getDefaultDescription
    pbFadeInAndShow(@sprites) { pbUpdate }
  end

  def pbFadeInAndShow(sprites, visiblesprites = nil)
    return if !@changedColor
    super
  end

  # Play test 2026-10-05: the title used to be drawn as a second window over
  # PIF's "Options" title (it showed through), and the list ran 32px under
  # the description box (last row cut off). Same layout as PIF otherwise.
  def initUIElements
    super
    @sprites["title"].dispose if @sprites["title"]
    @sprites["title"] = Window_UnformattedTextPokemon.newWithSize(
      _INTL(kif_title), 0, 0, Graphics.width, 64, @viewport)
  end

  # The randomizer's option window (004_RandScreen.rb) sizes the name column
  # to the page's longest name and shows "< value >" when a row's values
  # don't fit, so long names ("PIF's Improved Shinies", "Self-Fusion Stat
  # Boost") no longer run into their values (seen 2026-10-09).
  def initOptionsWindow
    height = Graphics.height - @sprites["title"].height - @sprites["textbox"].height
    unless defined?(KifRandOptionWindow)
      win = super
      win.height = height
      return win
    end
    win = KifRandOptionWindow.new(@PokemonOptions, 0, @sprites["title"].height, Graphics.width, height)
    win.viewport = @viewport
    win.visible = true
    return win
  end
end

# A section header row ("### GLOBAL ###"); does nothing when pressed.
def kif_header_option(text)
  return ButtonOption.new(_INTL(text), proc {}, "")
end

class KifOptionsMenuScene < KifOptionsBaseScene
  def initialize(menu)
    super()
    @menu = menu
  end

  def kif_title; KIF::Options.menu_info(@menu)[0]; end
  def kif_colors; KIF::Options.menu_info(@menu)[2, 2]; end

  def pbGetOptions(inloadscreen = false)
    options = []
    global = KIF::Options.entries(@menu).select { |s, _| s == :global }
    persave = KIF::Options.entries(@menu).select { |s, _| s == :save }
    if !global.empty?
      options << kif_header_option("### GLOBAL ###")
      global.each { |_, b| opt = b.call; options << opt if opt }
    end
    if !persave.empty?
      if KIF.in_game?
        options << kif_header_option("### PER-SAVE FILE ###")
        persave.each { |_, b| opt = b.call; options << opt if opt }
      elsif global.empty?
        options << kif_header_option("### LOAD A SAVE TO EDIT ###")
      end
    end
    return options
  end
end

class KifOptionsScene < KifOptionsBaseScene
  # Menus listed on this screen (Cody Settings lists its own)
  def kif_menu_ids; KIF::Options::MENUS.keys; end

  def kif_menu_buttons
    options = []
    kif_menu_ids.each do |menu|
      next unless KIF::Options.menu_used?(menu)
      options << ButtonOption.new(_INTL(KIF::Options.menu_label(menu)),
                                  proc { @kif_open = menu; kif_open_menu },
                                  _INTL(KIF::Options.menu_info(menu)[1]))
    end
    return options
  end

  def pbGetOptions(inloadscreen = false)
    options = kif_menu_buttons
    options << EnumOption.new(_INTL("Increment Slider by"),
                              KIF::Options::SLIDER_STEPS.map { |s| s.to_s },
                              proc { $PokemonSystem.raiserb },
                              proc { |value| $PokemonSystem.raiserb = value },
                              _INTL("For large sliders (e.g. shiny odds), changes the increment rate of those sliders."))
    options << EnumOption.new(_INTL("DEBUG"), [_INTL("Off"), _INTL("On")],
                              proc { $PokemonSystem.debug },
                              proc { |value|
                                $PokemonSystem.debug = value
                                KIF.sync_debug
                              },
                              [_INTL("Doesn't force debug to be activated"),
                               _INTL("Force debug to be activated")])
    return options
  end

  def kif_open_menu
    menu = @kif_open
    return if !menu
    pbFadeOutIn {
      scene = KifOptionsMenuScene.new(menu)
      screen = PokemonOptionScreen.new(scene)
      screen.pbStartScreen
    }
    @kif_open = nil
  end
end

#===============================================================================
# Entry point: "Modules" button at the bottom of PIF's main Options menu
#===============================================================================
class PokemonGameOption_Scene < PokemonOption_Scene
  alias kif_pbGetOptions pbGetOptions unless method_defined?(:kif_pbGetOptions)

  def pbGetOptions(inloadscreen = false)
    options = kif_pbGetOptions(inloadscreen)
    # Options > Modules (012_KIF_ModulesMenu.rb) holds KIF's and Cody's
    # settings, sorted by module (was "KIF Settings" + "Cody Settings")
    options << ButtonOption.new(_INTL("Modules"),
                                proc { kif_open_settings },
                                _INTL("Turn KIF's features on or off and change their settings"))
    KIF::ModCompat.add_root_mod_options(self, options, inloadscreen) if defined?(KIF::ModCompat)
    return options
  end

  def kif_open_settings
    pbFadeOutIn {
      scene = KifModulesScene.new
      screen = PokemonOptionScreen.new(scene)
      screen.pbStartScreen
    }
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
