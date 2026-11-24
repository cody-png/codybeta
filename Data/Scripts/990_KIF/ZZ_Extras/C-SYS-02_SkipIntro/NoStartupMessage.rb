#===============================================================================
# C-SYS-02 – No PIF start-up announcement (2026-10-11)
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
#   above PIF's own version: that would send KIF players to PIF's installer.
#   KIF's updater (C-SYS-06, no module) answers that check instead, so it
#   stays hidden even with this module Off.
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
      KIF.verbose("Start-up message skipped: #{dropped.uniq.join(' | ')}") if !dropped.empty? && defined?(KIF.verbose)
      return dropped
    rescue => e
      KIF.log("Start-up message check failed (#{e.class}: #{e.message})") if defined?(KIF.log)
      return []
    end
  end
end

KIF::SkipIntro.silence_startup_messages
