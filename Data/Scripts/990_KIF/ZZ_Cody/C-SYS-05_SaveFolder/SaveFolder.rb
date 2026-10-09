#===============================================================================
# C-SYS-05 – KIF's own save folder (Cody, 2026-10-09)
#   KIF Beta keeps its saves in %APPDATA%\KIF (Game.ini Title = KIF), apart
#   from old KIF's %APPDATA%\kurayinfinitefusion. On the very first launch,
#   if the old folder has saves and the new one has none, the game offers to
#   copy them over (copied, so old KIF keeps working with its own; the save
#   backups folder, which can be big, stays where it is). Asked only
#   once; the answer is remembered by a marker file in the new folder.
#===============================================================================
module KIF
  module SaveFolder
    OLD_NAME = "kurayinfinitefusion"
    MARKER   = "KIF_first_launch.krs"
    # saves, their backups, KIF options/markers, controller bindings
    PATTERNS = [/\.rxdata\z/i, /\.rxdata\.bak\z/i, /\.kro\z/i, /\.krs\z/i, /\Akeybindings\.mkxp1\z/i]

    module_function

    def new_dir
      return File.dirname(SaveData::FILE_PATH)
    end

    def old_dir(base = new_dir)
      return File.join(File.dirname(File.expand_path(base)), OLD_NAME)
    end

    def saves_in(dir)
      return [] unless Dir.exist?(dir)
      return Dir.children(dir).select { |f| f =~ /\.rxdata\z/i }
    end

    # Should the first-launch question be asked?
    def offer?(new_d = new_dir, old_d = old_dir(new_d))
      return false if File.exist?(File.join(new_d, MARKER))
      return false if File.expand_path(new_d) == File.expand_path(old_d)
      return !saves_in(old_d).empty? && saves_in(new_d).empty?
    end

    # Copy the old folder's saves etc. (never over a file already there)
    def import(new_d = new_dir, old_d = old_dir(new_d))
      n = 0
      Dir.children(old_d).each do |f|
        src = File.join(old_d, f)
        next unless File.file?(src) && PATTERNS.any? { |p| f =~ p }
        dst = File.join(new_d, f)
        next if File.exist?(dst)
        File.binwrite(dst, File.binread(src))
        n += 1
      end
      return n
    end

    def mark_done(new_d = new_dir)
      File.binwrite(File.join(new_d, MARKER), "first launch done #{Time.now}\n")
    rescue
      nil
    end

    def first_launch
      return if File.exist?(File.join(new_dir, MARKER))
      if offer?
        count = saves_in(old_dir).length
        if pbConfirmMessage(_INTL("Saves from the old KIF were found ({1} files). Copy them into KIF's new save folder?", count))
          n = import
          pbMessage(_INTL("Copied {1} files. Your old KIF keeps its own copies, and the old save backups stay in the old folder.", n))
          KIF.log("Save folder: copied #{n} files from #{old_dir}")
        else
          pbMessage(_INTL("Okay. You can still copy them yourself later: the old saves are in {1}.", old_dir))
          KIF.log("Save folder: old saves not copied (player said no)")
        end
      end
      mark_done
    rescue => e
      KIF.log("Save folder first launch failed (#{e.class}: #{e.message})")
    end

    module LoadScreen
      def pbStartLoadScreen(*args)
        KIF::SaveFolder.first_launch
        return super
      end
    end
  end
end

PokemonLoadScreen.prepend(KIF::SaveFolder::LoadScreen) if defined?(PokemonLoadScreen)
