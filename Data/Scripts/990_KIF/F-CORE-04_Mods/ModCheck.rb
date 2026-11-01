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

    #---------------------------------------------------------------------------
    # The mod scan (2026-11-01): what a mod's code does, in plain words.
    # Colours: green = nothing to tell the player, yellow = worth a look,
    # red = does something dangerous or more than it says. A text scan, not a
    # sandbox: a determined author can write code it does not see (see the
    # guide, "What this cannot stop"). Plain Ruby with no game code.
    #---------------------------------------------------------------------------
    # The same names, colours and words as KIF::ModContract (a kit test checks
    # they match); copied here so this file can be loaded on its own.
    PERMISSION_NAMES = %w[network programs native game_files save_files outside_files environment clipboard load_code marshal eval objectspace].freeze
    PERM_SEVERITY = { "network" => :yellow, "programs" => :red, "native" => :red, "game_files" => :yellow,
                      "save_files" => :yellow, "outside_files" => :red, "environment" => :yellow, "clipboard" => :yellow,
                      "load_code" => :yellow, "marshal" => :yellow, "eval" => :info, "objectspace" => :info }.freeze
    PERM_TEXT = { "network" => "Uses the internet", "programs" => "Starts other programs on your computer",
                  "native" => "Calls Windows or system code directly", "game_files" => "Changes files in the game folder",
                  "save_files" => "Changes your save files and KIF settings", "outside_files" => "Reads or changes files outside the game",
                  "environment" => "Reads your computer's settings", "clipboard" => "Reads or sets your clipboard",
                  "load_code" => "Loads code from outside its own folder", "marshal" => "Reads saved-object files",
                  "eval" => "Builds code from text while running", "objectspace" => "Looks through everything the game has loaded" }.freeze
    PROGRAM_EXT = %w[.exe .dll .bat .cmd .ps1 .vbs .msi .scr .com .jar .so .dylib .sh .lnk].freeze
    ARCHIVE_EXT = %w[.zip .7z .rar].freeze
    # files and folders that are not part of a mod (KIF's lists, an author's git and editor files)
    SKIP_FILES = %w[.gitignore .gitattributes .gitkeep .keep .DS_Store Thumbs.db desktop.ini .kif_installed .kif_provenance .installed_assets].freeze
    SKIP_FOLDERS = %w[.git .idea .vscode .claude].freeze
    # library names a mod may require without saying so (the guard uses the same list)
    STDLIB = %w[json zlib digest digest/sha1 digest/md5 digest/sha2 fileutils set time date securerandom stringio strscan pp ostruct forwardable
                timeout benchmark tempfile open3 socket net/http net/https uri openssl open-uri base64 csv erb logger monitor observer pathname
                psych yaml rbconfig etc shellwords singleton English delegate comparable bigdecimal matrix prime tsort weakref].freeze
    HOST_RE = /\A(?:\*\.)?[a-z0-9](?:[a-z0-9\-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9\-]{0,61}[a-z0-9])?)*\z/i
    MAX_FINDINGS = 60
    PER_RULE_FILE = 3

    Finding = Struct.new(:rule, :severity, :permission, :file, :line, :text, :snippet) do
      def to_a; return [rule, severity.to_s, permission, file, line, text, snippet]; end
      def self.from_a(a); return new(a[0].to_s, a[1].to_s.to_sym, a[2], a[3], a[4].to_i, a[5].to_s, a[6].to_s); end
    end

    class Report
      attr_reader :color, :findings, :declared, :inferred, :undeclared, :unused, :fingerprint, :files, :stamps, :bytes, :ms, :hosts
      def initialize(h)
        @color = h[:color]
        @findings = h[:findings] || []
        @declared = h[:declared]
        @inferred = h[:inferred] || []
        @undeclared = h[:undeclared] || []
        @unused = h[:unused] || []
        @fingerprint = h[:fingerprint].to_s
        @files = h[:files] || {}
        @stamps = h[:stamps] || {}
        @bytes = h[:bytes].to_i
        @ms = h[:ms].to_f
        @hosts = h[:hosts] || []
      end

      # what the mod holds: its own list when it has one, else what the code was found to do
      def held; return @declared || @inferred; end

      # plain-words problems, worst first, one line each (info findings are left out)
      def lines(max = 6)
        by = {}
        @findings.reject { |f| f.severity == :info }.sort_by { |f| [f.severity == :red ? 0 : 1, f.rule] }.each { |f| (by[f.text] ||= []) << f }
        out = by.map do |text, fs|
          f = fs[0]
          where = if f.file.to_s.empty? then ""
                  elsif f.line.to_i > 0 then " (#{f.file}:#{f.line}#{fs.length > 1 ? ", #{fs.length - 1} more" : ''})"
                  else " (#{f.file})" end
          "#{text}#{where}"
        end
        return out.first(max)
      end

      # "Uses the internet (api.github.com)" for each permission the mod holds
      def permission_lines
        return held.select { |p| PERM_TEXT[p] }.map do |p|
          p == "network" && !@hosts.empty? ? "#{PERM_TEXT[p]} (#{@hosts.first(3).join(', ')})" : PERM_TEXT[p]
        end
      end

      def to_h
        return { "color" => @color.to_s, "findings" => @findings.map(&:to_a), "declared" => @declared, "inferred" => @inferred,
                 "undeclared" => @undeclared, "unused" => @unused, "fingerprint" => @fingerprint, "files" => @files,
                 "stamps" => @stamps, "bytes" => @bytes, "ms" => @ms, "hosts" => @hosts }
      end

      def self.from_h(h)
        h = {} unless h.is_a?(Hash)
        return new(:color => (h["color"] || "green").to_sym, :findings => Array(h["findings"]).map { |a| Finding.from_a(a) },
                   :declared => h["declared"], :inferred => Array(h["inferred"]), :undeclared => Array(h["undeclared"]),
                   :unused => Array(h["unused"]), :fingerprint => h["fingerprint"], :files => h["files"] || {},
                   :stamps => h["stamps"] || {}, :bytes => h["bytes"], :ms => h["ms"], :hosts => Array(h["hosts"]))
      end
    end

    # One line of code in two views: raw (comment removed) and code (text inside quotes
    # emptied, so words in messages do not count; the code inside "#{...}" is kept)
    STR_RE = /"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`(?:[^`\\]|\\.)*`|\?["'`]|(?<![^\s])#(?![{$@]).*/m
    DEF_RE = /\bdef\s+(?:self\.)?[\w?!=]+|\balias(?:_method)?\s+[:\w?!=]+\s*,?\s*[:\w?!=]*/
    # a cheap test on the raw line: every rule's key word is in here, so most lines are never looked at again
    TRIGGER = /system|spawn|exec|`|%x|popen|Open3|Process|syscall|System|IO\.|\bopen\b|Win32|Fiddle|FFI|\bDL\b|Net::|Socket|URI|HTTP|pbDownload|pbPost|Updater|File\.|FileUtils|Dir\.|mkdir_p|rm_tree|to_file|save_data|~[\\\/]|[A-Za-z]:[\\\/]|APPDATA|USERPROFILE|Documents|Desktop|Downloads|Startup|Start Menu|CurrentVersion|reg add|ENV|Etc\.|eval|Marshal|YAML|Psych|ObjectSpace|\bload\b|require|Base64|unpack|pack|\\x|send|const_get|super_method|instance_method|KIF::Mod|Trace|trace|Signal|trap|at_exit|^\s*(?:class|module)\s+(?:Kernel|File|IO|Dir|Marshal|ENV|Process|FileUtils|ObjectSpace|Socket|HTTPLite)|\.(?:bat|cmd|ps1|vbs)|exit!|abort|fork|kill|clipboard/
    BIDI_RE = /[‪-‮⁦-⁩]/
    R14_RE = /^[ \t]*unless[ \t]+(?:self\.)?(?:private_)?method_defined\?[^\n]*\n[ \t]*def\b/
    R01_CALL = /(?<![\w.:@$])(?:system|spawn|exec)(?:\s*\(|[ \t]+(?!if\b|unless\b|while\b|until\b|and\b|or\b|then\b|do\b|end\b|rescue\b|ensure\b|in\b|not\b)[\w"'`:\[%*@$])/
    R01_OTHER = /\bKernel\.(?:system|spawn|exec)\b|\bIO\.popen\b|\bOpen3\b|\bPTY\.spawn\b|\bProcess\.(?:spawn|exec|daemon)\b|(?<![\w.:@$])syscall\b|\bSystem\.launch\b|%x[(\[{<|!\/]|`X`/
    R01_PIPE = /(?<![\w.:@$])open\s*\(?\s*["']\s*\||\bIO\.(?:read|readlines|foreach|write|binread)\s*\(?\s*["']\s*\|/
    R02_RE = /\b(?:Win32API|Fiddle|FFI)\b|\bDL\.dlopen\b/
    R03_RE = /\bNet::HTTP|\b(?:TCPSocket|TCPServer|UDPSocket|UNIXSocket)\b|\bSocket\.|\bURI\.open\b|\bOpenURI\b|\bHTTPLite\b|(?<![\w.:@$])(?:pbDownloadToString|pbDownloadToFile|pbPostData|pbDownloadData)\b|\bKIF::Updater\.(?:fetch|download)\b/
    R03_REQ = /\brequire\s*\(?\s*["'](?:open-uri|net\/https?|socket)["']/
    R04_RE = /\bFile\.(?:write|binwrite|delete|unlink|rename|chmod|lchmod|chown|truncate|symlink|link|utime|mkfifo)\b|\bFileUtils\b|\bDir\.(?:mkdir|rmdir|delete|unlink)\b|\bIO\.(?:write|binwrite|copy_stream)\b|\.to_file\b|\bKIF\.(?:rm_tree|mkdir_p)\b|(?<![\w.])mkdir_p\b|(?<![\w.:@$])save_data\s*\(/
    R04_OPEN = /(?<![\w.:@$])(?:File\.(?:open|new)|open)\s*\(?/
    R05_RE = /Dir\.home|["']~[\\\/]|["'][A-Za-z]:[\\\/]|\bAPPDATA\b|\bUSERPROFILE\b|[\\\/](?:AppData|Documents|Desktop|Downloads|Startup)(?:[\\\/"'])/
    R06_RE = /(?<![\w:])ENV\b(?!\w)|\bEtc\.|\bDir\.home\b/
    R07A_RE = /(?<![\w.:@$])eval\b(?![?!:=])|\bbinding\.eval\b|\bKernel\.eval\b/
    R07B_RE = /\b(?:class|module|instance)_eval\b/
    R08_RE = /\bMarshal\.(?:load|restore)\b|\b(?:YAML|Psych)\.(?:load|unsafe_load|load_file|unsafe_load_file)\b/
    R09_RE = /\bObjectSpace\.(?:each_object|_id2ref|garbage_collect)\b/
    R10_RE = /(?<![\w.:@$])(?:load|require|require_relative)\b(?![?!:=])/
    R11_SEND = /(?<![\w:@$])(?:send|__send__|public_send|const_get)\s*\(?\s*([^,)\n]*)/
    R11_DANGER = /(?<![\w:@$])(?:send|__send__|public_send)\s*\(?\s*[:"'](?:system|exec|spawn|eval|instance_eval|class_eval|module_eval|load|require|syscall|fork|open|popen|`)\b/
    R12_RE = /\bKIF::Mod(?:Guard|Trust|SecurityUI|Contract)\b|\bTracePoint\b|\bset_trace_func\b|\bSignal\.trap\b|(?<![\w.:@$])trap\s*\(?\s*["':]|\bObjectSpace\.define_finalizer\b|(?<![\w.:@$])at_exit\b|^\s*(?:class|module)\s+(?:Kernel|File|IO|Dir|Marshal|ENV|Process|FileUtils|ObjectSpace|Win32API|Fiddle|Open3|Socket|TCPSocket|Net::HTTP|HTTPLite)\b|\b(?:Kernel|File|IO|Dir|Marshal|Process)\.(?:singleton_class\.)?(?:prepend|alias_method|define_method|define_singleton_method|remove_method|undef_method)\b/
    R13_RE = /Start Menu[\\\/]|[\\\/]Startup\b|CurrentVersion[\\\/]+Run|\breg\s+add\b|["'][^"'\n]*\.(?:bat|cmd|ps1|vbs)["']/
    R20_RE = /(?<![\w.:@$])(?:exit!|abort(?![\w?!=])|fork(?![\w?!=]))|\bProcess\.(?:kill|abort)\b/
    R21_RE = /\bInput\.clipboard\b/
    BUILT_RE = /\+|\.join\b|<<|\.reverse\b|\.chr\b|\.pack\b|\.gsub\b|\.sub\(|\.tr\(|\.concat\b|\bBase64\b|\.unpack|\.map\b|%[(\[]|\bformat\b|\bsprintf\b/

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

    #---------------------------------------------------------------------------
    # Scanning
    #---------------------------------------------------------------------------
    # Report for a mod folder (or one .rb file). json: the mod.json as a Hash
    # (or nil). stamps: the Report#stamps of an earlier scan; a file whose size
    # and time are unchanged is not read again for its hash.
    def scan(path, json = nil, stamps = nil)
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      rep = Scanner.new(json.is_a?(Hash) ? json : nil).run(path.to_s, stamps.is_a?(Hash) ? stamps : {})
      rep.instance_variable_set(:@ms, ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round(1))
      return rep
    end

    # [fingerprint, {rel => blob sha}, stamps] without reading the code
    def fingerprint(path, stamps = nil)
      files = {}
      st = {}
      list_files(path.to_s).each do |rel, full, lst|
        next if lst.symlink?
        sha, stamp = file_sha(full, lst, stamps && stamps[rel])
        files[rel] = sha
        st[rel] = stamp
      end
      return [fingerprint_of(files), files, st]
    end

    # SHA-1 over the sorted "sha path" lines (crc32 based when the game has no SHA-1)
    def fingerprint_of(files)
      text = files.sort.map { |rel, sha| "#{sha} #{rel}\n" }.join
      return sha1_hex(text)
    end

    def sha1_hex(data)
      load_digest
      return Digest::SHA1.hexdigest(data) if defined?(Digest::SHA1)
      return format("%08x", Zlib.crc32(data)).ljust(40, "0")
    end

    def load_digest
      return if defined?(Digest::SHA1)
      require "digest/sha1"
    rescue LoadError, StandardError
      begin
        require "zlib"
      rescue LoadError, StandardError
        nil
      end
    end

    # git's id for a file (what a catalog lists), streamed
    def file_sha(full, lst, old, data = nil)
      mt = lst.mtime.to_i
      return [old[2], old] if old.is_a?(Array) && old[0] == lst.size && old[1] == mt && old[2].to_s.length == 40
      load_digest
      if defined?(Digest::SHA1)
        d = Digest::SHA1.new
        d << "blob #{lst.size}\0"
        if data then d << data else File.open(full, "rb") { |f| while (chunk = f.read(1 << 20)); d << chunk; end } end
        sha = d.hexdigest
      else
        crc = 0
        if data then crc = Zlib.crc32(data) else File.open(full, "rb") { |f| while (chunk = f.read(1 << 20)); crc = Zlib.crc32(chunk, crc); end } end
        sha = format("%08x", crc).ljust(40, "0")
      end
      return [sha, [lst.size, mt, sha]]
    rescue SystemCallError
      return ["0" * 40, [0, 0, "0" * 40]]
    end

    # [relative path, full path, lstat] of what belongs to the mod
    def list_files(path)
      return [[File.basename(path), path, File.lstat(path)]] if File.file?(path)
      out = []
      Dir.glob(File.join("**", "*"), File::FNM_DOTMATCH, base: path).sort.each do |rel|
        parts = rel.split("/")
        next if rel.end_with?("/.") || parts.last == "." || parts.last == ".."
        next if (parts[0..-2] & SKIP_FOLDERS).any? || SKIP_FOLDERS.include?(parts.last)
        next if parts.length == 1 && SKIP_FILES.include?(parts[0])
        full = File.join(path, rel)
        lst = (File.lstat(full) rescue nil)
        next unless lst
        next if lst.directory? && !lst.symlink?
        next if SKIP_FILES.include?(parts.last) && !lst.symlink?
        out << [rel, full, lst]
      end
      return out
    rescue SystemCallError
      return out || []
    end

    def hosts_ok?(list)
      return false unless list.is_a?(Array) && list.length <= 10
      return list.all? do |h|
        h.is_a?(String) && (h == "127.0.0.1" || (h =~ HOST_RE && h !~ /\A[\d.]+\z/ && !h.include?(":")))
      end
    end

    # mod.json "api_version": a whole number above 0 (or its text)
    def api_version_ok?(v)
      return (v.is_a?(Integer) && v > 0) || (v.is_a?(String) && v =~ /\A[1-9]\d{0,5}\z/) ? true : false
    end

    # The scan itself. One instance per mod.
    class Scanner
      def initialize(json)
        @json = json
        @hosts = json && json["network_hosts"].is_a?(Array) ? json["network_hosts"].select { |h| h.is_a?(String) } : []
        @hosts_given = !@hosts.empty? && KIF::ModCheck.hosts_ok?(json["network_hosts"])
        @findings = []
        @counts = Hash.new(0)
        @used = {}
        @file_eval = false
      end

      def add(rule, sev, perms, file, line, text, snippet = "")
        Array(perms).each { |p| @used[p] ||= [file, line] }
        key = [rule, file, sev]
        @counts[key] += 1
        return if (@counts[key] > PER_RULE_FILE && !%w[R30 R31 R32].include?(rule)) || @findings.length >= MAX_FINDINGS
        snip = snippet.to_s.strip[0, 90].gsub(/[^\x20-\x7e]/, "?")
        @findings << Finding.new(rule, sev, Array(perms)[0], file, line, text, snip)
      end

      def run(path, stamps)
        files = {}
        st = {}
        bytes = 0
        KIF::ModCheck.list_files(path).each do |rel, full, lst|
          if lst.symlink?
            add("R16", :red, nil, rel, 0, "Contains a link to somewhere else")
            next
          end
          size = lst.size
          bytes += size
          base = File.basename(rel)
          ext = File.extname(base).downcase
          if PROGRAM_EXT.include?(ext) then add("R16", :red, nil, rel, 0, "Contains a program file")
          elsif ARCHIVE_EXT.include?(ext) then add("R16", :red, nil, rel, 0, "Contains an archive")
          elsif base.start_with?(".") then add("R16", :yellow, nil, rel, 0, "Contains a hidden file")
          end
          add("R16", :red, nil, rel, 0, "Contains a file name KIF will not write") if defined?(KIF) && KIF.respond_to?(:safe_rel_path?) && !KIF.safe_rel_path?(rel)
          add("R16", :yellow, nil, rel, 0, "Contains a very large file") if size > MAX_FILE
          if ext == ".rb"
            data = File.binread(full)
            sha, stamp = KIF::ModCheck.file_sha(full, lst, stamps[rel], data)
            text = data.dup.force_encoding("UTF-8")
            text = text.scrub("?") unless text.valid_encoding?
            scan_text(rel, text)
          else
            sha, stamp = KIF::ModCheck.file_sha(full, lst, stamps[rel])
          end
          files[rel] = sha
          st[rel] = stamp
        end
        add("R16", :yellow, nil, "", 0, "Is very large in all") if bytes > MAX_MOD
        return finish(files, st, bytes)
      end

      #-------------------------------------------------------------------------
      def scan_text(rel, text)
        @file_eval = false
        if text.match?(BIDI_RE)
          n = text.each_line.with_index(1) { |l, i| break i if l.match?(BIDI_RE) }
          add("R17", :red, nil, rel, n.is_a?(Integer) ? n : 0, "Hides text with direction tricks")
        end
        if text.include?("unless") && (m = R14_RE.match(text))
          add("R14", :yellow, nil, rel, text[0, m.begin(0)].count("\n") + 1, "Stops working after F12 (compatibility)", m[0].lines.first.to_s)
        end
        n = 0
        text.each_line do |line|
          n += 1
          len = line.length
          long_line(rel, n, line) if len > 200
          next if line =~ /\A\s*#/
          next unless line.match?(TRIGGER)
          scan_line(rel, n, line)
        end
        if @file_eval && text =~ /Zlib::(?:Inflate|GzipReader)|Zlib\.inflate/
          add("R11", :red, nil, rel, 0, "Hides what the code does", "Zlib with eval")
        end
      end

      # long lines and coded strings
      def long_line(rel, n, line)
        if line.length > 2000
          gap = line =~ /[ \t]{80,}[^ \t\r\n#]/
          add("R11", gap ? :red : :info, nil, rel, n, gap ? "Hides what the code does" : "Has a very long line", line[0, 60])
        end
        if (m = line.match(/["']([A-Za-z0-9+\/=]{200,})["']/))
          s = m[1]
          coded = s =~ /[a-z]/ && s =~ /[A-Z]/ && s =~ /\d/
          add("R11", coded ? :red : :info, nil, rel, n, coded ? "Hides what the code does" : "Has a long block of data", s[0, 40])
        end
      end

      def views(line)
        return [line, line] unless line.include?('"') || line.include?("'") || line.include?("`") || line.include?("#") || line.include?("?")
        raw = line.gsub(STR_RE) { |m| m.start_with?("#") ? "" : m }
        code = line.gsub(STR_RE) do |m|
          case m[0]
          when "#" then ""
          when "?" then " "
          when "`" then "`X`" + interp(m)
          when '"' then '""' + interp(m)
          else "''"
          end
        end
        return [raw, code]
      end

      def interp(m)
        return "" unless m.include?('#{')
        return " ;" + m.scan(/#\{([^}]*)\}/).flatten.join(" ; ") + "; "
      end

      # the arguments of a call that starts at index i of s (depth 0 pieces, at most 4)
      def args_at(s, i)
        i += 1 while s[i] == " " || s[i] == "("
        out = []
        cur = +""
        depth = 0
        q = nil
        while i < s.length
          ch = s[i]
          if q
            cur << ch
            q = nil if ch == q && s[i - 1] != "\\"
          elsif ch == '"' || ch == "'" then q = ch; cur << ch
          elsif "([{".include?(ch) then depth += 1; cur << ch
          elsif ")]}".include?(ch)
            break if depth == 0
            depth -= 1; cur << ch
          elsif ch == "," && depth == 0 then out << cur.strip; cur = +""; break if out.length >= 3
          elsif ch == "\n" then break
          else cur << ch end
          i += 1
        end
        out << cur.strip
        return out
      end

      def write_open?(raw, at)
        a = args_at(raw, at)
        return false if a.length < 2
        m = a[1]
        m = a[2] if m =~ /\A(?:encoding|external_encoding|textmode|binmode):/ && a[2]
        kw = a.drop(1).find { |x| x =~ /\Amode:\s*(.*)/ }
        m = $1.to_s if kw
        return !!(m =~ /\A["'](?:[wa]|r\+)/) if m =~ /\A["']/
        return !!(m =~ /File::(?:WRONLY|RDWR|CREAT|APPEND|TRUNC)/) if m =~ /\AFile::|\AIO::/
        return false if m =~ /\A(?:encoding|external_encoding|textmode|binmode|perm|chomp|universal_newline)/
        return true
      end

      def scan_line(rel, n, line)
        raw, code = views(line)
        c = code.gsub(DEF_RE, "def X")
        r = raw
        snip = line
        hit = lambda { |rule, sev, perms, text| add(rule, sev, perms, rel, n, text, snip) }

        # embedded code in a text handed to eval
        if (c =~ /\beval\b|_eval\b/) && raw =~ /_?eval\s*\(?\s*(["'])(.*)\1/
          inner = $2
          c = c + " ;" + inner if inner !~ /\A\s*\z/
        end

        if c.match?(R01_CALL) || c.match?(R01_OTHER) || r.match?(R01_PIPE)
          hit.call("R01", :red, "programs", "Starts other programs on your computer")
        end
        hit.call("R02", :red, "native", "Calls Windows or system code directly") if c.match?(R02_RE)
        if c.match?(R03_RE) || r.match?(R03_REQ)
          hit.call("R03", @hosts_given ? :yellow : :red, "network", "Uses the internet")
        end
        if c.match?(R04_RE)
          hit.call("R04", :yellow, %w[game_files save_files], "Writes or deletes files")
        elsif (rd = r.gsub(DEF_RE, "def X")) && (m = R04_OPEN.match(rd)) && write_open?(rd, m.end(0))
          hit.call("R04", :yellow, %w[game_files save_files], "Writes or deletes files")
        end
        hit.call("R05", :red, "outside_files", "Reads or changes files outside the game") if r.match?(R05_RE)
        hit.call("R06", :yellow, "environment", "Reads your computer's settings") if c.match?(R06_RE)
        if c.match?(R07A_RE)
          # eval of one plain text is read as code above; anything built (joined, interpolated, from a variable) is flagged
          m = r.match(/\beval\b\s*\(?\s*/)
          arg = m ? args_at(r, m.end(0))[0].to_s : ""
          lit = arg.match?(/\A(?:"(?:[^"\\#]|\\.)*"|'(?:[^'\\]|\\.)*')\z/)
          unless lit
            @file_eval = true
            hit.call("R07a", :yellow, "eval", "Builds code from text while running")
          end
        end
        if c.match?(R07B_RE) && (m = r.match(/\b(?:class|module|instance)_eval\b\s*\(?\s*([^\n]*)/))
          a = m[1].strip
          if a.empty? || a =~ /\A(?:do\b|\{|&)/
            nil
          elsif a.start_with?("<<")
            @file_eval = true if a !~ /__FILE__/
            hit.call("R07b", a =~ /__FILE__/ ? :info : :yellow, "eval", "Builds code from text while running")
          else
            @file_eval = true
            hit.call("R07b", :yellow, "eval", "Builds code from text while running")
          end
        end
        if c.match?(R08_RE)
          if r =~ /Marshal\.(?:load|restore)\s*\(?\s*Marshal\.dump/
            hit.call("R08", :info, nil, "Copies objects with Marshal")
          else
            hit.call("R08", :yellow, "marshal", "Reads saved-object files")
          end
        end
        hit.call("R09", :info, "objectspace", "Looks through everything the game has loaded") if c.match?(R09_RE)
        scan_load(rel, n, r, c, snip) if c.match?(R10_RE) && c !~ /\balias\b/
        scan_hidden(rel, n, r, c, snip)
        hit.call("R12", :red, nil, "Tries to change KIF's protection") if c.match?(R12_RE)
        hit.call("R13", :red, "programs", "Sets itself up to run outside the game") if r.match?(R13_RE)
        if c.match?(R20_RE)
          kill = c.match?(/\bProcess\.(?:kill|abort)\b|(?<![\w.:@$])fork/)
          hit.call("R20", :yellow, kill ? "programs" : nil, "Can close the game or other programs")
        end
        hit.call("R21", :yellow, "clipboard", "Reads or sets your clipboard") if c.match?(R21_RE)
      end

      def scan_load(rel, n, r, c, snip)
        m = r.match(/(?<![\w.:@$])(load|require|require_relative)\b\s*\(?\s*([^\n]*)/)
        return unless m
        kind = m[1]
        a = m[2].strip
        return if a.empty? || a =~ /\A[=?!:]/
        if a =~ /\A["'][^"']*#\{/
          add("R10", :info, nil, rel, n, "Loads code from outside its own folder", snip)
        elsif a =~ /\A(["'])([^"']*)\1/
          lit = $2
          if lit =~ /\.rb\z/ || kind == "require_relative"
            if lit =~ /\A(?:[\/~]|[A-Za-z]:)/ || lit.include?("..")
              add("R10", :yellow, "load_code", rel, n, "Loads code from outside its own folder", snip)
            else
              add("R10", :info, nil, rel, n, "Loads code from outside its own folder", snip)
            end
          elsif kind == "load"
            add("R10", :yellow, "load_code", rel, n, "Loads code from outside its own folder", snip)
          elsif !STDLIB.include?(lit) && lit !~ /\A(?:digest|json|net|openssl|psych|racc|rexml|date|time)\//
            add("R10", :yellow, "load_code", rel, n, "Loads code from outside its own folder", snip)
          end
        elsif a =~ /\A(?:File\.(?:join|expand_path|dirname|realpath)\b|__dir__|Dir\.pwd|[@$]?[A-Za-z_]\w*\s*(?:\z|\)|\bif\b|\bunless\b|\brescue\b|;))/
          add("R10", :info, nil, rel, n, "Loads code from outside its own folder", snip)
        else
          add("R10", :yellow, "load_code", rel, n, "Loads code from outside its own folder", snip)
        end
      end

      # code that is built, coded or reached by name so the other rules cannot see it
      def scan_hidden(rel, n, r, c, snip)
        bad = false
        bad = true if c.match?(/\bBase64\b/)
        bad = true if r =~ /\bunpack1?\s*\(?\s*["']m0?["']/
        bad = true if r =~ /\bpack\s*\(?\s*["']c\*["']/
        bad = true if r =~ /(?:\\x[0-9a-fA-F]{2}){8,}/
        bad = true if r =~ R11_DANGER
        bad = true if c =~ /\.super_method\b|\binstance_method\s*\(\s*:(?:system|exec|spawn|eval|`|open|load|require)\b/
        if !bad && (m = R11_SEND.match(r))
          arg = m[1].gsub(/#\{[^}]*\}/, "")
          bad = true if arg =~ /\\[xu]\h/ || arg =~ BUILT_RE
        end
        add("R11", :red, nil, rel, n, "Hides what the code does", snip) if bad
      end

      #-------------------------------------------------------------------------
      def finish(files, st, bytes)
        json = @json
        declared = nil
        problems = []
        if json && json.key?("permissions")
          list = json["permissions"]
          if list.is_a?(Array) && list.all? { |x| x.is_a?(String) }
            unknown = list - PERMISSION_NAMES
            problems << "mod.json lists permissions KIF does not know: #{unknown.first(3).join(', ')}" unless unknown.empty?
            declared = list & PERMISSION_NAMES
          else
            problems << "mod.json permissions must be a list of names"
          end
        end
        if json && json.key?("network_hosts") && !(json["network_hosts"].is_a?(Array) && KIF::ModCheck.hosts_ok?(json["network_hosts"]))
          problems << "mod.json network_hosts must be plain host names (no http://, no port, no IP number, at most 10)"
        end
        problems << "mod.json api_version must be a whole number above 0" if json && json.key?("api_version") && !KIF::ModCheck.api_version_ok?(json["api_version"])
        problems << "mod.json permission_notes must be a short sentence for each permission" if json && json.key?("permission_notes") && !json["permission_notes"].is_a?(Hash)
        problems.each { |t| add("R32", :yellow, nil, "mod.json", 0, t.gsub(/[^\x20-\x7e]/, "?")) }

        used = @used.keys
        undeclared = []
        unused = []
        if declared
          undeclared = used - declared
          if used.include?("game_files") && !(declared & %w[game_files save_files]).empty?
            undeclared -= %w[game_files save_files]
          end
          undeclared.each do |p|
            where = @used[p]
            sev = %w[network programs native outside_files].include?(p) ? :red : :yellow
            add("R30", sev, p, where[0], where[1], "Does more than it says: #{PERM_TEXT[p].sub(/\A./) { |ch| ch.downcase }}")
          end
          unused = declared - used
          unused.each { |p| add("R31", :info, p, "mod.json", 0, "Asks for more than it uses: #{PERM_TEXT[p].sub(/\A./) { |ch| ch.downcase }}") }
        end
        color = :green
        color = :yellow if @findings.any? { |f| f.severity == :yellow }
        color = :red if @findings.any? { |f| f.severity == :red }
        return Report.new(:color => color, :findings => @findings, :declared => declared, :inferred => used & PERMISSION_NAMES,
                          :undeclared => undeclared, :unused => unused, :fingerprint => KIF::ModCheck.fingerprint_of(files),
                          :files => files, :stamps => st, :bytes => bytes, :hosts => @hosts_given ? @hosts : [])
      end
    end
  end
end
