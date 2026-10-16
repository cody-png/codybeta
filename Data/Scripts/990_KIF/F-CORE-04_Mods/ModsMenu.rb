#===============================================================================
# F-CORE-04 – a mod's own settings page (2026-10-14)
# Options > KIF Settings > Mods lists every installed mod with On/Off (applies
# at the next start) and, for mods that added settings while loading, a page
# with just their settings (016_KIF_SettingsScreen.rb draws both). The list
# comes from KIF::Mods.entries (KIF's own mods and Mod Manager's), so another
# mod manager can show its mods there too.
#===============================================================================
module KIF
  module Mods
    # the setting rows a mod registered while it loaded
    def self.page_options(entry)
      return [] unless defined?(KIF::ModSettings)
      return KIF::ModSettings.options_for(entry.settings)
    end
  end
end
