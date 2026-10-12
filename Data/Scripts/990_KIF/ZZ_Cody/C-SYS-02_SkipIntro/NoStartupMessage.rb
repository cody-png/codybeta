#===============================================================================
# C-SYS-02 – No PIF start-up announcement (Cody, 2026-10-11)
#   PIF shows Settings::STARTUP_MESSAGES_KANTO / _HOENN on the load screen
#   (052_InfiniteFusion/System/MultiSaves.rb pbStartLoadScreen). The texts
#   come from Data/Scripts/DownloadedSettings.rb, which the game re-downloads
#   from PIF's server while "Download data" is on; since PIF 2 it says
#   "Pokémon Infinite Fusion 2 is now available! Download it from the game's
#   Discord!" on every launch. That is PIF's news, not KIF's: the texts are
#   emptied here (this folder loads after DownloadedSettings.rb; a downloaded
#   file only takes effect at the next boot, where this runs again). The
#   file itself is left alone. Nothing else in it is changed.
#   The same screen also shows "Version X is now available! Please use the
#   game's installer..." when LATEST_GAME_RELEASE (same downloaded file) is
#   above PIF's own version: that would send KIF players to PIF's installer,
#   so find_newer_available_version answers nil (logged once when it would
#   have fired). KIF gets its own updater later (Cody, 2026-10-11).
#===============================================================================
module KIF
  module SkipIntro
    STARTUP_MESSAGE_CONSTS = [:STARTUP_MESSAGES, :STARTUP_MESSAGES_KANTO, :STARTUP_MESSAGES_HOENN]

    def self.silence_startup_messages
      dropped = []
      STARTUP_MESSAGE_CONSTS.each do |c|
        next unless Settings.const_defined?(c, false)
        text = Settings.const_get(c)
        next if text.to_s.empty?
        dropped << text.to_s
        Settings.send(:remove_const, c)
        Settings.const_set(c, "")
      end
      KIF.log("Start-up message skipped: #{dropped.uniq.join(' | ')}") if !dropped.empty? && defined?(KIF.log)
      return dropped
    rescue => e
      KIF.log("Start-up message check failed (#{e.class}: #{e.message})") if defined?(KIF.log)
      return []
    end
  end
end

KIF::SkipIntro.silence_startup_messages

alias kif_pif_find_newer_available_version find_newer_available_version unless defined?(kif_pif_find_newer_available_version)
def find_newer_available_version
  newer = kif_pif_find_newer_available_version
  if newer
    KIF.log("PIF update prompt skipped (PIF #{newer} is out; this is KIF #{KIF::PORT_VERSION} on PIF #{Settings::GAME_VERSION_NUMBER})") if defined?(KIF.log)
    return nil
  end
  return nil
rescue => e
  KIF.log("PIF update check failed (#{e.class}: #{e.message})") if defined?(KIF.log)
  return nil
end
