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

  # A downloaded relative path that stays inside its folder: no "..", drive,
  # backslash or leading "/" (update manifests, mod catalogs).
  def self.safe_rel_path?(path)
    p = path.to_s
    return !(p.empty? || p.start_with?("/") || p =~ /\A[A-Za-z]:/ || p.include?("\\") || p.split("/").include?(".."))
  end

  # mkdir -p / rm -r (no FileUtils in the game's Ruby). rm_tree never follows
  # a folder link into what it points at.
  def self.mkdir_p(dir)
    return if dir.nil? || dir.empty? || File.directory?(dir)
    mkdir_p(File.dirname(dir))
    Dir.mkdir(dir) unless File.directory?(dir)
  end

  # Keeps a disk cache folder from only growing: past `keep` files, the
  # oldest half (by time) is removed. Called once per session per cache.
  def self.trim_cache_dir(dir, keep)
    return unless File.directory?(dir)
    files = Dir.children(dir).map { |c| File.join(dir, c) }.select { |p| File.file?(p) }
    return if files.length <= keep
    files.sort_by { |p| File.mtime(p) }.first(files.length - keep / 2).each { |p| File.delete(p) rescue nil }
    log("Cache #{dir}: trimmed to #{keep / 2} files") if respond_to?(:log)
  rescue SystemCallError
    nil
  end

  def self.rm_tree(path)
    return unless File.exist?(path) || File.symlink?(path)
    if File.directory?(path) && !File.symlink?(path)
      Dir.children(path).each { |c| rm_tree(File.join(path, c)) }
      Dir.rmdir(path)
    else
      File.delete(path)
    end
  end

  # True when the player is in the overworld of a loaded save (KIF only shows
  # per-save options in that case).
  def self.in_game?
    return $scene.is_a?(Scene_Map) && !$game_switches.nil?
  end

  # The console (debug mode) and KIF_log.txt in the save folder (see
  # 010_KIF_SessionLog.rb)
  def self.log(msg)
    echoln("[KIF] #{msg}") if defined?(echoln)
    KIF::SessionLog.write(msg) if defined?(KIF::SessionLog)
  end

  # Verbose logging, for Cody and testers: on in debug mode, or when a file
  # named verbose.txt is in the Logs folder (or the save folder). Players get
  # the short log. Looked up once a session.
  VERBOSE_MARKER = "verbose.txt"

  def self.verbose?
    return @verbose unless @verbose.nil?
    @verbose = begin
      on = $DEBUG || marker?(VERBOSE_MARKER)
      on ||= defined?(KIF::Paths) && File.exist?(File.join(KIF::Paths.logs, VERBOSE_MARKER))
      on ? true : false
    rescue
      false
    end
    return @verbose
  end

  # A log line only verbose logging writes (details that help testing and
  # would only fill a player's log)
  def self.verbose(msg)
    log(msg) if verbose?
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
    data = File.binread(full)
    actual = Zlib.crc32(data)
    return if actual == crc
    # the same file with other line endings (a release zip has LF, a
    # Windows checkout CRLF) is not a change
    lf = data.gsub("\r\n", "\n")
    return if Zlib.crc32(lf) == crc || Zlib.crc32(lf.gsub("\n", "\r\n")) == crc
    @drift << "#{path} (#{what}): expected CRC #{crc}, found #{actual}"
    log("BASE FILE CHANGED since port – re-check override of #{what} in #{path}")
  rescue
    nil
  end

  def self.drift_report
    return @drift.dup
  end
end
