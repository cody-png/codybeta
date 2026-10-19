#===============================================================================
# C-SYS-06 – KIF updater (2026-10-11; replaces PIF's "use the
# installer" prompt, which C-SYS-02 hides)
#
# At the load screen (where PIF asked about its own versions) KIF reads the
# version of the newest build on GitHub (one tiny file). If it is newer than
# this one: "KIF Beta X is out (you have Y)" - Update now / What's new /
# Later / Skip this version.
#
# Update now downloads only the files that changed, not the whole game:
#   * every build ships Data/KIF/update_manifest.txt: one line per game file
#     with its git blob id and size (written at build time by the kit's
#     tools/gen_manifest.py);
#   * the new build's manifest is compared with this one's; files whose id
#     changed (or that are missing here) are downloaded into "KIF Update/<v>"
#     next to the .exe, each checked against its id (git blob SHA-1) or size;
#   * files the new build no longer has are removed - only shipped files
#     under Data/, Graphics/, Audio/ and Fonts/, never saves, Mods, Logs,
#     Import Sprites or anything the player added;
#   * the game closes; a small "KIF update" window waits for it, moves the
#     new files in (robocopy) and starts the game again; the next start says
#     "KIF Beta was updated to X". If moving fails (a file in use), the next
#     start offers to try again.
# Downloads run in the background through Windows' own curl.exe (no window),
# so the progress bar moves and B cancels; without curl, KIF downloads one
# file at a time itself.
#
# Where builds come from (github.com/cody-png/codybeta):
#   Stable - the "release" branch (moves only when a release is published)
#   Beta   - the "beta-testing" branch (test builds)
# Options > KIF Settings > General settings > "Updates": Stable / Beta / Off (default: the channel of
# the build that is installed) and "Check for Updates" (any time).
# Sprite sheets the player installed (Graphics/CustomBattlers, Battlers) are
# only replaced when the new build changed that sheet itself.
# For testing, a file "KIF_update_source.txt" next to the .exe can hold
# another source (a folder or file:/// URL laid out like the repository).
#===============================================================================
module KIF
  module Updater
    REPO       = "cody-png/codybeta"
    RAW_BASE   = "https://raw.githubusercontent.com/#{REPO}"
    PAGE       = "https://github.com/#{REPO}/releases"
    BRANCHES   = ["release", "beta-testing"]          # channel 0 Stable, 1 Beta
    MANIFEST   = "Data/KIF/update_manifest.txt"
    STAGED_MANIFEST = "manifest.txt"   # in the update folder, beside files/
    NOTES      = "Data/KIF/update_notes.txt"
    VERSION_FILE = "Data/VERSION"
    STAGE_DIR  = "KIF Update"
    SOURCE_FILE = "KIF_update_source.txt"
    REMOVABLE  = %w[Data/ Graphics/ Audio/ Fonts/]
    KEEP_THEIRS = %w[Graphics/CustomBattlers/ Graphics/Battlers/]   # player-installed sprites
    NEVER      = %w[Mods/ Logs/ Import\ Sprites/ KIF\ Update/ Graphics/CustomBattlers/local_sprites/ Cache/ ExportedPokemons/]

    Manifest = Struct.new(:version, :channel, :files)   # files: path => [sha, size]

    #---------------------------------------------------------------------------
    # Small helpers
    #---------------------------------------------------------------------------
    module_function

    # the folder the game runs in: Data, Graphics and Mods live here, also in
    # a "Game Files" layout (only Logs / Import Sprites sit next to the .exe)
    def root
      return Dir.pwd
    end

    def stage_root
      return File.join(root, STAGE_DIR)
    end

    def log(msg)
      KIF.log("Updater: #{msg}") if defined?(KIF.log)
    end

    def version_parts(v)
      return v.to_s.scan(/\d+/).map(&:to_i)
    end

    # true when version a is newer than version b
    def newer?(a, b)
      x = version_parts(a)
      y = version_parts(b)
      return false if x.empty?
      n = [x.length, y.length].max
      return ((x + [0] * (n - x.length)) <=> (y + [0] * (n - y.length))) == 1
    end

    def current_version
      return defined?(KIF::PORT_VERSION) ? KIF::PORT_VERSION.to_s : "0"
    end

    def parse_manifest(text)
      return nil unless text
      text = text.dup.force_encoding("UTF-8")
      lines = text.split("\n")
      head = lines.shift.to_s.chomp("\r")
      return nil unless head.start_with?("KIF-MANIFEST 1 ")
      info = {}
      head.split(" ").each { |kv| k, v = kv.split("=", 2); info[k] = v if v }
      files = {}
      lines.each do |l|
        l = l.chomp("\r")
        next if l.empty?
        sha, size, path = l.split(" ", 3)
        next unless path && sha =~ /\A[0-9a-f]{40}\z/
        # only plain paths inside the game folder ("Audio/ME/x..mp3" is fine, a ".." part is not)
        next unless KIF.safe_rel_path?(path)
        files[path] = [sha, size.to_i]
      end
      return nil if info["files"].to_i != files.length   # cut short
      return Manifest.new(info["version"], info["channel"], files)
    end

    # channel of the installed build (first line of its manifest only)
    def installed_channel
      path = File.join(root, MANIFEST)
      head = File.open(path, "rb") { |f| f.gets.to_s }
      return head[/channel=(\w+)/, 1]
    rescue StandardError
      return nil
    end

    def default_channel
      return installed_channel == "beta" ? 1 : 0
    end

    def channel
      return 2 unless $PokemonSystem && $PokemonSystem.respond_to?(:kif_updates)
      return $PokemonSystem.kif_updates.to_i
    end

    def local_manifest
      path = File.join(root, MANIFEST)
      return nil unless File.file?(path)
      return parse_manifest(File.binread(path))
    rescue StandardError
      return nil
    end

    # Where the new build is read from: a test source, else the channel's branch
    def source(ch = channel)
      file = File.join(root, SOURCE_FILE)
      if File.file?(file)
        line = File.read(file).to_s.strip.split(/\r?\n/).first.to_s.strip
        unless line.empty?
          if !(line =~ %r{\A\w+://}) && File.directory?(line)
            full = File.expand_path(line).tr("\\", "/").sub(%r{\A/}, "")
            line = "file:///" + full.split("/").map { |seg| seg.b.gsub(/[^A-Za-z0-9\-._~:]/n) { |c| format("%%%02X", c.ord) } }.join("/")
          end
          return line.chomp("/")
        end
      end
      branch = BRANCHES[ch]
      return branch ? "#{RAW_BASE}/#{branch}" : nil
    end

    def url_for(base, path)
      enc = path.split("/").map do |seg|
        seg.b.gsub(/[^A-Za-z0-9\-._~]/n) { |c| format("%%%02X", c.ord) }
      end
      return base.chomp("/") + "/" + enc.join("/")
    end

    def file_url_path(url)
      p = url.sub(%r{\Afile:///?}, "")
      p = p.gsub(/%([0-9A-Fa-f]{2})/) { $1.hex.chr }.force_encoding("UTF-8")
      p = "/" + p unless p =~ /\A[A-Za-z]:/ || p.start_with?("/")
      return p
    end

    # body of a URL (http(s) or file://), nil when it can't be read
    def fetch(url)
      if url.start_with?("file:")
        path = file_url_path(url)
        return File.file?(path) ? File.binread(path) : nil
      end
      return nil unless defined?(HTTPLite)
      res = HTTPLite.get(url)
      return nil unless res.is_a?(Hash) && res[:status].to_i == 200
      return res[:body]
    rescue StandardError, (defined?(MKXPError) ? MKXPError : StandardError) => e
      log("#{url} not read (#{e.class}: #{e.message})")
      return nil
    end

    def remote_version(base)
      v = fetch(url_for(base, VERSION_FILE)).to_s.strip
      return v =~ /\A\d+(\.\d+)*\z/ ? v : nil
    end

    def sha_ok?
      return @sha_ok unless @sha_ok.nil?
      begin
        require "digest/sha1" unless defined?(Digest::SHA1)
      rescue LoadError, StandardError
        nil
      end
      @sha_ok = defined?(Digest::SHA1) ? true : false
      return @sha_ok
    end

    # git's id for a file: SHA-1 of "blob <size>\0" + the bytes
    def git_sha(path)
      d = Digest::SHA1.new
      d << "blob #{File.size(path)}\0"
      File.open(path, "rb") { |f| while (chunk = f.read(1 << 20)); d << chunk; end }
      return d.hexdigest
    end

    def good_file?(path, sha, size)
      return false unless File.file?(path) && File.size(path) == size
      return true unless sha_ok?
      return git_sha(path) == sha
    rescue StandardError
      return false
    end

    def under?(path, prefixes)
      return prefixes.any? { |p| path.start_with?(p) }
    end

    def removable?(path)
      return under?(path, REMOVABLE) && !under?(path, NEVER)
    end

    # What to download / remove to go from the installed build to `remote`
    def plan(local, remote, dir = root)
      downloads = []
      remote.files.each do |path, (sha, size)|
        next if under?(path, NEVER)
        here = File.join(dir, path)
        if local
          l = local.files[path]
          same = l && l[0] == sha && File.file?(here)
        elsif under?(path, KEEP_THEIRS)
          same = File.file?(here)           # no manifest: keep installed sprites
        else
          same = File.file?(here) && File.size(here) == size && (!sha_ok? || git_sha(here) == sha)
        end
        downloads << [path, sha, size] unless same
      end
      removals = []
      if local
        local.files.each_key do |path|
          next if remote.files.has_key?(path) || !removable?(path)
          # only files still as shipped (a sprite the player replaced is theirs)
          removals << path if File.exist?(File.join(dir, path)) && good_file?(File.join(dir, path), *local.files[path])
        end
      end
      return { :downloads => downloads, :removals => removals,
               :bytes => downloads.inject(0) { |s, d| s + d[2] } }
    end

    def size_text(bytes)
      return "#{bytes} bytes" if bytes < 1024
      return format("%.0f KB", bytes / 1024.0) if bytes < 1024 * 1024
      return format("%.1f MB", bytes / 1048576.0) if bytes < 1024 ** 3
      return format("%.2f GB", bytes / 1073741824.0)
    end

    def mkdir_p(dir); KIF.mkdir_p(dir); end

    def rm_tree(path)
      KIF.rm_tree(path)
    rescue StandardError => e
      log("couldn't remove #{path} (#{e.class})")
    end

    def writable?(dir)
      mkdir_p(dir)
      probe = File.join(dir, ".kif_write_test")
      File.open(probe, "wb") { |f| f.write("") }
      File.delete(probe)
      return true
    rescue StandardError
      return false
    end

    def windows?
      return false unless defined?(Win32API)
      return Win.available?
    end

    # Windows proper: the update window (apply.cmd, robocopy) can run. Under
    # Wine/Proton (Linux, Steam Deck) those may be missing, so the files are
    # moved in by the game itself and the player starts it again.
    def update_window?
      return windows? && !Win.wine?
    end

    #---------------------------------------------------------------------------
    # Windows processes without a console window (curl), and the update window
    #---------------------------------------------------------------------------
    module Win
      CREATE_NO_WINDOW   = 0x08000000
      CREATE_NEW_CONSOLE = 0x00000010
      STILL_ACTIVE       = 259

      module_function

      def api(dll, fn, args, ret)
        @api ||= {}
        @api[fn] ||= Win32API.new(dll, fn, args, ret)
        return @api[fn]
      end

      def available?
        return @available unless @available.nil?
        @available = begin
          api("kernel32", "GetCurrentProcessId", [], "L").call > 0
        rescue StandardError, LoadError, NameError
          false
        end
        return @available
      end

      # true under Wine / Proton (ntdll has wine_get_version there only)
      def wine?
        return @wine unless @wine.nil?
        @wine = begin
          !api("ntdll", "wine_get_version", [], "p").call.to_s.empty?
        rescue StandardError, LoadError, NameError, RuntimeError
          false
        end
        KIF::Updater.log("running under Wine/Proton: the game moves update files in itself") if @wine
        return @wine
      end

      def x64?
        return [nil].pack("p").size == 8
      end

      def wide(s)
        return (s.to_s + "\0").encode("UTF-16LE").b
      end

      # [process handle, pid] or nil
      def spawn(cmdline, flags, cwd = nil)
        si = x64? ? [104].pack("L") + "\0" * 100 : [68].pack("L") + "\0" * 64
        pi = "\0" * (x64? ? 24 : 16)
        ok = api("kernel32", "CreateProcessW", %w[p p p p i L p p p p], "i")
               .call(nil, wide(cmdline), nil, nil, 0, flags, nil, cwd ? wide(cwd) : nil, si, pi)
        return nil if ok == 0
        h, t, pid = x64? ? pi.unpack("Q2L") : pi.unpack("L3")
        api("kernel32", "CloseHandle", %w[L], "i").call(t)
        return [h, pid]
      rescue StandardError, NameError => e
        KIF::Updater.log("couldn't start a process (#{e.class}: #{e.message})")
        return nil
      end

      # nil while running, else the exit code
      def exit_code(h)
        buf = "\0" * 4
        api("kernel32", "GetExitCodeProcess", %w[L p], "i").call(h, buf)
        code = buf.unpack("L")[0]
        return code == STILL_ACTIVE ? nil : code
      end

      def kill(h)
        api("kernel32", "TerminateProcess", %w[L L], "i").call(h, 1)
      end

      def close(h)
        api("kernel32", "CloseHandle", %w[L], "i").call(h)
      end

      # Ends this game at once. Kernel.exit! alone left the game open after
      # an update (Cody, 0.21.56), so the update window waited for ever.
      def quit_now
        me = api("kernel32", "GetCurrentProcess", [], "L").call
        api("kernel32", "TerminateProcess", %w[L L], "i").call(me, 0)
      rescue StandardError, NameError
        nil
      ensure
        Kernel.exit!(0)
      end

      def exe_path
        buf = "\0" * 2048
        n = api("kernel32", "GetModuleFileNameW", %w[L p L], "L").call(0, buf, 1024)
        return nil if n <= 0
        return buf[0, n * 2].force_encoding("UTF-16LE").encode("UTF-8")
      rescue StandardError, NameError
        return nil
      end

      def curl
        sys = ENV["SystemRoot"] || ENV["WINDIR"] || "C:/Windows"
        path = File.join(sys, "System32", "curl.exe")
        return File.file?(path) ? path : nil
      end
    end

    def win_path(p)
      return p.to_s.tr("/", "\\")
    end

    #---------------------------------------------------------------------------
    # Progress screen
    #---------------------------------------------------------------------------
    def status(title, line, frac = nil, foot = nil)
      unless @sprite && !@sprite.disposed?
        vp = Viewport.new(0, 0, Graphics.width, Graphics.height)
        vp.z = 999_999
        @sprite = Sprite.new(vp)
        @sprite.bitmap = Bitmap.new(Graphics.width, Graphics.height)
      end
      b = @sprite.bitmap
      b.fill_rect(0, 0, b.width, b.height, Color.new(16, 16, 24))
      mid = b.height / 2
      b.font.size = 26
      b.font.color = Color.new(248, 248, 248)
      b.draw_text(0, mid - 70, b.width, 32, title, 1)
      b.font.size = 22
      b.draw_text(0, mid - 28, b.width, 28, line, 1)
      if frac
        w = b.width - 96
        b.fill_rect(48, mid + 10, w, 14, Color.new(56, 56, 72))
        b.fill_rect(48, mid + 10, (w * [[frac, 0].max, 1].min).to_i, 14, Color.new(96, 200, 120))
      end
      if foot
        b.font.color = Color.new(160, 160, 176)
        b.draw_text(0, mid + 36, b.width, 28, foot, 1)
      end
      Graphics.update
      Input.update
    rescue StandardError
      nil
    end

    def hide_status
      return unless @sprite
      vp = @sprite.viewport
      @sprite.bitmap.dispose rescue nil
      @sprite.dispose rescue nil
      vp.dispose rescue nil
      @sprite = nil
    end

    def cancel_pressed?
      return Input.trigger?(Input::BACK) rescue false
    end

    #---------------------------------------------------------------------------
    # Downloading
    #---------------------------------------------------------------------------
    def staged(dir, path)
      return File.join(dir, "files", path)
    end

    def curl_quote(s)
      return "\"" + s.to_s.gsub("\\", "\\\\\\\\").gsub("\"", "\\\"") + "\""
    end

    # Downloads `items` ([path, sha, size]) into dir/files; returns the paths
    # that couldn't be fetched, or :cancelled
    def download(base, items, dir, version, title = nil)
      total = items.inject(0) { |s, it| s + it[2] }
      title ||= _INTL("Updating to KIF Beta {1}", version)
      todo = items.reject { |path, sha, size| good_file?(staged(dir, path), sha, size) }   # resumed downloads
      if !todo.empty? && windows? && (curl = Win.curl)
        cfg = File.join(dir, "download.cfg")
        File.open(cfg, "wb") do |f|
          todo.each do |path, _sha, _size|
            f.write("url = #{curl_quote(url_for(base, path))}\n")
            f.write("output = #{curl_quote(win_path(staged(dir, path)))}\n")
          end
        end
        err = File.join(dir, "curl_errors.txt")
        cmd = "\"#{win_path(curl)}\" -K \"#{win_path(cfg)}\" --parallel --parallel-max 6 --create-dirs " \
              "--fail --retry 3 --retry-delay 1 -L -s -S --stderr \"#{win_path(err)}\""
        h, _pid = Win.spawn(cmd, Win::CREATE_NO_WINDOW, root)
        if h
          last = 0
          loop do
            code = Win.exit_code(h)
            if Time.now.to_f - last > 0.25 || code
              last = Time.now.to_f
              got = items.inject(0) { |s, (path, _sha, _size)| p = staged(dir, path); s + (File.file?(p) ? File.size(p) : 0) }
              status(title, _INTL("{1} of {2}", size_text([got, total].min), size_text(total)),
                     total > 0 ? got.to_f / total : 1, _INTL("{1}: cancel (you can update later)", KIF::Keys.name(Input::BACK)))
            else
              Graphics.update
              Input.update
            end
            if cancel_pressed?
              Win.kill(h)
              Win.close(h)
              return :cancelled
            end
            break if code
          end
          Win.close(h)
          log("curl finished (#{File.file?(err) ? File.read(err).lines.length : 0} error lines)")
        end
      end
      # whatever is still missing or wrong: one at a time
      failed = []
      bad = items.reject { |path, sha, size| good_file?(staged(dir, path), sha, size) }
      bad.each_with_index do |(path, sha, size), i|
        status(title, _INTL("{1} ({2} of {3})", File.basename(path), i + 1, bad.length),
               (i + 1).to_f / bad.length, _INTL("{1}: cancel (you can update later)", KIF::Keys.name(Input::BACK)))
        return :cancelled if cancel_pressed?
        data = fetch(url_for(base, path))
        dest = staged(dir, path)
        if data
          mkdir_p(File.dirname(dest))
          File.open(dest, "wb") { |f| f.write(data) }
        end
        failed << path unless good_file?(dest, sha, size)
      end
      return failed
    end

    #---------------------------------------------------------------------------
    # Moving the files in
    #---------------------------------------------------------------------------
    def apply_script(dir, version, pid, exe)
      # % starts a variable in a .cmd file: a folder named "KIF 100%" broke it
      r = win_path(root).gsub("%", "%%")
      s = win_path(dir).gsub("%", "%%")
      m = win_path(MANIFEST)
      lines = []
      lines << "@echo off"
      lines << "chcp 65001 >nul"
      lines << "title KIF update"
      lines << "echo Finishing the KIF Beta #{version} update. This window closes by itself."
      # the game closes itself; one still open after 20 s is closed here
      lines << "set /a waited=0"
      lines << ":wait"
      lines << "tasklist /FI \"PID eq #{pid}\" 2>nul | find \"#{pid}\" >nul"
      lines << "if errorlevel 1 goto go"
      lines << "set /a waited+=1"
      lines << "if %waited% GEQ 20 taskkill /PID #{pid} /F >nul 2>&1"
      lines << "timeout /t 1 /nobreak >nul"
      lines << "goto wait"
      lines << ":go"
      lines << "robocopy \"#{s}\\files\" \"#{r}\" /E /MOVE /R:10 /W:1 /NFL /NDL /NJH /NJS /NP >nul"
      lines << "if errorlevel 8 goto fail"
      lines << "if exist \"#{s}\\#{STAGED_MANIFEST}\" copy /y \"#{s}\\#{STAGED_MANIFEST}\" \"#{r}\\#{m}\" >nul"
      lines << "if exist \"#{s}\\remove.txt\" for /f \"usebackq delims=\" %%f in (\"#{s}\\remove.txt\") do if exist \"#{r}\\%%f\" del /f /q \"#{r}\\%%f\""
      lines << "echo ok> \"#{s}\\done.txt\""
      lines << "start \"\" \"#{win_path(exe).gsub('%', '%%')}\"" if exe
      lines << "exit /b 0"
      lines << ":fail"
      lines << "echo failed> \"#{s}\\failed.txt\""
      lines << "echo The new files couldn't be moved in (a file was in use). Start the game again to try once more."
      lines << "pause"
      return lines.join("\r\n") + "\r\n"
    end

    def start_apply(dir)
      cmd = File.join(dir, "apply.cmd")
      h, _pid = Win.spawn("cmd.exe /c \"\"#{win_path(cmd)}\"\"", Win::CREATE_NEW_CONSOLE, root)
      Win.close(h) if h
      return h ? true : false
    end

    # Without Windows (and in the kit): move the files in now; the game uses
    # them from the next start
    def apply_in_ruby(dir)
      files = File.join(dir, "files")
      failed = File.join(dir, "failed.txt")
      File.open(failed, "wb") { |f| f.write("moving") }   # stays if anything below raises
      moved = 0
      walk = lambda do |sub|
        Dir.children(File.join(files, sub)).each do |c|
          rel = sub.empty? ? c : "#{sub}/#{c}"
          src = File.join(files, rel)
          if File.directory?(src)
            walk.call(rel)
          else
            dest = File.join(root, rel)
            mkdir_p(File.dirname(dest))
            File.delete(dest) if File.exist?(dest)
            File.rename(src, dest)
            moved += 1
          end
        end
      end
      walk.call("") if File.directory?(files)
      man = File.join(dir, STAGED_MANIFEST)
      if File.file?(man)
        dest = File.join(root, MANIFEST)
        mkdir_p(File.dirname(dest))
        File.delete(dest) if File.exist?(dest)
        File.rename(man, dest)
      end
      rm_file = File.join(dir, "remove.txt")
      if File.file?(rm_file)
        File.read(rm_file).force_encoding("UTF-8").split(/\r?\n/).each do |rel|
          rel = rel.tr("\\", "/")
          next if rel.empty? || !removable?(rel)
          p = File.join(root, rel)
          File.delete(p) if File.file?(p)
        end
      end
      File.delete(failed) if File.file?(failed)
      File.open(File.join(dir, "done.txt"), "wb") { |f| f.write("ok") }
      return moved
    end

    # Wine/Proton (no "close it and start it again" message): the
    # files are already moved in, so a new copy of the game is started and
    # this one closes. Without Windows' process API: the old message.
    def restart_after_apply(version)
      exe = windows? ? (Win.exe_path || File.join(root, "InfiniteFusion.exe")) : nil
      if exe
        pbMessage(_INTL("KIF Beta {1} is installed. The game restarts now.", version))
        h, _pid = Win.spawn("\"#{win_path(exe)}\"", 0, root)
        if h
          Win.close(h)
          log("#{version}: moved in by the game, restarted")
          (KIF::SessionLog.finish rescue nil) if defined?(KIF::SessionLog)
          Win.quit_now
          return true
        end
        log("#{version}: the game couldn't start itself again")
      end
      pbMessage(_INTL("KIF Beta {1} is installed. Close the game and start it again to use it.", version))
      return true
    end

    #---------------------------------------------------------------------------
    # The whole update; true when the game is about to close for it
    #---------------------------------------------------------------------------
    def update(base, version, in_game = false)
      unless writable?(stage_root)
        pbMessage(_INTL("The game folder can't be written to, so KIF can't update itself here (a folder like Program Files?)."))
        pbMessage(_INTL("Get KIF Beta {1} from {2}", version, PAGE))
        return false
      end
      status(_INTL("Updating to KIF Beta {1}", version), _INTL("Reading the file list..."))
      body = fetch(url_for(base, MANIFEST))
      remote = parse_manifest(body)
      if !remote || remote.version.to_s != version
        hide_status
        pbMessage(_INTL("The file list for KIF Beta {1} couldn't be read. Try again later.", version))
        log("manifest for #{version} unreadable (got #{remote ? remote.version : 'nothing'})")
        return false
      end
      local = local_manifest
      status(_INTL("Updating to KIF Beta {1}", version), _INTL("Checking your files...")) unless local
      plan = plan(local, remote)
      hide_status
      n = plan[:downloads].length
      if n == 0 && plan[:removals].empty?
        pbMessage(_INTL("Your files already match KIF Beta {1}.", version))
        return false
      end
      msg = _INTL("{1} files to download ({2}).", n, size_text(plan[:bytes]))
      msg += " " + _INTL("Any progress since your last save will be lost when the game restarts.") if in_game
      return false unless pbConfirmMessage(msg + " " + _INTL("Update now?"))
      dir = File.join(stage_root, version)
      mkdir_p(File.join(dir, "files"))
      result = download(base, plan[:downloads], dir, version)
      hide_status
      if result == :cancelled
        pbMessage(_INTL("Update cancelled. What was downloaded is kept for next time."))
        return false
      end
      unless result.empty?
        log("#{result.length} files failed: #{result.first(5).join(', ')}")
        pbMessage(_INTL("{1} files couldn't be downloaded. Check your connection and try again later.", result.length))
        return false
      end
      # the list the plan was made from: kept beside files/ and moved in only
      # after every file is in, so a failed move can't leave a new list over
      # old files (the next update trusts the list)
      File.open(File.join(dir, STAGED_MANIFEST), "wb") { |f| f.write(body) }
      File.open(File.join(dir, "remove.txt"), "wb") { |f| f.write(plan[:removals].map { |p| win_path(p) }.join("\r\n")) }
      File.open(File.join(dir, "version.txt"), "wb") { |f| f.write(version) }
      log("#{version}: #{n} files (#{size_text(plan[:bytes])}) downloaded, #{plan[:removals].length} to remove")
      if update_window?
        exe = Win.exe_path || File.join(root, "InfiniteFusion.exe")
        File.open(File.join(dir, "apply.cmd"), "wb") { |f| f.write(apply_script(dir, version, Process.pid, exe)) }
        if start_apply(dir)
          pbMessage(_INTL("KIF Beta {1} is ready. The game closes now and starts again in a moment.", version))
          (KIF::SessionLog.finish rescue nil) if defined?(KIF::SessionLog)
          Win.quit_now
          return true
        end
        pbMessage(_INTL("The update window couldn't be started. The new files are in \"{1}\".", STAGE_DIR))
        return false
      end
      apply_in_ruby(dir)
      return restart_after_apply(version)
    end

    #---------------------------------------------------------------------------
    # Asking
    #---------------------------------------------------------------------------
    def show_notes(base)
      text = base ? fetch(url_for(base, NOTES)) : nil
      text = File.binread(File.join(root, NOTES)) if text.nil? && File.file?(File.join(root, NOTES))
      lines = text.to_s.force_encoding("UTF-8").split(/\r?\n/).map(&:strip).reject(&:empty?)
      if lines.empty?
        pbMessage(_INTL("No notes for this version."))
        return
      end
      lines.each_slice(3) { |chunk| pbMessage(chunk.join("\n")) }
    end

    # Stable asked, nothing there, but the beta branch answers: the release
    # branch simply doesn't exist yet (not a network problem)
    def no_stable_yet?(ch, base)
      return false unless ch == 0
      beta = source(1)
      return false if beta.nil? || beta == base   # a test source overrides both
      return !remote_version(beta).nil?
    end

    # at the load screen (manual: from Options, also says "up to date")
    def check(manual = false)
      ch = channel
      return false if ch == 2 && !manual
      ch = default_channel if ch == 2
      base = source(ch)
      return false unless base
      v = remote_version(base)
      if v.nil?
        log("no version found at #{base}")
        return false unless manual
        if no_stable_yet?(ch, base)
          pbMessage(_INTL("No stable release has been published yet. Set Updates to Beta (Options > System) to get test builds."))
        else
          pbMessage(_INTL("Couldn't reach the update server. Try again later."))
        end
        return false
      end
      unless newer?(v, current_version)
        pbMessage(_INTL("KIF Beta {1} is the newest {2} version.", current_version, ch == 1 ? _INTL("beta") : _INTL("stable"))) if manual
        return false
      end
      if !manual && $PokemonSystem && $PokemonSystem.kif_update_skip.to_s == v
        return false
      end
      in_game = manual && $scene.is_a?(Scene_Map)
      loop do
        cmd = pbMessage(_INTL("KIF Beta {1} is out (you have {2}).", v, current_version),
                        [_INTL("Update now"), _INTL("What's new"), _INTL("Later"), _INTL("Skip this version")], 3)
        case cmd
        when 0
          return update(base, v, in_game)
        when 1
          show_notes(base)
        when 3
          $PokemonSystem.kif_update_skip = v if $PokemonSystem
          pbMessage(_INTL("You won't be asked about {1} again. Options > System > Check for Updates still finds it.", v))
          return false
        else
          return false
        end
      end
    rescue StandardError => e
      hide_status
      log("check failed (#{e.class}: #{e.message}) #{e.backtrace.first(3).join(' | ')}")
      return false
    end

    # An update that was moved in (or wasn't) since the last start
    def after_update
      dir0 = stage_root
      return unless File.directory?(dir0)
      Dir.children(dir0).sort.each do |v|
        dir = File.join(dir0, v)
        next unless File.directory?(dir)
        if File.file?(File.join(dir, "done.txt"))
          rm_tree(dir)
          if v == current_version
            log("updated to #{v}")
            cmd = pbMessage(_INTL("KIF Beta was updated to {1}.", v), [_INTL("OK"), _INTL("What's new")], 1)
            show_notes(nil) if cmd == 1
          end
        # failed.txt: the move stopped partway (the scripts, and so the version, may already be new)
        elsif !newer?(current_version, v) &&
              (File.file?(File.join(dir, "failed.txt")) || (File.file?(File.join(dir, "apply.cmd")) && v != current_version))
          cmd = pbMessage(_INTL("The update to KIF Beta {1} didn't finish (a file was in use).", v),
                          [_INTL("Try again"), _INTL("Discard it")], 0)
          if cmd == 0 && !update_window?
            File.delete(File.join(dir, "failed.txt")) rescue nil
            apply_in_ruby(dir)
            restart_after_apply(v)
          elsif cmd == 0
            File.delete(File.join(dir, "failed.txt")) rescue nil
            # written again: the old script waits for the game that wrote it,
            # whose process id may now belong to another program
            exe = Win.exe_path || File.join(root, "InfiniteFusion.exe")
            File.open(File.join(dir, "apply.cmd"), "wb") { |f| f.write(apply_script(dir, v, Process.pid, exe)) }
            if start_apply(dir)
              (KIF::SessionLog.finish rescue nil) if defined?(KIF::SessionLog)
              Win.quit_now
            end
          else
            rm_tree(dir)
          end
        elsif !File.file?(File.join(dir, "apply.cmd")) && (newer?(current_version, v) || v == current_version)
          rm_tree(dir)   # an unfinished download of a version we already have
        end
      end
      Dir.rmdir(dir0) if File.directory?(dir0) && Dir.children(dir0).empty?
    rescue StandardError => e
      log("after-update check failed (#{e.class}: #{e.message})")
    end
  end
end

KIF::Options.define(:kif_updates, KIF::Updater.default_channel, :global)   # 0 Stable, 1 Beta, 2 Off
KIF::Options.define(:kif_update_skip, "", :global)

KIF::Options.add(:others, :global) {
  EnumOption.new(_INTL("Updates"), [_INTL("Stable"), _INTL("Beta"), _INTL("Off")],
                 proc { $PokemonSystem.kif_updates },
                 proc { |value| $PokemonSystem.kif_updates = value },
                 [_INTL("At start-up, KIF checks for new releases and offers to update"),
                  _INTL("Also offers test builds (may have bugs)"),
                  _INTL("KIF never checks for updates by itself")])
}
KIF::Options.add(:others, :global) {
  ButtonOption.new(_INTL("Check for Updates"), proc { KIF::Updater.check(true) },
                   _INTL("Looks for a newer KIF Beta now"))
}

# The load screen's version check (PIF's spot). KIF's own check runs here
# and PIF's is never asked: it would tell KIF players to use PIF's installer
# whenever PIF releases a newer version.
def find_newer_available_version
  KIF::Updater.after_update
  KIF::Updater.check(false)
  return nil
end
