#===============================================================================
# Mods catalog – Browse and Updates in Options > KIF Settings > Mods
# The catalog is the KIF-Mods/mods repository on GitHub (the one Mod Manager
# 2.0 reads): one folder per mod with its mod.json. One GitHub API call lists
# every file with its git id and size; the mod.json files come from
# raw.githubusercontent.com. Downloads go through the updater's downloader
# (curl, then a file-by-file fallback) and every file is checked against its
# git id before it is moved in.
#
# Installing: every file goes to Mods/<folder>/ (its pictures and sounds are
# found there, KIF::ModAssets). .kif_installed in the mod folder
# lists what was installed, so an update can remove files the mod dropped
# (only ones still unchanged). Other files in the folder (a mod's own
# settings) are never touched.
#
# A text file KIF_mods_source.txt next to the game holding a folder path
# reads the catalog from that folder instead (laid out like the repository).
# With Mod Manager 2.0 installed, its own browser is used and these tabs are
# not shown.
#
# More catalogs (2026-10-16): a modder can keep their own repository laid out
# the same way, and Browse lists it under KIF-Mods. Added by
#   * KIF_mods_catalogs.txt next to the game: one per line,
#     "owner/repo", "owner/repo@branch" or a folder, then an optional name
#     ("Stonewall/kr-mods@main Kanto Reloaded"); # starts a comment
#   * a mod's mod.json: "catalog": "owner/repo@branch" (its updates come
#     from there)
#   * Ruby: KIF::ModCatalog.add_catalog("owner/repo", branch: "main", name: "...")
# A mod found in two catalogs comes from the first one (KIF-Mods first).
# A catalog's modpacks/<folder>/modpack.json files are its modpacks
# (KIF::ModPacks).
#===============================================================================
module KIF
  module ModCatalog
    REPO       = "KIF-Mods/mods"
    DISCORD_REPO = "cody-png/kif-discord-mods"   # mods only shared on Discord (made with import_mods.py)
    OWN_REPO     = "cody-png/kif-mods"           # KIF's own mods from now on (Cody, 2026-10-20)
    SOURCE_FILE = "KIF_mods_source.txt"
    CATALOGS_FILE = "KIF_mods_catalogs.txt"
    ASSET_DIRS = %w[Graphics Audio Fonts]
    RECORD     = ".kif_installed"
    ASSETS     = ".installed_assets"
    SKIP       = %w[modpacks]
    # authors' git/editor files inside a mod folder; a mod's own dotfile
    # (pokedex_voice_over's vendor/.project-root) still installs
    JUNK       = %w[.git .gitignore .gitattributes .gitkeep .keep .idea .vscode .claude .DS_Store Thumbs.db desktop.ini]
    CACHE_TIME = 600   # seconds a fetched list is reused
    # What a catalog (internet text) may hold, well above the real ones (the
    # biggest mod: 3,251 files, 23 MB; mod.json 7 KB). A mod over a limit is
    # not installed, a catalog over one is not read.
    MAX_TREE_FILES = 100_000        # GitHub's own cut-off for one file list
    MAX_TEXT       = 16 * 1024 * 1024   # one answer from a catalog
    MAX_JSON       = 64 * 1024      # a mod.json / modpack.json
    MAX_MOD_FILES  = 10_000
    MAX_MOD_FILE   = 64 * 1024 * 1024
    MAX_MOD_BYTES  = 256 * 1024 * 1024
    # KIF's own bookkeeping in a mod folder: a catalog can't ship these
    RESERVED   = /\A(\.kif_installed|\.kif_provenance|\.installed_assets|.*\.kif_old|.*\.kif_game)\z/i
    PROVENANCE = ".kif_provenance"   # where a mod's files came from (repo, commit, every file's hash); written at install
    REPO_RE    = %r{\A[\w.-]+/[\w.-]+\z}
    BRANCH_RE  = %r{\A[\w.-]+(/[\w.-]+)*\z}
    # GitHub trees (by head commit) and mod.json texts (by blob sha) kept
    # between sessions in the save folder, so an unchanged catalog costs one
    # small request (2026-10-22)
    DISK_CACHE = "KIF_catalog_cache.dat"

    # one catalog: a GitHub repository (or a folder laid out like one)
    class Catalog
      attr_reader :repo, :branch, :path
      def initialize(repo, branch = "main", name = nil, path = nil)
        @repo = repo.to_s
        @branch = (branch || "main").to_s
        @name = name
        @path = path
      end
      def local?;   return !@path.nil?; end
      def name;     return (@name && !@name.to_s.empty?) ? @name.to_s : (local? ? File.basename(@path) : @repo); end
      def key;      return local? ? File.expand_path(@path) : "#{@repo.downcase}@#{@branch}"; end
      def tree_url(ref = @branch); return "https://api.github.com/repos/#{@repo}/git/trees/#{ref}?recursive=1"; end
      # tiny answer holding the branch's head commit sha
      def ref_url;  return "https://api.github.com/repos/#{@repo}/git/refs/heads/#{@branch}"; end
      # the branch's name, and the commit it pointed at when the file list was read: the files
      # come from that commit, so the list and the files cannot be from two different states
      def branch_base; return "https://raw.githubusercontent.com/#{@repo}/#{@branch}"; end
      def commit; return KIF::ModCatalog.commit_of(self); end
      def raw_base; return "https://raw.githubusercontent.com/#{@repo}/#{commit || @branch}"; end
      def base
        return raw_base unless local?
        return KIF::Updater.file_url(@path)
      end
    end

    # the commit each GitHub catalog's file list was read at (catalog key => 40 hex)
    @commits ||= {}
    def self.commit_of(cat); return (@commits ||= {})[cat.key]; end
    def self.pin(cat, sha)
      return unless sha.to_s =~ /\A[0-9a-f]{40}\z/
      (@commits ||= {})[cat.key] = sha
    end

    # Text from a catalog (a mod's name, author...) as plain one-line text:
    # no control characters and no "\" (the message box reads \ codes), cut at max
    def self.clean_text(text, max)
      s = KIF::PixelFont.utf8(text.to_s).gsub(/[\x00-\x1f\x7f]+/, " ").tr("\\", "/").strip
      return s.length > max ? s[0, max - 3] + "..." : s
    end

    # an id is compared with other ids, never shown as it is: one with a control character,
    # a backslash or a hundred characters isn't an honest one
    def self.plain_id?(id)
      s = id.to_s
      return !s.empty? && s.length <= 100 && s !~ /[\x00-\x1f\x7f\\]/
    end

    # "owner/repo" and a branch that can only name a branch on GitHub (no "..", no odd characters)
    def self.valid_repo?(repo)
      s = repo.to_s
      return s =~ REPO_RE && s.split("/").none? { |p| p =~ /\A\.+\z/ } ? true : false
    end

    def self.valid_branch?(branch)
      s = branch.to_s
      return s.length <= 100 && s =~ BRANCH_RE && s.split("/").none? { |p| p =~ /\A\.+\z/ } ? true : false
    end

    # one mod in the catalog
    class Item
      attr_reader :folder, :json, :files, :catalog
      def initialize(folder, json, files, catalog = nil)
        @folder = folder
        @json = json || {}
        @files = files     # rel path => [sha, size]
        @catalog = catalog
      end
      def base; return @catalog ? @catalog.base : KIF::ModCatalog.base; end
      def requires_kif; return @json["requires_kif"]; end
      def commit; return @catalog ? @catalog.commit : nil; end   # the commit its files come from (nil: a local catalog)
      # the catalog's words, as plain short text (mod.json comes from the internet)
      def text(v, max); return KIF::ModCatalog.clean_text(v, max); end
      def id;      return (@json["id"] || @folder).to_s; end   # a matching key, not display text: as written
      def name;    t = text(@json["name"], 60); return t.empty? ? text(@folder, 60) : t; end
      def version; return text(@json["version"], 32); end
      def author;  return text(@json["author"], 60); end
      def tags;    return Array(@json["tags"]).first(12).map { |t| text(t, 24) }; end
      def size;    return @files.values.inject(0) { |s, (_sha, sz)| s + sz.to_i }; end
      def description
        d = @json["description"]
        d = d.first(50).join(" ") if d.is_a?(Array)
        return text(d, 2000)
      end
      def dependencies
        return KIF::ModRules.ids_in(@json["dependencies"])
      end
      def incompatible
        return KIF::ModRules.ids_in(@json["incompatible"])
      end
    end

    module_function

    def updater; return KIF::Updater; end
    def root;    return updater.root; end
    def mods_dir; return File.join(root, KIF::Mods::FOLDER); end

    def log(msg); KIF.log("Mods catalog: #{msg}"); end

    # Mod Manager 2.0 has its own browser
    def available?
      return !defined?(::ModManager)
    end

    def source
      file = File.join(root, SOURCE_FILE)
      if File.file?(file)
        line = File.read(file).to_s.strip.split(/\r?\n/).first.to_s.strip
        return line if !line.empty? && File.directory?(line)
      end
      return nil
    end

    def base
      return catalogs[0].base
    end

    # KIF-Mods (or the KIF_mods_source.txt folder), then the others
    @added = []
    def add_catalog(repo, branch: "main", name: nil)
      repo = repo.to_s.strip
      return false if repo.empty?
      path = File.directory?(repo) ? repo : nil
      unless path || (valid_repo?(repo) && valid_branch?(branch || "main"))
        log("\"#{repo}\" isn't a GitHub repository (owner/repo) or a folder")
        return false
      end
      c = Catalog.new(path ? nil : repo, branch, name, path)
      return false if @added.any? { |x| x.key == c.key }
      @added << c
      @items = nil
      return true
    end

    # "owner/repo@branch Name" / a folder path
    def parse_catalog(line)
      line = line.to_s.sub(/#.*\z/, "").strip
      return nil if line.empty?
      # a folder (its path may have spaces), then the name
      words = line.split(/\s+/)
      words.length.downto(1) do |n|
        dir = words[0, n].join(" ")
        return Catalog.new(nil, nil, words[n..-1].join(" "), dir) if File.directory?(dir)
      end
      spec, name = line.split(/\s+/, 2)
      repo, branch = spec.split("@", 2)
      return nil unless valid_repo?(repo) && (branch.nil? || valid_branch?(branch))
      return Catalog.new(repo, branch, name)
    end

    def catalogs
      s = source
      list = [s ? Catalog.new(nil, nil, "KIF-Mods", s) : Catalog.new(REPO, "main", "KIF-Mods")]
      unless s   # a local test source stays alone
        list << Catalog.new(OWN_REPO, "main", "KIF Mods (cody-png)")
        list << Catalog.new(DISCORD_REPO, "main", "Discord Mods")
      end
      file = File.join(root, CATALOGS_FILE)
      if File.file?(file)
        File.read(file).to_s.force_encoding("UTF-8").split(/\r?\n/).each do |l|
          c = parse_catalog(l)
          list << c if c
        end
      end
      list.concat(@added)
      seen = {}
      return list.select { |c| seen[c.key] ? false : (seen[c.key] = true) }
    end

    def items;   return @items; end
    def packs;   return @packs || []; end
    def checked; return @checked; end
    def error;   return @error; end
    # catalogs that couldn't be read last time: [Catalog, ...]
    def failed;  return @failed || []; end

    def find(id)
      return nil unless @items
      return @items.find { |it| it.id == id || it.folder == id }
    end

    #---------------------------------------------------------------------------
    # Reading the catalog
    #---------------------------------------------------------------------------
    def load(force = false)
      return @items if @items && !force && @checked && Time.now - @checked < CACHE_TIME
      @installed_index = nil
      @error = nil
      @failed = []
      list = []
      packs = []
      cats = catalogs
      begin_stats(cats.length)
      cats.each do |cat|
        files = tree_for(cat, force)
        if files.nil?
          @failed << cat
          log("#{cat.name}: couldn't be read")
          next
        end
        list.concat(items_in(cat, files, list))
        packs.concat(packs_in(cat, files, packs))
      end
      updater.hide_status
      if list.empty? && !@failed.empty?
        @error = _INTL("Couldn't reach the mod catalog. Check the internet connection and try again.")
        return @items
      end
      @items = list
      @packs = packs
      @checked = Time.now
      log("#{list.length} mods listed (#{cats.length - @failed.length} of #{cats.length} catalogs)")
      return @items
    ensure
      end_stats("list read")
    end

    # Load screen: the installed mods with an update, reading only their own
    # catalog entries so the start stays quick. Browse still reads the whole
    # list when opened.
    # shortcut: matched by folder name, a renamed mod folder isn't checked at start-up
    def startup_updates
      @installed_index = nil
      have = installed_index.values
      return [] if have.empty?
      out = []
      cats = catalogs
      begin_stats(cats.length)
      cats.each_with_index do |c, i|
        files = tree_for(c)
        if files.nil?
          break if i == 0   # the first catalog didn't answer: most likely offline
          next
        end
        mine = files.select { |path, _| have.include?(path.split("/", 2)[0]) }
        out.concat(items_in(c, mine, out))
      end
      return out.select { |it| update?(it) && !kif_problem(it) }
    ensure
      end_stats("start-up check")
      updater.hide_status
    end

    #---------------------------------------------------------------------------
    # Network use: trees reused for CACHE_TIME in memory, and on disk while
    # the branch's head commit is the same; mod.json texts by blob sha
    #---------------------------------------------------------------------------
    def begin_stats(n)
      @stats = { :cats => n, :req => 0, :bytes => 0, :hits => 0, :t => Time.now }
    end

    def end_stats(what)
      s = @stats
      return unless s
      @stats = nil
      save_disk if @dirty
      log(format("%s: %d catalogs, %d requests (%s), %.1fs, %d from cache",
                 what, s[:cats], s[:req], updater.size_text(s[:bytes]), Time.now - s[:t], s[:hits]))
    end

    def get(url)
      text = updater.fetch(url)
      if text && text.bytesize > MAX_TEXT
        log("#{url}: #{text.bytesize} bytes, more than a catalog file is; dropped")
        text = nil
      end
      if @stats
        @stats[:req] += 1
        @stats[:bytes] += text.to_s.bytesize
      end
      KIF.verbose("Mods catalog: #{url}: #{text ? "#{text.to_s.bytesize} bytes" : 'no answer'}")
      return text
    end

    def hit(what)
      @stats[:hits] += 1 if @stats
      KIF.verbose("Mods catalog: #{what} from cache")
    end

    def disk_path; return File.join(KIF.save_dir, DISK_CACHE); end

    # {:trees => {catalog key => [head sha, files]}, :json => {blob sha => text}};
    # a missing or broken file is an empty cache
    def disk
      return @disk if @disk
      d = begin
            File.file?(disk_path) ? File.open(disk_path, "rb") { |f| Marshal.load(f) } : nil
          rescue StandardError
            log("cache file unreadable, ignored")
            nil
          end
      d = nil unless d.is_a?(Hash) && d[:trees].is_a?(Hash) && d[:json].is_a?(Hash)
      @disk = d || { :trees => {}, :json => {} }
      return @disk
    end

    # only today's catalogs and the mod.json texts their trees still list
    def save_disk
      @dirty = false
      d = disk
      keys = catalogs.map(&:key)
      d[:trees].select! { |k, v| keys.include?(k) && v.is_a?(Array) && v[1].is_a?(Hash) }
      live = {}
      d[:trees].each_value { |_head, files| files.each_value { |sha, _size| live[sha] = true } }
      d[:json].select! { |sha, _| live[sha] }
      tmp = disk_path + ".tmp"
      File.open(tmp, "wb") { |f| Marshal.dump(d, f) }
      File.rename(tmp, disk_path)
    rescue StandardError => e
      log("cache not saved (#{e.class}: #{e.message})")
    end

    # rel path => [sha, size] for a catalog
    def tree_for(cat, force = false)
      return local_tree(cat.path) if cat.local?
      @trees ||= {}
      at, files = @trees[cat.key]
      if !force && at && Time.now - at < CACHE_TIME
        hit("#{cat.name} file list")
        return files
      end
      head = get(cat.ref_url).to_s[/"object"\s*:\s*\{[^}]*?"sha"\s*:\s*"([0-9a-f]{40})"/, 1]
      # no answer (offline, rate limited): the big list wouldn't come either
      return nil unless head
      pin(cat, head)
      old = disk[:trees][cat.key]
      if old.is_a?(Array) && old[0] == head && old[1].is_a?(Hash) && old[1].length <= MAX_TREE_FILES
        hit("#{cat.name} file list (#{head[0, 7]})")
        files = filter_tree(cat, old[1])   # saved by an older KIF: its file names are checked now
      else
        files = remote_tree(cat, cat.tree_url(head))
        return nil unless files
        disk[:trees][cat.key] = [head, files]
        @dirty = true
      end
      @trees[cat.key] = [Time.now, files]
      return files
    end

    # a catalog's small json file: from the cache when its blob sha is known
    def cached_text(cat, info, url)
      sha, size = info
      return updater.fetch(url) if cat.local?   # file:// catalogs: as before
      if (text = disk[:json][sha])
        hit(url)
        return text
      end
      text = get(url)
      return nil unless text
      # the branch may have moved since the list was read, or the answer was changed on the way: not used
      unless blob_ok?(text, sha, size)
        log("#{url} isn't the file the catalog's list names; not used")
        return nil
      end
      disk[:json][sha] = text
      @dirty = true
      return text
    end

    # text is that blob (the branch may have moved since the tree was read)
    def blob_ok?(text, sha, size)
      t = text.to_s.b
      return false unless t.bytesize == size
      return true unless updater.sha_ok?
      return Digest::SHA1.hexdigest("blob #{t.bytesize}\0".b + t) == sha
    end

    # the mods of one catalog (one already listed by an earlier catalog is
    # skipped)
    def items_in(cat, files, before = [])
      by_folder = {}
      files.each do |path, info|
        top, rest = path.split("/", 2)
        next if rest.nil? || top.start_with?(".") || SKIP.include?(top) || rest.split("/").any? { |s| JUNK.include?(s) }
        next if KIF::Mods::SKIP_DIRS.any? { |d| d.casecmp?(top) } || File.basename(rest) =~ RESERVED   # not a mod's folder; KIF's own lists
        (by_folder[top] ||= {})[rest] = info
      end
      out = []
      folders = by_folder.keys.select { |f| by_folder[f].has_key?("mod.json") }.sort_by(&:downcase)
      folders.each_with_index do |f, i|
        status(_INTL("Reading the mod list"), _INTL("{1}: {2} of {3}", cat.name, i + 1, folders.length), (i + 1).to_f / folders.length)
        next log("#{cat.name}: #{f}/mod.json is #{by_folder[f]['mod.json'][1]} bytes, over #{MAX_JSON}; skipped") if by_folder[f]["mod.json"][1].to_i > MAX_JSON
        text = cached_text(cat, by_folder[f]["mod.json"], updater.url_for(cat.base, "#{f}/mod.json"))
        json = text ? (KIF::Mods::MiniJSON.parse(KIF::PixelFont.utf8(text).sub(/\A﻿/, "")) rescue nil) : nil
        next log("#{cat.name}: #{f}/mod.json unreadable") unless json.is_a?(Hash)
        it = Item.new(f, json, by_folder[f], cat)
        next log("#{cat.name}: #{f}/mod.json has an id KIF won't use; skipped") unless plain_id?(it.id)
        if (twin = (before + out).find { |o| o.id == it.id || o.folder == it.folder })
          log("#{cat.name}: #{it.id} is also in #{twin.catalog ? twin.catalog.name : 'KIF-Mods'} - that one is used")
          next
        end
        out << it
      end
      return out
    end

    # the modpacks of one catalog (one already listed by an earlier catalog
    # is skipped)
    def packs_in(cat, files, before = [])
      folders = files.keys.map { |p| p =~ %r{\Amodpacks/([^/]+)/modpack\.json\z} ? $1 : nil }.compact.sort_by(&:downcase)
      out = []
      folders.each do |f|
        next log("#{cat.name}: modpacks/#{f}/modpack.json is over #{MAX_JSON} bytes; skipped") if files["modpacks/#{f}/modpack.json"][1].to_i > MAX_JSON
        text = cached_text(cat, files["modpacks/#{f}/modpack.json"], updater.url_for(cat.base, "modpacks/#{f}/modpack.json"))
        json = text ? (KIF::Mods::MiniJSON.parse(KIF::PixelFont.utf8(text).sub(/\A\uFEFF/, "")) rescue nil) : nil
        next log("#{cat.name}: modpacks/#{f}/modpack.json unreadable") unless json.is_a?(Hash) && json["mods"].is_a?(Array)
        pk = KIF::ModPacks::Pack.new(f, json, cat)
        next if (before + out).any? { |o| o.id == pk.id }
        out << pk
      end
      return out
    end

    # rel path => [sha, size], from GitHub's tree listing
    def remote_tree(cat = nil, url = nil)
      cat ||= catalogs[0]
      status(_INTL("Reading the mod list"), _INTL("Contacting GitHub ({1})...", cat.name))
      text = get(url || cat.tree_url)
      return nil unless text
      text = text.to_s.dup.force_encoding("UTF-8").scrub("?")   # a broken byte makes a path that is refused below
      out = {}
      bad = {}
      # GitHub sends this list on one line or spread over many (a new repo
      # got the second), so spaces between the parts don't matter
      text.scan(/\{\s*"path"\s*:\s*"((?:[^"\\]|\\.)*)"\s*,\s*"mode"\s*:\s*"(\d+)"\s*,\s*"type"\s*:\s*"blob"\s*,\s*"sha"\s*:\s*"([0-9a-f]{40})"\s*,\s*"size"\s*:\s*(\d+)/) do |p, mode, sha, size|
        if out.length + bad.length >= MAX_TREE_FILES
          log("#{cat.name}: more than #{MAX_TREE_FILES} files listed; the catalog isn't read")
          return nil
        end
        path = unescape(p)
        # a link (120000) or a submodule (160000) can point out of the mod's folder: the whole mod is left out
        if mode == "120000" || mode == "160000"
          bad[unsafe_scope(path)] = path
          next
        end
        unless KIF.safe_rel_path?(path)
          bad[unsafe_scope(path)] = path
          next
        end
        out[path] = [sha, size.to_i]
      end
      if text =~ /"truncated"\s*:\s*true/
        log("tree listing was cut short by GitHub")
        return nil   # a partial list would offer mods with missing files
      end
      drop_unsafe(cat, out, bad)
      return out.empty? ? nil : out
    end

    # a file list without the mods that have a file name KIF won't write
    def filter_tree(cat, files)
      bad = {}
      files.each_key { |p| bad[unsafe_scope(p)] = p unless KIF.safe_rel_path?(p) }
      return files if bad.empty?
      out = files.dup
      drop_unsafe(cat, out, bad)
      return out
    end

    # the mod (or modpack) an unsafe path belongs to
    def unsafe_scope(path)
      parts = path.split("/", 3)
      return (parts[0] == "modpacks" ? parts[0, 2] : parts[0, 1]).join("/")
    end

    # A mod with a file KIF won't write is left out whole: the rest of it would be a broken mod
    def drop_unsafe(cat, out, bad)
      bad.each do |scope, path|
        log("#{cat.name}: #{scope.inspect[0, 60]} has a file or link KIF won't install (#{path.inspect[0, 80]}); left out")
        out.delete_if { |p, _| p == scope || p.start_with?(scope + "/") } unless scope.empty?
      end
    end

    def unescape(s)
      s = s.gsub(/\\u(d[89ab][0-9a-f]{2})\\u(d[c-f][0-9a-f]{2})/i) { [0x10000 + (($1.hex - 0xD800) << 10) + ($2.hex - 0xDC00)].pack("U") }   # an emoji, as GitHub may write it
      return s.gsub(/\\u([0-9a-fA-F]{4})/) { [$1.hex].pack("U") }.gsub(/\\(["\\\/])/, '\1')
    end

    def local_tree(dir)
      out = {}
      bad = {}
      # base: keeps the folder out of the pattern: in a typed path like
      # D:\Mods\Catalog the backslashes (and any [ ] { }) are glob syntax, so
      # nothing was found (2026-10-22)
      Dir.glob(File.join("**", "*"), File::FNM_DOTMATCH, base: dir).each do |rel|
        p = File.join(dir, rel)
        rel = rel.tr("\\", "/")
        next if rel.split("/").any? { |seg| seg == ".git" }
        next bad[unsafe_scope(rel)] = rel if File.symlink?(p)   # a link can point out of the mod's folder
        next unless File.file?(p)
        next bad[unsafe_scope(rel)] = rel unless KIF.safe_rel_path?(rel)
        out[rel] = [updater.sha_ok? ? updater.git_sha(p) : "", File.size(p)]
      end
      drop_unsafe(Catalog.new(nil, nil, nil, dir), out, bad)
      return out
    end

    def status(title, line, frac = nil)
      updater.status(title, line, frac)
    end

    #---------------------------------------------------------------------------
    # What is installed
    #---------------------------------------------------------------------------
    # Mods folders, the one whose copy loads first: the save folder's on a
    # phone, as in KIF::Mods (a read-only game folder's mod is updated there)
    def mod_dirs
      return KIF::Mods.extra_folders + [mods_dir]
    end

    # the installed copy's folder: the catalog's folder name when it holds
    # this mod (the copy that loads), then the mod's id among mods that load,
    # so an update lands on the copy the player has even when they renamed
    # its folder, and never on a switched-Off or "_" copy of it beside the
    # live one (a backup, a template). A folder name can hold another mod
    # in the other Mods folder on a phone.
    def folder_of(item)
      d = mod_dirs.find do |x|
        j = File.join(x, item.folder.to_s, "mod.json")
        id = File.file?(j) ? (KIF::Mods.read_json(j) || {}).fetch("id", item.id) : nil
        id.to_s == item.id
      end
      return File.join(d, item.folder) if d
      c = installed_index[item.id]
      return File.join((@installed_in || {})[item.id] || mods_dir, c) if c
      return File.join(mod_dirs.first, item.folder)   # a new install: the save folder's Mods when the game folder is read-only
    end

    # mod id => folder of the mods that load, read once (cleared on load and
    # after an install); also the save folder's Mods when the game folder is
    # read-only (phones)
    def installed_index
      return @installed_index if @installed_index
      @installed_index = {}
      @installed_in = {}   # mod id => the Mods folder it is in (a folder name can be in both)
      mod_dirs.each do |dir|
        next unless File.directory?(dir)
        Dir.children(dir).sort.each do |c|
          next if c.start_with?(".", "_") || KIF::Mods::SKIP_DIRS.include?(c) || KIF::Mods.disabled.include?(c)
          j = File.join(dir, c, "mod.json")
          next unless File.file?(j)
          id = ((KIF::Mods.read_json(j) || {})["id"] || c).to_s
          next if @installed_index[id]
          @installed_index[id] = c
          @installed_in[id] = dir
        end
      end
      return @installed_index
    end

    # the mod.json of the installed copy
    def installed_json(item)
      j = File.join(folder_of(item), "mod.json")
      return nil unless File.file?(j)
      json = KIF::Mods.read_json(j) || {}
      return other_mod?(json, item) ? nil : json   # another mod's folder is not this mod installed
    end

    # the mod.json of item's folder is a different mod's: another id, and the folder
    # wasn't installed from a catalog (.kif_installed) - a hand-made mod, say, that
    # has the catalog mod's folder name
    def other_mod?(json, item)
      return json.key?("id") && json["id"].to_s != item.id && !File.file?(File.join(folder_of(item), RECORD))
    end

    def size_label(item)
      return updater.size_text(item.size)
    end

    def installed?(item)
      return !installed_json(item).nil?
    end

    def installed_version(item)
      j = installed_json(item)
      return j ? j["version"].to_s : nil
    end

    def update?(item)
      v = installed_version(item)
      return false if v.nil?
      return updater.newer?(item.version, v) if v =~ /\A\d+(\.\d+)*/ && item.version =~ /\A\d+(\.\d+)*/
      return false
    end

    def updates
      return (@items || []).select { |it| update?(it) }
    end

    # where a file of the mod lives once installed (game folder for assets)
    # every file stays in the mod's folder; its pictures / sounds are found
    # there by KIF::ModAssets (Cody, 2026-10-20: nothing is copied into the game)
    def dest_for(item, rel)
      return File.join(folder_of(item), rel)
    end

    def asset?(rel)
      return ASSET_DIRS.include?(rel.split("/", 2)[0])
    end

    def record(item)
      return record_at(folder_of(item))
    end

    def record_at(folder)
      p = File.join(folder, RECORD)
      return {} unless File.file?(p)
      out = {}
      File.read(p).split(/\r?\n/).each do |l|
        sha, rel = l.split(" ", 2)
        out[rel] = sha if rel
      end
      return out
    rescue StandardError
      return {}
    end

    #---------------------------------------------------------------------------
    # Installing and updating
    #---------------------------------------------------------------------------
    # the mod and what it needs that isn't installed, needed ones first
    def install_list(item)
      out = []
      missing = []
      visit = lambda do |it, stack|
        it.dependencies.each do |d|
          next if stack.include?(d)
          dep = find(d)
          if dep.nil?
            missing << d unless installed_id?(d) || missing.include?(d)
            next
          end
          visit.call(dep, stack + [it.id]) unless installed?(dep) || out.include?(dep)
        end
        out << it unless out.include?(it)
      end
      visit.call(item, [])
      return [out, missing]
    end

    def installed_id?(id)
      dirs = ([mods_dir] + KIF::Mods.extra_folders).select { |d| File.directory?(d) }
      return false if dirs.empty?
      return true if dirs.any? { |d| File.directory?(File.join(d, id)) }
      return KIF::Mods.entries.any? { |e| e.id == id || e.name == id } rescue false
    end

    # why a catalog mod wouldn't start on this KIF, or nil
    def kif_problem(item)
      spec = item.requires_kif
      return nil if KIF::ModRules.version_ok?(spec)
      return _INTL("Needs {1} (this is KIF {2}).", KIF::ModRules.version_text(spec), KIF::ModRules.kif_version)
    end

    # installed mods this one says it doesn't work with
    def conflicts(item)
      return item.incompatible.select { |id| (find(id) && installed?(find(id))) || installed_id?(id) }
    end

    # files to download for item: everything (new install) or what changed
    def plan(item)
      item.files.map { |rel, (sha, size)| [rel, sha, size] }.reject do |rel, sha, size|
        updater.good_file?(dest_for(item, rel), sha, size)
      end
    end

    # why each mod of the last install() failed: mod name => :net, :space, :write,
    # :limits (too many or too big files), :clash (another mod's folder) or :needs
    # (a mod it needs failed)
    def failures; return @failures || {}; end

    # a mod with more files, or bigger ones, than any real mod has
    def too_big?(item)
      return item.files.length > MAX_MOD_FILES || item.size > MAX_MOD_BYTES ||
             item.files.values.any? { |_sha, size| size.to_i > MAX_MOD_FILE }
    end

    # the folder it would install into holds a different mod
    def clash?(item)
      j = File.join(folder_of(item), "mod.json")
      return File.file?(j) && other_mod?(KIF::Mods.read_json(j) || {}, item)
    end

    # Installs or updates every mod in list. Returns [done, failed names, :cancelled or nil].
    # Nothing is left half installed: the files are downloaded into the staging
    # folder first, then moved in all together (move_in puts everything back if
    # one move fails), and no error reaches the screen as a crash.
    def install(list, ask = nil)
      stage = File.join(updater.stage_root, "mods")
      done = []
      failed = []
      failed_items = []
      @failures = {}
      mark = lambda do |item, why|
        failed << item.name
        failed_items << item
        @failures[item.name] = why
      end
      list.each_with_index do |item, i|
        if item.dependencies.any? { |d| failed_items.any? { |f| f.id == d || f.folder == d } }
          log("#{item.folder}: not installed, a mod it needs failed")
          mark.call(item, :needs)
          next
        end
        if too_big?(item)
          log("#{item.folder}: not installed, more files or bytes than a mod has (#{item.files.length} files, #{updater.size_text(item.size)})")
          mark.call(item, :limits)
          next
        end
        if clash?(item)
          log("#{item.folder}: not installed, #{folder_of(item)} holds a different mod")
          mark.call(item, :clash)
          next
        end
        dir = File.join(stage, item.folder)
        title = list.length > 1 ? _INTL("Installing {1} ({2} of {3})", item.name, i + 1, list.length) : _INTL("Installing {1}", item.name)
        begin
          todo = plan(item)
          unless todo.empty?
            bad = updater.download(updater.url_for(item.base, item.folder), todo, dir, item.version, title)
            if bad == :cancelled
              updater.hide_status
              log("#{item.folder}: cancelled")
              return [done, failed, :cancelled]
            end
            unless bad.empty?
              log("#{item.folder}: #{bad.length} files didn't download (#{bad.first(3).join(', ')})")
              mark.call(item, :net)
              next
            end
          end
          # what is about to be installed is read before it is moved in: nothing of it has run, and a No leaves everything as it was
          consent = nil
          if ask && !todo.empty? && defined?(KIF::ModCheck) && File.directory?(File.join(dir, "files"))
            rep = KIF::ModCheck.scan(File.join(dir, "files"), item.json)
            consent = ask.call(item, rep)
            unless consent
              log("#{item.folder}: not installed, the player said no after the check (#{rep.color})")
              updater.rm_tree(dir) if File.directory?(dir)
              mark.call(item, :declined)
              next
            end
          end
          move_in(item, todo, dir)
          # the player was asked about what it does and said yes: it is not held again at the next start
          KIF::ModTrust.accept_folder(item.folder) if consent == :accepted && defined?(KIF::ModTrust)
          done << item
          log("#{item.folder} #{item.version} installed (#{todo.length} files)")
        rescue StandardError => e
          log("#{item.folder}: not installed (#{e.class}: #{e.message})")
          mark.call(item, e.is_a?(Errno::ENOSPC) ? :space : :write)
        end
        updater.rm_tree(dir) if File.directory?(dir)   # a download that came up short skipped this line: it stays for next time
      end
      updater.hide_status
      return [done, failed, nil]
    end

    GAME_COPY = ".kif_game"   # older KIF: a game file a mod's file replaced, kept to put back

    # rel is one of the game's own files (the installed update manifest)
    def game_file?(rel)
      m = (updater.local_manifest rescue nil)
      return m ? m.files.has_key?(rel) : false
    end

    # Once, for mods an older KIF installed: their pictures / sounds were
    # copied into the game's folders (listed in .installed_assets) and a game
    # file they replaced was kept as <file>.kif_game. Now they move into the
    # mod's own folder and the game's files come back. A file that isn't the
    # mod's any more (a KIF update or the player changed it) stays.
    def migrate_copied_assets(mods_dir)
      Dir.glob(File.join(mods_dir, "*", ASSETS)).each do |marker|
        folder = File.dirname(marker)
        rec = record_at(folder)
        moved = back = left = 0
        File.read(marker).split(/\r?\n/).map(&:strip).each do |rel|
          next if rel.empty? || !KIF.safe_rel_path?(rel) || !asset?(rel)
          game = File.join(root, rel)
          mine = File.join(folder, rel)
          keep = game + GAME_COPY
          ours = File.file?(game) && (rec[rel].nil? || !updater.sha_ok? || updater.git_sha(game) == rec[rel])
          if ours && !File.exist?(mine) && (File.file?(keep) || !game_file?(rel))
            updater.mkdir_p(File.dirname(mine))
            File.rename(game, mine)
            moved += 1
          elsif ours && File.file?(keep)
            File.delete(game)   # the mod has its own copy already
            moved += 1
          elsif ours
            left += 1   # replaced by a KIF before 0.21.62, no copy kept: a KIF update brings the game's back
          end
          if File.file?(keep)
            if File.file?(game)
              File.delete(keep)   # a newer game file is there: it stays
            else
              File.rename(keep, game)
              back += 1
            end
          end
        end
        File.delete(marker)
        log("#{File.basename(folder)}: #{moved} files moved into the mod, #{back} game files back" + (left > 0 ? ", #{left} game files still the mod's (no copy was kept)" : ""))
      rescue StandardError => e
        log("#{File.basename(folder.to_s)}: couldn't tidy the copied files (#{e.class}: #{e.message}); tried again next start")
      end
    end

    # All or nothing. Every staged file is checked first; then each old file is
    # moved aside (not deleted) and the new one moved in, and the old copies
    # and the files the mod dropped are only removed once every file and the
    # mod's list (.kif_installed) are in. If anything fails on the way, the
    # old files come back, new files go, and a folder this install made is
    # removed: an existing working mod is never left half updated, a new one
    # never half there. (A game closed in the middle of the moves is not
    # covered: mod.json is moved last, so the mod then still shows its old
    # version, or none, and the install is offered again.)
    def move_in(item, todo, dir)
      folder = folder_of(item)
      fresh = !File.exist?(folder)
      old = record(item)
      todo.each do |rel, _sha, _size|
        src = updater.staged(dir, rel)
        raise Errno::ENOENT, "downloaded file missing: #{rel}" unless File.file?(src)
      end
      updater.mkdir_p(folder)
      moved = []   # [new file, its old copy set aside or nil]
      begin
        # mod.json last: its version is what says the mod is installed
        todo = todo.sort_by { |rel, _, _| rel == "mod.json" ? 1 : 0 }
        todo.each do |rel, _sha, _size|
          src = updater.staged(dir, rel)
          dest = dest_for(item, rel)
          updater.mkdir_p(File.dirname(dest))
          aside = dest + ".kif_old"
          File.delete(aside) if File.file?(aside)
          had = File.file?(dest)
          File.rename(dest, aside) if had
          begin
            File.rename(src, dest)
          rescue StandardError
            File.rename(aside, dest) if had && File.file?(aside) && !File.file?(dest)
            raise
          end
          moved << [dest, had ? aside : nil]
        end
        rec_path = File.join(folder, RECORD)
        File.open(rec_path + ".tmp", "wb") do |f|
          item.files.sort.each { |rel, (sha, _size)| f.write("#{sha} #{rel}\r\n") }
        end
        File.rename(rec_path + ".tmp", rec_path)
      rescue StandardError
        put_back(moved, folder, fresh)
        raise
      end
      write_provenance(item, folder)
      # done: the old copies go, and the files the mod no longer has when they're still as installed
      moved.each { |_dest, aside| (File.delete(aside) rescue nil) if aside }
      old.each do |rel, sha|
        next if item.files.has_key?(rel) || !KIF.safe_rel_path?(rel)
        p = dest_for(item, rel)
        next unless File.file?(p)
        # a file that can't be checked is kept: it may be the player's edit
        (File.delete(p) if updater.sha_ok? && updater.git_sha(p) == sha) rescue nil
      end
      KIF::Mods.sources.each { |s| s.instance_variable_set(:@entries, nil) if s.is_a?(KIF::Mods::NativeSource) }
      @installed_index = nil
    end

    # Where the mod's files came from, next to the list of what was installed (.kif_provenance):
    # the catalog, the commit, the date and every file's git hash. The mod check compares them
    # again at each start; a file that no longer matches reads "Changed since it was installed".
    def write_provenance(item, folder)
      cat = item.catalog
      pr = { "repo" => (cat.nil? ? REPO : (cat.local? ? "local" : cat.repo)), "branch" => (cat && !cat.local? ? cat.branch : ""),
             "commit" => item.commit.to_s, "installed" => Time.now.strftime("%Y-%m-%d"), "kif" => KIF::ModRules.kif_version,
             "verified" => updater.sha_ok? ? true : false, "files" => item.files.sort.map { |rel, (sha, _size)| [rel, sha] }.to_h }
      path = File.join(folder, PROVENANCE)
      File.open(path + ".tmp", "wb") { |f| f.write(KIF::ModPublish.to_json(pr)) }
      File.rename(path + ".tmp", path)
    rescue StandardError => e
      log("#{item.folder}: provenance not written (#{e.class}: #{e.message})")
      (File.delete(path + ".tmp") rescue nil)
    end

    # undoes the moves of a failed move_in, last first
    def put_back(moved, folder, fresh)
      moved.reverse_each do |dest, aside|
        begin
          File.delete(dest) if File.file?(dest)
          File.rename(aside, dest) if aside && File.file?(aside)
        rescue StandardError => e
          log("couldn't put #{dest} back (#{e.class}: #{e.message})")
        end
      end
      (File.delete(File.join(folder, RECORD) + ".tmp") rescue nil)
      updater.rm_tree(folder) if fresh
    end
  end
end

#===============================================================================
# The questions and messages around an install or update
#===============================================================================
module KIF
  module ModCatalogUI
    module_function

    def cat; return KIF::ModCatalog; end

    # USE on a mod in Browse: Install / Update, Read description
    def menu(item)
      cmds = [_INTL("Read description"), _INTL("Cancel")]
      if cat.update?(item)
        cmds.unshift(_INTL("Update"))
      elsif !cat.installed?(item)
        cmds.unshift(_INTL("Install"))
      end
      cmd = pbMessage(KIF::PixelFont.utf8(item.name), cmds, cmds.length)
      return if cmd < 0 || cmd == cmds.length - 1
      cmd == cmds.length - 2 ? KIF::ModReadme.show_catalog(item) : install(item)
    end

    def install(item)
      updating = cat.update?(item)
      if cat.installed?(item) && !updating
        pbMessage(_INTL("{1} is installed (v{2}). Switch it On or Off under Installed.", item.name, cat.installed_version(item)))
        return
      end
      why = cat.kif_problem(item)
      if why
        pbMessage(_INTL("{1} won't start on this KIF. {2}", item.name, why))
        return
      end
      list, missing = cat.install_list(item)
      unless missing.empty?
        pbMessage(_INTL("{1} needs {2}, which isn't in the catalog. Install that first.", item.name, missing.join(", ")))
        return
      end
      if (big = list.find { |it| cat.too_big?(it) })
        pbMessage(_INTL("{1} is bigger than a mod can be here, so it isn't installed.", big.name))
        return
      end
      if (other = list.find { |it| cat.clash?(it) })
        pbMessage(_INTL("The Mods folder \"{1}\" already holds a different mod, so {2} isn't installed. Rename or remove that folder first.", other.folder, other.name))
        return
      end
      bad = cat.conflicts(item)
      unless bad.empty?
        names = bad.map { |id| (f = cat.find(id)) ? f.name : id }
        return unless pbConfirmMessage(_INTL("{1} doesn't work with {2}, which you have. Install it anyway?", item.name, names.join(", ")))
      end
      bytes = list.inject(0) { |s, it| s + cat.plan(it).inject(0) { |t, f| t + f[2] } }
      q = if updating
            _INTL("Update {1} to v{2} ({3})? Your settings are kept.", item.name, item.version, KIF::Updater.size_text(bytes))
          elsif list.length > 1
            _INTL("Install {1} ({2})? It also needs {3}, which will be installed too.", item.name,
                  KIF::Updater.size_text(bytes), list[0...-1].map(&:name).join(", "))
          else
            _INTL("Install {1} ({2})?", item.name, KIF::Updater.size_text(bytes))
          end
      sec = defined?(KIF::ModSecurityUI) ? KIF::ModSecurityUI.catalog_lines(item) : ""
      q = "#{q} #{sec}" unless sec.empty?
      return unless pbConfirmMessage(KIF::PixelFont.utf8(q))
      run(list)
    end

    def update_all
      ups = cat.updates.reject { |it| cat.kif_problem(it) }
      return if ups.empty?
      bytes = ups.inject(0) { |s, it| s + cat.plan(it).inject(0) { |t, f| t + f[2] } }
      return unless pbConfirmMessage(_INTL("Update {1} mods ({2})? Their settings are kept.", ups.length, KIF::Updater.size_text(bytes)))
      run(ups)
    end

    # a modpack or a share code: installs the mods from it the player
    # doesn't have and updates the ones older than it wants
    def install_set(title, wanted)
      p = KIF::ModPacks.plan(wanted)
      notes = []
      notes << _INTL("Not in any catalog: {1}.", p[:missing].join(", ")) unless p[:missing].empty?
      notes << _INTL("Won't start on this KIF: {1}.", p[:wont].join(", ")) unless p[:wont].empty?
      off = p[:off].empty? ? nil : _INTL("Installed but Off: {1}. Switch them On under Installed.", p[:off].join(", "))
      if p[:list].empty?
        pbMessage(KIF::PixelFont.utf8(([_INTL("You have every mod from {1} that the catalogs have.", title)] + notes + [off].compact).join(" ")))
        return
      end
      pbMessage(KIF::PixelFont.utf8(notes.join(" "))) unless notes.empty?
      fresh = p[:list].count { |it| !cat.installed?(it) }
      ups = p[:list].length - fresh
      bytes = p[:list].inject(0) { |s, it| s + cat.plan(it).inject(0) { |t, f| t + f[2] } }
      size = KIF::Updater.size_text(bytes)
      q = if ups == 0
            _INTL("Install {1} mods from {2} ({3})?", fresh, title, size)
          elsif fresh == 0
            _INTL("Update {1} mods for {2} ({3})? Their settings are kept.", ups, title, size)
          else
            _INTL("Install {1} mods and update {2} for {3} ({4})?", fresh, ups, title, size)
          end
      return unless pbConfirmMessage(KIF::PixelFont.utf8(q))
      run(p[:list])
      pbMessage(KIF::PixelFont.utf8(off)) if off
    end

    def install_pack(pk)
      install_set(pk.name, pk.mods)
    end

    # Share Code tab: copy a code for the mods that are On
    def share_export
      list = KIF::ModPacks.mine
      return pbMessage(_INTL("No mods are On, so there's nothing to share.")) if list.empty?
      code = KIF::ModPacks.encode(list)
      copied = begin
                 Input.clipboard = code
                 true
               rescue StandardError, NameError
                 false
               end
      shown = KIF::ModPacks.spaced(code)
      if copied
        pbMessage(_INTL("Copied the code for your {1} mods. Paste it to share it:\n{2}", list.length, shown))
      else
        pbMessage(_INTL("Your code for {1} mods (copying didn't work, so write it down):\n{2}", list.length, shown))
      end
      KIF.log("Mods: share code for #{list.length} mods copied#{copied ? '' : ' (clipboard failed)'}")
    end

    # Share Code tab: a code someone copied (clipboard, or typed in)
    def share_import
      clip = (Input.clipboard.to_s rescue "")
      code = clip.strip =~ /\AKIFr?-/ ? clip : nil
      code ||= pbMessageFreeText(_INTL("Type the share code (it starts with KIF-)."), "", false, 500)
      return if code.nil? || code.strip.empty?
      list = KIF::ModPacks.decode(code)
      return pbMessage(_INTL("That isn't a share code. Codes start with KIF-.")) unless list
      cat.load if cat.items.nil?
      return pbMessage(cat.error || _INTL("Couldn't reach the mod catalog. Check the internet connection and try again.")) if cat.items.nil?
      KIF.log("Mods: share code with #{list.length} mods: #{list.map(&:first).join(', ')}")
      install_set(_INTL("the share code"), list)
    end

    # load screen, right after KIF's own update check (Cody, 2026-10-20);
    # nothing when Updates is Off or the catalogs don't answer
    def startup_check
      return false unless cat.available? && KIF::Updater.channel != 2
      ups = cat.startup_updates
      return false if ups.empty?
      cat.log("updates at start-up: #{ups.map { |it| "#{it.id} #{it.version}" }.join(', ')}")
      if by_hand?   # once per set of new versions
        told = ups.map { |it| "#{it.id} #{it.version}" }.sort.join(";")
        return false if KIF::Updater.stored_choices["phone_mods_told"] == told
        KIF::Updater.store_choice("phone_mods_told", told)
        phone_notice(ups)
        return false
      end
      q = ups.length == 1 ? _INTL("An update for 1 mod. Open Mods > Updates?") : _INTL("Updates for {1} mods. Open Mods > Updates?", ups.length)
      return false unless pbMessage(q, [_INTL("Yes"), _INTL("Later")], 2) == 0
      KIF::SettingsScreen.mods_view = KIF::SettingsScreen::VIEWS.index(:updates)
      pbFadeOutIn { KifSettingsScreen.new(true, :mods).main }
      return true
    rescue StandardError => e
      cat.log("start-up check failed (#{e.class}: #{e.message})")
      return false
    end

    # A phone whose game folder can't be written (JoiPlay's usually can):
    # nothing is downloaded or installed; the player is told what's new and
    # updates mods by hand
    def by_hand?
      return KIF.mobile? && !KIF::Paths.game_writable?
    end

    def phone_notice(list)
      pbMessage(KIF::PixelFont.utf8(_INTL("New mod versions: {1}.", list.map { |it| "#{it.name} #{it.version}" }.join(", "))))
      pbMessage(_INTL("On phones, mods are installed and updated by hand: download the mod and put its folder in the Mods folder."))
    end

    # After the download, before anything is moved in: a mod that does more than it says, is red or
    # was withdrawn is asked about once (default No). An update asks only about what is new.
    def review(item, rep)
      return true unless defined?(KIF::ModSecurityUI) && KIF::ModSecurityUI.active?
      reasons = KIF::ModSecurityUI.install_reasons(item, rep)
      return true if reasons.empty?
      text = _INTL("{1} does more than it says: {2} Install anyway?", item.name, reasons.join(" "))
      return pbMessage(KIF::PixelFont.utf8(text), [_INTL("No"), _INTL("Install anyway")], 1) == 1 ? :accepted : false
    end

    def run(list)
      return phone_notice(list) if by_hand?
      done, failed, cancelled = cat.install(list, method(:review))
      if cancelled
        pbMessage(_INTL("Stopped. Nothing half-downloaded was installed."))
      elsif !failed.empty?
        why = cat.failures
        groups = failed.group_by { |n| why[n] || :net }
        {
          :net => _INTL("{1} couldn't be downloaded. Check the internet connection and try again."),
          :space => _INTL("{1} couldn't be installed: there isn't enough free space. Nothing was changed."),
          :write => _INTL("{1} couldn't be installed: KIF couldn't write its files. Nothing was changed."),
          :limits => _INTL("{1} is bigger than a mod can be here, so it isn't installed."),
          :clash => _INTL("{1} would go into a Mods folder that holds a different mod, so it isn't installed."),
          :declined => _INTL("{1} was not installed, as you chose."),
          :needs => _INTL("{1} needs a mod that couldn't be installed, so it isn't installed.")
        }.each do |key, text|
          names = groups[key]
          pbMessage(KIF::PixelFont.utf8(text.sub("{1}", names.join(", ")))) if names
        end
      end
      unless done.empty?
        pbMessage(_INTL("{1} is ready. It starts working the next time the game starts.", done.map(&:name).join(", ")))
      end
    end
  end
end
