#===============================================================================
# Where KIF's own folders are (Cody, 2026-10-10)
#   Logs: every KIF log goes to a "Logs" folder next to the game's .exe
#   (session log, error log, frame log, Entrances returns, AI compare), so a
#   tester sends one folder. Saves stay in %APPDATA%\KIF.
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

    def self.packed?
      return root != (Dir.pwd rescue root)
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
end
