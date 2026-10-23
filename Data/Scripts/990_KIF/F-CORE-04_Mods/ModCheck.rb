#===============================================================================
# F-CORE-04 – the community catalog's mod check, in the game (2026-10-22)
# The same rules as tools/check_mods.rb in the catalog repository
# (cody-png/kif-discord-mods), which checks every pull request: Publish a mod
# (ModPublish.rb) runs them before anything is uploaded, so a modder sees the
# problems first. Same messages, word for word; kit test 401 runs both on the
# same folders and compares.
# Plain Ruby with no game code (only MiniJSON when the engine has no JSON),
# so the catalog's script could load this file instead of keeping a copy.
# When check_mods.rb changes, change this file the same way.
#===============================================================================
module KIF
  module ModCheck
    ID = /\A[a-z0-9][a-z0-9_\-]*\z/
    VERSION = /\A\d+(\.\d+){0,3}([a-z0-9.\-]*)?\z/i
    BLOCKED_EXT = %w[.exe .dll .bat .cmd .ps1 .vbs .msi .scr .com .jar .so .dylib .sh .lnk .zip .7z .rar].freeze
    MAX_FILE = 25 * 1024 * 1024
    MAX_MOD = 100 * 1024 * 1024
    LIST_FIELDS = %w[scripts dependencies load_after incompatible replaces credits].freeze
    REQUIRES = /\A\s*([<>=]=?\s*)?\d+(\.\d+)*(\s*,\s*([<>=]=?\s*)?\d+(\.\d+)*)*\s*\z/
    CATALOG = %r{\A[\w.\-]+/[\w.\-]+(@[\w.\-/]+)?\z}
    # Code a reviewer should read (not forbidden: some mods have a reason)
    RISKY = {
      /\b(system|spawn|exec)\s*[(\s]["'\w]/ => "starts a program",
      /`[^`\n]+`|%x[({\[]/ => "starts a program (backticks)",
      /IO\.popen|Open3/ => "starts a program",
      /Win32API|Fiddle|DL\.dlopen/ => "calls Windows directly",
      /Net::HTTP|TCPSocket|UDPSocket|URI\.open|open-uri/ => "uses the network",
      /File\.(delete|unlink)|FileUtils\.(rm|rm_rf|rm_r|remove)|Dir\.(delete|rmdir|unlink)/ => "deletes files",
      /Marshal\.load/ => "loads Marshal data (only safe for the mod's own files)",
      /\beval\s*\(|instance_eval\s*\(\s*[a-z]|binding\.eval/ => "evaluates text as code",
      /ENV\[/ => "reads environment variables"
    }.freeze
    # Never uploaded (Tools/publish_mod.*): a modder's own git folder and the
    # lists KIF writes into installed mods
    LEFT_OUT_DIRS = %w[.git].freeze
    LEFT_OUT_FILES = %w[.kif_installed .installed_assets].freeze

    module_function

    # [object, nil] or [nil, why]. Strict like the catalog's JSON.parse: a
    # byte-order mark or text after the closing } fails there, so here too.
    def parse_json(text)
      text = text.to_s
      return [nil, "unexpected byte-order mark at the start"] if text.b.start_with?("\xEF\xBB\xBF".b)
      # Ruby's own JSON only: the game's JSON module (003_HTTP_Utilities.rb)
      # parses with eval, which would run code written in a mod.json
      if defined?(::JSON::ParserError)
        begin
          return [::JSON.parse(text), nil]
        rescue StandardError => e
          return [nil, e.message.lines.first.to_s.strip]
        end
      end
      mj = KIF::Mods::MiniJSON
      v = mj.parse(text)
      s = mj.instance_variable_get(:@s).to_s
      i = mj.instance_variable_get(:@i).to_i
      i += 1 while i < s.length && s[i] =~ /\s/
      return [nil, "unexpected text"] if v.nil? && text.strip != "null" || i < s.length
      return [v, nil]
    rescue StandardError => e
      return [nil, e.message.lines.first.to_s.strip]
    end

    # the files that would be uploaded: [relative path, full path]
    def files(path)
      # base: a [ ] { } in the game's path isn't read as a pattern
      Dir.glob(File.join("**", "*"), File::FNM_DOTMATCH, base: path).map { |rel| [rel, File.join(path, rel)] }
        .select { |rel, f| File.file?(f) && !rel.split("/").include?(".") }.reject do |rel, _|
        parts = rel.split("/")
        (parts[0..-2] & LEFT_OUT_DIRS).any? || (parts.length == 1 && LEFT_OUT_FILES.include?(parts[0]))
      end
    end

    # One mod folder. dir: the folder's name in the catalog; others:
    # {catalog folder => id} of the mods already there.
    # Returns [errors, warnings] (lists of text).
    def check(path, dir = File.basename(path), others = {})
      err = []
      warn = []
      jpath = File.join(path, "mod.json")
      unless File.file?(jpath)
        err << "no mod.json in the folder"
        return [err, warn]
      end
      json, why = parse_json((File.read(jpath, encoding: "UTF-8") rescue ""))
      if why
        err << "mod.json isn't valid JSON (#{why})"
        return [err, warn]
      end
      unless json.is_a?(Hash)
        err << "mod.json must be an object { ... }"
        return [err, warn]
      end
      id = json["id"].to_s
      err << "\"id\" is missing or has characters other than a-z, 0-9, _ and - (got #{json['id'].inspect})" unless id =~ ID
      %w[name author description].each { |k| err << "\"#{k}\" is missing" if json[k].to_s.strip.empty? }
      err << "\"version\" should look like 1.0 or 1.2.3 (got #{json['version'].inspect})" unless json["version"].to_s =~ VERSION
      if (other = others.find { |d, i| i.to_s == id && d != dir })
        err << "id \"#{id}\" is already used by #{other[0]}"
      end
      LIST_FIELDS.each do |k|
        next unless json.key?(k)
        v = json[k]
        ok = v.is_a?(Array) && v.all? { |x| x.is_a?(String) || (x.is_a?(Hash) && x["id"]) }
        err << "\"#{k}\" must be a list of names" unless ok
      end
      if json.key?("requires_kif") && json["requires_kif"].to_s !~ REQUIRES
        err << "\"requires_kif\" should look like \">=1.1.0\" or \">=1.1.0, <2.0\""
      end
      if json.key?("catalog") && json["catalog"].to_s !~ CATALOG
        err << "\"catalog\" should look like owner/repo or owner/repo@branch"
      end
      warn << "sets settings for the player (\"locks\": #{json['locks'].keys.join(', ')})" if json["locks"].is_a?(Hash) && !json["locks"].empty?
      warn << "takes over KIF features (\"replaces\": #{Array(json['replaces']).join(', ')})" unless Array(json["replaces"]).empty?

      list = files(path)
      total = 0
      list.each do |rel, f|
        size = File.size(f)
        total += size
        err << "#{rel}: #{File.extname(f)} files aren't allowed (unpack archives; no programs)" if BLOCKED_EXT.include?(File.extname(f).downcase)
        err << "#{rel}: #{(size / 1048576.0).round(1)} MB, over the 25 MB limit per file" if size > MAX_FILE
      end
      err << "#{(total / 1048576.0).round(1)} MB in all, over the 100 MB limit per mod" if total > MAX_MOD

      scripts = Array(json["scripts"]).map(&:to_s)
      scripts.each { |s| err << "script \"#{s}\" listed in mod.json isn't in the folder" unless File.file?(File.join(path, s)) }
      rbs = list.select { |rel, _| rel.end_with?(".rb") }
      err << "no .rb scripts" if rbs.empty? && scripts.empty? && !json["assets_only"]
      rbs.each do |rel, f|
        src = File.binread(f).force_encoding("UTF-8")
        unless src.valid_encoding?
          err << "#{rel}: not UTF-8 text"
          next
        end
        if defined?(RubyVM::InstructionSequence)
          begin
            RubyVM::InstructionSequence.compile(src, rel)
          rescue SyntaxError => e
            err << "#{rel}: doesn't compile: #{e.message.lines.first(2).join(' ').strip}"
            next
          end
        end
        src.each_line.with_index(1) do |line, n|
          next if line.lstrip.start_with?("#")
          RISKY.each { |re, what| warn << "#{rel}:#{n} #{what}: `#{line.strip[0, 90]}`" if line =~ re }
        end
      end
      return [err, warn]
    end
  end
end
