#===============================================================================
# F-CORE-10 shared contract: API level, permission names, where a mod's data
# lives, and which mod a piece of running code belongs to. Both the event bus
# and the mod guard use it. Keep this file identical in every branch.
#===============================================================================
module KIF
  API_LEVEL     = 1 unless const_defined?(:API_LEVEL)       # the API this KIF offers
  API_MIN_LEVEL = 1 unless const_defined?(:API_MIN_LEVEL)   # oldest level still supported without a warning

  module ModContract
    # permission => [colour when used, plain words]. :info never changes a colour.
    PERMISSIONS = {
      "network"       => [:yellow, "Uses the internet"],
      "programs"      => [:red,    "Starts other programs on your computer"],
      "native"        => [:red,    "Calls Windows or system code directly"],
      "game_files"    => [:yellow, "Changes files in the game folder"],
      "save_files"    => [:yellow, "Changes your save files and KIF settings"],
      "outside_files" => [:red,    "Reads or changes files outside the game"],
      "environment"   => [:yellow, "Reads your computer's settings"],
      "clipboard"     => [:yellow, "Reads or sets your clipboard"],
      "load_code"     => [:yellow, "Loads code from outside its own folder"],
      "marshal"       => [:yellow, "Reads saved-object files"],
      "eval"          => [:info,   "Builds code from text while running"],
      "objectspace"   => [:info,   "Looks through everything the game has loaded"]
    }.freeze
    # blocked when undeclared (default mode); the rest are only logged
    BLOCKING = %w[network programs native game_files save_files outside_files load_code].freeze

    @roots = {}        # "d:/game/mods/foo/" => "foo"      (folder mods)
    @files = {}        # "d:/game/mods/foo.rb" => "foo.rb" (loose files)

    def self.permission?(name); return PERMISSIONS.key?(name.to_s); end

    # one folder name for a mod id, safe in a file name
    def self.safe_id(id); return id.to_s.downcase.gsub(/[^a-z0-9_\-]/, "_")[0, 64]; end

    # Where a mod's own files live (both the data store and Safe use this).
    def self.data_dir(mod_id); return File.join(KIF.save_dir, "KIF_ModData", safe_id(mod_id)); end

    def self.norm(path); return File.expand_path(path.to_s).tr("\\", "/").downcase; end

    # id: the mod's key (folder name; see Entry#id). path: its folder or its .rb file.
    def self.register_root(id, path)
      p = norm(path)
      if File.directory?(path.to_s) then @roots[p + "/"] = id.to_s else @files[p] = id.to_s end
    end

    def self.forget_roots; @roots.clear; @files.clear; end
    def self.roots; return @roots.dup; end

    # Register every mod KIF lists (the Mods list reads the disk, cheap and idempotent).
    def self.refresh_roots
      return unless defined?(KIF::Mods) && KIF::Mods.respond_to?(:entries)
      KIF::Mods.entries.each { |e| register_root(e.id, e.path) if e.path && e.kind != :mod_manager }
    rescue StandardError
      nil
    end

    # the mod that owns a source file, or nil (KIF, the base game, Ruby itself)
    def self.owner_of_path(path)
      return nil if path.nil? || (@roots.empty? && @files.empty?)
      q = norm(path)
      return @files[q] if @files.key?(q)
      @roots.each { |root, id| return id if q.start_with?(root) }
      return nil
    end

    # Paths that never decide who is calling: Ruby's own files, the internal
    # frames and text run with eval (those take the next frame out).
    def self.transparent?(path)
      return true if path.nil? || path.start_with?("<internal:") || path.start_with?("(eval")
      return true if path.include?("/lib/ruby/")
      d = (defined?(RbConfig) ? RbConfig::CONFIG["rubylibdir"] : nil)
      return d ? path.start_with?(d) : false
    end

    # The mod a call belongs to: the NEAREST frame that is not transparent
    # decides. Under a mod root -> that mod. KIF's or the game's code (Safe.rb
    # included) -> nil, which means "not a mod, allowed". Why the nearest and not
    # the whole stack: mods wrap game methods (SaveData.save_to_file, Game.load...)
    # and the game's own file writes below their wrapper are not theirs.
    # Pass caller_locations(1, 40) taken in the method that is being guarded.
    def self.caller_owner(locations)
      locations.each do |l|
        p = l.absolute_path || l.path
        next if transparent?(p)
        return owner_of_path(p)
      end
      return nil
    end
  end
end
