#===============================================================================
# C-SYS-06 – KIF updater (2026-10-11; replaces PIF's "use the
# installer" prompt, which C-SYS-02 hides)
#
# At the load screen (where PIF asked about its own versions) KIF reads the
# version of the newest build on GitHub (one tiny file). If it is newer than
# this one: "KIF X is out (you have Y)" - Update now / What's new /
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
#   * at every start, editor and repo-script files older builds left
#     (DEV_LEFTOVERS, never in a file list) are removed, but not in a git checkout;
#   * the game closes; a small "KIF update" window waits for it, moves the
#     new files in (robocopy) and starts the game again; the next start says
#     "KIF was updated to X". If moving fails (a file in use), the next
#     start offers to try again.
# Downloads run in the background through Windows' own curl.exe (no window),
# so the progress bar moves and B cancels; without curl, KIF downloads one
# file at a time itself.
# Phones (JoiPlay, Kirin; 2026-10-23) and Wine/Proton can't start programs,
# so once every file is downloaded and checked the game moves them in itself
# (apply_in_ruby): scripts last, then the file list, removals, Data/VERSION.
# "failed.txt" says "moving" meanwhile; if the game is closed then, the next
# start finishes the move before KIF's scripts load (000_0UpdateFinish.rb).
# A phone can't restart the game: the player is asked to close and reopen it.
# A phone whose game folder is read-only only gets told (phone_notice).
#
# Where builds come from (github.com/cody-png/codybeta):
#   Stable - the "release" branch (moves only when a release is published)
#   Beta   - the "beta-testing" branch (new versions before they reach Stable)
#   Test   - the "test" branch of the private repo cody-png/kif-test (2026-10-25),
#            read with a test code: a GitHub fine-grained token (that repo only,
#            Contents read-only) Cody makes per tester and can cancel. Options >
#            System > Test Code takes it (pasted); it is kept in KIF_updates.kro
#            in the save folder, sent only to TEST_BASE over HTTPS (curl: in its
#            config file in the save folder, never on the command line) and
#            masked in the log and on screen. Test builds are numbered
#            <released version>-test.<n> (1.2.3-test.1): the compare reads only
#            the numbers, so that is newer than 1.2.3 and older than 1.2.4.
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
    TEST       = 3                                    # channel 3 Test (2 is Off)
    TEST_BASE  = "https://raw.githubusercontent.com/cody-png/kif-test/test"
    CODE_SHAPE = /\Agithub_pat_[A-Za-z0-9_]{30,250}\z/   # GitHub fine-grained tokens
    CODE_REFUSED = [401, 403, 404]                    # GitHub's answer to a cancelled, expired or wrong code
    MANIFEST   = "Data/KIF/update_manifest.txt"
    STAGED_MANIFEST = "manifest.txt"   # in the update folder, beside files/
    NOTES      = "Data/KIF/update_notes.txt"
    VERSION_FILE = "Data/VERSION"
    STAGE_DIR  = "KIF Update"
    SOURCE_FILE = "KIF_update_source.txt"
    REMOVABLE  = %w[Data/ Graphics/ Audio/ Fonts/]
    KEEP_THEIRS = %w[Graphics/CustomBattlers/ Graphics/Battlers/]   # player-installed sprites
    NEVER      = %w[Mods/ Logs/ Import\ Sprites/ KIF\ Update/ Graphics/CustomBattlers/local_sprites/ Cache/ ExportedPokemons/]
    RETIRED    = %w[BETA_TESTING.md]   # outside REMOVABLE, once shipped to Stable by mistake: removed when the new list drops them
    # never in any file list (PIF's own Data/.idea, zips before 2026-10-09), so plan() can't remove them
    DEV_LEFTOVERS = %w[.idea Data/.idea Data/.DS_Store build_release.cmd push_branches.cmd push_stable.cmd publish_release.cmd]

    Manifest = Struct.new(:version, :channel, :files)   # files: path => [sha, size]

    #---------------------------------------------------------------------------
    # Small helpers
    #---------------------------------------------------------------------------
    module_function

    # the folder the game runs in: Data, Graphics and Mods live here, also in
    # a "Game Files" layout (only Logs / Import Sprites sit next to the .exe)
    def root
      return File.expand_path(".")   # JoiPlay rewrites the usual working-folder call to ""
    end

    # the last check got no version back (offline, blocked, filtered)
    def unreachable
      return @unreachable ? true : false
    end

    # in the game folder; the save folder when that can't be written
    def stage_root
      return File.expand_path(KIF::Paths.writable(STAGE_DIR))
    end

    def log(msg)
      KIF.log("Updater: #{mask(msg)}") if defined?(KIF.log)
    end

    # a test code shown as github_pat_...<last 4> (log, screen)
    def mask(text)
      return text.to_s.gsub(/github_pat_[A-Za-z0-9_]+/) { |c| "github_pat_..." + c[-4, 4] }
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
      return %w[beta test].include?(installed_channel) ? 1 : 0
    end

    # Updates (Stable / Beta / Off) and "Skip this version" are often picked
    # on the load screen, before there's a save to write them into, so they
    # are also kept in a small file in the save folder (Cody, 2026-10-19)
    CHOICES_FILE = "KIF_updates.kro"

    def choices_path
      return File.join(KIF.save_dir, CHOICES_FILE)
    end

    def stored_choices
      h = {}
      return h unless File.file?(choices_path)
      File.read(choices_path).split(/\r?\n/).each do |l|
        k, v = l.split("=", 2)
        h[k] = v.to_s if k && !k.empty?
      end
      return h
    rescue StandardError
      return {}
    end

    def store_choice(key, value)   # nil removes the key
      h = stored_choices
      value.nil? ? h.delete(key.to_s) : h[key.to_s] = value.to_s
      KIF.mkdir_p(KIF.save_dir)
      File.open(choices_path, "wb") { |f| f.write(h.map { |k, v| "#{k}=#{v}" }.join("\r\n")) }
    rescue StandardError => e
      log("couldn't keep the update choice (#{e.class}: #{e.message})")
    end

    def channel
      c = stored_choices["channel"]
      c = if c =~ /\A[0-3]\z/ then c.to_i
          elsif $PokemonSystem && $PokemonSystem.respond_to?(:kif_updates) then $PokemonSystem.kif_updates.to_i
          else 2
          end
      return c == TEST && !test_code ? 1 : c   # Test without a code: Beta
    end

    def code_shape?(code)
      return code.to_s =~ CODE_SHAPE ? true : false
    end

    def test_code
      c = stored_choices["test_code"]
      return code_shape?(c) ? c : nil
    end

    # the code goes to the test repo over HTTPS only, never anywhere else
    # (@trying_code: a code being checked before it is kept)
    def auth_headers(url)
      return nil unless url.to_s.start_with?(TEST_BASE + "/")
      code = @trying_code || test_code
      return code_shape?(code) ? { "Authorization" => "token #{code}" } : nil
    end

    # GitHub turned the test code down (not: the server couldn't be reached, nor
    # a file a newer test build dropped mid-download: Data/VERSION is read again)
    def code_refused?(base)
      return false unless base == TEST_BASE && CODE_REFUSED.include?(@last_status)
      return remote_version(base).nil? && CODE_REFUSED.include?(@last_status)
    end

    # curl's list of test-repo files with the code's header (Windows): removed
    # after each download, and at start-up and on leaving in case a download was cut off
    def auth_cfg_path
      return File.join(File.expand_path(KIF.save_dir), "KIF_download.cfg")
    end

    def remove_auth_cfg
      (File.delete(auth_cfg_path) if File.file?(auth_cfg_path)) rescue nil
    end

    def skipped_version
      return stored_choices["skip"] || ($PokemonSystem && $PokemonSystem.kif_update_skip).to_s
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
          line = file_url(line) if !(line =~ %r{\A\w+://}) && File.directory?(line)
          return line.chomp("/")
        end
      end
      return TEST_BASE if ch == TEST
      branch = BRANCHES[ch]
      return branch ? "#{RAW_BASE}/#{branch}" : nil
    end

    # file:/// URL of a local folder (a test source, a local mod catalog)
    def file_url(dir)
      full = File.expand_path(dir).tr("\\", "/").sub(%r{\A/}, "")
      return "file:///" + full.split("/").map { |seg| seg.b.gsub(/[^A-Za-z0-9\-._~:]/n) { |c| format("%%%02X", c.ord) } }.join("/")
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
    # (@last_status: the answer's HTTP status, 0 for none)
    def fetch(url)
      @last_status = 0
      if url.start_with?("file:")
        path = file_url_path(url)
        return File.file?(path) ? File.binread(path) : nil
      end
      return nil unless defined?(HTTPLite)
      t = Time.now
      auth = auth_headers(url)
      # mkxp-z's HTTPLite.get follows no redirect unless a third argument asks: the code stays on TEST_BASE
      res = auth ? HTTPLite.get(url, auth) : HTTPLite.get(url)
      @last_status = res[:status].to_i if res.is_a?(Hash)
      secs = Time.now - t
      unless res.is_a?(Hash) && res[:status].to_i == 200
        log(format("%s answered %s after %.1fs", url, res.is_a?(Hash) ? res[:status].inspect : "nothing", secs))
        return nil
      end
      # slow or big answers only: the one-at-a-time fallback fetches thousands
      bytes = res[:body].to_s.bytesize
      log(format("%s: %s in %.1fs", url, size_text(bytes), secs)) if secs >= 2 || bytes >= 1048576
      return res[:body]
    rescue StandardError, (defined?(MKXPError) ? MKXPError : StandardError) => e
      log("#{url} not read (#{e.class}: #{e.message})")
      return nil
    end

    def remote_version(base)
      v = fetch(url_for(base, VERSION_FILE)).to_s.strip
      return v =~ /\A\d+(\.\d+)*(-test\.\d+)?\z/ ? v : nil
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
      return RETIRED.include?(path) || (under?(path, REMOVABLE) && !under?(path, NEVER))
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
          # a sprite sheet PIF re-downloaded since (no longer as shipped) is newer art: kept
          same = true if !same && l && under?(path, KEEP_THEIRS) && File.file?(here) && !good_file?(here, *l)
        elsif under?(path, KEEP_THEIRS)
          same = File.file?(here)           # no manifest: keep installed sprites
        else
          same = File.file?(here) && File.size(here) == size && (!sha_ok? || git_sha(here) == sha)
        end
        downloads << [path, sha, size] unless same
      end
      removals = []
      if local
        # a name that only changes case is the same file on Windows/Android: never removed after the new one moved in
        new_names = {}
        remote.files.each_key { |p| new_names[p.downcase] = true }
        local.files.each_key do |path|
          next if new_names[path.downcase] || !removable?(path)
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
      return false if KIF.respond_to?(:mobile?) && KIF.mobile?   # JoiPlay fakes part of Win32API
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
      CREATE_UNICODE_ENVIRONMENT = 0x00000400
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
        # the environment the game started with: Steam (Multiplayer) adds SDL_GAMECONTROLLER_IGNORE_DEVICES
        # and more to this one, and a copy started with those saw no controller (F12, update restart)
        env = $kif_start_env.is_a?(Hash) && !$kif_start_env.empty? ? wide($kif_start_env.map { |k, v| "#{k}=#{v}\0" }.join) : nil
        flags |= CREATE_UNICODE_ENVIRONMENT if env
        ok = api("kernel32", "CreateProcessW", %w[p p p p i L p p p p], "i")
               .call(nil, wide(cmdline), nil, nil, 0, flags, env, cwd ? wide(cwd) : nil, si, pi)
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

      # Ends this game at once (~0.1 s in the real engine, as Kernel.exit! alone).
      # In 0.21.56 the game "left open" was waiting at the message before it.
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
      title ||= _INTL("Updating to KIF {1}", version)
      status(title, _INTL("Checking downloaded files...")) if File.directory?(File.join(dir, "files"))
      todo = items.reject { |path, sha, size| good_file?(staged(dir, path), sha, size) }   # resumed downloads
      curl = !todo.empty? && windows? && Win.curl
      log("downloading #{todo.length} of #{items.length} files (#{size_text(total)} in all) #{curl ? 'with curl' : 'one at a time'}")
      if curl
        # the test code: in a config file in the save folder (removed below), never on the command line, which other programs can read
        auth = auth_headers(url_for(base, VERSION_FILE))
        auth_cfg = auth ? auth_cfg_path : nil
        cfg = auth_cfg || File.join(dir, "download.cfg")
        mkdir_p(dir)   # a mod install's staging folder doesn't exist yet (1.0.1: every Windows mod install failed here)
        File.open(cfg, "wb") do |f|
          auth.each { |k, v| f.write("header = #{curl_quote("#{k}: #{v}")}\n") } if auth
          todo.each do |path, _sha, _size|
            f.write("url = #{curl_quote(url_for(base, path))}\n")
            f.write("output = #{curl_quote(win_path(staged(dir, path)))}\n")
          end
        end
        err = File.join(dir, "curl_errors.txt")
        # -q first: the player's own .curlrc is never read (its "verbose" wrote the code into curl_errors.txt);
        # no -L with the code: an old Windows curl (7.55) sends the header along to any host a redirect names
        cmd = "\"#{win_path(curl)}\" -q -K \"#{win_path(cfg)}\" --parallel --parallel-max 6 --create-dirs " \
              "--fail --retry 3 --retry-delay 1 --connect-timeout 15#{auth ? '' : ' -L'} -s -S --stderr \"#{win_path(err)}\""
        h, _pid = Win.spawn(cmd, Win::CREATE_NO_WINDOW, root)
        log("curl couldn't be started") unless h
        if h
          started = Time.now
          code = nil   # read after the loop
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
              log(format("cancelled after %.0fs", Time.now - started))
              return :cancelled
            end
            break if code
          end
          Win.close(h)
          secs = [Time.now - started, 0.1].max
          got = todo.inject(0) { |s, (path, _sha, _size)| p = staged(dir, path); s + (File.file?(p) ? File.size(p) : 0) }
          errors = File.file?(err) ? File.read(err).lines.map(&:strip).reject(&:empty?) : []
          log(format("curl finished in %.0fs, %s (%s/s), exit code %s, %d error lines%s", secs, size_text(got),
                     size_text((got / secs).to_i), code.inspect, errors.length, errors.empty? ? "" : ": " + errors.first(3).join(" | ")))
        end
      end
      # whatever is still missing or wrong: one at a time
      failed = []
      # (without curl, todo was just checked: every staged file read again would double a phone's wait)
      bad = curl ? items.reject { |path, sha, size| good_file?(staged(dir, path), sha, size) } : todo
      log("#{bad.length} files left for one at a time") unless bad.empty? || todo.empty? || !curl
      last = 0
      streak = 0   # out here: a variable first set inside the block starts again for every file
      bad.each_with_index do |(path, sha, size), i|
        # drawn 4 times a second: a frame per file added minutes to thousands of files
        if Time.now.to_f - last > 0.25 || i + 1 == bad.length
          last = Time.now.to_f
          status(title, _INTL("{1} ({2} of {3})", File.basename(path), i + 1, bad.length),
                 (i + 1).to_f / bad.length, _INTL("{1}: cancel (you can update later)", KIF::Keys.name(Input::BACK)))
        else
          Input.update
        end
        return :cancelled if cancel_pressed?
        data = fetch(url_for(base, path))
        dest = staged(dir, path)
        if data
          mkdir_p(File.dirname(dest))
          File.open(dest, "wb") { |f| f.write(data) }
        end
        if good_file?(dest, sha, size)
          streak = 0
        else
          failed << path
          streak += 1
          # the server is gone: don't spend an hour trying every file (what was fetched is kept)
          if streak >= 20
            failed.concat(bad[(i + 1)..-1].map(&:first))
            log("one at a time: 20 failures in a row, stopped")
            break
          end
        end
      end
      log("one at a time: #{bad.length - failed.length} of #{bad.length} fetched") unless bad.empty?
      return failed
    ensure
      (File.delete(auth_cfg) if auth_cfg && File.file?(auth_cfg)) rescue nil
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
      lines << "echo Finishing the KIF #{version} update. This window closes by itself."
      # the game closes itself (gone ~0.1 s after starting this): the first 10 tries
      # look again at once, then once a second; one still open after ~20 s more is closed here
      lines << "set /a waited=0"
      lines << ":wait"
      lines << "tasklist /FI \"PID eq #{pid}\" 2>nul | find \"#{pid}\" >nul"
      lines << "if errorlevel 1 goto go"
      lines << "set /a waited+=1"
      lines << "if %waited% GEQ 30 taskkill /PID #{pid} /F >nul 2>&1"
      lines << "if %waited% GEQ 10 timeout /t 1 /nobreak >nul"
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

    # Without Windows (phones, Wine, the kit): move the files in now; the game
    # uses them from the next start. Scripts are read once at start-up and an
    # open sound or font keeps its old file on Android/Linux, so replacing
    # files under the running game is safe. Under Wine a file the game has
    # open (the .exe, its DLLs) is renamed aside instead (UpdateFinish.discard).
    def apply_in_ruby(dir)
      files = File.join(dir, "files")
      failed = File.join(dir, "failed.txt")
      # stays if anything below raises or the game is closed: 000_0UpdateFinish.rb finishes it
      File.open(failed, "wb") { |f| f.write(KIF::UpdateFinish::MOVING) }
      list = KIF::UpdateFinish.staged_files(files)
      title = _INTL("Installing KIF {1}", File.basename(dir))
      last = 0
      list.each_with_index do |rel, i|
        if Time.now.to_f - last > 0.25
          last = Time.now.to_f
          status(title, _INTL("{1} of {2} files", i + 1, list.length), (i + 1).to_f / list.length, _INTL("Don't close the game."))
        end
        KIF::UpdateFinish.move(File.join(files, rel), File.join(root, rel))
      end
      hide_status
      moved = list.length
      man = File.join(dir, STAGED_MANIFEST)
      KIF::UpdateFinish.move(man, File.join(root, MANIFEST)) if File.file?(man)
      rm_file = File.join(dir, "remove.txt")
      if File.file?(rm_file)
        File.read(rm_file).force_encoding("UTF-8").split(/\r?\n/).each do |rel|
          rel = rel.tr("\\", "/")
          next if rel.empty? || !removable?(rel)
          p = File.join(root, rel)
          KIF::UpdateFinish.discard(p) if File.file?(p)
        end
      end
      # the version last: an update cut off before here is still the old one's
      ver = File.join(files, VERSION_FILE)
      if File.file?(ver)
        KIF::UpdateFinish.move(ver, File.join(root, VERSION_FILE))
        moved += 1
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
        pbMessage(_INTL("KIF {1} is installed. The game restarts now.", version) + "\\wtnp[20]")   # no button: it says "now"
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
      pbMessage(_INTL("KIF {1} is installed. Close the game and start it again to use it.", version))
      # phones: the old scripts must not keep running on the new maps and data
      unless exe
        log("#{version}: moved in by the game, closing")
        (KIF::SessionLog.finish rescue nil) if defined?(KIF::SessionLog)
        close_game
      end
      return true
    end

    def close_game
      exit
    end

    #---------------------------------------------------------------------------
    # The whole update; true when the game is about to close for it
    #---------------------------------------------------------------------------
    def update(base, version, in_game = false)
      unless KIF::Paths.game_writable? && writable?(stage_root)
        pbMessage(_INTL("The game folder can't be written to, so KIF can't update itself here (a folder like Program Files?)."))
        pbMessage(_INTL("Get KIF {1} from {2}", version, PAGE)) unless base == TEST_BASE   # the release page has no test builds
        return false
      end
      status(_INTL("Updating to KIF {1}", version), _INTL("Reading the file list..."))
      body = fetch(url_for(base, MANIFEST))
      remote = parse_manifest(body)
      if !remote || remote.version.to_s != version
        hide_status
        return test_code_refused if code_refused?(base)
        pbMessage(_INTL("The file list for KIF {1} couldn't be read. Try again later.", version))
        log("manifest for #{version} unreadable (got #{remote ? remote.version : 'nothing'})")
        return false
      end
      local = local_manifest
      status(_INTL("Updating to KIF {1}", version), _INTL("Checking your files...")) unless local
      t = Time.now
      plan = plan(local, remote)
      # without a local list every file is read and hashed: minutes of disk and CPU
      log(format("files compared in %.1fs (%s)", Time.now - t, local ? "from the local file list" : "no local file list, every file hashed"))
      hide_status
      n = plan[:downloads].length
      if n == 0 && plan[:removals].empty?
        pbMessage(_INTL("Your files already match KIF {1}.", version))
        return false
      end
      msg = _INTL("{1} files to download ({2}).", n, size_text(plan[:bytes]))
      # every platform closes the game once the update is moved in (Windows and Wine start it again, phones don't)
      msg += " " + _INTL("Any progress since your last save will be lost when the game closes for the update.") if in_game
      return false unless pbConfirmMessage(msg + " " + _INTL("Update now?"))
      dir = File.join(stage_root, version)
      mkdir_p(File.join(dir, "files"))
      begin
        result = download(base, plan[:downloads], dir, version)
      rescue Errno::ENOSPC
        hide_status
        log("#{version}: the device is full")
        pbMessage(_INTL("There isn't enough free space for the update ({1} needed). What was downloaded is kept for next time.", size_text(plan[:bytes])))
        return false
      end
      hide_status
      if result == :cancelled
        pbMessage(_INTL("Update cancelled. What was downloaded is kept for next time."))
        return false
      end
      unless result.empty?
        log("#{result.length} files failed: #{result.first(5).join(', ')}")
        return test_code_refused if code_refused?(base)   # nothing is moved in: the game stays as it was
        pbMessage(_INTL("{1} files couldn't be downloaded. Check your connection and try again later.", result.length))
        return false
      end
      # the list the plan was made from: kept beside files/ and moved in only
      # after every file is in, so a failed move can't leave a new list over
      # old files (the next update trusts the list)
      File.open(File.join(dir, STAGED_MANIFEST), "wb") { |f| f.write(body) }
      File.open(File.join(dir, "remove.txt"), "wb") { |f| f.write(plan[:removals].map { |p| win_path(p) }.join("\r\n")) }
      File.open(File.join(dir, "version.txt"), "wb") { |f| f.write(version) }
      File.open(File.join(dir, "from.txt"), "wb") { |f| f.write(current_version) }   # What's new after the update
      log("#{version}: #{n} files (#{size_text(plan[:bytes])}) downloaded, #{plan[:removals].length} to remove")
      if update_window?
        exe = Win.exe_path || File.join(root, "InfiniteFusion.exe")
        File.open(File.join(dir, "apply.cmd"), "wb") { |f| f.write(apply_script(dir, version, Process.pid, exe)) }
        # goes on by itself: it waited for a button, so the game sat there until the update
        # window's backstop killed it, with no end line in the log (Cody, 2026-10-25). The
        # window starts after it, so it can't cover the message or take its key presses.
        pbMessage(_INTL("KIF {1} is ready. The game closes now and starts again in a moment.", version) + "\\wtnp[20]")
        if start_apply(dir)
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
    # The notes file keeps older versions' notes below the newest, each under
    # its "KIF 1.2.4" line: shown is what is newer than since (the version
    # the player has, or had before the update), else the newest version's.
    NOTES_HEAD = /\AKIF (\d\S*)\z/

    def show_notes(base, since = base && current_version)
      text = base ? fetch(url_for(base, NOTES)) : nil
      text = File.binread(File.join(root, NOTES)) if text.nil? && File.file?(File.join(root, NOTES))
      lines = text.to_s.force_encoding("UTF-8").split(/\r?\n/).map(&:strip).reject(&:empty?)
      if lines.empty?
        pbMessage(_INTL("No notes for this version."))
        return
      end
      sections = lines.slice_before { |l| l =~ NOTES_HEAD }.to_a
      shown = since ? sections.select { |s| !(v = s[0][NOTES_HEAD, 1]) || newer?(v, since) } : []
      shown = sections.first(1) if shown.empty?
      # the Update history's full-screen reader (Updater_History.rb), not 3-line
      # message boxes over a black screen; B or A closes it (Cody, 2026-10-26)
      show_text(_INTL("What's new"), shown.flatten)
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
    # A copy installed as one fixed version (the installer's "this version
    # only", which leaves KIF_pinned.txt next to the game): no automatic
    # update check; Options > Check for Updates still asks
    PINNED_FILE = "KIF_pinned.txt"

    def pinned
      path = File.join(root, PINNED_FILE)
      return nil unless File.file?(path)
      v = File.read(path).to_s.strip
      return v.empty? ? current_version : v
    rescue StandardError
      return nil
    end

    def check(manual = false)
      ch = channel
      return false if ch == 2 && !manual
      if !manual && (pin = pinned)
        log("pinned to KIF #{pin} (#{PINNED_FILE}): no automatic update check")
        return false
      end
      ch = default_channel if ch == 2
      base = source(ch)
      return false unless base
      v = remote_version(base)
      @unreachable = v.nil?   # the load screen skips the mod check then (Updater_Startup.rb)
      if v.nil?
        log("no version found at #{base}")
        return test_code_refused if code_refused?(base)
        return false unless manual
        if no_stable_yet?(ch, base)
          pbMessage(_INTL("No stable release has been published yet. Set Updates to Beta (Options > System) to get the newest version."))
        else
          pbMessage(_INTL("Couldn't reach the update server. Try again later."))
        end
        return false
      end
      unless newer?(v, current_version)
        pbMessage(_INTL("KIF {1} is the newest {2} version.", current_version,
                        { 1 => _INTL("beta"), TEST => _INTL("test") }[ch] || _INTL("stable"))) if manual
        return false
      end
      if !manual && skipped_version == v
        return false
      end
      # a phone whose game folder can be written updates like a computer
      return phone_notice(base, v, manual) if KIF.mobile? && !(KIF::Paths.game_writable? && writable?(stage_root))
      in_game = manual && $scene.is_a?(Scene_Map)
      loop do
        cmd = pbMessage(_INTL("KIF {1} is out (you have {2}).", v, current_version),
                        [_INTL("Update now"), _INTL("What's new"), _INTL("Later"), _INTL("Skip this version")], 3)
        case cmd
        when 0
          return update(base, v, in_game)
        when 1
          show_notes(base)
        when 3
          $PokemonSystem.kif_update_skip = v if $PokemonSystem
          store_choice("skip", v)
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

    #---------------------------------------------------------------------------
    # Test code (Options > System > Test Code)
    #---------------------------------------------------------------------------
    def test_code_menu
      if test_code
        cmd = pbMessage(_INTL("Test code: {1}", mask(test_code)),
                        [_INTL("Leave Test builds"), _INTL("Enter a new code"), _INTL("Back")], 3)
        return leave_test if cmd == 0
        return false unless cmd == 1
      end
      return enter_test_code
    rescue StandardError => e
      hide_status
      log("test code menu failed (#{e.class}: #{e.message})")
      return false
    end

    # pasted (as Multiplayer's join codes) or typed; shown masked once entered
    def enter_test_code
      clip = (Input.clipboard.to_s rescue "").strip
      text = code_shape?(clip) ? clip : ""
      loop do
        help = if text.empty? then _INTL("Paste the test code you were sent.")
               elsif code_shape?(text) then _INTL("Code looks right.")
               else _INTL("That isn't a test code. Test codes start with github_pat_.")
               end
        shown = text.empty? ? "_" : (code_shape?(text) ? mask(text) : "?")
        case pbMessage(_INTL("Test code: {1}\n{2}", shown, help),
                       [_INTL("Paste"), _INTL("Type the code"), _INTL("Use this code"), _INTL("Back")], 4)
        when 0 then text = (Input.clipboard.to_s rescue "").strip
        when 1 then text = (pbMessageFreeText(_INTL("Test code:"), "", true, 255) || text).strip   # a password box
        when 2
          next pbMessage(help) unless code_shape?(text)
          return use_test_code(text)
        else return false
        end
      end
    end

    # checked by reading the test build's Data/VERSION with it
    def use_test_code(code)
      # an engine without a save folder keeps saves (and KIF_updates.kro) in the game folder, which people copy and share
      if File.expand_path(KIF.save_dir) == File.expand_path(root)
        log("test code not kept: the save folder is the game folder")
        pbMessage(_INTL("Test codes can't be used in this copy of the game: it keeps its saves in the game folder, which gets copied and shared."))
        return false
      end
      status(_INTL("Test builds"), _INTL("Checking the code..."))
      begin
        @trying_code = code
        v = remote_version(TEST_BASE)
      ensure
        @trying_code = nil
      end
      hide_status
      unless v
        refused = CODE_REFUSED.include?(@last_status)
        log("test code #{mask(code)} not accepted (#{refused ? "GitHub answered #{@last_status}" : 'no answer'})")
        pbMessage(refused ? _INTL("This code doesn't work. It may have been cancelled or run out. Ask for a new one.") :
                            _INTL("Couldn't reach the update server. Try again later."))
        return false
      end
      store_choice("test_code", code)
      store_choice("channel", TEST)
      unless test_code == code && channel == TEST   # KIF_updates.kro couldn't be written
        log("test code #{mask(code)} works but couldn't be kept in #{CHOICES_FILE}")
        pbMessage(_INTL("The code works, but it couldn't be kept: KIF can't write to its save folder. Try again later."))
        return false
      end
      # off the clipboard, where another Paste (Multiplayer's join code) would show it
      (Input.clipboard = "" if (Input.clipboard.to_s.strip rescue "") == code) rescue nil
      $PokemonSystem.kif_updates = TEST if $PokemonSystem
      log("test code #{mask(code)} accepted: Updates set to Test (newest test build #{v})")
      pbMessage(_INTL("The code works. Updates is now set to Test."))
      check(true) if pbConfirmMessage(_INTL("Look for a test build now?"))
      return true
    end

    def leave_test
      store_choice("test_code", nil)
      store_choice("channel", 1)
      remove_auth_cfg
      if test_code   # KIF_updates.kro couldn't be written
        log("left Test builds: the code couldn't be removed from #{CHOICES_FILE}")
        pbMessage(_INTL("Your test code couldn't be removed: KIF can't write to its save folder. Try again later."))
        return false
      end
      $PokemonSystem.kif_updates = 1 if $PokemonSystem
      log("left Test builds: code removed, Updates set to Beta")
      pbMessage(_INTL("Updates is set to Beta and your test code is removed. You get the next Beta that is newer than this version."))
      return true
    end

    # a cancelled or expired code: said plainly, with the way back to Beta
    def test_code_refused
      log("the test code was turned down (GitHub answered #{@last_status})")
      if pbConfirmMessage(_INTL("Your test code doesn't work any more (it was cancelled or ran out). Go back to Beta updates?"))
        leave_test
      else
        pbMessage(_INTL("You can enter a new code in Options > System > Test Code."))
      end
      return false
    end

    # Phones whose game folder can't be written: nothing is
    # downloaded; the player installs the new full game from the release
    # page. Said once per version at start-up; Check for Updates always says it.
    RELEASE_PAGE = "https://github.com/#{REPO}/releases/latest"

    def phone_notice(base, v, manual)
      return false if !manual && stored_choices["phone_told"] == v
      store_choice("phone_told", v)
      log("#{v} is out: told the player (phone, no download)")
      loop do
        cmd = pbMessage(_INTL("KIF {1} is out (you have {2}).", v, current_version), [_INTL("What's new"), _INTL("OK")], 2)
        break unless cmd == 0
        show_notes(base)
      end
      if base == TEST_BASE   # the release page has no test builds
        pbMessage(_INTL("Test builds can't be installed on this phone: KIF can't write to its game folder here."))
        return false
      end
      copied = begin
                 Input.clipboard = RELEASE_PAGE
                 true
               rescue StandardError, NameError
                 false
               end
      pbMessage(copied ? _INTL("On phones KIF can't update itself. The link to the full new version is copied:\n{1}", RELEASE_PAGE) :
                         _INTL("On phones KIF can't update itself. Get the full new version here:\n{1}", RELEASE_PAGE))
      return false
    end

    # Format twins (1.2.0 turned ~1,800 WAVs/MP3s into Oggs): an installer
    # copied over an older KIF never deletes, so "x.wav" stays beside the
    # shipped "x.ogg", and the game tries .wav and .mp3 before .ogg. Once per
    # version, an Audio/ file the installed file list doesn't have is removed
    # when the list has the same name in another audio format and that file
    # is really there (a stale list, as in a dev checkout, never costs the
    # only copy of a sound) and is newer (a sound the player put in after
    # installing, to replace a shipped one, is theirs). Kept per game folder:
    # two installs can share the save folder.
    AUDIO_EXTS = %w[.wav .mp3 .ogg .mid .midi .wma]

    def twins_key(dir = root); "twins:" + File.expand_path(dir).downcase; end

    def remove_format_twins(dir = root)
      key = twins_key(dir)
      return 0 if stored_choices[key] == current_version || !KIF::Paths.game_writable?
      man = local_manifest
      return 0 unless man
      listed = {}
      stems = {}
      man.files.each_key do |p|
        listed[p.downcase] = true   # Windows and Android storage ignore case
        ext = File.extname(p).downcase
        (stems[p[0, p.length - ext.length].downcase] ||= []) << p if p.start_with?("Audio/") && AUDIO_EXTS.include?(ext)
      end
      removed = 0
      walk = lambda do |rel|
        Dir.children(File.join(dir, rel)).each do |c|
          r = "#{rel}/#{c}"
          full = File.join(dir, r)
          next walk.call(r) if File.directory?(full)
          ext = File.extname(c).downcase
          twins = AUDIO_EXTS.include?(ext) && !listed[r.downcase] && stems[r[0, r.length - ext.length].downcase]
          next unless twins && twins.any? { |q| (t = File.join(dir, q)) && File.file?(t) && File.mtime(full) <= File.mtime(t) }
          begin
            File.delete(full)
            removed += 1
          rescue StandardError => e
            log("couldn't remove #{r} (#{e.class})")
          end
        end
      end
      walk.call("Audio") if File.directory?(File.join(dir, "Audio"))
      log("removed #{removed} old audio files the shipped Ogg/other format replaced") if removed > 0
      store_choice(key, current_version)
      return removed
    rescue StandardError => e
      log("format twin check failed (#{e.class}: #{e.message})")
      return 0
    end

    def remove_dev_leftovers(dir = root)
      return [] if File.exist?(File.join(dir, ".git")) || !KIF::Paths.game_writable?   # a git checkout is Cody's
      gone = DEV_LEFTOVERS.select { |p| File.exist?(File.join(dir, p)) }
      gone.each { |p| rm_tree(File.join(dir, p)) }
      log("removed files an older build left: #{gone.join(', ')}") unless gone.empty?
      return gone
    rescue StandardError => e
      log("leftover check failed (#{e.class}: #{e.message})")   # runs in an ensure: must never raise at the load screen
      return []
    end

    # An update that was moved in (or wasn't) since the last start
    def after_update
      dir0 = stage_root
      return unless File.directory?(dir0)
      Dir.children(dir0).sort.each do |v|
        dir = File.join(dir0, v)
        next unless File.directory?(dir)
        if File.file?(File.join(dir, "done.txt"))
          from = (File.read(File.join(dir, "from.txt")) rescue nil)   # nil: an older updater staged it
          rm_tree(dir)
          if v == current_version
            # the update removed the old formats it shipped itself (and kept the player's own): no twin cleanup
            store_choice(twins_key, v)
            log("updated to #{v}")
            cmd = pbMessage(_INTL("KIF was updated to {1}.", v), [_INTL("OK"), _INTL("What's new"), _INTL("All updates")], 1)
            show_notes(nil, from) if cmd == 1
            history if cmd == 2   # Update history (Updater_History.rb)
          end
        # failed.txt: the move stopped partway (the scripts, and so the version, may already be new)
        # apply.cmd without done.txt: the update window was closed partway, also after the new scripts were in
        # (done.txt is written only once everything is moved, so finishing again is always safe; playtest 2026-10-24)
        elsif !newer?(current_version, v) &&
              (File.file?(File.join(dir, "failed.txt")) || File.file?(File.join(dir, "apply.cmd")))
          # moved in by the game itself and cut off (closed partway): finished
          # without asking, half an update can't be safely discarded
          moving = (File.read(File.join(dir, "failed.txt")) rescue "") == KIF::UpdateFinish::MOVING
          # once the scripts (and so the version) are new, discarding would leave a mixed game the updater calls up to date
          choices = [_INTL("Try again")]
          choices << _INTL("Discard it") unless v == current_version
          cmd = moving ? 0 : pbMessage(_INTL("The update to KIF {1} didn't finish (a file was in use).", v), choices, 0)
          cmd = 0 if cmd < 0 || cmd >= choices.length
          if cmd == 0 && (moving || !update_window?)
            log("#{v}: finishing an update that was cut off while moving files in") if moving
            File.delete(File.join(dir, "failed.txt")) rescue nil
            apply_in_ruby(dir)
            # as in the done.txt branch: the update removed the formats it shipped (a phone's close runs the ensure below)
            store_choice(twins_key, current_version)
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
        elsif !newer?(v, current_version)
          # an unfinished download or update of a version we already have (an
          # older one's apply.cmd is never finished and kept the twin cleanup waiting)
          rm_tree(dir)
        end
      end
      Dir.rmdir(dir0) if File.directory?(dir0) && Dir.children(dir0).empty?
    rescue StandardError => e
      log("after-update check failed (#{e.class}: #{e.message})")
    ensure
      # after the files are in: during a move the file list still names the old formats
      d = stage_root
      pending = (File.directory?(d) && Dir.children(d).any? { |v| File.file?(File.join(d, v, "failed.txt")) || File.file?(File.join(d, v, "apply.cmd")) }) rescue true
      remove_format_twins unless pending
      remove_dev_leftovers
      remove_auth_cfg   # a test download cut off (game killed) left the code there
    end
  end
end

KIF::Options.define(:kif_updates, KIF::Updater.default_channel, :global)   # 0 Stable, 1 Beta, 2 Off
KIF::Options.define(:kif_update_skip, "", :global)

KIF::Options.add(:others, :global) {
  names = [_INTL("Stable"), _INTL("Beta"), _INTL("Off")]
  descs = [_INTL("At start-up, KIF checks for new releases and offers to update"),
           _INTL("Also offers new versions before they reach Stable"),
           _INTL("KIF never checks for updates by itself")]
  if KIF::Updater.test_code   # Test is there only with a code (Test Code below)
    names << _INTL("Test")
    descs << _INTL("Offers test builds, with your test code")
  end
  EnumOption.new(_INTL("Updates"), names,
                 proc { KIF::Updater.channel },
                 proc { |value| $PokemonSystem.kif_updates = value; KIF::Updater.store_choice("channel", value) },
                 descs)
}
KIF::Options.add(:others, :global) {
  ButtonOption.new(_INTL("Check for Updates"), proc { KIF::Updater.check(true) },
                   _INTL("Looks for a newer KIF now"))
}
KIF::Options.add(:others, :global) {
  ButtonOption.new(_INTL("Test Code"), proc { KIF::Updater.test_code_menu },
                   _INTL("Enter the code you were sent to get test builds, or stop getting them."))
}

# The load screen's version check (PIF's spot). KIF's own check runs here
# and PIF's is never asked: it would tell KIF players to use PIF's installer
# whenever PIF releases a newer version.
def find_newer_available_version
  KIF::Updater.after_update
  updating = KIF::Updater.check(false)
  KIF::ModCatalogUI.startup_check if defined?(KIF::ModCatalogUI) && updating != true
  return nil
end
