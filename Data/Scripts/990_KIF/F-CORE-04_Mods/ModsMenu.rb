#===============================================================================
# F-CORE-04 – Mods menu (2026-10-14)
# Options > KIF Settings > Mods: every installed mod with On/Off (applies at
# the next start) and, for mods that added settings while loading, a page
# with just their settings. "Settings by category" keeps the old Mod Settings
# page. The list comes from KIF::Mods.entries (KIF's own mods and Mod
# Manager's), so another mod manager can show its mods here too.
#===============================================================================
class KifModsScene < KifOptionsBaseScene
  def kif_title; "Mods"; end

  def getDefaultDescription
    return _INTL("Your mods. Switching one On or Off applies the next time the game starts.")
  end

  def self.describe(e)
    bits = []
    bits << _INTL("Failed to load (see Logs/KIF_errorlog.txt).") if e.error
    who = []
    who << "v#{e.version}" if e.version && !e.version.empty?
    who << _INTL("by {1}", e.author) if e.author && !e.author.empty? && e.author != "Unknown"
    bits << who.join(" ") unless who.empty?
    bits << e.description.to_s.gsub(/\s+/, " ")[0, 90] if e.description && !e.description.empty?
    bits << _INTL("Mod Manager mod.") if e.kind == :mod_manager
    bits << _INTL("Mods folder: {1}", e.id) if bits.empty?
    return bits.join(" ")
  end

  def pbGetOptions(inloadscreen = false)
    options = []
    list = KIF::Mods.entries
    list.each do |e|
      options << EnumOption.new(e.name.to_s[0, 28], [_INTL("On"), _INTL("Off")],
                                proc { e.enabled? ? 0 : 1 },
                                proc { |v| e.source.set_enabled(e, v == 0) if e.enabled? != (v == 0) },
                                KifModsScene.describe(e))
    end
    list.each do |e|
      next if e.settings.empty?
      options << ButtonOption.new(_INTL("{1} settings", e.name.to_s[0, 22]),
                                  proc { @kif_mod = e; kif_open_mod },
                                  _INTL("Settings added by {1}", e.name))
    end
    if defined?(KIF::ModSettings) && KIF::ModSettings.active? && !KIF::ModSettings.registry.empty?
      options << ButtonOption.new(_INTL("Settings by category"),
                                  proc { @kif_mod = :categories; kif_open_mod },
                                  _INTL("Every mod's settings, sorted by category"))
    end
    return options
  end

  def kif_open_mod
    m = @kif_mod
    @kif_mod = nil
    return unless m
    pbFadeOutIn {
      scene = (m == :categories) ? KifModSettingsScene.new : KifModPageScene.new(m)
      PokemonOptionScreen.new(scene).pbStartScreen
    }
  end
end

class KifModPageScene < KifOptionsBaseScene
  def initialize(entry)
    super()
    @kif_entry = entry
  end

  def kif_title; @kif_entry.name.to_s; end
  def getDefaultDescription; return _INTL("Settings added by {1}", @kif_entry.name); end

  def pbGetOptions(inloadscreen = false)
    return @kif_entry.settings.map do |e|
      begin
        KIF::ModSettings.option_for(e)
      rescue StandardError => ex
        KIF.log("Mod setting #{e[:key]} has no row: #{ex.class}: #{ex.message}") if KIF.respond_to?(:log)
        nil
      end
    end.compact
  end
end
