#===============================================================================
# F-CORE-10 - KIF::Safe: what an honest mod calls instead of raw file and
# network code (2026-11-01)
#
# A mod that uses these never trips the mod guard: Safe is KIF's own code, it
# works out which mod called it, applies the same rules the guard applies, and
# adds limits of its own. Nothing here starts a program (open_url asks first).
#
#   KIF::Safe.write_text("notes.txt", "hello")     # in the mod's own data folder
#   KIF::Safe.read_json("settings.json", {})
#   KIF::Safe.write_json("settings.json", { "volume" => 3 })
#   KIF::Safe.read_own("data/table.txt")           # a file inside the mod's own folder (read only)
#   KIF::Safe.json_parse(text)                     # plain data from text, never run as code
#   KIF::Safe.http_get("https://api.github.com/x", timeout: 10)   # needs "network" in mod.json
#   KIF::Safe.open_url("https://example.org")      # asks the player first
#
# Rules: a relative path must pass KIF.safe_rel_path?; a file is at most 1 MB
# (up to 8 MB with max:), a mod has at most 64 files and 32 MB; writes go to a
# temporary file first, so a file is whole or not there; JSON is read with
# KIF::Mods::MiniJSON or Ruby's own JSON (never the game's JSON, which parses by
# eval), at most 16 deep, plain data only; http_* need the "network" permission and
# the host in network_hosts, take https only (loopback is allowed for tests),
# follow no redirect and stop at max_bytes.
#===============================================================================
module KIF
  module Safe
    class Error < StandardError; end

    MAX_FILE       = 1024 * 1024
    MAX_FILE_BIG   = 8 * 1024 * 1024
    MAX_FILES      = 64
    MAX_TOTAL      = 32 * 1024 * 1024
    MAX_DEPTH      = 16
    MAX_JSON       = 1024 * 1024
    MAX_BODY       = 2 * 1024 * 1024
    MAX_STRING     = 65_536

    @asker = nil
    @launcher = nil
    @http = nil

    class << self
      attr_writer :asker, :launcher, :http   # for tests

      #-------------------------------------------------------------------------
      # Who is calling
      #-------------------------------------------------------------------------
      def calling_mod(locs)
        return KIF::ModContract.caller_owner(locs)
      end

      def calling_mod!(locs)
        m = calling_mod(locs)
        raise Error, "KIF::Safe is for mods: call it from the mod's own code" unless m
        return m
      end

      def check_rel!(rel)
        raise Error, "not a plain file name: #{rel.to_s[0, 40].inspect}" unless rel.is_a?(String) && KIF.safe_rel_path?(rel)
        return rel
      end

      #-------------------------------------------------------------------------
      # The mod's data folder (outside the game folder; it stays when the mod is removed)
      #-------------------------------------------------------------------------
      def mod_dir(mod = nil)
        mod ||= calling_mod!(caller_locations(1, 40))
        d = KIF::ModContract.data_dir(mod)
        KIF.mkdir_p(d)
        return d
      end

      def data_path(mod, rel)
        check_rel!(rel)
        dir = KIF::ModContract.data_dir(mod)
        return File.join(dir, rel)
      end

      # the folder really is under the data folder (a link planted in it does not lead out)
      def inside_data!(mod, path)
        dir = KIF::ModContract.data_dir(mod)
        KIF.mkdir_p(dir)
        base = File.realpath(dir).tr("\\", "/").downcase
        real = File.realpath(File.dirname(path)).tr("\\", "/").downcase
        raise Error, "that path leaves the mod's data folder" unless real == base || real.start_with?(base + "/")
        if File.symlink?(path)
          raise Error, "that path is a link"
        end
      end

      def write_mod_file(mod, rel, data, max: nil)
        limit = [[max.to_i, MAX_FILE].max, MAX_FILE_BIG].min
        data = data.to_s
        raise Error, "#{rel}: #{data.bytesize} bytes, over the #{limit / 1024} KB limit" if data.bytesize > limit
        path = data_path(mod, rel)
        KIF.mkdir_p(File.dirname(path))
        inside_data!(mod, path)
        files = list_mod_files(mod)
        total = files.inject(0) { |s, f| s + (File.size(File.join(KIF::ModContract.data_dir(mod), f)) rescue 0) }
        old = File.file?(path) ? File.size(path) : 0
        raise Error, "too many files for one mod (#{MAX_FILES} at most)" if !files.include?(rel) && files.length >= MAX_FILES
        raise Error, "a mod may keep #{MAX_TOTAL / 1048576} MB in all" if total - old + data.bytesize > MAX_TOTAL
        tmp = "#{path}.#{$$}.tmp"
        File.binwrite(tmp, data)
        File.rename(tmp, path)
        return true
      ensure
        (File.delete(tmp) rescue nil) if tmp && File.file?(tmp)
      end

      def read_mod_file(mod, rel, max: nil)
        path = data_path(mod, rel)
        return nil unless File.file?(path)
        inside_data!(mod, path)
        limit = [[max.to_i, MAX_FILE].max, MAX_FILE_BIG].min
        raise Error, "#{rel}: over the #{limit / 1024} KB limit" if File.size(path) > limit
        return File.binread(path)
      end

      def delete_mod_file(mod, rel)
        path = data_path(mod, rel)
        return false unless File.file?(path)
        inside_data!(mod, path)
        File.delete(path)
        return true
      end

      def list_mod_files(mod)
        dir = KIF::ModContract.data_dir(mod)
        return [] unless File.directory?(dir)
        return Dir.glob(File.join("**", "*"), File::FNM_DOTMATCH, base: dir).select { |r| File.file?(File.join(dir, r)) && !File.symlink?(File.join(dir, r)) && r !~ /\.tmp\z/ }.sort
      end

      #-------------------------------------------------------------------------
      # In the calling mod's data folder
      #-------------------------------------------------------------------------
      def write_text(rel, text, max: nil); return write_mod_file(calling_mod!(caller_locations(1, 40)), rel, text.to_s, max: max); end

      def read_text(rel, max: nil)
        s = read_mod_file(calling_mod!(caller_locations(1, 40)), rel, max: max)
        return s && s.dup.force_encoding("UTF-8").scrub("?")
      end

      def write_json(rel, obj); return write_mod_file(calling_mod!(caller_locations(1, 40)), rel, json_dump(obj)); end

      def read_json(rel, default = nil)
        s = read_mod_file(calling_mod!(caller_locations(1, 40)), rel)
        return default if s.nil?
        return json_parse(s)
      rescue Error
        return default
      end

      # a file inside the mod's own folder (read only)
      def read_own(rel, max: nil)
        mod = calling_mod!(caller_locations(1, 40))
        check_rel!(rel)
        root = KIF::ModContract.roots.find { |_k, v| v == mod }
        return nil unless root
        path = File.join(root[0].chomp("/"), rel)
        return nil unless File.file?(path)
        real = File.realpath(path).tr("\\", "/").downcase
        base = File.realpath(root[0].chomp("/")).tr("\\", "/").downcase
        raise Error, "that path leaves the mod's folder" unless real.start_with?(base + "/")
        limit = [[max.to_i, MAX_FILE].max, MAX_FILE_BIG].min
        raise Error, "#{rel}: over the #{limit / 1024} KB limit" if File.size(path) > limit
        return File.binread(path)
      end

      #-------------------------------------------------------------------------
      # Plain data
      #-------------------------------------------------------------------------
      def plain?(obj, depth = 0)
        return false if depth > MAX_DEPTH
        case obj
        when nil, true, false, Integer then return true
        when Float then return obj.finite?
        when String then return obj.bytesize <= MAX_STRING * 4
        when Array then return obj.all? { |x| plain?(x, depth + 1) }
        when Hash then return obj.all? { |k, v| (k.is_a?(String) || k.is_a?(Symbol)) && plain?(v, depth + 1) }
        end
        return false
      end

      # a copy with String keys and no Symbols; raises Error for anything that is not plain data
      def sanitize(obj, depth = 0)
        raise Error, "nested deeper than #{MAX_DEPTH}" if depth > MAX_DEPTH
        case obj
        when nil, true, false, Integer, String then return obj
        when Float
          raise Error, "a number that is not finite" unless obj.finite?
          return obj
        when Symbol then return obj.to_s
        when Array then return obj.map { |x| sanitize(x, depth + 1) }
        when Hash
          out = {}
          obj.each do |k, v|
            raise Error, "a key that is not text" unless k.is_a?(String) || k.is_a?(Symbol)
            out[k.to_s] = sanitize(v, depth + 1)
          end
          return out
        end
        raise Error, "#{obj.class} is not plain data"
      end

      def json_dump(obj)
        return dump(sanitize(obj))
      end

      def dump(v)
        case v
        when nil then return "null"
        when true then return "true"
        when false then return "false"
        when Integer, Float then return v.to_s
        when String then return dump_str(v)
        when Array then return "[" + v.map { |x| dump(x) }.join(",") + "]"
        when Hash then return "{" + v.map { |k, x| dump_str(k.to_s) + ":" + dump(x) }.join(",") + "}"
        end
        return "null"
      end

      def dump_str(s)
        return '"' + s.gsub(/["\\\x00-\x1f]/) do |c|
          case c
          when '"' then '\\"'
          when "\\" then "\\\\"
          when "\n" then "\\n"
          when "\r" then "\\r"
          when "\t" then "\\t"
          else format("\\u%04x", c.ord)
          end
        end + '"'
      end

      # JSON text to plain data. Never run as code. Raises Error for bad text, too deep, too long or not plain.
      def json_parse(text, max_depth: MAX_DEPTH, max_bytes: MAX_JSON)
        t = text.to_s
        raise Error, "text longer than #{max_bytes} bytes" if t.bytesize > max_bytes
        v, why = KIF::ModCheck.parse_json(t.dup.force_encoding("UTF-8").scrub("?"))
        raise Error, "not JSON (#{why.to_s[0, 60]})" if why
        raise Error, "nested deeper than #{max_depth}" if depth_of(v) > max_depth
        return sanitize(v)
      end

      def depth_of(v, d = 0)
        return d + 1 if d > 200
        case v
        when Array then return v.empty? ? d : v.map { |x| depth_of(x, d + 1) }.max
        when Hash then return v.empty? ? d : v.values.map { |x| depth_of(x, d + 1) }.max
        end
        return d
      end

      #-------------------------------------------------------------------------
      # The internet: https only, one host list, no redirects, a size limit
      #-------------------------------------------------------------------------
      LOOPBACK = %w[localhost 127.0.0.1 ::1].freeze

      def parse_url(url)
        u = url.to_s
        raise Error, "not an address" if u.empty? || u.length > 2000 || u =~ /[\x00-\x20\x7f"<>\\^`{|}]/
        m = u.match(%r{\A(https?)://([^/:?#@\[\]]+|\[[0-9a-f:]+\])(?::(\d{1,5}))?(/[^#]*)?(?:#.*)?\z}i)
        raise Error, "only plain web addresses (https://host/path)" unless m
        scheme, host, port, path = m[1].downcase, m[2].downcase, m[3], m[4] || "/"
        host = host.delete("[]")
        loop_ok = LOOPBACK.include?(host)
        raise Error, "only https addresses" if scheme != "https" && !loop_ok
        port = (port || (scheme == "https" ? 443 : 80)).to_i
        raise Error, "that port is not allowed" if port < 1 || port > 65_535
        return [scheme, host, port, path]
      end

      def clean_headers(h)
        out = {}
        return out unless h.is_a?(Hash)
        h.first(16).each do |k, v|
          k = k.to_s
          v = v.to_s
          next if k !~ /\A[A-Za-z0-9\-]{1,40}\z/ || v =~ /[\x00-\x1f\x7f]/ || v.length > 500
          next if k =~ /\A(host|content-length|connection|transfer-encoding)\z/i
          out[k] = v
        end
        return out
      end

      # the same permission and host rules the guard applies, for the mod that called
      def net_check!(mod, host, what)
        return unless mod && defined?(KIF::ModGuard)
        KIF::ModGuard.judge(mod, "network", "#{what} #{host}", host)
      end

      def http_get(url, headers: {}, timeout: 10, max_bytes: MAX_BODY)
        mod = calling_mod(caller_locations(1, 40))
        scheme, host, port, path = parse_url(url)
        net_check!(mod, host, "http_get")
        return request(:get, scheme, host, port, path, nil, clean_headers(headers), timeout, max_bytes)
      end

      def http_post_json(url, obj, headers: {}, timeout: 10, max_bytes: MAX_BODY)
        mod = calling_mod(caller_locations(1, 40))
        scheme, host, port, path = parse_url(url)
        net_check!(mod, host, "http_post_json")
        body = json_dump(obj)
        raise Error, "the request is bigger than 1 MB" if body.bytesize > MAX_JSON
        h = clean_headers(headers).merge("Content-Type" => "application/json")
        return request(:post, scheme, host, port, path, body, h, timeout, max_bytes)
      end

      def request(verb, scheme, host, port, path, body, headers, timeout, max_bytes)
        t = [[timeout.to_f, 1.0].max, 60.0].min
        limit = [[max_bytes.to_i, 1024].max, MAX_FILE_BIG].min
        return @http.call(verb, scheme, host, port, path, body, headers, t, limit) if @http
        if defined?(::HTTPLite) && scheme == "https"
          url = "https://#{host}#{port == 443 ? '' : ":#{port}"}#{path}"
          res = verb == :get ? ::HTTPLite.get(url, headers) : ::HTTPLite.post(url, body.to_s, headers)
          raise Error, "no answer" unless res.is_a?(Hash)
          b = res[:body].to_s
          raise Error, "the answer is bigger than #{limit} bytes" if b.bytesize > limit
          return { :status => res[:status].to_i, :body => b.b }
        end
        require "net/http" unless defined?(::Net::HTTP)
        http = ::Net::HTTP.new(host, port)
        http.use_ssl = scheme == "https"
        http.open_timeout = t
        http.read_timeout = t
        req = verb == :get ? ::Net::HTTP::Get.new(path) : ::Net::HTTP::Post.new(path)
        headers.each { |k, v| req[k] = v }
        req["User-Agent"] ||= "KIF"
        req.body = body if body
        out = +"".b
        status = 0
        http.request(req) do |res|
          status = res.code.to_i
          res.read_body do |chunk|
            out << chunk
            raise Error, "the answer is bigger than #{limit} bytes" if out.bytesize > limit
          end
        end
        return { :status => status, :body => out }
      rescue Error
        raise
      rescue StandardError => e
        raise Error, "no answer (#{e.class})"
      end

      #-------------------------------------------------------------------------
      # Opening a page in the player's browser: https only, after the player says yes
      #-------------------------------------------------------------------------
      def ask(text)
        return @asker.call(text) if @asker
        return pbMessage(KIF::PixelFont.utf8(text), [_INTL("No"), _INTL("Yes")], 0) == 1
      end

      def open_url(url)
        mod = calling_mod(caller_locations(1, 40))
        u = url.to_s
        raise Error, "only https addresses" unless u =~ %r{\Ahttps://[^/:?#@\s]+(?::\d{1,5})?(?:/[^\s#]*)?(?:#\S*)?\z}i && u.length <= 500 && u !~ /[\x00-\x20\x7f"<>\\^`{|}]/
        who = mod ? (KIF::ModGuard.name_of(mod) rescue mod) : "KIF"
        return false unless ask(_INTL("{1} wants to open {2} in your browser. Open it?", who, u[0, 120]))
        if @launcher then @launcher.call(u)
        elsif defined?(::System) && ::System.respond_to?(:launch) then ::System.launch(u)
        else return false
        end
        return true
      end
    end
  end
end
