#===============================================================================
# SCOPE-02 – PIF fixes: save files that can't be read (2026-11-01)
# All in PIF 6.8.2's own save code (MultiSaves.rb, 001_SaveData.rb). Found by
# the save sweep, which fed the game damaged, cut-off and odd-but-well-formed
# save files and backups:
#  1. SaveData.valid? raised for anything but a Hash, so a backup that
#     couldn't be read crashed "Load an older backup" instead of saying it is
#     corrupt.
#  2. The slot scan at start-up read :player from a save without looking, so
#     one slot holding an empty or player-less hash stopped the game starting.
#     (Fixed in 000_Core/009b_KIF_SaveScan.rb, the one get_newest_save_slot: it
#     skips such slots and keeps the save times.)
#  3. A save slot that can't be read loads its newest backup; when that one
#     was damaged too (the same crash or power cut), the loader treated the
#     backup as a slot, found no backups for it and offered to delete the
#     backup, then closed the game. It now tries the backups newest to oldest.
#  4. Reading a save that needs Essentials conversions wrote a full copy next
#     to the saves on every read, failed (and called the save corrupt) when
#     that copy couldn't be written, and rewrote the save in place. The copy
#     is best effort and written once per content, the rewrite goes through a
#     temp file and a rename (SaveData.read_from_file, in F-CORE-02_SaveCompat/
#     000_ReadFromFile.rb: the old-save import wraps it, so it has to load first),
#     and neither can stop the save from loading.
#  5. The emergency save (a script hangs) copied the slot file first with no
#     rescue: a missing file or a full disk skipped the save it exists for.
#===============================================================================
KIF.guard_base("052_InfiniteFusion/System/MultiSaves.rb", 381334228,
               "SaveData.get_newest_save_slot, run_conversions, PokemonLoadScreen#try_load_backup, pbEmergencySave")

module SaveData
  class << self
    alias kif_sr_valid? valid? unless method_defined?(:kif_sr_valid?)

    def valid?(save_data)
      return false unless save_data.is_a?(Hash)
      return kif_sr_valid?(save_data)
    end
  end

  # Copy of 6.8.2 MultiSaves.rb:248-269 with the safety copy made by
  # kif_sr_safety_copy.
  def self.run_conversions(save_data)
    validate save_data => Hash
    conversions_to_run = self.get_conversions(save_data)
    return false if conversions_to_run.none?
    kif_sr_safety_copy(save_data)
    echoln "Running #{conversions_to_run.length} conversions..."
    conversions_to_run.each do |conversion|
      echo "#{conversion.title}..."
      conversion.run(save_data)
      echoln ' done.'
    end
    echoln '' if conversions_to_run.length > 0
    save_data[:essentials_version] = Essentials::VERSION
    save_data[:game_version] = Settings::GAME_VERSION_NUMBER
    return true
  end

  # The copy of a save from before its conversions: written whole or not at
  # all, once for each content (a conversion that fails makes every read of
  # the file start over), and never a reason not to load the save.
  def self.kif_sr_safety_copy(save_data)
    raw = Marshal.dump(save_data)
    @kif_sr_copied ||= {}
    return if @kif_sr_copied[raw.hash]
    @kif_sr_copied[raw.hash] = true
    KIF::SaveBackups.write_file(self.get_backup_file_path, raw)
  rescue StandardError => e
    KIF.log("Save copy before conversions not written (#{e.class}: #{e.message.to_s[0, 160]})")
  end
end

class PokemonLoadScreen
  # Copy of 6.8.2 MultiSaves.rb:431-477: backups newest to oldest, the first
  # one that reads as a save is loaded; only when none does, the save file
  # itself is offered for deletion.
  def try_load_backup(file_path)
    file_name = File.basename(file_path, ".rxdata")   # e.g. "File A"
    backup_dir = File.join(File.dirname(file_path), "backups", file_name)
    backups = Dir.exist?(backup_dir) ? Dir.children(backup_dir).select { |f|
      f.start_with?(file_name + "_") && f.end_with?(".rxdata")
    } : []
    # newest first by the numeric timestamp
    backups.sort_by! do |fname|
      [fname.sub(/^#{Regexp.escape(file_name)}_/, "").sub(/\.rxdata$/, "").to_i, fname]
    end
    backups.reverse!
    backups.each_with_index do |latest, i|
      save_data = (SaveData.read_from_file(File.join(backup_dir, latest)) rescue nil)
      next unless SaveData.valid?(save_data)
      timestamp_str = latest.sub(/^#{Regexp.escape(file_name)}_/, "").sub(/\.rxdata$/, "")
      if timestamp_str.length >= 12
        formatted_time = "#{timestamp_str[0, 4]}-#{timestamp_str[4, 2]}-#{timestamp_str[6, 2]} " +
                         "#{timestamp_str[8, 2]}:#{timestamp_str[10, 2]}"
      else
        formatted_time = timestamp_str
      end
      pbMessage(_INTL(
                  (i == 0 ? "The save file is corrupt. The most recent backup will be loaded instead.\n" :
                            "The save file is corrupt. The newest backups can't be read, so an older one will be loaded instead.\n") +
                    "\\C[2]{1}\\C[0]\nBackup date: \\C[3]{2}",
                  latest, formatted_time
                ))
      return save_data
    end
    self.prompt_save_deletion(file_path)
    return {}
  end
end

# Copy of 6.8.2 MultiSaves.rb:1127-1141: the copy of the slot file is only
# made if the file is there, and a failure to make it doesn't stop the save.
def pbEmergencySave
  oldscene = $scene
  $scene = nil
  pbMessage(_INTL("The script is taking too long. The game will restart."))
  return if !$Trainer
  return if !$Trainer.save_slot
  current_file = SaveData.get_full_path($Trainer.save_slot)
  begin
    file_copy(current_file, SaveData.get_backup_file_path) if File.file?(current_file)
  rescue SystemCallError, IOError => e
    KIF.log("Emergency save: copy of the slot file failed (#{e.class})")
  end
  if Game.save
    pbMessage(_INTL("\\se[]The game was saved.\\me[GUI save game] The previous save file has been backed up.\\wtnp[30]"))
  else
    pbMessage(_INTL("\\se[]Save failed.\\wtnp[30]"))
  end
  $scene = oldscene
end
