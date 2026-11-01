#===============================================================================
# F-CORE-10 Mod API - the event bus (KIF::API)
#
# A mod subscribes to an event instead of copying game code or aliasing a
# method. One mod's mistake never stops the game or the other mods: every
# handler runs inside its own begin/rescue.
#
#   KIF::API.on(:battle_start) { |ctx| KIF.log("battle with #{ctx[:battle]}") }
#   KIF::API.on(:damage_multipliers, "my_boost", priority: KIF::API::LATE) do |ctx|
#     ctx[:multipliers][:final_damage_multiplier] *= 1.1 if ctx[:user].hasType?(:FIRE)
#   end
#   KIF::API.on(:move_use) { |ctx| ctx.cancel!("not allowed") if ctx[:move].id == :SPLASH }
#
# Names of events and their fields are in 020_Events.rb (KIF::API::EVENTS) and
# in Logs/KIF_API_Reference.txt (Options > Mod tools > Write API reference).
# API level 1: names in this file may not change; new ones may be added.
#
# Rules (the same words the reference gives):
# - An event nobody listens to costs one Hash lookup.
# - Order: lower priority first (FIRST EARLY NORMAL LATE LAST), then the mod's
#   load order (KIF's own handlers first), then the order of registration.
#   MONITOR handlers run last, always, and get a frozen copy of the ctx.
# - A handler that raises is logged with the mod's name and skipped; the other
#   handlers and the game go on. 5 errors in a row, or 25 in a session, switch
#   that one handler off for the session (Options > Mod tools shows it).
# - The handler gets a ctx: ctx[:field] reads, ctx[:field] = v writes (only the
#   fields marked changeable), ctx.cancel!(reason) on events that can be
#   cancelled. Do not keep the ctx: hot events reuse one object.
# - Mods can only be as safe as the code in them: this is a guard rail, not a
#   sandbox (see KIF::ModTrust.about_text when it exists).
#===============================================================================
module KIF
  module API
    FIRST   = -1000 unless const_defined?(:FIRST)
    EARLY   =  -100 unless const_defined?(:EARLY)
    NORMAL  =     0 unless const_defined?(:NORMAL)
    LATE    =   100 unless const_defined?(:LATE)
    LAST    =  1000 unless const_defined?(:LAST)
    MONITOR =  2000 unless const_defined?(:MONITOR)

    MAX_DEPTH      = 8   unless const_defined?(:MAX_DEPTH)       # emit inside a handler
    BREAKER_ROW    = 5   unless const_defined?(:BREAKER_ROW)     # errors in a row
    BREAKER_TOTAL  = 25  unless const_defined?(:BREAKER_TOTAL)   # errors in a session
    HOT_WARN_MS    = 4.0 unless const_defined?(:HOT_WARN_MS)     # slow hot handler (profile mode)
    # named for events a later release may add (multiplayer); supports? says false
    RESERVED_EVENTS = [:net_connected, :net_disconnected, :coop_battle_begin, :coop_battle_end].freeze unless const_defined?(:RESERVED_EVENTS)

    class UnknownEvent < ArgumentError; end    # Mod Dev mode: an event name that does not exist
    class FieldError   < ArgumentError; end    # Mod Dev mode: writing a read-only or unknown field
    class PlainDataError < ArgumentError; end  # Mod Dev mode: data that is not plain (060_Data.rb)
    class LevelError   < RuntimeError; end     # require_level: the mod needs a newer KIF
    class HookError    < ArgumentError; end    # Mod Dev mode: a hook target that does not exist

    #---------------------------------------------------------------------------
    # What a handler receives. name, mod, reason, fields; [] / []= / ctx.field.
    #---------------------------------------------------------------------------
    class Ctx
      attr_reader :name, :mod, :reason

      def initialize
        @f = {}
        @rw = {}
        @defaults = {}
        @cancel_ok = false
        @cancelled = false
        @view_only = false
      end

      # internal: prepare for the next emit
      def reset!(name, info, fields)
        @name = name
        @f = fields
        @rw = info[:rw]
        @cancel_ok = info[:cancel] ? true : false
        @cancelled = false
        @reason = nil
        @mod = nil
        @view_only = false
        if @rw.empty?
          @defaults = API::EMPTY_HASH
        else
          @defaults = {}
          @rw.each_key { |k| @defaults[k] = @f[k] }
        end
        return self
      end

      def set_mod(m); @mod = m; end   # internal: the mod whose handler runs now

      # A frozen read-only copy (what MONITOR handlers get)
      def frozen_view(mod = nil)
        c = Ctx.new
        c.instance_variable_set(:@name, @name)
        c.instance_variable_set(:@f, @f.dup.freeze)
        c.instance_variable_set(:@rw, API::EMPTY_HASH)
        c.instance_variable_set(:@cancelled, @cancelled)
        c.instance_variable_set(:@reason, @reason)
        c.instance_variable_set(:@mod, mod)
        c.instance_variable_set(:@view_only, true)
        return c.freeze
      end

      def fields; return @f; end
      def to_h; return @f.dup; end
      def [](key); return @f[key.is_a?(Symbol) ? key : key.to_sym]; end

      # Writes a changeable field. A read-only or unknown field is logged once
      # and ignored (Mod Dev mode raises KIF::API::FieldError).
      def []=(key, value)
        key = key.to_sym
        if @view_only || !@rw.key?(key)
          API.field_violation(@name, key, @mod, @view_only)
          return value
        end
        return @f[key] = value
      end

      # The changeable field after validation: a value of the wrong kind or
      # outside the range written in the table gives back the value the game
      # had (logged once). The code that fires the event reads fields this way.
      def valid(key)
        spec = @rw[key]
        return @f[key] unless spec
        v = @f[key]
        r = API.coerce(spec[0], v, @defaults[key], spec[1])
        API.say("coerce:#{@name}:#{key}:#{@mod}", "Mod #{API::Attribution.display(@mod)}: event :#{@name} field #{key} got #{v.inspect[0, 40]}; the game's value is kept") if !r.equal?(v) && !(r == v)
        return r
      end

      def default(key); return @defaults[key]; end

      def cancel!(reason = nil)
        if @view_only
          API.say("cancelview:#{@name}", "Event :#{@name}: a MONITOR handler can not cancel")
        elsif @cancel_ok
          @cancelled = true
          @reason = reason.to_s[0, 140] if reason
        else
          API.say("cancel:#{@name}:#{@mod}", "Mod #{API::Attribution.display(@mod)}: event :#{@name} can not be cancelled")
        end
        return self
      end

      def cancelled?; return @cancelled; end

      # pause_menu_build helpers: ctx.hide(:kif_pc), ctx.relabel(:x, "Text"), ctx.move(:x, 5)
      def hide(id)
        list = @f[:entries]
        list.reject! { |e| e.id == id } if list.is_a?(Array) && !@view_only
        return self
      end

      def relabel(id, text)
        e = (@f[:entries] || []).find { |x| x.id == id }
        e.label = text if e && !@view_only
        return self
      end

      def move(id, order)
        e = (@f[:entries] || []).find { |x| x.id == id }
        e.order = order if e && !@view_only
        return self
      end

      def method_missing(m, *args)
        s = m.to_s
        if s.end_with?("=") && args.length == 1
          self[s.chomp("=")] = args[0]
        elsif args.empty? && @f.key?(m)
          @f[m]
        else
          super
        end
      end

      def respond_to_missing?(m, priv = false)
        return @f.key?(m) || m.to_s.end_with?("=") || super
      end

      def inspect; return "#<KIF::API::Ctx :#{@name} #{@f.keys.inspect}#{@cancelled ? ' cancelled' : ''}>"; end
    end

    EMPTY_HASH = {}.freeze unless const_defined?(:EMPTY_HASH)
    EMPTY_LIST = [].freeze unless const_defined?(:EMPTY_LIST)
    # what emit returns when nobody listens: not cancelled, no fields, never changes
    NO_CTX = Ctx.new.reset!(:none, { :rw => EMPTY_HASH, :cancel => nil }, EMPTY_HASH).freeze unless const_defined?(:NO_CTX)

    #---------------------------------------------------------------------------
    # A registered handler (or hook). event: the event name, or the hook target
    # text. stats: calls, errors, total_ms, max_ms (calls and times only count
    # in profile mode; errors always).
    #---------------------------------------------------------------------------
    class Subscription
      attr_reader :event, :id, :mod, :priority, :seq, :once, :blk, :cond, :order
      attr_accessor :cancelled_ok, :auto_off, :form, :target, :internal, :hook_off, :error_row, :error_total, :error_text
      attr_accessor :calls, :total_ms, :max_ms

      def initialize(event, id, mod, priority, seq, order, once, blk, cond)
        @event = event
        @id = id
        @mod = mod
        @priority = priority
        @seq = seq
        @order = order
        @once = once
        @blk = blk
        @cond = cond
        @cancelled_ok = false
        @auto_off = false
        @hook_off = false
        @error_row = 0
        @error_total = 0
        @calls = 0
        @total_ms = 0.0
        @max_ms = 0.0
      end

      # true while it can run: not auto-switched-off, its mod not disabled
      def enabled?
        return false if @auto_off || @hook_off
        return @mod.nil? || !API.mod_off?(@mod)
      end

      def sort_key; return [@priority, @order, @seq]; end
      def monitor?; return @priority >= API::MONITOR; end
      def off; API.remove_sub(self); return nil; end
      def stats
        return { :calls => @calls, :errors => @error_total, :total_ms => @total_ms.round(3), :max_ms => @max_ms.round(3) }
      end
      def inspect; return "#<KIF::API::Subscription :#{@event} #{@id} mod=#{@mod.inspect} prio=#{@priority}>"; end
    end

    @subs        ||= {}      # event => frozen Array<Subscription>, sorted
    @seq         ||= 0
    @said        ||= {}
    @custom      ||= {}      # events a mod defined (define_event)
    @disabled    ||= {}      # mod key => true (session only)
    @depth       ||= 0
    @hot_ctx     ||= {}
    @hot_busy    ||= {}
    @unloaders   ||= {}
    @profile_force = (@profile_force.nil? ? false : @profile_force)
    @dev_force     = (@dev_force.nil? ? false : @dev_force)
    @profile       = (@profile.nil? ? false : @profile)
    @trace         = nil unless defined?(@trace)

    class << self
      attr_reader :depth
      attr_accessor :profile_force, :dev_force
      attr_accessor :trace   # Array (ring buffer owned by 090_Dev.rb) or nil
    end

    #---------------------------------------------------------------------------
    # Levels and modes
    #---------------------------------------------------------------------------
    # The API level this KIF offers (KIF::API_LEVEL).
    def self.level; return KIF::API_LEVEL; end

    # True when the event is a real, usable event name of this level.
    def self.supports?(name)
      n = name.to_s.to_sym
      return false if RESERVED_EVENTS.include?(n)
      return EVENTS.key?(n) || @custom.key?(n)
    end

    # Raises KIF::API::LevelError (inside a mod's load, which blocks that mod)
    # when the mod needs a newer API than this KIF has.
    def self.require_level(n)
      raise LevelError, "needs API level #{n}, this KIF has #{level}" if n.to_i > level
      return true
    end

    # Mod Dev mode: strict checks (misuse raises into the mod's isolation).
    def self.dev?
      return true if @dev_force
      return ($PokemonSystem && $PokemonSystem.respond_to?(:kif_mod_dev) && $PokemonSystem.kif_mod_dev.to_i == 1) ? true : false
    rescue StandardError
      return false
    end

    # Timings are only measured in profile mode (Mod Dev mode, verbose logging)
    def self.profile?; return @profile; end

    # Called when a setting that changes the mode may have changed.
    def self.refresh_modes!
      @profile = @profile_force || dev? || KIF.verbose? ? true : false
      return @profile
    rescue StandardError
      return @profile = @profile_force ? true : false
    end

    #---------------------------------------------------------------------------
    # Logging that says a thing once
    #---------------------------------------------------------------------------
    def self.say(key, text)
      return false if @said[key]
      @said[key] = true
      KIF.log(text)
      return true
    end

    def self.clock; return Process.clock_gettime(Process::CLOCK_MONOTONIC); end

    # exceptions that must never be swallowed (quit, reset, engine errors)
    def self.fatal?(e)
      return true if e.is_a?(SystemExit) || e.is_a?(Interrupt) || e.is_a?(NoMemoryError)
      return true if defined?(::Reset) && ::Reset.is_a?(Class) && e.is_a?(::Reset)
      return true if defined?(::MKXPError) && ::MKXPError.is_a?(Class) && e.is_a?(::MKXPError)
      return false
    end

    #---------------------------------------------------------------------------
    # Event information
    #---------------------------------------------------------------------------
    # The row of EVENTS (or of define_event) for a name, or nil.
    def self.event_info(name)
      n = name.is_a?(Symbol) ? name : name.to_s.to_sym
      return EVENTS[n] || @custom[n]
    end

    # Every event name (core and mod-defined), as Symbols.
    def self.events; return EVENTS.keys + @custom.keys; end

    def self.custom_events; return @custom; end

    # all handlers of one event, in the order they run
    def self.subscribers(event)
      return (@subs[event.to_s.to_sym] || EMPTY_LIST).dup
    end

    # true when at least one handler is registered (internal emitters ask this
    # BEFORE they build the fields)
    def self.listening?(event)
      l = @subs[event]
      return !(l.nil? || l.empty?)
    end

    def self.subs_table; return @subs; end

    #---------------------------------------------------------------------------
    # Registering
    #---------------------------------------------------------------------------
    # KIF::API.on(event, id = nil, priority: 0, mod: nil, once: false,
    #             cancelled: false, if: nil) { |ctx| ... } -> Subscription or nil
    #   id        names the handler; the same (mod, event, id) replaces the
    #             older handler in place (default id: "file:line" of this call,
    #             so loading a file twice does not duplicate)
    #   priority  FIRST EARLY NORMAL LATE LAST MONITOR or any Integer
    #   mod       the mod key; normally found from the calling file
    #   once      the handler removes itself before it runs
    #   cancelled run even after another handler cancelled the event
    #   if:       a proc called first with the ctx; false skips the handler
    def self.on(event, id = nil, priority: 0, mod: nil, once: false, cancelled: false, **rest, &blk)
      raise ArgumentError, "KIF::API.on needs a block" unless blk
      locs = caller_locations(1, 40)
      key = mod.equal?(:kif) ? nil : (mod || Attribution.key_from_caller(locs))   # mod: :kif = KIF's own handler
      ev = event.is_a?(Symbol) ? event : event.to_s.to_sym
      unless supports_or_reserved?(ev)
        return unknown_event(ev, key)
      end
      id = id.to_s unless id.nil?
      id ||= "#{File.basename(locs[0].path.to_s)}:#{locs[0].lineno}"
      return add_sub(ev, id, key, priority.to_i, once ? true : false, cancelled ? true : false, rest[:if], blk)
    end

    def self.supports_or_reserved?(ev)
      return EVENTS.key?(ev) || @custom.key?(ev) || RESERVED_EVENTS.include?(ev)
    end

    def self.unknown_event(ev, key)
      near = nearest_name(ev)
      msg = "unknown event :#{ev}#{near ? "; did you mean :#{near}" : ""}"
      raise UnknownEvent, msg if dev?
      say("unknown:#{key}:#{ev}", "Mod #{Attribution.display(key)}: #{msg}")
      return nil
    end

    def self.nearest_name(ev)
      best = nil
      best_d = 3
      events.each do |n|
        d = distance(ev.to_s, n.to_s)
        (best = n; best_d = d) if d < best_d
      end
      return best
    end

    # edit distance (small strings only)
    def self.distance(a, b)
      return b.length if a.empty?
      return a.length if b.empty?
      prev = (0..b.length).to_a
      a.each_char.with_index(1) do |ca, i|
        cur = [i]
        b.each_char.with_index(1) do |cb, j|
          cur << [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca == cb ? 0 : 1)].min
        end
        prev = cur
      end
      return prev[b.length]
    end

    def self.add_sub(ev, id, key, priority, once, cancelled, cond, blk, form: nil, target: nil, internal: false)
      list = @subs[ev] || EMPTY_LIST
      old = list.find { |s| s.id == id && s.mod == key }
      seq = old ? old.seq : (@seq += 1)
      order = Attribution.load_index(key)
      sub = Subscription.new(ev, id, key, priority, seq, order, once, blk, cond)
      sub.cancelled_ok = cancelled
      sub.form = form
      sub.target = target
      sub.internal = internal
      arr = list.reject { |s| s.equal?(old) }
      arr << sub
      arr.sort_by!(&:sort_key)
      @subs[ev] = arr.freeze
      Points.arm(ev) if defined?(KIF::API::Points) && !internal
      return sub
    end

    # Removes a handler. KIF::API.off(subscription) or KIF::API.off("id", :event).
    # A mod can only remove its own handlers by id.
    def self.off(what, event = nil)
      if what.is_a?(Subscription)
        remove_sub(what)
        return true
      end
      key = Attribution.key_from_caller(caller_locations(1, 40))
      n = 0
      @subs.each do |ev, list|
        next if event && ev != event.to_sym
        list.each { |s| (remove_sub(s); n += 1) if s.id == what.to_s && (key.nil? || s.mod == key) && !s.internal }
      end
      return n > 0
    end

    def self.remove_sub(sub)
      list = @subs[sub.event]
      return unless list
      arr = list.reject { |s| s.equal?(sub) }
      return if arr.length == list.length
      @subs[sub.event] = arr.freeze
      Points.disarm_if_idle(sub.event) if defined?(KIF::API::Points) && arr.empty?
    end

    # Removes every handler a mod registered (events and hooks).
    def self.off_all(mod: nil)
      key = mod || Attribution.key_from_caller(caller_locations(1, 40))
      return 0 if key.nil?
      n = 0
      @subs.values.each { |list| list.each { |s| (remove_sub(s); n += 1) if s.mod == key && !s.internal } }
      n += Hook.remove_mod(key) if defined?(KIF::API::Hook)
      return n
    end

    # Everything a mod added through the API goes away (hot reload, tests).
    # Each part of the API registers an unloader (on_unload).
    def self.unload_mod(key)
      off_all(mod: key)
      @unloaders.each_value do |blk|
        begin
          blk.call(key)
        rescue StandardError => e
          KIF.log("Unloading #{key}: #{e.class}: #{e.message}")
        end
      end
      return true
    end

    # name: one unloader per name (a file that loads twice does not add twice)
    def self.on_unload(name = nil, &blk)
      @unloaders[name || blk.object_id] = blk
      return blk
    end

    #---------------------------------------------------------------------------
    # Mods switched off for this session (not saved)
    #---------------------------------------------------------------------------
    def self.disable_mod(key); @disabled[key.to_s] = true; end
    def self.enable_mod(key); @disabled.delete(key.to_s); end
    def self.mod_off?(key); return @disabled.empty? ? false : (@disabled[key.to_s] ? true : false); end
    def self.mod_enabled?(key); return !mod_off?(key); end

    #---------------------------------------------------------------------------
    # Mod-defined events: KIF::API.define_event("mymod.boss_phase",
    #   fields: { total: :rw, turn: :ro }, cancellable: false, doc: "...")
    # The name has a dot and starts with the mod's own name.
    #---------------------------------------------------------------------------
    def self.define_event(name, fields: {}, cancellable: false, doc: "")
      key = Attribution.key_from_caller(caller_locations(1, 40))
      s = name.to_s
      ok = s.include?(".") && s =~ /\A[a-z0-9_\-]+\.[a-z0-9_.\-]+\z/i
      if ok && key
        pre = s.split(".").first.downcase
        ok = [KIF::ModContract.safe_id(key), key.to_s.downcase, Attribution.json_id(key).to_s.downcase].include?(pre)
      end
      unless ok
        msg = "event name #{s.inspect} must look like \"#{key || 'mymod'}.something\" (the mod's name, a dot, a name)"
        raise ArgumentError, msg if dev?
        say("defev:#{key}:#{s}", "Mod #{Attribution.display(key)}: #{msg}")
        return nil
      end
      ev = s.to_sym
      rw = {}
      ro = []
      fields.each do |f, mode|
        if mode.to_s == "rw" || mode.is_a?(Array) then rw[f.to_sym] = mode.is_a?(Array) ? mode : [:obj, nil] else ro << f.to_sym end
      end
      @custom[ev] = { :since => KIF::API_LEVEL, :p => 0, :hot => false, :cancel => cancellable ? "cancelled by a handler" : nil,
                      :ro => ro, :rw => rw, :doc => doc.to_s[0, 300], :mod => key }.freeze
      return ev
    end

    #---------------------------------------------------------------------------
    # Emitting
    #---------------------------------------------------------------------------
    # KIF::API.emit(event, **fields) -> Ctx. For mod-defined events and tests.
    # Core events are fired by KIF itself; a mod can not fake them.
    def self.emit(event, **fields)
      ev = event.is_a?(Symbol) ? event : event.to_s.to_sym
      list = @subs[ev]
      return NO_CTX if list.nil? || list.empty?
      info = EVENTS[ev] || @custom[ev]
      return NO_CTX unless info
      if !info[:mod] && !EVENTS[ev].nil?
        key = Attribution.key_from_caller(caller_locations(1, 40))
        if key
          say("fake:#{key}:#{ev}", "Mod #{Attribution.display(key)} can not emit core event :#{ev}")
          return NO_CTX
        end
      end
      return dispatch(ev, info, fields, list)
    end

    # KIF's own firing: the event is known, the fields are built by the caller
    # (which checked listening? first).
    def self.fire(ev, fields)
      list = @subs[ev]
      return NO_CTX if list.nil? || list.empty?
      info = EVENTS[ev] || @custom[ev]
      return NO_CTX unless info
      return dispatch(ev, info, fields, list)
    end

    def self.dispatch(ev, info, fields, list)
      if @depth >= MAX_DEPTH
        say("depth:#{ev}", "Event :#{ev}: emitted from inside #{MAX_DEPTH} handlers, dropped")
        return NO_CTX
      end
      hot = info[:hot]
      if hot && !@hot_busy[ev]
        ctx = (@hot_ctx[ev] ||= Ctx.new)
        @hot_busy[ev] = true
        pooled = true
      else
        ctx = Ctx.new
        pooled = false
      end
      ctx.reset!(ev, info, fields)
      prof = @profile
      t0 = prof ? clock : nil
      @depth += 1
      begin
        list.each do |s|
          break if s.monitor?
          next unless s.enabled?
          next if ctx.cancelled? && !s.cancelled_ok
          run_sub(s, ctx, prof, hot)
        end
        list.each do |s|
          next unless s.monitor? && s.enabled?
          run_sub(s, ctx.frozen_view(s.mod), prof, hot)
        end
      ensure
        @depth -= 1
        @hot_busy[ev] = false if pooled
      end
      if prof
        ms = (clock - t0) * 1000.0
        tr = @trace
        tr.push([Time.now.to_f, ev, list.length, ms.round(3)]) if tr
        tr.shift if tr && tr.length > 500
      end
      return ctx
    end

    def self.run_sub(s, ctx, prof, hot)
      ctx.set_mod(s.mod) unless ctx.frozen?
      if s.cond
        begin
          return unless s.cond.call(ctx)
        rescue Exception => e
          raise if fatal?(e)
          sub_failed(s, e)
          return
        end
      end
      remove_sub(s) if s.once
      t0 = prof ? clock : nil
      begin
        s.blk.call(ctx)
        s.error_row = 0
      rescue Exception => e
        raise if fatal?(e)
        sub_failed(s, e)
      end
      if prof
        ms = (clock - t0) * 1000.0
        s.calls += 1
        s.total_ms += ms
        s.max_ms = ms if ms > s.max_ms
        say("slow:#{s.event}:#{s.mod}:#{s.id}", "Mod #{Attribution.display(s.mod)} hook :#{s.event} (#{s.id}) took #{ms.round(1)} ms; hot events run every frame") if hot && ms > HOT_WARN_MS
      end
    end

    # A handler raised: log it once per message, count it, switch it off after
    # repeated errors (the circuit breaker).
    def self.sub_failed(s, e)
      s.error_row += 1
      s.error_total += 1
      where = (e.backtrace || [])[0].to_s.sub(/\A.*[\/\\]/, "")
      who = Attribution.display(s.mod)
      if say("err:#{s.object_id}:#{e.class}:#{e.message[0, 80]}",
             "Mod \"#{who}\" hook :#{s.event} (#{s.id}) raised #{e.class}: #{e.message[0, 160]}#{where.empty? ? '' : " at #{where}"}")
        KIF.verbose("  " + (e.backtrace || [])[0, 3].join(" | "))
        KIF::CrashLog.write("Mod \"#{who}\" hook :#{s.event} (#{s.id})\r\n" + KIF::CrashLog.describe(e)) if defined?(KIF::CrashLog) && !s.instance_variable_get(:@crashlogged)
        s.instance_variable_set(:@crashlogged, true)
      end
      s.error_text = "#{e.class}: #{e.message[0, 100]}"
      if !s.auto_off && (s.error_row >= BREAKER_ROW || s.error_total >= BREAKER_TOTAL)
        s.auto_off = true
        KIF.log("Mod \"#{who}\" hook :#{s.event} (#{s.id}) switched off after repeated errors")
      end
    end

    #---------------------------------------------------------------------------
    # Fields
    #---------------------------------------------------------------------------
    def self.field_violation(event, field, mod, view)
      msg = view ? "event :#{event}: a MONITOR handler can not write field #{field}" :
                   "event :#{event}: field #{field} is read-only or unknown"
      raise FieldError, msg if dev? && !view
      say("field:#{mod}:#{event}:#{field}", "Mod #{Attribution.display(mod)}: #{msg}")
    end

    # KIF::API.coerce(kind, value, default, range = nil) -> value or default
    # kinds: :int :float (finite; an Integer becomes a Float) :bool :sym :str :array :hash :obj
    def self.coerce(kind, value, default, range = nil)
      ok = case kind
           when :int   then value.is_a?(Integer)
           when :float then (value.is_a?(Float) && value.finite?) || value.is_a?(Integer)
           when :bool  then value == true || value == false
           when :sym   then value.is_a?(Symbol)
           when :str   then value.is_a?(String)
           when :array then value.is_a?(Array)
           when :hash  then value.is_a?(Hash)
           else true
           end
      return default unless ok
      return default if range && value.is_a?(Numeric) && !range.cover?(value)
      return value.to_f if kind == :float && value.is_a?(Integer)
      return value
    end

    #---------------------------------------------------------------------------
    # KIF::API.rescuing(label = nil) { } - runs the block; a raise is logged
    # under the calling mod's name and the block gives nil.
    #---------------------------------------------------------------------------
    def self.rescuing(label = nil)
      key = Attribution.key_from_caller(caller_locations(1, 40))
      return yield
    rescue Exception => e
      raise if fatal?(e)
      say("rescuing:#{key}:#{label}:#{e.class}:#{e.message[0, 60]}",
          "Mod \"#{Attribution.display(key)}\"#{label ? " (#{label})" : ''} raised #{e.class}: #{e.message[0, 160]} at #{(e.backtrace || [])[0].to_s.sub(/\A.*[\/\\]/, '')}")
      return nil
    end
  end
end
