#===============================================================================
# F-CORE-10 Mod API - the hook engine: any game method, one rule
#
# For what the events do not cover. A mod hooks a method without writing
# `alias` and `def` itself, and the engine keeps every hook on the method in
# one wrapper, so mods do not stack on each other and one failing hook does not
# stop the rest.
#
#   KIF::API.around("PokeBattle_Battler#pbUseMove") { |call| call.proceed }
#   KIF::API.before("Game_Event#start", "my_id") { |call| call.skip!(false) if bad? }
#   KIF::API.after("pbItemBall") { |call| KIF.log("gave #{call.args[0]}") }
#   KIF::API.unhook("PokeBattle_Battler#pbUseMove", "my_id")
#   KIF::API.hooks; KIF::API.hooked?("Graphics.update")
#
# target:  "Class#method" (instance) | "Class.method" (class method) |
#          "Object#pbGlobalFunction" | [Class, :method] | [Class, :method, :singleton]
# call:    receiver, args (Array; change it in before/around), kwargs, block,
#          proceed(*new_args) -> result (runs the next hook or the game's method),
#          result / result=, skip!(value) (before: do not run the method, return value),
#          called? (true once the method ran)
# around:  the block's value is the method's result. before: may change
#          call.args or call.skip!. after: may set call.result.
# defer:   true waits for a method another mod defines (retried when the mods
#          finished loading).
# A target that does not exist is logged once and gives nil (Mod Dev mode raises
# KIF::API::HookError). Keyword arguments pass through.
#
# THE FORM RULE (kit tests 294 and 501): a method is wrapped with alias or with
# Module#prepend, never with both.
#  1. A class method (a singleton class) or a global function (Object): ALIAS.
#     The alias is taken from the class's own method, below any module already
#     prepended, so a prepended hook can not make it loop.
#  2. A module KIF or EBDX prepended in front of the class already defines the
#     method: PREPEND (ours stays outermost, like KIF's).
#  3. Otherwise ALIAS.
# The form is recorded in KIF::API::Hook.forms and never switched.
# heal! checks every installed wrapper (after a second script run, or when a mod
# replaced the method) and repairs or reports it; a mod that REPLACES a method
# (plain def) wins and is reported as bypassed in KIF::API.collisions.
#
# The API can not be a way around the guard: Kernel, File, IO, Dir, Marshal,
# Process, ENV, threads, native-call classes and KIF's own security modules are
# refused. (Raw monkey patching stays possible; this keeps the API clean.)
#===============================================================================
module KIF
  module API
    #---------------------------------------------------------------------------
    # What a hook block receives
    #---------------------------------------------------------------------------
    class Call
      attr_reader :receiver, :pcount
      attr_accessor :block
      attr_accessor :args, :kwargs, :result

      def initialize(receiver, args, kwargs, block, orig)
        @receiver = receiver
        @args = args
        @kwargs = kwargs
        @block = block
        @orig = orig
        @arounds = nil
        @pos = 0
        @called = false
        @pcount = 0
        @skipped = false
        @result = nil
        @data = nil
        @point = nil
        @sub = nil
      end

      def setup(arounds, point); @arounds = arounds; @point = point; end
      def called?; return @called; end
      def skipped?; return @skipped; end
      # free space for the hooks of one call (one hook's before and after can share state)
      def data; return @data ||= {}; end

      # before: do not run the method; the call returns value
      def skip!(value = nil)
        @skipped = true
        @result = value
        return value
      end

      # Runs the next hook around the method, then the method itself. With
      # arguments, those replace call.args for the rest of the chain.
      def proceed(*new_args)
        @args = new_args unless new_args.empty?
        @pcount += 1
        nxt = @arounds && @arounds[@pos]
        if nxt.nil?
          @called = true
          @result = @orig.call(@args, @kwargs, @block)
          return @result
        end
        pos = @pos
        @pos = pos + 1
        begin
          val = API::Hook.invoke(nxt, self, true)
        ensure
          @pos = pos
        end
        @result = val unless val.equal?(API::Hook::NOTHING)
        return @result
      end
    end

    module Hook
      NOTHING = Object.new unless const_defined?(:NOTHING)
      module Prepends; end unless const_defined?(:Prepends)

      DENY_NAMES = %w[Kernel BasicObject Module Class File IO Dir FileUtils Marshal ObjectSpace Process ENV
                      Win32API HTTPLite Fiddle Thread Signal Etc Open3 Socket TCPSocket UDPSocket].freeze unless const_defined?(:DENY_NAMES)
      DENY_PREFIX = %w[KIF::ModGuard KIF::ModTrust KIF::Safe KIF::ModContract KIF::API::Hook Net:: Fiddle:: DL:: FFI::].freeze unless const_defined?(:DENY_PREFIX)
      WRAPPER_FILE = "030_Hook.rb" unless const_defined?(:WRAPPER_FILE)

      Point = Struct.new(:key, :klass, :name, :single, :form, :alias_name, :prepend_mod, :subs, :vis, :bypassed) unless const_defined?(:Point)

      @points  ||= {}    # "Class#name" => Point
      @forms   ||= {}    # "Class#name" => :alias | :prepend
      @pending ||= []    # [kind, target, id, priority, mod, blk] waiting for a method (defer: true)
      @alias_n ||= 0

      class << self
        attr_reader :points, :forms
      end

      #-------------------------------------------------------------------------
      # Targets
      #-------------------------------------------------------------------------
      # -> [class, :name, singleton?] or nil
      def self.resolve(target)
        if target.is_a?(Array)
          k, n, s = target
          return nil unless k.is_a?(Module)
          return [k, n.to_sym, s == :singleton]
        end
        m = target.to_s.match(/\A\s*([A-Z][\w:]*)\s*([#.])\s*(\S+)\s*\z/)
        return nil unless m
        k = (Object.const_get(m[1]) rescue nil)
        return nil unless k.is_a?(Module)
        return [k, m[3].to_sym, m[2] == "."]
      end

      def self.text(klass, name, single)
        return "#{klass.name || klass.inspect}#{single ? '.' : '#'}#{name}"
      end

      def self.target_class(klass, single); return single ? klass.singleton_class : klass; end

      def self.method_exists?(klass, name, single)
        tc = target_class(klass, single)
        return tc.method_defined?(name) || tc.private_method_defined?(name)
      end

      def self.exists?(target)
        r = resolve(target)
        return false unless r
        return method_exists?(r[0], r[1], r[2])
      end

      # every target a wrapper is installed on (for the collision snapshot)
      def self.targets; return @points.values.map { |p| text(p.klass, p.name, p.single) }; end

      def self.denied?(klass, name, single)
        n = klass.name.to_s
        return true if DENY_NAMES.include?(n)
        return true if DENY_PREFIX.any? { |p| n.start_with?(p) }
        return true if single && ["Kernel", "Object", "BasicObject", "Module", "Class"].include?(n)
        # Object holds the game's global functions (pbItemBall...): those are fine, the rest of Object is not
        return true if klass.equal?(Object) && !single && !(name.to_s =~ /\A(pb|get_|is_|has_|set_|show_|play_|find_)/ || ALLOWED_GLOBALS.include?(name.to_s))
        return false
      end
      ALLOWED_GLOBALS = %w[onStartingNewGame onLoadExistingGame].freeze unless const_defined?(:ALLOWED_GLOBALS)

      #-------------------------------------------------------------------------
      # Registering a hook (the public around / before / after end here)
      #-------------------------------------------------------------------------
      def self.add(form, target, id, priority, mod, defer, blk, locs)
        raise ArgumentError, "KIF::API.#{form} needs a block" unless blk
        key = mod || Attribution.key_from_caller(locs)
        r = resolve(target)
        if r.nil?
          return bad_target(target, key, "is not a target (use \"Class#method\", \"Class.method\" or [Class, :method])", defer, [form, target, id, priority, key, blk])
        end
        klass, name, single = r
        if denied?(klass, name, single)
          API.say("deny:#{key}:#{text(klass, name, single)}", "Mod \"#{Attribution.display(key)}\": #{text(klass, name, single)} can not be hooked through the API")
          return nil
        end
        unless method_exists?(klass, name, single)
          return bad_target(target, key, "does not exist", defer, [form, target, id, priority, key, blk])
        end
        id = (id || "#{File.basename(locs[0].path.to_s)}:#{locs[0].lineno}").to_s
        return attach(form, klass, name, single, id, priority.to_i, key, blk, false)
      end

      def self.bad_target(target, key, why, defer, row)
        if defer
          @pending << row
          return nil
        end
        msg = "hook target #{target.is_a?(Array) ? target.inspect : target} #{why}"
        raise HookError, msg if API.dev?
        API.say("hooktarget:#{key}:#{target}", "Mod \"#{Attribution.display(key)}\": #{msg}")
        return nil
      end

      # Retry the hooks that waited for a method (mods loaded, tests).
      def self.resolve_pending
        todo = @pending.dup
        @pending.clear
        todo.each do |form, target, id, priority, key, blk|
          r = resolve(target)
          if r && method_exists?(r[0], r[1], r[2]) && !denied?(r[0], r[1], r[2])
            attach(form, r[0], r[1], r[2], (id || "deferred:#{target}").to_s, priority.to_i, key, blk, false)
          else
            @pending << [form, target, id, priority, key, blk]
          end
        end
      end

      def self.pending; return @pending.dup; end

      def self.attach(form, klass, name, single, id, priority, key, blk, internal)
        pt = install(klass, name, single)
        return nil unless pt
        old = pt.subs.find { |s| s.id == id && s.mod == key && s.form == form }
        seq = old ? old.seq : (API.instance_variable_set(:@seq, API.instance_variable_get(:@seq) + 1))
        sub = Subscription.new(text(klass, name, single), id, key, priority, seq, Attribution.load_index(key), false, blk, nil)
        sub.form = form
        sub.target = pt
        sub.internal = internal
        arr = pt.subs.reject { |s| s.equal?(old) }
        arr << sub
        arr.sort_by!(&:sort_key)
        pt.subs = arr.freeze
        return sub
      end

      def self.detach(sub)
        pt = sub.target
        return unless pt.is_a?(Point)
        pt.subs = pt.subs.reject { |s| s.equal?(sub) }.freeze
      end

      # a mod's hooks go away (hot reload, tests)
      def self.remove_mod(key)
        n = 0
        @points.each_value do |pt|
          mine = pt.subs.select { |s| s.mod == key && !s.internal }
          next if mine.empty?
          pt.subs = (pt.subs - mine).freeze
          n += mine.length
        end
        @pending.reject! { |row| row[4] == key }
        return n
      end

      #-------------------------------------------------------------------------
      # Installing the wrapper
      #-------------------------------------------------------------------------
      def self.point_key(klass, name, single)
        return "#{klass.name || klass.object_id}#{single ? '.' : '#'}#{name}"
      end

      def self.kif_source?(um)
        loc = um.source_location
        return loc ? (loc[0].to_s.include?("990_KIF") || loc[0].to_s.include?("660_EBDX")) : false
      end

      def self.own_method?(m, name)
        return m.instance_methods(false).include?(name) || m.private_instance_methods(false).include?(name)
      end

      def self.choose_form(tc, name, single)
        return :alias if single || tc.equal?(Object)
        pre = tc.ancestors.take_while { |a| !a.equal?(tc) }
        hit = pre.any? { |m| !m.equal?(tc) && own_method?(m, name) && kif_source?(m.instance_method(name)) }
        return hit ? :prepend : :alias
      end

      # the class's own method, below every module prepended in front of it
      def self.method_below(tc, name)
        um = tc.instance_method(name)
        pre = tc.ancestors.take_while { |a| !a.equal?(tc) }
        return um if pre.empty?
        below = um
        below = below.super_method while below && pre.include?(below.owner)
        raise NameError, "#{tc}##{name} is only defined by prepended modules" unless below
        return below
      end

      def self.visibility(tc, name)
        return :private if tc.private_method_defined?(name)
        return :protected if tc.protected_method_defined?(name)
        return :public
      end

      def self.install(klass, name, single)
        key = point_key(klass, name, single)
        pt = @points[key]
        return pt if pt
        tc = target_class(klass, single)
        form = @forms[key] || choose_form(tc, name, single)
        vis = visibility(tc, name)
        pt = Point.new(key, klass, name, single, form, nil, nil, EMPTY_LIST, vis, false)
        if form == :prepend
          mod = prepend_module(klass, single)
          pt.prepend_mod = mod
          define_wrapper(mod, name, pt)
          mod.send(vis, name) unless vis == :public
          tc.prepend(mod) unless tc.ancestors.include?(mod)
        else
          below = method_below(tc, name)
          pt.alias_name = :"kifapi_#{name}_#{@alias_n += 1}"
          tc.send(:define_method, pt.alias_name, below)
          tc.send(:private, pt.alias_name)
          define_wrapper(tc, name, pt)
          tc.send(vis, name) unless vis == :public
        end
        @forms[key] = form
        @points[key] = pt
        return pt
      rescue NameError, ArgumentError, TypeError => e
        API.say("install:#{key}", "Hook engine: #{key} could not be wrapped (#{e.class}: #{e.message[0, 120]})")
        return nil
      end

      def self.prepend_module(klass, single)
        cname = "#{single ? 'S_' : ''}#{klass.name.to_s.gsub('::', '_')}"
        cname = "Anon_#{klass.object_id}" if cname.empty? || cname =~ /\A\d/ || cname !~ /\A[A-Z]/
        cname = cname.sub(/\A([a-z])/) { $1.upcase }
        return Prepends.const_get(cname) if Prepends.const_defined?(cname, false)
        return Prepends.const_set(cname, Module.new)
      end

      # The wrapper. With no hook on the point it is one call and one array test.
      def self.define_wrapper(owner, name, point)
        if point.form == :alias
          als = point.alias_name
          owner.send(:define_method, name) do |*args, **kw, &blk|
            return send(als, *args, **kw, &blk) if point.subs.empty?
            KIF::API::Hook.run(point, self, args, kw, blk) { |a, k, b| send(als, *a, **k, &b) }
          end
        else
          owner.send(:define_method, name) do |*args, **kw, &blk|
            return super(*args, **kw, &blk) if point.subs.empty?
            KIF::API::Hook.run(point, self, args, kw, blk) { |a, k, b| super(*a, **k, &b) }
          end
        end
      end

      #-------------------------------------------------------------------------
      # Running the hooks of one call
      #-------------------------------------------------------------------------
      def self.run(point, recv, args, kw, blk, &orig)
        call = Call.new(recv, args, kw, blk, orig)
        subs = point.subs
        subs.each do |s|
          next unless s.form == :before && s.enabled?
          invoke(s, call, false)
          break if call.skipped?
        end
        unless call.skipped?
          arounds = subs.select { |s| s.form == :around && s.enabled? }
          if arounds.empty?
            call.result = orig.call(call.args, call.kwargs, call.block)
            call.proceed_done!
          else
            # (an around block that never calls proceed replaces the method)
            call.setup(arounds, point)
            val = call.proceed
          end
        end
        subs.each do |s|
          next unless s.form == :after && s.enabled?
          invoke(s, call, false)
        end
        return call.result
      end

      # One hook block, isolated. For an around the block's value is returned
      # (NOTHING when it raised before the method ran: the chain goes on).
      def self.invoke(s, call, around)
        prof = API.profile?
        t0 = prof ? API.clock : nil
        val = NOTHING
        n0 = call.pcount
        begin
          val = s.blk.call(call)
          s.error_row = 0
        rescue Exception => e
          raise if API.fatal?(e)
          API.sub_failed(s, e)
          # the method must still run when an around hook failed before it did
          val = call.proceed if around && call.pcount == n0
        end
        if prof
          ms = (API.clock - t0) * 1000.0
          s.calls += 1
          s.total_ms += ms
          s.max_ms = ms if ms > s.max_ms
        end
        return around ? (val.equal?(NOTHING) ? call.result : val) : val
      end

      #-------------------------------------------------------------------------
      # Repairs
      #-------------------------------------------------------------------------
      def self.ours?(um)
        loc = um.source_location
        return loc ? (File.basename(loc[0].to_s) == WRAPPER_FILE && loc[0].to_s.include?("F-CORE-10_ModAPI")) : false
      end

      # is our wrapper still in the method table (as the method or as a copy someone aliased)?
      def self.reachable?(pt)
        tc = target_class(pt.klass, pt.single)
        if pt.form == :prepend
          return tc.ancestors.include?(pt.prepend_mod) && own_method?(pt.prepend_mod, pt.name) && ours?(pt.prepend_mod.instance_method(pt.name))
        end
        ([tc] + tc.ancestors.take_while { |a| !a.equal?(tc) }).each do |m|
          (m.instance_methods(false) + m.private_instance_methods(false)).each do |n|
            next if n == pt.alias_name
            um = (m.instance_method(n) rescue nil)
            return true if um && um.original_name == pt.name && ours?(um)
          end
        end
        return false
      end

      # Checks every wrapper. Returns the points that were bypassed or re-installed.
      def self.heal!
        resolve_pending
        out = []
        @points.each_value do |pt|
          next if pt.bypassed
          begin
            next if reachable?(pt)
            tc = target_class(pt.klass, pt.single)
            cur = (tc.instance_method(pt.name) rescue nil)
            next unless cur
            loc = cur.source_location
            who = loc ? KIF::ModContract.owner_of_path(loc[0]) : nil
            if who
              pt.bypassed = true
              API::Collisions.add({ :mod => who, :target => text(pt.klass, pt.name, pt.single), :kind => :bypassed, :was => "KIF mod API wrapper" })
              KIF.log("Mod #{Attribution.display(who)} replaced #{text(pt.klass, pt.name, pt.single)}; hooks and events on it stopped")
              out << pt
            elsif pt.form == :alias
              tc.send(:define_method, pt.alias_name, method_below(tc, pt.name))
              tc.send(:private, pt.alias_name)
              define_wrapper(tc, pt.name, pt)
              tc.send(pt.vis, pt.name) unless pt.vis == :public
              out << pt
            end
          rescue StandardError => e
            API.say("heal:#{pt.key}", "Hook engine: #{pt.key} could not be repaired (#{e.class}: #{e.message[0, 100]})")
          end
        end
        return out
      end
    end

    class Call
      def proceed_done!; @called = true; end
    end

    #---------------------------------------------------------------------------
    # Public API
    #---------------------------------------------------------------------------
    # KIF::API.around(target, id = nil, priority: 0, mod: nil, defer: false) { |call| ... }
    def self.around(target, id = nil, priority: 0, mod: nil, defer: false, &blk)
      return Hook.add(:around, target, id, priority, mod, defer, blk, caller_locations(1, 40))
    end

    # KIF::API.before(target, id = nil, ...) { |call| } - may change call.args or call.skip!(value)
    def self.before(target, id = nil, priority: 0, mod: nil, defer: false, &blk)
      return Hook.add(:before, target, id, priority, mod, defer, blk, caller_locations(1, 40))
    end

    # KIF::API.after(target, id = nil, ...) { |call| } - may set call.result
    def self.after(target, id = nil, priority: 0, mod: nil, defer: false, &blk)
      return Hook.add(:after, target, id, priority, mod, defer, blk, caller_locations(1, 40))
    end

    # Removes hooks: unhook(subscription) or unhook(target, id). A mod removes only its own.
    def self.unhook(target, id = nil)
      if target.is_a?(Subscription)
        Hook.detach(target)
        return true
      end
      key = Attribution.key_from_caller(caller_locations(1, 40))
      r = Hook.resolve(target)
      return false unless r
      pt = Hook.points[Hook.point_key(r[0], r[1], r[2])]
      return false unless pt
      gone = pt.subs.select { |s| (id.nil? || s.id == id.to_s) && (key.nil? || s.mod == key) && !s.internal }
      pt.subs = (pt.subs - gone).freeze
      return !gone.empty?
    end

    # [[target, form, id, mod, priority, enabled, stats], ...] of the mods' hooks
    def self.hooks
      out = []
      Hook.points.each_value do |pt|
        pt.subs.each do |s|
          next if s.internal
          out << [Hook.text(pt.klass, pt.name, pt.single), s.form, s.id, s.mod, s.priority, s.enabled?, s.stats]
        end
      end
      return out
    end

    def self.hooked?(target)
      r = Hook.resolve(target)
      return false unless r
      pt = Hook.points[Hook.point_key(r[0], r[1], r[2])]
      return pt ? !pt.subs.empty? : false
    end

    on_unload(:hook) { |key| Hook.remove_mod(key) }
  end
end
