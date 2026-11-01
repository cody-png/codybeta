#===============================================================================
# F-CORE-04 - the mod guard (2026-11-01)
#
# Watches the calls that can hurt a player (starting programs, native code, the
# internet, files outside the mod's own folders, loading code from elsewhere,
# and a few that only tell on a mod: the environment, the clipboard, Marshal,
# ObjectSpace) and works out which mod made the call from the file the code
# came from. A mod that does not hold the permission is stopped (Denied, an
# ordinary StandardError the mod can rescue) or only noted, by Mod protection:
#   Off      nothing is noted or stopped
#   Normal   stops programs, native code, the internet, files and loading code
#            a mod did not ask for; only notes the rest (default)
#   Strict   stops everything the mod did not ask for
#   Warn     notes everything, stops nothing
#
# What a mod holds: the permissions in its mod.json, or for an older mod the
# ones its code was found to use, plus what the player allowed in Options > Mods
# (ModTrust.permission_set).
#
# This is NOT a sandbox. A mod is Ruby running in the game's own process; see
# ABOUT_UNGUARDED for what the guard does not see. It stops the common lazy
# attacks and honest mistakes, leaves an audit trail and gives the player a
# switch. KIF's own code and the game's code are never stopped.
#
# Doors are modules prepended once (Module#prepend, never an alias, so kit
# test 294/501's rule holds); a second script run installs no second door.
#===============================================================================
module KIF
  module ModGuard
    class Denied < StandardError; end
    Note = Struct.new(:time, :mod, :permission, :detail, :blocked) unless const_defined?(:Note, false)

    WORDS = {
      "programs" => "start a program", "native" => "call Windows or system code directly",
      "network" => "use the internet", "game_files" => "change files in the game folder",
      "save_files" => "change your save files", "outside_files" => "read or change files outside the game",
      "environment" => "read your computer's settings", "clipboard" => "read or set your clipboard",
      "load_code" => "load code from outside its own folder", "marshal" => "read a saved-object file",
      "objectspace" => "look through everything the game has loaded", "protection" => "change KIF's protection"
    }.freeze unless const_defined?(:WORDS)

    ABOUT_UNGUARDED = "KIF does not see: text eval (eval, class_eval and instance_eval with a string); Ruby reflection " \
                      "(send, public_send, method().call, instance_variable_set, const_get, define_method) used to reach " \
                      "a door or a helper that is not listed; patching KIF or the game, which is what modding is; changing " \
                      "game state in memory (money, Pokemon, flags), which the game then saves; threads and endless loops; " \
                      "memory use; require_relative; code run with a file name of its own (eval with a file argument is nobody's); mods that " \
                      "other loaders start before KIF; anything a started program does; mods drawing fake messages. A mod " \
                      "with Ruby skill can get around the guard. Do not install mods you do not trust.".freeze unless const_defined?(:ABOUT_UNGUARDED)
    MODES = [:off, :normal, :strict, :warn].freeze unless const_defined?(:MODES)

    THIS_FILE = __FILE__ unless const_defined?(:THIS_FILE)
    @doors ||= {}
    @busy ||= {}.compare_by_identity   # thread => true while the guard is working (not readable from a thread's own variables)
    @events ||= []
    @counts ||= Hash.new(0)
    @logged ||= Hash.new(0)
    @tampered ||= {}
    @armed = false if @armed.nil?
    @mode ||= nil
    @pc ||= {}
    @own ||= {}
    @notice ||= nil
    @notified ||= false

    class << self
      attr_reader :doors

      def armed?; return @armed; end

      #-------------------------------------------------------------------------
      # Mode
      #-------------------------------------------------------------------------
      def mode
        return @mode if @mode
        # the setting lives in the trust file (the Options row writes it there): a plain assignment to the player's settings object changes nothing
        v = defined?(KIF::ModTrust) ? KIF::ModTrust.protection : nil
        return MODES[v] || :normal if v.is_a?(Integer)
        return :normal
      end

      def mode=(v)
        deny_if_mod!("change the protection mode", caller_locations(1, 40))
        v = MODES[v] if v.is_a?(Integer)
        @mode = MODES.include?(v) ? v : :normal
      end

      def deny_if_mod!(what, locs)
        owner = KIF::ModContract.caller_owner(locs)
        deny_call!(owner, what) if owner
      end

      def deny_call!(owner, what)
        note(owner, "protection", what, true)
        raise Denied, "KIF stopped mod \"#{name_of(owner)}\": it tried to change KIF's protection (#{what}). Options > Mods > #{name_of(owner)} to review it."
      end

      #-------------------------------------------------------------------------
      # Events
      #-------------------------------------------------------------------------
      def events(mod = nil)
        return mod ? @events.select { |e| e.mod == mod } : @events.dup
      end

      def count(mod); return @counts[mod]; end

      def clear_events
        deny_if_mod!("clear the record", caller_locations(1, 40))
        @events = []
        @counts = Hash.new(0)
        @logged = Hash.new(0)
        @notice = nil
        @notified = false
      end

      # one message for the first stop of a session ("A mod was stopped: X. See Options > Mods."), then nil
      def take_notice
        n = @notice
        @notice = nil
        return n
      end

      def tampered?(mod); return @tampered[mod] ? true : false; end

      def name_of(mod)
        e = (KIF::ModTrust.entry_for(mod) rescue nil)
        return (e && e.name) ? e.name.to_s : mod.to_s
      end

      def note(mod, perm, detail, blocked)
        d = detail.to_s.gsub(/[^\x20-\x7e]/, "?")[0, 90]
        last = @events.last
        unless last && last.mod == mod && last.permission == perm && last.detail == d && last.blocked == blocked
          @events << Note.new(Time.now, mod, perm, d, blocked)
          @events.shift if @events.length > 200
        end
        @counts[mod] += 1 if blocked
        key = [mod, perm]
        @logged[key] += 1
        if @logged[key] <= 3
          KIF.log("ModGuard: #{mod} #{perm} #{d} -> #{blocked ? 'BLOCKED' : 'noted'}#{@logged[key] == 3 ? ' (more are not logged)' : ''}")
        end
        if blocked && !@notified
          @notified = true
          @notice = "A mod was stopped: #{name_of(mod)}. See Options > Mods."
          KIF::ModSecurityUI.schedule if defined?(KIF::ModSecurityUI)
        end
      end

      #-------------------------------------------------------------------------
      # Who is calling: the nearest frame that is not transparent decides
      #-------------------------------------------------------------------------
      def reset_cache
        @pc = {}
        @own = {}
        KIF::ModTrust.reset_cache if defined?(KIF::ModTrust)
      end

      # a mod's key, :t (Ruby's own files and eval text: look further out), or false (KIF, the game)
      def classify(path)
        c = @pc[path]
        return c unless c.nil?
        # the guard's own frames (a door's super call, with a block running below it) never decide who is calling
        c = (path == THIS_FILE || own_file?(path) || KIF::ModContract.transparent?(path)) ? :t : (KIF::ModContract.owner_of_path(path) || false)
        return @pc[path] = c
      end

      # ModGuard.rb and ModTrust.rb never decide who is calling
      def own_file?(path)
        return false unless path.is_a?(String) && path.end_with?("/ModTrust.rb")
        return File.dirname(path) == File.dirname(THIS_FILE)
      end

      def walk(locs)
        locs.each do |l|
          c = classify(l.path)
          next if c == :t
          return c.is_a?(String) ? c : nil
        end
        return nil
      end

      #-------------------------------------------------------------------------
      # The check behind every door
      #-------------------------------------------------------------------------
      def check(kind, name, args, kw, blk, loc, cls)
        t = Thread.current
        return if @busy[t]
        @busy[t] = true
        begin
          mod = cls.is_a?(String) ? cls : walk(caller_locations(2, 40))
          return unless mod
          perm, detail, host = needs(kind, mod, name, args, kw, blk, loc)
          return unless perm
          judge(mod, perm, detail, host)
        ensure
          @busy.delete(t)
        end
      end

      def judge(mod, perm, detail, host = nil)
        m = mode
        return if m == :off
        held = KIF::ModTrust.permission_set(mod)
        ok = held == :all || held.include?(perm)
        ok = false if ok && perm == "network" && host && held != :all && !host_allowed?(mod, host)
        if ok
          note(mod, perm, detail, false) if held == :all && @logged[[mod, perm]] < 3
          return
        end
        block = case m
                when :strict then true
                when :warn then false
                else KIF::ModContract::BLOCKING.include?(perm)
                end
        note(mod, perm, detail, block)
        return unless block
        n = name_of(mod)
        raise Denied, "KIF stopped mod \"#{n}\": it tried to #{WORDS[perm] || perm}. Options > Mods > #{n} to allow it."
      end

      def host_allowed?(mod, host)
        h = host.to_s.downcase
        return true if h == "localhost" || h == "127.0.0.1" || h == "::1"
        list = KIF::ModTrust.hosts_for(mod)
        return true if list.empty?
        return list.any? do |x|
          x = x.to_s.downcase
          x.start_with?("*.") ? h.end_with?(x[1..-1]) : h == x
        end
      end

      def host_of(a)
        if a.is_a?(String)
          return $2.downcase if a =~ %r{\A[a-z][a-z0-9+.\-]*://([^/?#@]*@)?(\[[^\]]+\]|[^/:?#]+)}i
          return a.downcase
        end
        return a.host.to_s.downcase if a.respond_to?(:host)
        return nil
      end

      #-------------------------------------------------------------------------
      # What a call needs: [permission, detail, host] or nil
      #-------------------------------------------------------------------------
      def needs(kind, mod, name, args, kw, blk, loc)
        a0 = args[0]
        case kind
        when :program then return ["programs", "#{name} #{short(a0)}"]
        when :native then return ["native", name.to_s]
        when :net then h = host_of(a0); return ["network", "#{name} #{h || short(a0)}", h]
        when :env then return ["environment", "ENV #{name}"]
        when :clipboard then return ["clipboard", name.to_s]
        when :marshal then return ["marshal", "#{name}"]
        when :objspace then return blk.nil? && name.to_s == "each_object" ? nil : ["objectspace", name.to_s]
        when :write then return path_need(mod, a0, true, name)
        when :fopen then return path_need(mod, a0, write_mode?(args, kw), name)
        when :read then return path_need(mod, a0, false, name)
        when :glob then return path_need(mod, glob_dir(args, kw), false, name)
        when :iopath
          return ["programs", "#{name} #{short(a0)}"] if a0.is_a?(String) && a0.start_with?("|")
          return path_need(mod, a0, %w[write binwrite].include?(name.to_s), name)
        when :kopen
          if a0.is_a?(String)
            return ["programs", "open #{short(a0)}"] if a0.start_with?("|")
            h = host_of(a0)
            return ["network", "open #{h}", h] if a0 =~ %r{\Ahttps?://}i
          end
          return path_need(mod, a0, write_mode?(args, kw), name)
        when :load then return load_need(mod, name, a0, loc)
        when :launch then return ["programs", "launch #{short(a0)}"]
        when :copy_stream
          to = args[1]
          w = (to.is_a?(String) || to.respond_to?(:to_path)) ? path_need(mod, to, true, name) : nil
          return w if w
          from = a0
          return (from.is_a?(String) || from.respond_to?(:to_path)) ? path_need(mod, from, false, name) : nil
        when :autoload then return load_need(mod, name, args[1], loc)
        when :url then h = host_of(a0); return ["network", "#{name} #{h || short(a0)}", h]
        end
        return nil
      end

      def lib_names; return KIF::ModCheck::STDLIB; end

      # The first three arguments as plain text where they are path-like objects, so the path the guard checked
      # is the path the call gets (an object could answer to_path differently the second time).
      def fix_args(args)
        return args unless args.any? { |a| !(a.is_a?(String) || a.is_a?(Integer) || a.nil? || a == true || a == false || a.is_a?(Symbol) || a.is_a?(Array) || a.is_a?(Hash) || a.is_a?(Float) || a.is_a?(IO) || a.is_a?(Module)) }
        return args.each_with_index.map do |a, i|
          next a if i > 2 || a.is_a?(String) || a.is_a?(Integer) || a.nil? || a == true || a == false || a.is_a?(Symbol) || a.is_a?(Array) || a.is_a?(Hash) || a.is_a?(Float) || a.is_a?(IO) || a.is_a?(Module)
          s = a.respond_to?(:to_path) ? a.to_path : (a.respond_to?(:to_str) ? a.to_str : a)
          s.is_a?(String) ? s.dup.freeze : a
        end
      end

      def short(x); return x.is_a?(String) ? x[0, 60] : x.class.to_s; end

      def write_mode?(args, kw)
        m = args[1]
        m = kw[:mode] if kw && kw[:mode]
        m = args[2] if m.is_a?(Hash)
        return true if m.is_a?(String) && m =~ /\A(?:[wa]|r\+)/
        return (m & (File::WRONLY | File::RDWR | File::CREAT | File::APPEND | File::TRUNC)) != 0 if m.is_a?(Integer)
        return false
      end

      def glob_dir(args, kw)
        base = kw && kw[:base]
        pat = args[0]
        pat = pat.first if pat.is_a?(Array)
        return nil unless pat.is_a?(String)
        dir = pat.split(/[*?{\[]/, 2)[0].to_s
        dir = File.dirname(dir + "x") if !dir.end_with?("/") && !dir.empty?
        return base ? File.join(base.to_s, dir) : dir
      end

      def path_of(p)
        return p if p.is_a?(String)
        return p.to_path if p.respond_to?(:to_path)
        return nil
      end

      # normalised absolute path with links followed as far as the path exists
      def resolve(path)
        full = File.expand_path(path.to_s)
        base = full
        rest = []
        until base == File.dirname(base)
          break if File.exist?(base) || File.symlink?(base)
          rest.unshift(File.basename(base))
          base = File.dirname(base)
        end
        real = (File.realpath(base) rescue base)
        return File.join(real, *rest).tr("\\", "/").downcase
      end

      def inside?(full, dir)
        d = dir.to_s.chomp("/")
        return full == d || full.start_with?(d + "/")
      end

      def own_root(mod)
        return @own[mod] if @own.key?(mod)
        r = KIF::ModContract.roots.find { |_k, v| v == mod }
        return @own[mod] = (r ? resolve(r[0].chomp("/")) : nil)
      end

      def game_dir; return @game_dir ||= resolve("."); end

      def lib_dirs
        return @lib_dirs ||= begin
          c = defined?(RbConfig) ? RbConfig::CONFIG : {}
          l = %w[rubylibdir rubyarchdir sitelibdir sitearchdir vendorlibdir vendorarchdir].map { |k| c[k] }.compact
          l.concat(Gem.path) if defined?(Gem) && Gem.respond_to?(:path)
          l.map { |d| resolve(d) }.uniq
        end
      end

      # the permission a file call needs, or nil
      def path_need(mod, path, write, name)
        p = path_of(path)
        return nil unless p && !p.empty?
        full = resolve(p)
        detail = "#{name} #{p[0, 60]}"
        if write
          return ["programs", detail] if KIF::ModCheck::PROGRAM_EXT.include?(File.extname(full))
          own = own_root(mod)
          return nil if (own && inside?(full, own)) || inside?(full, resolve(KIF::ModContract.data_dir(mod)))
          return ["save_files", detail] if inside?(full, resolve(KIF.save_dir))
          return ["game_files", detail] if inside?(full, game_dir)
          return ["outside_files", detail]
        end
        own = own_root(mod)
        return nil if own && inside?(full, own)
        return nil if inside?(full, game_dir) || inside?(full, resolve(KIF.save_dir)) || lib_dirs.any? { |d| inside?(full, d) }
        return ["outside_files", detail]
      end

      # load and require (not require_relative: a door cannot see the file that calls it, see ABOUT_UNGUARDED): only the mod's own folder, other mods, the game's scripts and Ruby's library
      def load_need(mod, name, a0, loc)
        return nil unless a0.is_a?(String) || a0.respond_to?(:to_path)
        n = path_of(a0)
        detail = "#{name} #{n[0, 60]}"
        if name.to_s == "load" || n =~ %r{\A(?:\.{1,2}/|/|[A-Za-z]:|~)} || n.include?("\\") || (n.include?("/") && File.file?(File.expand_path(n)))
          full = resolve(n)
        else
          base = n.sub(/\.rb\z/, "")
          return nil if lib_names.include?(base) || lib_names.include?(base.split("/")[0])
          return ["load_code", detail]
        end
        return ["load_code", detail] if name.to_s == "load" && File.extname(full) != ".rb"
        own = own_root(mod)
        return nil if own && inside?(full, own)
        return nil if KIF::ModContract.roots.any? { |k, _v| inside?(full, resolve(k.chomp("/"))) }
        return nil if inside?(full, resolve("Data/Scripts")) || lib_dirs.any? { |d| inside?(full, d) }
        return ["load_code", detail]
      end

      #-------------------------------------------------------------------------
      # Doors
      #-------------------------------------------------------------------------
      def make_door(target, name, kind)
        guard = self
        door = Module.new
        door.send(:define_method, name) do |*args, **kw, &blk|
          if guard.armed?
            l = caller_locations(1, 1)[0]
            c = l ? guard.classify(l.path) : :t
            if c
              args = guard.fix_args(args)   # an object that answers to_path twice is asked once
              guard.check(kind, name, args, kw, blk, l, c)
            end
          end
          r = super(*args, **kw, &blk)
          guard.rearm_after_require(args[0]) if name == :require && guard.armed?
          r
        end
        door.send(:private, name) if target.private_method_defined?(name) && !target.public_method_defined?(name)
        target.prepend(door)
        return door
      end

      def door!(target, name, kind)
        return unless target
        return unless target.method_defined?(name) || target.private_method_defined?(name)
        key = "#{target.inspect}##{name}"
        return if @doors[key]
        @doors[key] = [target, name, make_door(target, name, kind)]
      end

      def doors_for(target, names, kind)
        names.each { |n| door!(target, n, kind) }
      end

      def install_doors
        k = Kernel
        ks = Kernel.singleton_class
        [k, ks].each do |t|
          doors_for(t, %i[system spawn exec ` fork exit! syscall], :program)
          doors_for(t, %i[open], :kopen)
          doors_for(t, %i[load require], :load)
        end
        if defined?(Process)
          doors_for(Process.singleton_class, %i[spawn exec daemon kill detach], :program)
        end
        doors_for(IO.singleton_class, %i[popen], :program)
        doors_for(IO.singleton_class, %i[read readlines foreach binread write binwrite sysopen], :iopath)
        doors_for(IO.singleton_class, %i[copy_stream], :copy_stream)   # FileUtils.cp and mv use it with two paths
        doors_for(Kernel, %i[autoload], :autoload)
        door!(Module, :autoload, :autoload)
        fs = File.singleton_class
        doors_for(fs, %i[open new], :fopen)
        doors_for(fs, %i[write binwrite delete unlink rename chmod lchmod chown truncate symlink link utime mkfifo], :write)
        doors_for(fs, %i[read readlines foreach binread], :read)
        ds = Dir.singleton_class
        doors_for(ds, %i[children entries each_child foreach exist?], :read)
        doors_for(ds, [:glob, :[]], :glob)
        doors_for(ds, %i[mkdir rmdir delete unlink], :write)
        if defined?(Bitmap) && Bitmap.method_defined?(:to_file)
          # an instance method: the path is the first argument
          door!(Bitmap, :to_file, :write)
        end
        env = ENV.singleton_class
        doors_for(env, [:[], :fetch, :to_h, :to_hash, :each, :each_pair, :key?, :has_key?, :include?, :values_at, :keys, :values, :[]=, :store, :delete, :update, :merge!], :env)
        doors_for(Marshal.singleton_class, %i[load restore], :marshal)
        doors_for(ObjectSpace.singleton_class, %i[each_object _id2ref garbage_collect], :objspace)
        if defined?(Input) && Input.respond_to?(:clipboard)
          doors_for(Input.singleton_class, %i[clipboard clipboard=], :clipboard)
        end
        if defined?(System) && System.respond_to?(:launch)
          doors_for(System.singleton_class, %i[launch], :launch)
        end
        install_optional
      end

      # doors for libraries that may load later (a mod's require arms them again)
      def install_optional
        if defined?(::Psych) then doors_for(::Psych.singleton_class, %i[load unsafe_load load_file unsafe_load_file], :marshal) end
        [:TCPSocket, :TCPServer, :UDPSocket, :Socket].each do |c|
          next unless Object.const_defined?(c)
          doors_for(Object.const_get(c).singleton_class, %i[new open tcp tcp_server_loop getaddrinfo], :net)
        end
        if defined?(::Net::HTTP)
          doors_for(::Net::HTTP.singleton_class, %i[new start get get_response post post_form get_print], :net)
        end
        doors_for(::OpenURI.singleton_class, %i[open_uri], :net) if defined?(::OpenURI)
        if defined?(::URI) && ::URI.respond_to?(:open) then doors_for(::URI.singleton_class, %i[open], :net) end
        if defined?(::HTTPLite)
          doors_for(::HTTPLite.singleton_class, (::HTTPLite.singleton_methods & %i[get post put delete head patch request]), :net)
        end
        if defined?(::Win32API) then doors_for(::Win32API.singleton_class, %i[new], :native) end
        if defined?(::Fiddle)
          doors_for(::Fiddle.singleton_class, %i[dlopen], :native)
          doors_for(::Fiddle::Function.singleton_class, %i[new], :native) if defined?(::Fiddle::Function)
          doors_for(::Fiddle::Handle.singleton_class, %i[new], :native) if defined?(::Fiddle::Handle)
        end
        doors_for(::DL.singleton_class, %i[dlopen], :native) if defined?(::DL) && ::DL.respond_to?(:dlopen)
        doors_for(::FFI::Library, %i[ffi_lib], :native) if defined?(::FFI::Library)
        if defined?(KIF::Updater)
          doors_for(KIF::Updater.singleton_class, %i[fetch download], :url)
        end
        %i[pbDownloadToString pbDownloadToFile pbPostData].each { |m| door!(Object, m, :url) }
        doors_for(KIF.singleton_class, %i[rm_tree mkdir_p], :write)
      end

      def arm!
        deny_if_mod!("arm", caller_locations(1, 40))
        install_doors
        @want_armed = true
        @game_dir = nil
        @lib_dirs = nil
        reset_cache
        @armed = true
        watch
      end

      # every 30 seconds: are the doors still the guard's? (a mod that undoes one is found within that time)
      def watch
        return if @watching || !defined?(KIF::API) || !KIF::API.respond_to?(:every)
        @watching = true
        KIF::API.every(seconds: 30, scope: :always, id: "kif_modguard_verify") do
          verify.each { |key| KIF.log("ModGuard: #{key} was changed") }
        end
      rescue StandardError
        @watching = false
      end

      def disarm!
        deny_if_mod!("switch off", caller_locations(1, 40))
        @armed = false
        @want_armed = false
      end

      # a require of a library whose doors are not there yet arms them (called by the require door's result)
      def rearm_after_require(name)
        install_optional if name.to_s =~ /\A(?:socket|net\/http|net\/https|open-uri|fiddle|ffi|win32api|psych|yaml)/
      end

      # names of the doors that do not resolve to the guard's module any more
      def verify
        bad = []
        if @want_armed && !@armed   # a mod flipped the switch from inside
          bad << "ModGuard.armed"
          @armed = true
        end
        @doors.each do |key, (target, name, door)|
          owner = (target.instance_method(name).owner rescue nil)
          bad << key unless owner.equal?(door)
        end
        return bad
      end

      # after a mod's files are loaded: find out whether it undid a door
      def after_load(mod)
        return unless @armed
        bad = verify
        bad.each do |key|
          next if @tampered[mod]
          @tampered[mod] = true
          note(mod, "protection", "#{key} was changed", false)
          KIF.log("ModGuard: #{key} was changed (mod #{mod})")
        end
      end
    end
  end
end
