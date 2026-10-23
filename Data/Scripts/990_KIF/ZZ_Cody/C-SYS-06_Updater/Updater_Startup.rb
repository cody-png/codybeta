#===============================================================================
# C-SYS-06 – Start-up downloads: fewer, timed (2026-10-22)
#   A player's game sat for ages at the load screen; their antivirus (Avast)
#   scans every HTTPS download in full before the game gets it. PIF fetches,
#   on every start and before the menu shows:
#     * dex.json, 22.9 MB (custom Pokédex entries; only read when an entry
#       page shows one): now only when the copy is a week old or missing;
#     * DownloadedSettings.rb, 3 KB: now at most once a day.
#   KIF's own steps (version check, mod update check) are timed in KIF_log;
#   the mod check (GitHub's file lists, over 1 MB) is skipped when the
#   version check couldn't reach the server or was slow, and runs at most
#   every MOD_CHECK_HOURS (Browse and Updates in Options still check now).
#===============================================================================
module KIF
  module Startup
    DEX_MAX_AGE      = 7 * 24 * 3600
    SETTINGS_MAX_AGE = 24 * 3600
    MOD_CHECK_HOURS  = 12
    SLOW_SECONDS     = 4.0   # a version check slower than this: the mod check waits for next time

    # Runs the block and logs how long it took: always when it was slow,
    # otherwise only with verbose logging
    def self.timed(label)
      t = Time.now
      ret = yield
      secs = Time.now - t
      line = format("Start-up: %s in %.1fs", label, secs)
      secs >= 1.0 ? KIF.log(line) : KIF.verbose(line)
      return ret, secs
    end

    # A file that's newer than max_age seconds
    def self.fresh?(path, max_age)
      return File.file?(path) && File.size(path) > 0 && (Time.now - File.mtime(path)) < max_age
    rescue StandardError
      return false
    end

    def self.mod_check_due?
      last = KIF::Updater.stored_choices["modcheck"].to_i
      return Time.now.to_i - last >= MOD_CHECK_HOURS * 3600
    end

    def self.mod_checked!
      KIF::Updater.store_choice("modcheck", Time.now.to_i)
    end
  end
end

alias kif_su_updateCustomDexFile updateCustomDexFile unless defined?(kif_su_updateCustomDexFile)

def updateCustomDexFile
  if KIF::Startup.fresh?(Settings::CUSTOM_DEX_ENTRIES_PATH, KIF::Startup::DEX_MAX_AGE)
    KIF.verbose("Start-up: dex.json kept (under a week old)")
    return
  end
  KIF::Startup.timed("dex.json download") { kif_su_updateCustomDexFile }
end

alias kif_su_updateHttpSettingsFile updateHttpSettingsFile unless defined?(kif_su_updateHttpSettingsFile)

def updateHttpSettingsFile
  if KIF::Startup.fresh?(Settings::HTTP_CONFIGS_FILE_PATH, KIF::Startup::SETTINGS_MAX_AGE)
    KIF.verbose("Start-up: PIF settings file kept (under a day old)")
    return
  end
  KIF::Startup.timed("PIF settings file download") { kif_su_updateHttpSettingsFile }
end

# The load screen's version check (PIF's spot, defined in Updater.rb):
# KIF's check, then the mod check when it's due and the network answered well
alias kif_su_find_newer_available_version find_newer_available_version unless defined?(kif_su_find_newer_available_version)

def find_newer_available_version
  KIF::Updater.after_update
  updating, secs = KIF::Startup.timed("KIF version check") { KIF::Updater.check(false) }
  return nil if updating == true || !defined?(KIF::ModCatalogUI)
  if KIF::Updater.unreachable || secs > KIF::Startup::SLOW_SECONDS
    KIF.log(format("Start-up: mod update check skipped (version check %s, %.1fs)", KIF::Updater.unreachable ? "got no answer" : "was slow", secs))
  elsif KIF::Startup.mod_check_due?
    KIF::Startup.timed("mod update check") { KIF::ModCatalogUI.startup_check }
    KIF::Startup.mod_checked!
  else
    KIF.verbose("Start-up: mod update check not due (every #{KIF::Startup::MOD_CHECK_HOURS} h)")
  end
  return nil
end
