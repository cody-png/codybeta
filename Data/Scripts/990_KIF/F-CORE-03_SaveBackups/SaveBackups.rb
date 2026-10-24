#===============================================================================
# F-CORE-03 – Infinite Save Backups (DemICE)
# Source: KIF 0.20.7 052_AddOns/MultiSaves_Infinite Save Backups.rb
#
# PIF 6.8.2 already backs up a save file before overwriting it
# (backups/<slot>/<slot>_<date>.rxdata, MultiSaves.rb:1019) and has a "load
# a backup" menu, but deletes all but the newest 10. KIF never deleted its
# backups.
#
# Others > "Save Backups" (all saves):
#   Infinite           – backups of the saves you make in the save menu
#                        (and Quicksave) are never deleted (KIF); saves the
#                        game makes by itself (autosave, Transfer Box, PC,
#                        Battle Frontier) keep their newest 10 as
#                        "<slot>_<date>_autosave", or a long game filled
#                        gigabytes (2026-10-18; Transfer Box 2026-10-19)
#   Newest 10 (default since 2026-10-22) – 6.8.2's limit (Settings::SAVEFILE_NB_BACKUPS)
#   Off                – no backups (named ones still work)
# Save menu, either way (KIF): "Name the next backup" – type a name, then
# save; a copy of that save is kept as a backup under the name – and
# "Open the save folder", and "Compress old backups" (see below).
#
# 6.8.2 adaptations: backups use 6.8.2's folder and names, so its load-backup
# menu lists them (named ones show "date – name"). KIF kept its own
# "<slot> <n> <time> <map>" files next to the saves.
#
# Compressed backups (KIF 1.2, 2026-10-22): new backups are gzip files under
# the same .rxdata names (about a tenth of the size); SaveData.get_data_from_file
# reads either kind. Old plain backups stay as they are until the player uses
# the save menu's "Compress old backups".
#===============================================================================
KIF::Options.define(:savebackups, 1, :global)   # 0 Infinite, 1 Newest 10 (default, 2026-10-22), 2 Off

KIF::Options.add(:others, :global) {
  EnumOption.new(_INTL("Save Backups"), [_INTL("Infinite"), _INTL("Newest 10"), _INTL("Off")],
                 proc { $PokemonSystem.savebackups },
                 proc { |value| $PokemonSystem.savebackups = value },
                 [_INTL("Every save you make keeps a backup; autosaves keep their newest ones"),
                  _INTL("Only the newest 10 backups of each save file are kept"),
                  _INTL("No backups (named backups still work). Backups already made are kept")])
}

module KIF
  module SaveBackups
    AUTO = "autosave"
    @next_name = nil
    @player_saving = false
    @normal_box = false   # save menu / load screen open: messages use the normal bottom box
    class << self
      attr_accessor :next_name, :player_saving, :normal_box
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

    GZ_MAGIC = "\x1F\x8B".b

    # a gzip backup (the name stays <slot>_<date>.rxdata, so PIF's menu,
    # the trim and every name check treat it like a plain one)
    def self.gz?(path)
      return File.binread(path, 2) == GZ_MAGIC
    rescue StandardError
      return false
    end

    # 6: ~1/10 of the size in 10-25 ms on a PC; phones take the faster 1 (~1/8)
    def self.level
      return KIF.mobile? ? Zlib::BEST_SPEED : Zlib::DEFAULT_COMPRESSION
    end

    # gzip of raw if it reads back byte-exact and is smaller, else raw
    def self.packed(raw)
      gz = Zlib.gzip(raw, level: level)
      return (gz.bytesize < raw.bytesize && Zlib.gunzip(gz) == raw) ? gz : raw
    rescue StandardError => e
      KIF.log("Save backup not compressed: #{e.message}")
      return raw
    end

    # temp file + rename: a backup is never half written
    def self.write_file(dest, data)
      tmp = dest + ".tmp"
      File.binwrite(tmp, data)
      File.rename(tmp, dest)
    ensure
      (File.delete(tmp) if tmp && File.exist?(tmp)) rescue nil
    end

    def self.copy(save_path, slot, name = nil)
      return unless File.exist?(save_path)
      clean = name.to_s.gsub(/[\\\/:*?"<>|]/, "").strip
      dir = slot_dir(save_path, slot)
      t = Time.now; file = nil
      # two saves in one second: the next free second, so neither backup is lost
      loop do
        stamp = t.strftime("%Y%m%d%H%M%S")
        file = clean.empty? ? "#{slot}_#{stamp}.rxdata" : "#{slot}_#{stamp}_#{clean}.rxdata"
        break unless File.exist?(File.join(dir, file))
        t += 1
      end
      write_file(File.join(dir, file), packed(File.binread(save_path)))
    rescue => e
      KIF.log("Save backup failed: #{e.message}")
    end

    # Save menu > Compress old backups: every plain backup is gzipped; the
    # original is replaced only once the compressed file on disk reads back
    # byte for byte. Returns [compressed, bytes freed, left as they were]
    def self.compress_old(root = File.join(SaveData::SAVE_DIR.to_s, "backups"))
      done = 0; freed = 0; kept = 0
      return [0, 0, 0] unless Dir.exist?(root)
      Dir.children(root).sort.each do |slot|
        sdir = File.join(root, slot)
        next unless File.directory?(sdir)
        Dir.children(sdir).sort.each do |c|
          path = File.join(sdir, c)
          next unless c.end_with?(".rxdata") && File.file?(path) && !gz?(path)
          Graphics.update rescue nil
          tmp = path + ".tmp"
          begin
            raw = File.binread(path)
            gz = Zlib.gzip(raw, level: level)
            next if gz.bytesize >= raw.bytesize   # nothing to gain
            File.binwrite(tmp, gz)
            unless Zlib::GzipReader.open(tmp) { |f| f.read }.b == raw   # .b: read gives text encoding
              kept += 1
              KIF.log("Compress old backups: #{c} did not read back the same, left as it was")
              next
            end
            mtime = File.mtime(path)
            File.rename(tmp, path)
            File.utime(mtime, mtime, path) rescue nil
            done += 1; freed += raw.bytesize - gz.bytesize
          rescue StandardError => e
            kept += 1
            KIF.log("Compress old backups: #{c} left as it was (#{e.message})")
          ensure
            (File.delete(tmp) if File.exist?(tmp)) rescue nil
          end
        end
      end
      return [done, freed, kept]
    end

    def self.compress_old_menu
      return unless pbConfirmMessage(_INTL("Compress the backups made before KIF compressed them? Each one is checked before its old copy is replaced."))
      done, freed, kept = compress_old
      if done == 0 && kept == 0
        pbMessage(_INTL("There are no old backups to compress."))
      else
        mb = format("%.1f", freed / 1048576.0)
        pbMessage(done == 1 ? _INTL("Compressed 1 backup and freed {1} MB.", mb) : _INTL("Compressed {1} backups and freed {2} MB.", done, mb)) if done > 0
        pbMessage(kept == 1 ? _INTL("1 backup couldn't be checked, so it was left as it was.") :
                              _INTL("{1} backups couldn't be checked, so they were left as they were.", kept)) if kept > 0
      end
    end

    # oldest unnamed (or autosave) backups beyond Settings::SAVEFILE_NB_BACKUPS
    def self.trim(save_path, slot, auto = false)
      dir = slot_dir(save_path, slot)
      tail = auto ? "_#{AUTO}" : ""
      plain = Dir.children(dir).select { |c| c =~ /\A#{Regexp.escape(slot.to_s)}_\d{14}#{tail}\.rxdata\z/ }.sort
      plain[0...[plain.length - Settings::SAVEFILE_NB_BACKUPS, 0].max].each { |c| File.delete(File.join(dir, c)) }
    rescue => e
      KIF.log("Save backup clean-up failed: #{e.message}")
    end

    def self.open_folder
      path = SaveData::SAVE_DIR.to_s
      # a phone can't open a file manager from the game (starting one can hang it)
      return pbMessage(_INTL("Your saves are in:\n{1}", path)) if KIF.mobile?
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

    # Infinite: back up without 6.8.2's clean-up of old backups.
    # PIF: 6.8.2's limit, but named backups are never trimmed (6.8.2 deleted
    # any *.rxdata in the folder)
    def backup_savefile(save_path, slot)
      return if $PokemonSystem && $PokemonSystem.savebackups.to_i == 2   # Off
      auto = !KIF::SaveBackups.player_saving
      KIF::SaveBackups.copy(save_path, slot, auto ? KIF::SaveBackups::AUTO : nil)
      KIF::SaveBackups.trim(save_path, slot, auto) if auto || !KIF::SaveBackups.infinite?
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

# Every save read (PIF's "Load an older backup", the corrupt-save fallback,
# KIF) goes through here: a gzip backup is read through Zlib, the rest as PIF
module SaveData
  class << self
    alias kif_bk_get_data_from_file get_data_from_file unless method_defined?(:kif_bk_get_data_from_file)

    def get_data_from_file(file_path)
      return kif_bk_get_data_from_file(file_path) unless KIF::SaveBackups.gz?(file_path)
      # same reading as PIF 6.8.2 001_SaveData.rb:23-35, from the gzip stream
      save_data = nil
      Zlib::GzipReader.open(file_path) do |file|
        data = Marshal.load(file)
        if data.is_a?(Hash)
          save_data = data
          next
        end
        save_data = [data]
        save_data << Marshal.load(file) until file.eof?
      end
      return save_data
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
  # Copy of PIF 6.8.2 MultiSaves.rb:822-849 with the KIF entries
  # (KIF MultiSaves_Infinite Save Backups.rb:61-118).
  def pbSaveScreen
    ret = false
    box = KIF::SaveBackups.normal_box                                   # KIF
    KIF::SaveBackups.normal_box = true                                  # KIF
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
        _INTL("Compress old backups"),                                  # KIF
        _INTL("Don't save")
      ]
      opt = pbMessage(_INTL("Would you like to save the game?"), choices, 6)   # KIF: 6
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
      elsif opt == 4                                                    # KIF
        pbPlayDecisionSE
        KIF::SaveBackups.compress_old_menu
      else
        pbPlayCancelSE
      end
    end
    @scene.pbEndScreen
    return ret
  ensure
    KIF::SaveBackups.normal_box = box                                   # KIF
  end
end

# The load screen too: its $game_system is the last session's (title after
# playing) or the newest save's (start-up), with whatever text options an
# event left there (the intro: top, no frame, over the save panel). A
# prepended module, not an alias: Session Log, Save Folder and Sprite Import
# prepend pbStartLoadScreen too.
module KIF
  module SaveBackups
    module LoadScreenBox
      def pbStartLoadScreen(*args)
        box = KIF::SaveBackups.normal_box
        KIF::SaveBackups.normal_box = true
        return super
      ensure
        KIF::SaveBackups.normal_box = box
      end
    end
  end
end

PokemonLoadScreen.prepend(KIF::SaveBackups::LoadScreenBox)

# The save menu's question and messages use the normal box at the bottom even
# when the event that opened it set other text options (the new-game intro:
# top of the screen, no frame, which put them over the save panel).
# $game_system only changes while a box is placed, so a save made there keeps
# the event's options.
alias kif_bk_pbRepositionMessageWindow pbRepositionMessageWindow unless defined?(kif_bk_pbRepositionMessageWindow)

def pbRepositionMessageWindow(msgwindow, linecount = 2)
  sys = $game_system
  return kif_bk_pbRepositionMessageWindow(msgwindow, linecount) unless KIF::SaveBackups.normal_box && sys
  old = [sys.message_position, sys.message_frame]
  begin
    sys.message_position, sys.message_frame = 2, 0
    return kif_bk_pbRepositionMessageWindow(msgwindow, linecount)
  ensure
    sys.message_position, sys.message_frame = old
  end
end

# Saves the player picks (save menu, another slot, Quicksave) all go through
# doSave; every other Game.save is the game saving by itself
class PokemonSaveScreen
  alias kif_bk_doSave doSave unless method_defined?(:kif_bk_doSave)

  def doSave(slot)
    KIF::SaveBackups.player_saving = true
    return kif_bk_doSave(slot)
  ensure
    KIF::SaveBackups.player_saving = false
  end
end
