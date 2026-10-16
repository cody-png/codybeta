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
#===============================================================================
module KIF
  module ModCatalog
    REPO       = "KIF-Mods/mods"
    TREE_URL   = "https://api.github.com/repos/#{REPO}/git/trees/main?recursive=1"
    RAW_BASE   = "https://raw.githubusercontent.com/#{REPO}/main"
    SOURCE_FILE = "KIF_mods_source.txt"
    ASSET_DIRS = %w[Graphics Audio Fonts]
    RECORD     = ".kif_installed"
    ASSETS     = ".installed_assets"
    SKIP       = %w[modpacks]
    CACHE_TIME = 600   # seconds a fetched list is reused

    # one mod in the catalog
    class Item
      attr_reader :folder, :json, :files
      def initialize(folder, json, files)
        @folder = folder
        @json = json || {}
        @files = files     # rel path => [sha, size]
      end
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
        return Array(@json["dependencies"]).map { |x| x.is_a?(Hash) ? x["id"].to_s : x.to_s }.reject(&:empty?)
      end
      def incompatible
        return Array(@json["incompatible"]).map { |x| x.is_a?(Hash) ? x["id"].to_s : x.to_s }.reject(&:empty?)
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
      s = source
      return RAW_BASE unless s
      full = File.expand_path(s).tr("\\", "/").sub(%r{\A/}, "")
      return "file:///" + full.split("/").map { |seg| seg.b.gsub(/[^A-Za-z0-9\-._~:]/n) { |c| format("%%%02X", c.ord) } }.join("/")
    end

    def items;   return @items; end
    def checked; return @checked; end
    def error;   return @error; end

    def find(id)
      return nil unless @items
      return @items.find { |it| it.id == id || it.folder == id }
    end

    #---------------------------------------------------------------------------
    # Reading the catalog
    #---------------------------------------------------------------------------
    def load(force = false)
      return @items if @items && !force && @checked && Time.now - @checked < CACHE_TIME
      @error = nil
      files = source ? local_tree(source) : remote_tree
      if files.nil?
        @error = _INTL("Couldn't reach the mod catalog. Check the internet connection and try again.")
        return @items
      end
      by_folder = {}
      files.each do |path, info|
        top, rest = path.split("/", 2)
        next if rest.nil? || top.start_with?(".") || SKIP.include?(top)
        (by_folder[top] ||= {})[rest] = info
      end
      list = []
      folders = by_folder.keys.select { |f| by_folder[f].has_key?("mod.json") }.sort_by(&:downcase)
      folders.each_with_index do |f, i|
        status(_INTL("Reading the mod list"), _INTL("{1} of {2}", i + 1, folders.length), (i + 1).to_f / folders.length)
        text = updater.fetch(updater.url_for(base, "#{f}/mod.json"))
        json = text ? (KIF::Mods::MiniJSON.parse(KIF::PixelFont.utf8(text).sub(/\A﻿/, "")) rescue nil) : nil
        next log("#{f}/mod.json unreadable") unless json.is_a?(Hash)
        list << Item.new(f, json, by_folder[f])
      end
      updater.hide_status
      @items = list
      @checked = Time.now
      log("#{list.length} mods listed")
      return @items
    end

    # rel path => [sha, size], from GitHub's tree listing
    def remote_tree
      status(_INTL("Reading the mod list"), _INTL("Contacting GitHub..."))
      text = updater.fetch(TREE_URL)
      return nil unless text
      text = text.to_s.dup.force_encoding("UTF-8")
      out = {}
      text.scan(/\{"path":"((?:[^"\\]|\\.)*)","mode":"\d+","type":"blob","sha":"([0-9a-f]{40})","size":(\d+)/) do |p, sha, size|
        out[unescape(p)] = [sha, size.to_i]
      end
      log("tree listing was cut short by GitHub") if text.include?('"truncated":true')
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
    def folder_of(item)
      return File.join(mods_dir, item.folder)
    end

    # the mod.json of the installed copy (looked up by folder, then by id)
    def installed_json(item)
      j = File.join(folder_of(item), "mod.json")
      return KIF::Mods.read_json(j) || {} if File.file?(j)
      return nil unless File.directory?(mods_dir)
      Dir.children(mods_dir).each do |c|
        j = File.join(mods_dir, c, "mod.json")
        next unless File.file?(j)
        h = KIF::Mods.read_json(j) || {}
        return h if h["id"].to_s == item.id
      end
      return nil
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
          bad = updater.download(updater.url_for(base, item.folder), todo, dir, item.version, title)
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

    def move_in(item, todo, dir)
      old = record(item)
      updater.mkdir_p(folder_of(item))
      todo.each do |rel, _sha, _size|
        src = updater.staged(dir, rel)
        dest = dest_for(item, rel)
        updater.mkdir_p(File.dirname(dest))
        File.delete(dest) if File.file?(dest)
        File.rename(src, dest)
      end
      # files the mod no longer has: removed when they're still as installed
      old.each do |rel, sha|
        next if item.files.has_key?(rel)
        p = dest_for(item, rel)
        next unless File.file?(p)
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
      list, missing = cat.install_list(item)
      unless missing.empty?
        pbMessage(_INTL("{1} needs {2}, which isn't in the catalog. Install that first.", item.name, missing.join(", ")))
        return
      end
      bad = cat.conflicts(item)
      unless bad.empty?
        return unless pbConfirmMessage(_INTL("{1} doesn't work with {2}, which you have. Install it anyway?", item.name, bad.join(", ")))
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
      ups = cat.updates
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
