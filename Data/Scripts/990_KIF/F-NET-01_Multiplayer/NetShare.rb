#===============================================================================
# F-NET-01 – Multiplayer: mod state API (KIF::Net.share / KIF::Net.on_share)
# For modders: Claude Docs/Base KIF/MULTIPLAYER_MOD_API.md
#
# A mod shares its own data with the other player:
#   KIF::Net.on_share(:my_mod) { |from, key, data| ... }   # register (also the whitelist)
#   KIF::Net.share(:my_mod, "spawns", { "map" => 5, "list" => [...] })   # true when sent
#   KIF::Net.on_share(:my_mod, host_only: true) { ... }    # only the host's game may send
# Rules (MULTIPLAYER_PLAN.md 1.6):
#   * a mod id is whitelisted by on_share on BOTH games: each game tells the
#     other its list when they connect (mod_ls); share sends nothing for a mod
#     the partner doesn't have, and a share for a mod this game doesn't have
#     is ignored with one log line
#   * data is JSON-safe only: Hash (String/Symbol keys), Array, String,
#     Integer (|n| <= 2^53), finite Float, true, false, nil; symbols arrive
#     as strings; nesting at most 8 deep
#   * at most 8 KB of data a message, 30 messages and 32 KB a second each way
#     (all mods together); over that, share returns false / the message is dropped
#   * nothing received is eval'd, Marshal-loaded or turned into a class,
#     method or file name; a handler that raises is logged, never fatal
# Messages: mod_ls {ids: "a,b,c"}, mod_sh {m: mod id, k: key, d: data}.
# Same messages over every transport (direct today, Steam later).
#===============================================================================
module KIF
  module Net
    TYPES["mod_ls"] = { "ids" => [String, 2_000] }
    TYPES["mod_sh"] = { "m" => [String, 32], "k" => [String, 64], "d" => [Object] }

    module ModShare
      ID        = /\A[A-Za-z0-9_.\-]{1,32}\z/
      MAX_DATA  = 8_192
      MAX_BYTES = 32_768   # a second, each way
      MAX_MSGS  = 30       # a second, each way
      MAX_DEPTH = 8
      MAX_INT   = 2**53
      BAD = Object.new.freeze
      @handlers = {}       # mod id => [block, host_only]
      @warned = {}

      class << self
        attr_reader :handlers
      end

      def self.ids; @handlers.keys.sort; end

      def self.register(mod_id, host_only, blk)
        id = mod_id.to_s
        raise ArgumentError, "mod id #{id.inspect}: use 1-32 of A-Z a-z 0-9 _ . -" unless id =~ ID
        raise ArgumentError, "KIF::Net.on_share(#{id}) needs a block" unless blk
        # a second mod with the same id doesn't take over the first one's messages
        if @handlers[id] && !@handlers[id][0].equal?(blk)
          note(id, "already registered by another mod; the first one keeps it")
          return id
        end
        @handlers[id] = [blk, host_only ? true : false]
        s = Net.session if Net.respond_to?(:session)
        announce(s) if s&.connected?
        return id
      end

      # per connection: the partner's mod ids and the rate counters
      def self.state(s)
        s.instance_variable_get(:@kif_mod_share) ||
          s.instance_variable_set(:@kif_mod_share, { peer: [], tx: [0, 0, 0], rx: [0, 0, 0] })
      end

      def self.on_connect(s)
        s.instance_variable_set(:@kif_mod_share, nil)
        @warned.clear
        announce(s)
      end

      def self.announce(s); s.post("mod_ls", "ids" => ids.join(",")[0, 2_000]); end

      def self.partner_has?(s, mod_id); s&.connected? ? state(s)[:peer].include?(mod_id.to_s) : false; end

      # a copy holding only JSON-safe values, or BAD
      def self.clean(v, depth = 0)
        return BAD if depth > MAX_DEPTH
        case v
        when nil, true, false then return v
        when Integer then return v.abs <= MAX_INT ? v : BAD
        when Float then return v.finite? ? v : BAD
        when Symbol then return clean(v.to_s, depth)
        when String
          s = v.dup.force_encoding("UTF-8")
          return s.valid_encoding? ? s : BAD
        when Array
          a = v.map { |x| clean(x, depth + 1) }
          return a.any? { |x| x.equal?(BAD) } ? BAD : a
        when Hash
          h = {}
          v.each do |k, x|
            return BAD unless k.is_a?(String) || k.is_a?(Symbol)
            ks = clean(k.to_s, depth)
            c = clean(x, depth + 1)
            return BAD if ks.equal?(BAD) || c.equal?(BAD)
            h[ks] = c
          end
          return h
        end
        return BAD
      end

      def self.spend(st, dir, bytes)
        sec = Net.now.floor
        r = st[dir]
        r[0], r[1], r[2] = sec, 0, 0 if r[0] != sec
        return false if r[1] + 1 > MAX_MSGS || r[2] + bytes > MAX_BYTES
        r[1] += 1
        r[2] += bytes
        return true
      end

      # one log line per mod and reason until the next connection
      def self.note(id, why)
        k = "#{id}|#{why}"
        Net.log("mod share #{id =~ ID ? id : '(bad id)'}: #{why}") unless @warned[k]
        @warned[k] = true
        return false
      end

      def self.share(s, mod_id, key, data)
        id = mod_id.to_s
        return false unless s&.connected?
        h = @handlers[id] or return note(id, "not registered in this game (call KIF::Net.on_share first)")
        return note(id, "the partner's game doesn't have this mod; nothing sent") unless state(s)[:peer].include?(id)
        return note(id, "only the host's game shares it") if h[1] && s.role != :host
        k = key.to_s
        return note(id, "a key is 1-64 characters, no control characters") unless k.length.between?(1, 64) && k !~ /[\x00-\x1f\x7f]/
        d = clean(data)
        return note(id, "data must be JSON-safe (Hash, Array, String, Integer, Float, true, false, nil)") if d.equal?(BAD)
        size = Wire.json(d).bytesize
        return note(id, "data over #{MAX_DATA} bytes (#{size})") if size > MAX_DATA
        return note(id, "over #{MAX_MSGS} messages or #{MAX_BYTES} bytes a second; dropped") unless spend(state(s), :tx, size)
        return s.post("mod_sh", "m" => id, "k" => k, "d" => d)
      end

      def self.receive(s, type, msg)
        st = state(s)
        case type
        when "mod_ls"
          st[:peer] = msg["ids"].split(",").select { |x| x =~ ID }.first(64)
        when "mod_sh"
          id = msg["m"]
          h = @handlers[id] if id =~ ID
          return note(id, "a mod this game doesn't have; ignored") unless h
          return note(id, "sent by a partner who isn't the host; ignored") if h[1] && s.role == :host
          d = clean(msg["d"])
          return note(id, "data that isn't JSON-safe; dropped") if d.equal?(BAD)
          size = Wire.json(d).bytesize
          return note(id, "data over #{MAX_DATA} bytes; dropped") if size > MAX_DATA
          return note(id, "partner over the rate limit; dropped") unless spend(st, :rx, size)
          begin
            h[0].call(Net.shown_name(s.partner), msg["k"], d)
          rescue StandardError, ScriptError, SystemStackError => e   # (NotImplementedError is a ScriptError)
            Net.log("mod share #{id}: its handler failed (#{e.class}: #{e.message})")
          end
        end
      end
    end

    #---------------------------------------------------------------------------
    # The public calls
    #---------------------------------------------------------------------------
    # true when sent; false when not connected, the partner lacks the mod, or
    # the data or rate doesn't fit (the reason is logged once)
    def self.share(mod_id, key, data)
      return ModShare.share(respond_to?(:session) ? session : nil, mod_id, key, data)
    end

    # block |from (partner's name), key, data|; host_only: drop what a
    # non-host partner sends for this mod (host-authoritative state)
    def self.on_share(mod_id, host_only: false, &blk)
      return ModShare.register(mod_id, host_only, blk)
    end

    def self.connected?; (respond_to?(:session) && session&.connected?) ? true : false; end
    def self.host?; (connected? && session.role == :host) ? true : false; end
    def self.partner_has?(mod_id); ModShare.partner_has?(respond_to?(:session) ? session : nil, mod_id); end
  end
end
