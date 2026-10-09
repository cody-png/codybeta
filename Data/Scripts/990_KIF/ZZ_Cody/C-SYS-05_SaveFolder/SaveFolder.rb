#===============================================================================
# C-SYS-05 – KIF's own save folder (Cody, 2026-10-09)
#   KIF Beta keeps its saves in %APPDATA%\KIF (Game.ini Title = KIF), apart
#   from old KIF's %APPDATA%\kurayinfinitefusion. On the very first launch,
#   if the old folder has saves and the new one has none, the game offers to
#   copy them over (copied, so old KIF keeps working with its own; the save
#   backups folder, which can be big, stays where it is). Asked only
#   once; the answer is remembered by a marker file in the new folder.
#   After that, "Import Old Saves" on the load menu does the same any time
#   old KIF has a save KIF doesn't. A save whose slot is already taken here
#   goes into the first free File slot instead, so nothing is overwritten.
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

    # Copy the old folder's saves etc. (never over a file already there).
    # With rehome, a save whose slot is taken goes into a free File slot.
    # Returns [files copied, saves moved to another slot, saves left behind]
    def import_report(new_d = new_dir, old_d = old_dir(new_d), rehome: false)
      n = 0
      moved = []
      left = []
      Dir.children(old_d).sort.each do |f|
        src = File.join(old_d, f)
        next unless File.file?(src) && PATTERNS.any? { |p| f =~ p }
        dst = File.join(new_d, f)
        if File.exist?(dst)
          next unless rehome && f =~ /\.rxdata\z/i
          next if already_here?(src, new_d)
          slot = free_slot(new_d)
          unless slot
            left << File.basename(f, ".*")
            next
          end
          dst = File.join(new_d, "#{slot}.rxdata")
          moved << "#{File.basename(f, '.*')} -> #{slot}"
        end
        File.binwrite(dst, File.binread(src))
        n += 1
      end
      return [n, moved, left]
    end

    def import(new_d = new_dir, old_d = old_dir(new_d))
      return import_report(new_d, old_d)[0]
    end

    def free_slot(new_d = new_dir)
      slots = defined?(SaveData::MANUAL_SLOTS) ? SaveData::MANUAL_SLOTS : []
      return slots.find { |sl| !File.exist?(File.join(new_d, "#{sl}.rxdata")) }
    end

    # Is a save with exactly this content already in the folder (any slot)?
    def already_here?(src, new_d)
      size = File.size(src)
      data = nil
      return saves_in(new_d).any? do |f|
        dst = File.join(new_d, f)
        next false unless File.size(dst) == size
        data ||= File.binread(src)
        File.binread(dst) == data
      end
    end

    # Old saves that aren't here yet, in any slot
    def importable(new_d = new_dir, old_d = old_dir(new_d))
      return saves_in(old_d).reject { |f| already_here?(File.join(old_d, f), new_d) }
    rescue
      return []
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

    #---------------------------------------------------------------------------
    # "Import Old Saves" on the load menu. It rides on 6.8.2's own menu link
    # list (Settings::MAIN_MENU_LINKS), which the menu builds its entries
    # from; choosing a link calls openUrlInBrowser, which hands this one
    # back here instead of opening a browser.
    #---------------------------------------------------------------------------
    MENU_LABEL = "Import Old Saves"
    MENU_URL   = "kif:import-old-saves"

    class << self
      attr_accessor :screen, :reload
    end

    def links
      l = defined?(Settings::MAIN_MENU_LINKS) ? Settings::MAIN_MENU_LINKS : nil
      return (l.is_a?(Hash) && !l.frozen?) ? l : nil
    end

    def update_menu
      l = links
      return unless l
      if File.expand_path(new_dir) != File.expand_path(old_dir) && !importable.empty?
        l[MENU_LABEL] = MENU_URL
      else
        l.delete(MENU_LABEL)
      end
    rescue
      nil
    end

    def menu_import
      list = importable
      if list.empty?
        pbMessage(_INTL("There are no saves in the old KIF folder that aren't here already."))
        return update_menu
      end
      return unless pbConfirmMessage(_INTL("Copy {1} save(s) from the old KIF into KIF? Nothing here will be overwritten.", list.length))
      n, moved, left = import_report(rehome: true)
      KIF.log("Save folder: menu import copied #{n} files from #{old_dir}" +
              (moved.empty? ? "" : ", moved #{moved.join(', ')}") +
              (left.empty? ? "" : ", no free slot for #{left.join(', ')}"))
      msg = _INTL("Copied {1} files. Your old KIF keeps its own copies.", n)
      msg += " " + _INTL("Some saves had a slot that was already taken here, so they went into another slot: {1}.", moved.join(", ")) unless moved.empty?
      msg += " " + _INTL("No free slot was left for: {1}.", left.join(", ")) unless left.empty?
      pbMessage(msg)
      update_menu
      # show the new saves: the menu reloads its slots (see Scene below)
      scr = self.screen
      if scr && n > 0
        newest = (SaveData.get_newest_save_slot rescue nil)
        if newest
          all = SaveData::AUTO_SLOTS + SaveData::MANUAL_SLOTS
          scr.instance_variable_set(:@selected_file, SaveData.get_next_slot(all, newest))
          self.reload = true
        end
      end
    rescue => e
      KIF.log("Save folder menu import failed (#{e.class}: #{e.message})")
    end

    module LoadScreen
      def pbStartLoadScreen(*args)
        KIF::SaveFolder.first_launch
        KIF::SaveFolder.update_menu
        KIF::SaveFolder.screen = self
        KIF::SaveFolder.reload = false
        return super
      ensure
        KIF::SaveFolder.screen = nil
      end
    end

    # After an import, the menu acts as if Left was pressed on the save
    # panel, which makes it reload the slots and land on the newest save.
    module Scene
      def pbChoose(*args)
        if KIF::SaveFolder.reload
          KIF::SaveFolder.reload = false
          return -3
        end
        return super
      end
    end
  end
end

PokemonLoadScreen.prepend(KIF::SaveFolder::LoadScreen) if defined?(PokemonLoadScreen)
PokemonLoad_Scene.prepend(KIF::SaveFolder::Scene) if defined?(PokemonLoad_Scene)

alias kif_sf_openUrlInBrowser openUrlInBrowser unless defined?(kif_sf_openUrlInBrowser)
def openUrlInBrowser(url = "")
  return KIF::SaveFolder.menu_import if url == KIF::SaveFolder::MENU_URL
  return kif_sf_openUrlInBrowser(url)
end
