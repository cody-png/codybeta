#===============================================================================
# Where KIF's own folders are (2026-10-10)
#   Logs: every KIF log goes to a "Logs" folder next to the game's .exe
#   (session log, error log, frame log, Entrances returns, AI compare), so a
#   bug report needs one folder. Saves stay in %APPDATA%\KIF.
#   "root" is the game folder; if the game is started inside a folder named
#   "Game Files" (a tidier release layout being tried), root is the folder
#   above it, so Logs and Import Sprites stay next to the .exe.
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

    # <root>/Logs, made when needed; the save folder if it can't be written
    def self.logs
      dir = File.join(root, "Logs")
      return @logs if @logs && @logs_for == dir
      @logs_for = dir
      begin
        Dir.mkdir(dir) unless Dir.exist?(dir)
        probe = File.join(dir, ".kif_write_test")
        File.open(probe, "wb") { |f| f.write("") }
        File.delete(probe)
        @logs = dir
      rescue StandardError
        @logs = (KIF.save_dir rescue ".")
      end
      return @logs
    end

    def self.log(name)
      return File.join(logs, name)
    end

    def self.import_sprites
      return File.join(root, "Import Sprites")
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
