#===============================================================================
# Options > Modules (Cody, 2026-10-10)
# Replaces the "KIF Settings" and "Cody Settings" buttons: one screen that
# sets each module Off / On / Hidden (011_KIF_Modules.rb) and opens the
# settings of the modules that are On. Settings come from every KIF and Cody
# menu, sorted by the module their code belongs to. "Mod Settings" (other
# mods' settings, when KIF provides them) is here too while that module is On.
#===============================================================================
class KifModuleSettingsScene < KifOptionsBaseScene
  # id: a module id, or :general for settings of always-on features
  def initialize(id)
    super()
    @module_id = id
  end

  def kif_title
    return "General settings" if @module_id == :general
    return KIF::Modules::MODULES[@module_id][0] + " settings"
  end

  def kif_colors; [[35, 130, 200], [20, 75, 115]]; end

  def getDefaultDescription
    return _INTL("Settings that are always available") if @module_id == :general
    return _INTL(KIF::Modules::MODULES[@module_id][1])
  end

  def self.entries_for(id)
    want = (id == :general) ? nil : id
    list = []
    KIF::Options.all_menu_ids.each do |menu|
      KIF::Options.entries(menu).each do |scope, builder|
        list << [scope, builder] if KIF::Modules.for_proc(builder) == want
      end
    end
    return list
  end

  def pbGetOptions(inloadscreen = false)
    options = []
    entries = KifModuleSettingsScene.entries_for(@module_id)
    global = entries.select { |s, _| s == :global }
    persave = entries.select { |s, _| s == :save }
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

class KifModulesScene < KifOptionsBaseScene
  def kif_title; "Modules"; end

  def getDefaultDescription
    return _INTL("Off: plays like PIF. Hidden: works, settings hidden. Reopen to see settings.")
  end

  def pbGetOptions(inloadscreen = false)
    options = []
    options << kif_header_option("### MODULES ###")
    KIF::Modules::MODULES.each do |id, (name, desc, _f)|
      options << EnumOption.new(_INTL(name),
                                KIF::Modules::STATE_NAMES.map { |s| _INTL(s) },
                                proc { KIF::Modules.state(id) },
                                proc { |value| KIF::Modules.set_state(id, value) },
                                _INTL(desc))
    end
    buttons = []
    KIF::Modules::MODULES.each do |id, (name, _d, _f)|
      next unless KIF::Modules.visible?(id)
      if id == :mod_settings
        if defined?(KIF::ModSettings) && KIF::ModSettings.active? && !KIF::ModSettings.registry.empty?
          buttons << ButtonOption.new(_INTL("Mod Settings"),
                                      proc { @kif_open = :mod_settings; kif_open_page },
                                      _INTL("Settings added by your mods"))
        end
        next
      end
      next if KifModuleSettingsScene.entries_for(id).empty?
      buttons << ButtonOption.new(_INTL("{1} settings", _INTL(name)),
                                  proc { @kif_open = id; kif_open_page },
                                  _INTL(KIF::Modules::MODULES[id][1]))
    end
    unless KifModuleSettingsScene.entries_for(:general).empty?
      buttons << ButtonOption.new(_INTL("General settings"),
                                  proc { @kif_open = :general; kif_open_page },
                                  _INTL("Settings that are always available"))
    end
    unless buttons.empty?
      options << kif_header_option("### SETTINGS ###")
      options.concat(buttons)
    end
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

  def kif_open_page
    page = @kif_open
    @kif_open = nil
    return unless page
    pbFadeOutIn {
      scene = (page == :mod_settings) ? KifModSettingsScene.new : KifModuleSettingsScene.new(page)
      PokemonOptionScreen.new(scene).pbStartScreen
    }
  end
end

module KIF
  module Options
    # Every menu settings can be registered in (KIF's and Cody's)
    def self.all_menu_ids
      return MENUS.keys + @extra_menus.keys
    end
  end
end
