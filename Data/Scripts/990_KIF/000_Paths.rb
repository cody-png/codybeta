#===============================================================================
# Where KIF's own folders are (2026-10-10)
#   Logs: every KIF log goes to a "Logs" folder next to the game's .exe
#   (session log, error log, frame log, Entrances returns, AI compare), so a
#   bug report needs one folder. Saves stay in %APPDATA%\KIF.
#   "root" is the game folder; if the game is started inside a folder named
#   "Game Files" (a tidier release layout being tried), root is the folder
#   above it, so Logs and Import Sprites stay next to the .exe.
#   A read-only game folder (JoiPlay): see game_writable? / writable below.
#===============================================================================
module KIF
  module Paths
    GAME_FILES = "Game Files"

    # (worked out each time: cheap, and follows the current folder)
    def self.root
      here = Dir.pwd
      return File.basename(here) == GAME_FILES ? File.dirname(here) : here
    rescue
      return "."
    end

    # <root>/Logs, made when needed. If it can't be written: on Android the
    # app's own folder on shared storage (Android/data/<app>/files/Logs: the
    # app can always write there and it can be read without root, so a phone
    # player can still send a log), else the save folder.
    def self.logs
      dir = File.join(root, "Logs")
      return @logs if @logs && @logs_for == dir
      @logs_for = dir
      @logs = [dir, android_logs].compact.find { |d| writable_dir?(d) } || (KIF.save_dir rescue ".")
      return @logs
    end

    def self.writable_dir?(dir)
      KIF.mkdir_p(dir) unless Dir.exist?(dir)
      probe = File.join(dir, ".kif_write_test")
      File.open(probe, "wb") { |f| f.write("") }
      File.delete(probe)
      return true
    rescue StandardError
      return false
    end

    # /storage/emulated/0/Android/data/<app>/files/Logs, from the app's private
    # save path (/data/user/0/<app>/... or /data/data/<app>/...); nil elsewhere
    def self.android_logs
      app = (KIF.save_dir rescue "").to_s[%r{\A/data/(?:user/\d+|data)/([^/]+)/}, 1]
      return nil unless app
      base = ENV["EXTERNAL_STORAGE"].to_s.empty? ? "/storage/emulated/0" : ENV["EXTERNAL_STORAGE"]
      return File.join(base, "Android", "data", app, "files", "Logs")
    end

    def self.log(name)
      return File.join(logs, name)
    end

    def self.import_sprites
      return File.join(root, "Import Sprites")
    end

    # Can KIF write into the game folder? On JoiPlay (Android) it can't, so
    # everything KIF writes there goes to the save folder instead (2026-10-23).
    # Tried once a session with a small file made and deleted; a failed try
    # is repeated once (an antivirus lock passes), and the file name is the
    # game's own (two copies of the game starting at once don't collide).
    WRITE_TEST = ".kif_write_test"

    # nil when a file could be written, else why not
    def self.write_probe
      name = "#{WRITE_TEST}_#{Process.pid}_#{(Time.now.to_f * 1000).to_i}"
      File.open(name, "wb") { |f| f.write("") }
      File.delete(name)
      return nil
    rescue StandardError => e
      (File.delete(name) rescue nil) if name
      return "#{e.class}: #{e.message}"
    end

    def self.game_writable?
      return @game_writable unless @game_writable.nil?
      why = write_probe
      if why
        sleep(0.2)
        why = write_probe
      end
      @game_writable = why.nil?
      KIF.log(@game_writable ? "Game folder can be written: KIF's caches and files stay in it" :
              "Game folder is read-only (#{why}): KIF's caches, Randomizer files and downloads go to the save folder (#{KIF.save_dir})") if KIF.respond_to?(:log)
      return @game_writable
    end

    # Where KIF writes (and reads back) one of its own folders or files:
    # the path in the game folder as before, or the same path in the save folder
    def self.writable(sub)
      return game_writable? ? sub : File.join(KIF.save_dir, sub)
    end

    # Folders players drop files into (Import Sprites, Mods): with a read-only
    # game folder, the save folder's copy is looked in as well
    def self.extra_drop_dir(name)
      return nil if game_writable?
      dir = File.join(KIF.save_dir, name)
      (KIF.mkdir_p(dir) rescue nil)   # made, so phone players find where it goes
      return dir
    end
  end

  # Running on a phone (JoiPlay / Kirin on Android): PIF's own Device:
  # Mobile option, an engine that says Android or iOS, or a Mobile.krs marker
  # file. JoiPlay fakes part of the Windows API, so Win32API being there says
  # nothing; Windows-only steps (curl, cmd, robocopy, restarting the .exe)
  # ask this first. Groundwork for mobile support (2026-10-22).
  MOBILE_MARKER = "Mobile.krs"

  def self.mobile?
    return true if $PokemonSystem && ($PokemonSystem.on_mobile rescue false)
    if @mobile_engine.nil?
      plat = (defined?(System) && System.respond_to?(:platform) ? System.platform.to_s : "") rescue ""
      # an engine that doesn't say: Android's own environment and storage paths
      why = if plat =~ /android|ios/i then "engine platform #{plat}"
            elsif RUBY_PLATFORM =~ /android/i then "Ruby platform #{RUBY_PLATFORM}"
            elsif ENV["ANDROID_ROOT"] || ENV["ANDROID_DATA"] then "Android environment"
            elsif (Dir.pwd rescue "") =~ %r{\A/(storage|sdcard|data)/} then "Android storage path"
            elsif marker?(MOBILE_MARKER) then MOBILE_MARKER
            end
      @mobile_engine = why ? true : false
      KIF.log("Phone detected (#{why})") if why && KIF.respond_to?(:log)
    end
    return @mobile_engine
  rescue StandardError
    return false
  end
end
