#===============================================================================
# SCOPE-02 – a save file that can't be read (2026-10-24)
#   PIF's save menu reads every File slot for its info box (MultiSaves.rb
#   slotSelect / getSaveInfoBoxContents), and one that can't be read (cut
#   off, damaged) raised there, so a new game could never be saved. That
#   slot now says "(can't be read)"; saving there overwrites it after its
#   old copy went to the backups, as for any save.
#   The load screen picks the newest save it can read. With none readable
#   there was no Continue and no Savefile management, so the unreadable
#   file's backups couldn't be reached from the game. It now picks an
#   unreadable file that has backups: PIF loads its newest backup in its
#   place, and Savefile management offers the older ones. One without
#   backups is left out (PIF would only offer to delete it and close).
#===============================================================================
module KIF
  module UnreadableSaves
    module_function

    # the first save slot whose file is there and has a backup (PIF's
    # try_load_backup folder and names)
    def slot_with_backups
      SaveData.each_slot do |slot|
        path = SaveData.get_full_path(slot)
        next unless File.file?(path)
        name = File.basename(path, ".rxdata")
        dir = File.join(File.dirname(path), "backups", name)
        next unless File.directory?(dir)
        return slot if Dir.children(dir).any? { |f| f.start_with?(name + "_") && f.end_with?(".rxdata") }
      end
      return nil
    rescue StandardError
      return nil
    end
  end
end

class PokemonSaveScreen
  alias kif_us_getSaveInfoBoxContents getSaveInfoBoxContents unless method_defined?(:kif_us_getSaveInfoBoxContents)

  def getSaveInfoBoxContents(slot)
    return kif_us_getSaveInfoBoxContents(slot)
  rescue StandardError => e
    KIF.log("Save slot #{slot} can't be read (#{e.class}: #{e.message.to_s[0, 160]})")
    return _INTL("<ac><c3=3050C8,D0D0C8>(can't be read)</c3></ac>")
  end
end

class PokemonLoadScreen
  # initialize is private: method_defined? never sees its copy
  alias kif_us_initialize initialize unless private_method_defined?(:kif_us_initialize)

  def initialize(*args)
    kif_us_initialize(*args)
    # nil: no save could be read
    @selected_file ||= KIF::UnreadableSaves.slot_with_backups
  end
end
