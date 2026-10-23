#===============================================================================
# C-SYS-06 – finishing an update the game was moving in itself (2026-10-23)
#   Phones and Wine/Proton move a downloaded update in from Ruby
#   (KIF::Updater.apply_in_ruby). If the game is closed or killed while it
#   does, "KIF Update/<v>/failed.txt" still says "moving". This file loads
#   before the rest of KIF's scripts, so the remaining files are moved in
#   here and KIF's scripts and data all load from the new build; the load
#   screen (Updater.after_update) then does the rest and asks for a restart.
#===============================================================================
module KIF
  module UpdateFinish
    STAGE_DIR = "KIF Update"
    MARKER    = "failed.txt"
    MOVING    = "moving"
    VERSION_FILE = "Data/VERSION"

    module_function

    # the staged files of one update (paths inside files/): Data/Scripts last,
    # Data/VERSION left out (the updater moves it in after everything else)
    def staged_files(files)
      out = []
      walk = lambda do |sub|
        Dir.children(sub.empty? ? files : File.join(files, sub)).sort.each do |c|
          rel = sub.empty? ? c : "#{sub}/#{c}"
          File.directory?(File.join(files, rel)) ? walk.call(rel) : out << rel
        end
      end
      walk.call("") if File.directory?(files)
      out.delete(VERSION_FILE)
      scripts, rest = out.partition { |rel| rel.start_with?("Data/Scripts/") }
      return rest + scripts
    end

    # A rename replaces the old file in one step (Android, Linux, Windows);
    # an old file a rename can't replace is deleted first
    def move(src, dest)
      KIF.mkdir_p(File.dirname(dest))
      File.rename(src, dest)
    rescue SystemCallError
      raise unless File.file?(src) && File.exist?(dest)
      File.delete(dest)
      File.rename(src, dest)
    end

    # true when version v is older than this game's (000_README.rb loads first)
    def older?(v)
      mine = (defined?(KIF::PORT_VERSION) ? KIF::PORT_VERSION.to_s : "0").scan(/\d+/).map(&:to_i)
      theirs = v.to_s.scan(/\d+/).map(&:to_i)
      n = [mine.length, theirs.length].max
      return ((theirs + [0] * (n - theirs.length)) <=> (mine + [0] * (n - mine.length))) == -1
    end

    # updates cut off while moving in: their remaining files, now
    def finish_cut_off(root = File.expand_path("."))
      dir0 = File.join(root, STAGE_DIR)
      return 0 unless File.directory?(dir0)
      moved = 0
      Dir.children(dir0).sort.each do |v|
        dir = File.join(dir0, v)
        marker = File.join(dir, MARKER)
        next unless File.file?(marker) && File.read(marker) == MOVING
        next if older?(v)   # a newer game was installed over it since: the load screen removes it
        files = File.join(dir, "files")
        staged_files(files).each do |rel|
          move(File.join(files, rel), File.join(root, rel))
          moved += 1
        end
      end
      return moved
    rescue StandardError
      return moved   # the load screen tries again (Updater.after_update)
    end
  end

  # the same as 001_KIF_Core.rb's, which loads after this file
  def self.mkdir_p(dir)
    return if dir.nil? || dir.empty? || File.directory?(dir)
    mkdir_p(File.dirname(dir))
    Dir.mkdir(dir) unless File.directory?(dir)
  end
end

KIF::UpdateFinish.finish_cut_off
