#===============================================================================
# Mods catalog – Browse and Updates in Options > KIF Settings > Mods
# The catalog is the KIF-Mods/mods repository on GitHub (the one Mod Manager
# 2.0 reads): one folder per mod with its mod.json. One GitHub API call lists
# every file with its git id and size; the mod.json files come from
# raw.githubusercontent.com. Downloads go through the updater's downloader
# (curl, then a file-by-file fallback) and every file is checked against its
# git id before it is moved in.
#
# Installing: Graphics/, Audio/ and Fonts/ inside a mod go to the game folder
# (listed in the mod's .installed_assets, the file Mod Manager uses too);
# everything else goes to Mods/<folder>/. .kif_installed in the mod folder
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
#===============================================================================
module KIF
  module ModCatalog
    REPO       = "KIF-Mods/mods"
    DISCORD_REPO = "cody-png/kif-discord-mods"   # mods only shared on Discord (made with import_mods.py)
    OWN_REPO     = "cody-png/kif-mods"           # KIF Beta's own mods from now on (Cody, 2026-10-20)
    SOURCE_FILE = "KIF_mods_source.txt"
    CATALOGS_FILE = "KIF_mods_catalogs.txt"
    ASSET_DIRS = %w[Graphics Audio Fonts]
    RECORD     = ".kif_installed"
    ASSETS     = ".installed_assets"
    SKIP       = %w[modpacks]
    CACHE_TIME = 600   # seconds a fetched list is reused

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
      def tree_url; return "https://api.github.com/repos/#{@repo}/git/trees/#{@branch}?recursive=1"; end
      def raw_base; return "https://raw.githubusercontent.com/#{@repo}/#{@branch}"; end
      def base
        return raw_base unless local?
        return KIF::Updater.file_url(@path)
      end
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
      def id;      return (@json["id"] || @folder).to_s; end
      def name;    return KIF::PixelFont.utf8((@json["name"] || @folder).to_s); end
      def version; return @json["version"].to_s; end
      def author;  return KIF::PixelFont.utf8(@json["author"].to_s); end
      def tags;    return Array(@json["tags"]).map { |t| KIF::PixelFont.utf8(t.to_s) }; end
      def size;    return @files.values.inject(0) { |s, (_sha, sz)| s + sz.to_i }; end
      def description
        d = @json["description"]
        d = d.join(" ") if d.is_a?(Array)
        return KIF::PixelFont.utf8(d.to_s)
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
      unless path || repo =~ %r{\A[\w.-]+/[\w.-]+\z}
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
      return nil unless repo =~ %r{\A[\w.-]+/[\w.-]+\z}
      return Catalog.new(repo, branch, name)
    end

    def catalogs
      s = source
      list = [s ? Catalog.new(nil, nil, "KIF-Mods", s) : Catalog.new(REPO, "main", "KIF-Mods")]
      unless s   # a local test source stays alone
        list << Catalog.new(OWN_REPO, "main", "KIF Beta Mods")
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
      cats = catalogs
      cats.each do |cat|
        files = cat.local? ? local_tree(cat.path) : remote_tree(cat)
        if files.nil?
          @failed << cat
          log("#{cat.name}: couldn't be read")
          next
        end
        list.concat(items_in(cat, files, list))
      end
      updater.hide_status
      if list.empty? && !@failed.empty?
        @error = _INTL("Couldn't reach the mod catalog. Check the internet connection and try again.")
        return @items
      end
      @items = list
      @checked = Time.now
      log("#{list.length} mods listed (#{cats.length - @failed.length} of #{cats.length} catalogs)")
      return @items
    end

    # the mods of one catalog (one already listed by an earlier catalog is
    # skipped)
    def items_in(cat, files, before = [])
      by_folder = {}
      files.each do |path, info|
        top, rest = path.split("/", 2)
        next if rest.nil? || top.start_with?(".") || SKIP.include?(top)
        (by_folder[top] ||= {})[rest] = info
      end
      out = []
      folders = by_folder.keys.select { |f| by_folder[f].has_key?("mod.json") }.sort_by(&:downcase)
      folders.each_with_index do |f, i|
        status(_INTL("Reading the mod list"), _INTL("{1}: {2} of {3}", cat.name, i + 1, folders.length), (i + 1).to_f / folders.length)
        text = updater.fetch(updater.url_for(cat.base, "#{f}/mod.json"))
        json = text ? (KIF::Mods::MiniJSON.parse(KIF::PixelFont.utf8(text).sub(/\A﻿/, "")) rescue nil) : nil
        next log("#{cat.name}: #{f}/mod.json unreadable") unless json.is_a?(Hash)
        it = Item.new(f, json, by_folder[f], cat)
        if (twin = (before + out).find { |o| o.id == it.id || o.folder == it.folder })
          log("#{cat.name}: #{it.id} is also in #{twin.catalog ? twin.catalog.name : 'KIF-Mods'} - that one is used")
          next
        end
        out << it
      end
      return out
    end

    # rel path => [sha, size], from GitHub's tree listing
    def remote_tree(cat = nil)
      cat ||= catalogs[0]
      status(_INTL("Reading the mod list"), _INTL("Contacting GitHub ({1})...", cat.name))
      text = updater.fetch(cat.tree_url)
      return nil unless text
      text = text.to_s.dup.force_encoding("UTF-8")
      out = {}
      text.scan(/\{"path":"((?:[^"\\]|\\.)*)","mode":"\d+","type":"blob","sha":"([0-9a-f]{40})","size":(\d+)/) do |p, sha, size|
        path = unescape(p)
        next log("skipped an unsafe file path: #{path}") unless KIF.safe_rel_path?(path)
        out[path] = [sha, size.to_i]
      end
      if text.include?('"truncated":true')
        log("tree listing was cut short by GitHub")
        return nil   # a partial list would offer mods with missing files
      end
      return out.empty? ? nil : out
    end

    def unescape(s)
      return s.gsub(/\\u([0-9a-fA-F]{4})/) { [$1.hex].pack("U") }.gsub(/\\(["\\\/])/, '\1')
    end

    def local_tree(dir)
      out = {}
      Dir.glob(File.join(dir, "**", "*"), File::FNM_DOTMATCH).each do |p|
        next unless File.file?(p)
        rel = p[(dir.length + 1)..-1].tr("\\", "/")
        next if rel.split("/").any? { |seg| seg == ".git" }
        out[rel] = [updater.sha_ok? ? updater.git_sha(p) : "", File.size(p)]
      end
      return out
    end

    def status(title, line, frac = nil)
      updater.status(title, line, frac)
    end

    #---------------------------------------------------------------------------
    # What is installed
    #---------------------------------------------------------------------------
    # the installed copy's folder (by folder name, then by id), so an update
    # lands on the copy the player has even when they renamed its folder
    def folder_of(item)
      own = File.join(mods_dir, item.folder)
      return own if File.file?(File.join(own, "mod.json"))
      c = installed_index[item.id]
      return c ? File.join(mods_dir, c) : own
    end

    # mod id => folder, read once (cleared on load and after an install)
    def installed_index
      return @installed_index if @installed_index
      @installed_index = {}
      return @installed_index unless File.directory?(mods_dir)
      Dir.children(mods_dir).sort.each do |c|
        j = File.join(mods_dir, c, "mod.json")
        next unless File.file?(j)
        id = ((KIF::Mods.read_json(j) || {})["id"] || c).to_s
        @installed_index[id] ||= c
      end
      return @installed_index
    end

    # the mod.json of the installed copy
    def installed_json(item)
      j = File.join(folder_of(item), "mod.json")
      return File.file?(j) ? (KIF::Mods.read_json(j) || {}) : nil
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
    def dest_for(item, rel)
      return File.join(root, rel) if asset?(rel)
      return File.join(folder_of(item), rel)
    end

    def asset?(rel)
      return ASSET_DIRS.include?(rel.split("/", 2)[0])
    end

    def record(item)
      p = File.join(folder_of(item), RECORD)
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
      return false unless File.directory?(mods_dir)
      return true if File.directory?(File.join(mods_dir, id))
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

    # Installs or updates every mod in list. Returns [done, failed names]
    def install(list)
      stage = File.join(updater.stage_root, "mods")
      done = []
      failed = []
      list.each_with_index do |item, i|
        todo = plan(item)
        dir = File.join(stage, item.folder)
        title = list.length > 1 ? _INTL("Installing {1} ({2} of {3})", item.name, i + 1, list.length) : _INTL("Installing {1}", item.name)
        unless todo.empty?
          bad = updater.download(updater.url_for(item.base, item.folder), todo, dir, item.version, title)
          if bad == :cancelled
            updater.hide_status
            log("#{item.folder}: cancelled")
            return [done, failed, :cancelled]
          end
          unless bad.empty?
            log("#{item.folder}: #{bad.length} files didn't download (#{bad.first(3).join(', ')})")
            failed << item.name
            next
          end
        end
        begin
          move_in(item, todo, dir)
          done << item
          log("#{item.folder} #{item.version} installed (#{todo.length} files)")
        rescue StandardError => e
          log("#{item.folder}: couldn't move the files in (#{e.class}: #{e.message})")
          failed << item.name
        end
        updater.rm_tree(dir) if File.directory?(dir)
      end
      updater.hide_status
      return [done, failed, nil]
    end

    GAME_COPY = ".kif_game"   # a game file a mod's asset replaced, kept to put back

    # rel is one of the game's own files (the installed update manifest)
    def game_file?(rel)
      m = (updater.local_manifest rescue nil)
      return m ? m.files.has_key?(rel) : false
    end

    def move_in(item, todo, dir)
      old = record(item)
      updater.mkdir_p(folder_of(item))
      # mod.json last: its version is what says the mod is installed, so a
      # move that fails halfway leaves the old version and is offered again
      todo = todo.sort_by { |rel, _, _| rel == "mod.json" ? 1 : 0 }
      todo.each do |rel, _sha, _size|
        src = updater.staged(dir, rel)
        dest = dest_for(item, rel)
        updater.mkdir_p(File.dirname(dest))
        # a game file replaced by a mod's asset is kept, not deleted
        kept = false
        if asset?(rel) && File.file?(dest) && !File.file?(dest + GAME_COPY) && game_file?(rel)
          File.rename(dest, dest + GAME_COPY)
          kept = true
        end
        # the old file is moved aside, not deleted, until the new one is in:
        # a rename that fails (antivirus still scanning the download) puts it back
        aside = dest + ".kif_old"
        File.delete(aside) if File.file?(aside)
        File.rename(dest, aside) if File.file?(dest)
        begin
          File.rename(src, dest)
        rescue StandardError
          File.rename(aside, dest) if File.file?(aside) && !File.file?(dest)
          File.rename(dest + GAME_COPY, dest) if kept && !File.file?(dest)
          raise
        end
        (File.delete(aside) rescue nil) if File.file?(aside)
      end
      # files the mod no longer has: removed when they're still as installed;
      # a game file it had replaced comes back
      old.each do |rel, sha|
        next if item.files.has_key?(rel)
        p = dest_for(item, rel)
        if File.file?(p + GAME_COPY)
          # a KIF update put a newer game file there since: it stays, the old copy goes
          if File.file?(p) && updater.sha_ok? && updater.git_sha(p) != sha
            File.delete(p + GAME_COPY)
            next
          end
          File.delete(p) if File.file?(p)
          File.rename(p + GAME_COPY, p)
          next
        end
        next unless File.file?(p)
        next if asset?(rel) && game_file?(rel)   # never delete the game's own file
        File.delete(p) if !updater.sha_ok? || updater.git_sha(p) == sha
      end
      File.open(File.join(folder_of(item), RECORD), "wb") do |f|
        item.files.sort.each { |rel, (sha, _size)| f.write("#{sha} #{rel}\r\n") }
      end
      assets = item.files.keys.select { |rel| asset?(rel) }.sort
      if assets.empty?
        File.delete(File.join(folder_of(item), ASSETS)) if File.file?(File.join(folder_of(item), ASSETS))
      else
        File.open(File.join(folder_of(item), ASSETS), "wb") { |f| f.write(assets.join("\n") + "\n") }
      end
      KIF::Mods.sources.each { |s| s.instance_variable_set(:@entries, nil) if s.is_a?(KIF::Mods::NativeSource) }
      @installed_index = nil
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
      return unless pbConfirmMessage(q)
      run(list)
    end

    def update_all
      ups = cat.updates.reject { |it| cat.kif_problem(it) }
      return if ups.empty?
      bytes = ups.inject(0) { |s, it| s + cat.plan(it).inject(0) { |t, f| t + f[2] } }
      return unless pbConfirmMessage(_INTL("Update {1} mods ({2})? Their settings are kept.", ups.length, KIF::Updater.size_text(bytes)))
      run(ups)
    end

    def run(list)
      done, failed, cancelled = cat.install(list)
      if cancelled
        pbMessage(_INTL("Stopped. Nothing half-downloaded was installed."))
      elsif !failed.empty?
        pbMessage(_INTL("{1} couldn't be downloaded. Check the internet connection and try again.", failed.join(", ")))
      end
      unless done.empty?
        pbMessage(_INTL("{1} is ready. It starts working the next time the game starts.", done.map(&:name).join(", ")))
      end
    end
  end
end
