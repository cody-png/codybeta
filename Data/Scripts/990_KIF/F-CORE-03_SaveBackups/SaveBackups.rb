#===============================================================================
# F-CORE-03 – Infinite Save Backups (DemICE)
# Source: KIF 0.20.7 052_AddOns/MultiSaves_Infinite Save Backups.rb
#
# PIF 6.8.2 already backs up a save file before overwriting it
# (backups/<slot>/<slot>_<date>.rxdata, MultiSaves.rb:1019) and has a "load
# a backup" menu, but deletes all but the newest 10. KIF never deleted its
# backups.
#
# Others > "Save Backups" (all saves; Cody 2026-10-05):
#   Infinite (default) – backups are never deleted (KIF)
#   PIF                – 6.8.2's limit (Settings::SAVEFILE_NB_BACKUPS)
# Save menu, either way (KIF): "Name the next backup" – type a name, then
# save; a copy of that save is kept as a backup under the name – and
# "Open the save folder".
#
# 6.8.2 adaptations: backups use 6.8.2's folder and names, so its load-backup
# menu lists them (named ones show "date – name"). KIF kept its own
# "<slot> <n> <time> <map>" files next to the saves.
#===============================================================================
KIF::Options.define(:savebackups, 0, :global)   # 0 Infinite, 1 PIF limit

KIF::Options.add(:others, :global) {
  EnumOption.new(_INTL("Save Backups"), [_INTL("Infinite"), _INTL("PIF")],
                 proc { $PokemonSystem.savebackups },
                 proc { |value| $PokemonSystem.savebackups = value },
                 [_INTL("Every save keeps a backup; none are deleted"),
                  _INTL("Only the newest backups are kept (PIF)")])
}

module KIF
  module SaveBackups
    @next_name = nil
    class << self
      attr_accessor :next_name
    end

    def self.infinite?
      return !$PokemonSystem || $PokemonSystem.savebackups.to_i == 0
    end

    def self.slot_dir(save_path, slot)
      dir = File.join(File.dirname(save_path), "backups")
      Dir.mkdir(dir) unless Dir.exist?(dir)
      dir = File.join(dir, slot)
      Dir.mkdir(dir) unless Dir.exist?(dir)
      return dir
    end

    def self.copy(save_path, slot, name = nil)
      return unless File.exist?(save_path)
      stamp = Time.now.strftime("%Y%m%d%H%M%S")
      clean = name.to_s.gsub(/[\\\/:*?"<>|]/, "").strip
      file = clean.empty? ? "#{slot}_#{stamp}.rxdata" : "#{slot}_#{stamp}_#{clean}.rxdata"
      # streamed copy (KIF read the whole save into memory first)
      IO.copy_stream(save_path, File.join(slot_dir(save_path, slot), file))
    rescue => e
      KIF.log("Save backup failed: #{e.message}")
    end

    def self.open_folder
      path = SaveData::SAVE_DIR.to_s
      if System.platform[/Windows/]
        system("explorer \"#{path.gsub('/', '\\')}\"")
      elsif System.platform[/Mac/]
        system("open", path)
      else
        system("xdg-open", path)
      end
    rescue => e
      KIF.log("Open save folder failed: #{e.message}")
    end
  end
end

module Game
  class << self
    alias kif_bk_backup_savefile backup_savefile unless method_defined?(:kif_bk_backup_savefile)
    alias kif_bk_save save unless method_defined?(:kif_bk_save)

    # Infinite: back up without 6.8.2's clean-up of old backups
    def backup_savefile(save_path, slot)
      return kif_bk_backup_savefile(save_path, slot) unless KIF::SaveBackups.infinite?
      KIF::SaveBackups.copy(save_path, slot)
    end

    # A named backup is a copy of the save just written (KIF)
    def save(slot = nil, auto = false, safe: false)
      ret = kif_bk_save(slot, auto, safe: safe)
      name = KIF::SaveBackups.next_name
      if ret && name && !auto
        slot ||= $Trainer.save_slot
        KIF::SaveBackups.copy(SaveData.get_full_path(slot), slot, name) if slot
        KIF::SaveBackups.next_name = nil
      end
      return ret
    end
  end
end

# Load-backup menu: "date – name" for named backups
class PokemonLoadScreen
  alias kif_bk_formatSaveDate formatSaveDate unless method_defined?(:kif_bk_formatSaveDate)

  def formatSaveDate(str)
    if str.to_s =~ /\A(\d{14})_(.+)\z/
      return "#{kif_bk_formatSaveDate($1)} - #{$2}"
    end
    return kif_bk_formatSaveDate(str)
  end
end

KIF.guard_base("052_InfiniteFusion/System/MultiSaves.rb", 381334228, "PokemonSaveScreen#pbSaveScreen")

class PokemonSaveScreen
  # Copy of PIF 6.8.2 MultiSaves.rb:822-849 with the two KIF entries
  # (KIF MultiSaves_Infinite Save Backups.rb:61-118).
  def pbSaveScreen
    ret = false
    @scene.pbStartScreen
    if !$Trainer.save_slot
      # New Game - must select slot
      ret = slotSelect
    else
      KIF::SaveBackups.next_name = nil                                  # KIF
      choices = [
        _INTL("Save to #{$Trainer.save_slot}"),
        _INTL("Save to another slot"),
        _INTL("Name the next backup"),                                  # KIF
        _INTL("Open the save folder"),                                  # KIF
        _INTL("Don't save")
      ]
      opt = pbMessage(_INTL("Would you like to save the game?"), choices, 5)   # KIF: 5
      if opt == 0
        pbSEPlay('GUI save choice')
        ret = doSave($Trainer.save_slot)
      elsif opt == 1
        pbPlayDecisionSE
        ret = slotSelect
      elsif opt == 2                                                    # KIF
        pbPlayDecisionSE
        name = pbMessageFreeText(_INTL("Backup name:"), "", false, 40)
        if name && !name.strip.empty?
          KIF::SaveBackups.next_name = name
          choices = [_INTL("Save to #{$Trainer.save_slot}"), _INTL("Save to another slot"), _INTL("Don't save")]
          opt = pbMessage(_INTL("Choose a save slot."), choices, 3)
          if opt == 0
            pbSEPlay('GUI save choice')
            ret = doSave($Trainer.save_slot)
          elsif opt == 1
            pbPlayDecisionSE
            ret = slotSelect
          else
            pbPlayCancelSE
          end
          KIF::SaveBackups.next_name = nil
        else
          pbPlayCancelSE
        end
      elsif opt == 3                                                    # KIF
        pbPlayDecisionSE
        KIF::SaveBackups.open_folder
      else
        pbPlayCancelSE
      end
    end
    @scene.pbEndScreen
    return ret
  end
end
