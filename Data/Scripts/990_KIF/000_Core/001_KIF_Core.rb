#===============================================================================
# KIF core helpers
#===============================================================================
module KIF
  # Folder that holds Game.rxdata. KIF keeps its marker files (*.krs) and
  # option presets (*.kro) here.
  def self.save_dir
    return File.dirname(SaveData::FILE_PATH)
  rescue
    return "."
  end

  # KIF "backdoor" marker files: DemICE.krs, Kurayami.krs, NoIntro.krs.
  # KIF checks the save folder (and, for DemICE.krs, the game folder).
  def self.marker?(filename)
    return File.exist?(File.join(save_dir, filename)) || File.exist?(filename)
  rescue
    return false
  end

  # True when the player is in the overworld of a loaded save (KIF only shows
  # per-save options in that case).
  def self.in_game?
    return $scene.is_a?(Scene_Map) && !$game_switches.nil?
  end

  def self.log(msg)
    echoln("[KIF] #{msg}") if defined?(echoln)
  end
end

#===============================================================================
# Base-method override guard
#
# When a KIF change sits in the middle of a long base method, the overlay
# redefines the whole method (a copy of the PIF 6.8.2 code plus the KIF
# hunks). Each such copy records the CRC32 of the base file it was copied
# from. If a later PIF update changes that file, a warning is printed to the
# console (and listed by KIF.drift_report) so the copy can be re-synced.
#===============================================================================
module KIF
  @drift = []

  def self.guard_base(path, crc, what)
    full = File.join("Data/Scripts", path)
    return unless File.exist?(full)
    actual = Zlib.crc32(File.binread(full))
    return if actual == crc
    @drift << "#{path} (#{what}): expected CRC #{crc}, found #{actual}"
    log("BASE FILE CHANGED since port – re-check override of #{what} in #{path}")
  rescue
    nil
  end

  def self.drift_report
    return @drift.dup
  end
end
