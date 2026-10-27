#===============================================================================
# C-SYS-05 – KIF's own save folder (2026-10-09)
#   KIF keeps its saves in %APPDATA%\KIF (Game.ini Title = KIF), apart
#   from old KIF's %APPDATA%\kurayinfinitefusion. On the very first launch,
#   if the old folder has saves and the new one has none, the game offers to
#   copy them over (copied, so old KIF keeps working with its own; the save
#   backups folder, which can be big, stays where it is). Asked only
#   once; the answer is remembered by a marker file in the new folder.
#   After that, "Import Old Saves" on the load menu does the same any time
#   old KIF has a save KIF doesn't. A save whose slot is already taken here
#   goes into the first free File slot instead, so nothing is overwritten.
#   (2026-10-26) The question and the result count saves only, and both say
#   when the copies fill every File slot (8 old saves did; the new game then
#   found no empty slot without having been told).
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
    # Returns [saves copied, saves moved to another slot, saves left behind]
    # (settings and controls files are copied too but not counted: the
    # player was asked about saves)
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
        n += 1 if f =~ /\.rxdata\z/i
      end
      forget_check(new_d)
      return [n, moved, left]
    end

    # Old KIF had 8 File slots too: copying 8 saves leaves none empty, and a
    # new game then had to save over one without having been told (test 26 Oct)
    def full?(dir)
      return defined?(SaveData::MANUAL_SLOTS) && !SaveData::MANUAL_SLOTS.empty? && free_slot(dir).nil?
    end

    def full_note(dir)
      return "" unless full?(dir)
      return " " + _INTL("All {1} save slots are in use now, so a new game has to save over one of them.", SaveData::MANUAL_SLOTS.length)
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

    # Old saves that aren't here yet, in any slot. Past the deadline the
    # rest count as not here (the import itself skips copies already here).
    def importable(new_d = new_dir, old_d = old_dir(new_d), deadline: nil)
      out = []
      saves_in(old_d).each do |f|
        if deadline && Time.now > deadline
          out << f
          next
        end
        out << f unless already_here?(File.join(old_d, f), new_d)
      end
      return out
    rescue
      return []
    end

    # The load menu's check, remembered until the old folder changes: on a
    # player's PC it took 158 s on every start (1.2.8 log, 27 Oct)
    CHECK_FILE = "KIF_import_check.krs"

    def old_fingerprint(old_d)
      return saves_in(old_d).sort.map do |f|
        p = File.join(old_d, f)
        "#{f}|#{File.size(p)}|#{File.mtime(p).to_i}"
      end.join("\n")
    end

    def import_hint?(new_d = new_dir, old_d = old_dir(new_d))
      return false unless Dir.exist?(old_d)
      fp = old_fingerprint(old_d)
      return false if fp.empty?
      cache = File.join(new_d, CHECK_FILE)
      saved = File.exist?(cache) ? File.binread(cache) : ""
      return saved.start_with?("1") if saved.sub(/\A[01]\n/, "") == fp
      t = Time.now
      res = !importable(new_d, old_d, deadline: t + 3).empty?
      secs = Time.now - t
      KIF.log(format("Save folder: old save check took %.1f s (%d old saves)", secs, saves_in(old_d).length)) if secs > 1
      File.binwrite(cache, (res ? "1\n" : "0\n") + fp) rescue nil
      return res
    end

    def forget_check(new_d = new_dir)
      cache = File.join(new_d, CHECK_FILE)
      File.delete(cache) if File.exist?(cache)
    rescue
      nil
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
        q = _INTL("Saves from the old KIF were found ({1} saves). Copy them into KIF's new save folder?", count)
        # the new folder is empty here: after the copy it has the old one's slots
        q += " " + _INTL("They fill all {1} save slots, so a new game would have to save over one.", SaveData::MANUAL_SLOTS.length) if full?(old_dir)
        if pbConfirmMessage(q)
          n = import
          pbMessage(_INTL("Copied {1} saves. Your old KIF keeps its own copies, and the old save backups stay in the old folder.", n) + full_note(new_dir))
          KIF.log("Save folder: copied #{n} saves from #{old_dir}")
          show_copied_saves if n > 0
        else
          pbMessage(_INTL("Okay. You can still copy them yourself later: the old saves are in {1}.", old_dir))
          KIF.log("Save folder: old saves not copied (player said no)")
        end
      end
      mark_done
    rescue => e
      KIF.log("Save folder first launch failed (#{e.class}: #{e.message})")
    end

    # The load menu was built before the copy (no Continue entry) and the
    # global settings came from an empty save: point the menu at the newest
    # copied save and read the boot values from it.
    def show_copied_saves
      scr = self.screen
      newest = (SaveData.get_newest_save_slot rescue nil)
      return unless scr && newest
      scr.instance_variable_set(:@selected_file, newest)
      begin
        data = SaveData.read_from_file(SaveData.get_full_path(newest))
        vals = SaveData.instance_variable_get(:@values) || []
        vals.each { |v| v.mark_as_unloaded if v.load_in_bootup? }
        SaveData.load_bootup_values(data)
        KIF::Modules.migrate_old_save if defined?(KIF::Modules)
        KIF.log("Save folder: boot values read from #{newest}")
      rescue => e
        KIF.log("Save folder: boot values not reloaded (#{e.class}: #{e.message})")
      end
    rescue => e
      KIF.log("Save folder: copied saves not shown (#{e.class}: #{e.message})")
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
      if File.expand_path(new_dir) != File.expand_path(old_dir) && import_hint?
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
      KIF.log("Save folder: menu import copied #{n} saves from #{old_dir}" +
              (moved.empty? ? "" : ", moved #{moved.join(', ')}") +
              (left.empty? ? "" : ", no free slot for #{left.join(', ')}"))
      msg = _INTL("Copied {1} saves. Your old KIF keeps its own copies.", n)
      msg += " " + _INTL("Some saves had a slot that was already taken here, so they went into another slot: {1}.", moved.join(", ")) unless moved.empty?
      msg += " " + _INTL("No free slot was left for: {1}.", left.join(", ")) unless left.empty?
      msg += full_note(new_dir) if n > 0 && left.empty?
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
        KIF::SaveFolder.screen = self
        KIF::SaveFolder.first_launch
        KIF::SaveFolder.update_menu
        KIF::SaveFolder.reload = false
        return super
      ensure
        KIF::SaveFolder.screen = nil
      end

      # A save copied into another slot (an import that found its slot taken,
      # or a copy made by hand) still names its old slot, and saving or
      # autosave would write over that other save. It belongs to the file it
      # was loaded from. Only the loaded copy changes, never the file.
      def load_save_file(file_path)
        data = super
        begin
          slot = File.basename(file_path.to_s, ".*")
          pl = data.is_a?(Hash) ? data[:player] : nil
          if pl.respond_to?(:save_slot=) && pl.save_slot && pl.save_slot != slot &&
             defined?(SaveData::MANUAL_SLOTS) && SaveData::MANUAL_SLOTS.include?(slot)
            KIF.log("Save #{slot} still named slot #{pl.save_slot}: it saves to #{slot}")
            pl.save_slot = slot
          end
        rescue StandardError => e
          KIF.log("Save slot check failed (#{e.class}: #{e.message})")
        end
        return data
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
  if KIF.mobile?   # no browser to start from inside the game on a phone
    Input.clipboard = url rescue nil
    return pbMessage(_INTL("The link (copied if your device allows):\n{1}", url))
  end
  return kif_sf_openUrlInBrowser(url)
end
