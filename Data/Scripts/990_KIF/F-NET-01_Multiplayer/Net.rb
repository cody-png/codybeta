#===============================================================================
# F-NET-01 – Multiplayer, phase 1: the connection between two games
# (new in KIF 1.3, 2026-10-23; design: Claude Docs/Base KIF/MULTIPLAYER_PLAN.md)
#
# Peer to peer, no server: one game hosts (TCP 52411, or the next free of
# 52412-52415), the other joins with a join code. Optional community relay
# (Tools/kif_relay.rb) for players who can't host; none is built in.
# Or over Steam (NetSteam.rb, Session#host_steam): the same frames, each one
# Steam message, between members of a friends-only lobby.
#
# Wire: every frame is a 4-byte big-endian length + payload.
#   Handshake (plain JSON, max 1 KB a frame), SPAKE2 (module Spake2 below):
#     joiner -> host  {"t":"hi","v":3,"n":nJ,"x":X}    nJ, nH: 16 random bytes
#     host -> joiner  {"t":"hi","v":3,"n":nH,"y":Y}    X = g^x M^w, Y = g^y N^w
#     joiner -> host  {"t":"auth","p":HMAC(Ke, "KIF2 join")}   Ke = SHA-256(nJ, nH,
#     host -> joiner  {"t":"auth","p":HMAC(Ke, "KIF2 host")}   X, Y, K = g^2xy, w)
#     The joiner proves first. A wrong proof: {"t":"no","why":"code"} and the
#     line closes; 5 wrong proofs from one address and it's ignored for 10
#     minutes; at most 10 failed handshakes in 10 seconds (a line that gets the
#     host's hi and leaves without a proof counts as one). A host keeps a few
#     handshakes going at once (4, 2 for one address; a full table drops the
#     oldest line of the address holding the most), so a silent connection
#     can't hold the door, and one address opens 12 connections in 10 s at most.
#     "busy" is only said to someone with the right code (signed). "wait" and
#     "code" arrive unsigned: the joiner keeps them as a hint and reports them
#     only if the line then closes.
#   Then the joiner says hello and the host's player is asked "Let <name>
#   join?". The host answers with its own hello, or a signed
#   {"t":"no","why":"declined"} (also after 60 s without an answer). After 3
#   no's in 10 minutes the host stops asking and says no; at most 3 questions
#   a minute. An address (an IPv6 /64) that was told No waits 10 minutes, and
#   the join code is new after a join or a No (not after a timeout).
#   After the proofs (max 64 KB a frame): payload = 32-byte MAC + 8-byte
#     number + encrypted JSON object {"t":type,...}. Keys come from Ke and
#     both nonces, one set per direction. The cipher is HMAC-SHA256 in counter
#     mode over (number, block); MAC = HMAC-SHA256(direction key, number +
#     ciphertext), checked before anything is decrypted or read. A frame with
#     a wrong MAC, an old number (replay) or fields that don't fit its type is
#     dropped; a type this version doesn't know is ignored. 5 bad frames close
#     the line, and so does a number that skips one (a frame cut out on the
#     way). A line also closes when it sends more than 192 KB a second
#     (after a 1.5 MB burst) or more than 4 MB sit unread. A line closes too
#     when its messages would cost the game too long to read: Net.cost counts
#     a message's values, keys and escapes from its text, before it is parsed,
#     against a budget that fills 20,000 a second (100,000 saved).
#   The first signed message each way is "hello" (name, KIF version). Until the
#   host's player has said yes only a short hello, no, bye or ping is read (the
#   rest counts as a bad frame, unparsed).
#   "ping" every 5 s of quiet; 20 s without a byte = lost. "bye" = clean close.
#   A line whose writes make no progress for 10 s is closed.
#
# Peer data is never Marshal-loaded or eval'd: only JSON text (ASCII, nesting
# limited) read by the small parser below into Hash/Array/String/Integer/
# Float/true/false/nil, then checked against TYPES.
#
# Threads: an accept thread (host), a connect thread (join), and a reader
# and a writer thread per connection. They only move bytes (the reader also
# closes a line that is too fast, stalled, or silent in its handshake);
# everything else runs on the game's thread in Session#poll, which never
# waits and stops after about 8 ms of work.
# Only socket calls built into the engine's Ruby are used (no socket.rb
# helpers such as connect_nonblock/accept_nonblock, no Net::HTTP, no IPAddr).
#===============================================================================
module KIF
  module Net
    PORT       = 52411
    PORT_TRIES = 5       # 52411..52415
    LAN_PORT   = 52412
    RELAY_PORT = 52413
    MAX_FRAME  = 65_536
    MAX_PRE    = 1024    # frames before the handshake is done
    MAX_BAD    = 5       # bad frames before the line is closed
    MAX_RATE   = 400     # frames a second before the line is closed
    PROTO      = 3       # 3: sealed frames, 32-digit picture hashes, 8-digit trade ids, co-op teams of up to 36 foes (with the Exp split)
    HS_LIMIT   = 10      # failed handshakes a host puts up with in 10 s
    MAX_PENDING   = 4    # handshakes a host runs at once (the oldest makes room)
    MAX_PER_ADDR  = 2    # ... of them from one address
    MAX_SOCKS     = 8    # accepted sockets waiting for the game to look at them
    MAX_ASKS      = 3    # "no" answers in 10 minutes before the host stops asking
    MAX_STRANGERS = 5    # wrong visitors a relay host puts up with
    POLL_BUDGET   = 0.008 # seconds of frame work in one Session#poll (at least one frame)
    MAX_OUT       = 512  # frames waiting to be written before the line is closed
    WRITE_TIMEOUT = 10.0 # seconds a write may make no progress
    MAX_VALUES    = 4200 # values (numbers, strings, lists...) in one message from the partner:
                         # an 8 KB mod value is at most 4096 of them (0,0,0...), plus the message's own
    PARSE_MAX     = 20_000 # ... and in any other text Wire.parse is asked to read
    ARRAY_MAX     = 256  # a list field without its own limit
    HASH_MAX      = 128  # a table field without its own limit
    OBJ_ARRAY_MAX = 4096 # a list or table inside an [Object] field (mod data): whatever 8 KB can hold
    OBJ_HASH_MAX  = 2048
    MAX_CONNECTS  = 12   # connections one address (an IPv6 /64 counts as one) may open in 10 s
    RELAY_WAIT    = 120  # seconds a joiner waits for a relay to pair it (the relay answers at once when the host is there)
    MAX_ESCAPES   = 8_000 # backslashes in one message (each letter outside ASCII is one); a 64 KB string of them takes 50 ms to unescape
    BACKLOG       = 64   # events waiting for Net.update: nothing more is read from the line meanwhile
    ASK_LIMIT     = 3    # "Let <name> join?" prompts a minute; more visitors are told "wait"
    DECLINE_WAIT  = 600  # seconds an address that was told No is turned away
    # The parser's time goes with the number of values in a message (2-5 us each for numbers, long numbers,
    # floats, texts, escapes and table keys alike), not with its bytes: Net.cost counts them from the text.
    # An honest message has a few hundred (a co-op start about 150, 24 battle events 750); the biggest the
    # mod API allows, 8 KB of numbers, about 4100.
    FRAME_VALUES  = 4_500    # most a message may cost; more is a bad frame, unparsed
    VALUE_BURST   = 20_000   # most a line may send at once (the mod API's 16500 values at once)...
    VALUE_RATE    = 5_000    # ...then this many a second (about 2% of the game's thread); counted by when the
                             # frames arrived, so what piled up while the game was busy is not counted twice

    # Message types after the handshake: field => [class, max length] or
    # [Integer, min, max] or [Array, max items] or [Hash, max keys] or [Object]
    # (any value, but the key must be there). Later features (Soul Link,
    # trading) add theirs.
    TYPES = {
      "hello" => { "name" => [String, 24], "ver" => [String, 16] },
      "ping"  => {},
      "bye"   => {},
      "wave"  => {},
      "no"    => { "why" => [String, 16] },
      # Soul Link (F-BATTLE-05 SoulLink.rb): codes are checked again there
      "sl_hello" => { "link" => [String, 16], "seen" => [Integer, 0, 1_000_000_000],
                      "acked" => [Integer, 0, 1_000_000_000], "code" => [String, 1500] },
      "sl_link"  => { "code" => [String, 1500] },
      "sl_up"    => { "code" => [String, 16_000] },   # (60 events at most: under 10,000)
      "sl_party" => { "ids" => [String, 600] },   # id:species:level:hp:totalhp,...
    }
    # Largest signed frame (bytes of JSON) and most values (nodes) a message type may have; a
    # parse costs the game thread a few microseconds a node. The type is read from where every
    # sender writes it, first: a frame without it is dropped, one of a type this game doesn't
    # know is not read at all. A type with only text and number fields gets both limits from its
    # fields (frame_limits); one with a Hash or an Array field gets MAX_FRAME bytes and FREE_NODES
    # values unless it adds its own here (a full co-op frame has about 1,100 values, a mod's 8 KB
    # of numbers about 4,000); those frames still cost up to FREE_NODES values of parsing each.
    TYPE_MAX = {}
    TYPE_NODES = {}
    FRAME_SLACK = 256   # bytes (and 32 nodes) a newer version's extra field may need
    FREE_NODES = MAX_VALUES
    NO_WHY = { "code" => :code, "busy" => :busy, "wait" => :wait, "declined" => :declined }

    # What reading a message will cost the game thread, counted from its text before it is parsed:
    # one for each place a value starts ([ { , :), a quarter for each backslash escape (slow to unescape).
    def self.cost(text); text.count("[{,:") + 1 + text.count("\\") / 4; end
    # Text from the other game, safe to show in a PIF message or draw: no
    # backslash (message codes such as \wtnp[99999] or \v[1]), no "<" (a tag such
    # as <img=file> loads a file; one that is not a picture crashes the game) and
    # no ">" except in "->", no control characters (a new line stays) and no
    # text-direction characters.
    UNSAFE_TEXT = /[\\<\x00-\x09\x0b-\x1f\x7f\u0080-\u009f\u200e\u200f\u2028\u2029\u202a-\u202e\u2066-\u2069]|(?<!-)>/
    def self.safe_text(s, max = 200)
      return s.to_s.dup.force_encoding("UTF-8").scrub("").gsub("\r\n", "\n").gsub(UNSAFE_TEXT, "")[0, max]
    end

    # a name from the other game, safe to show in a PIF message (no \ codes)
    def self.shown_name(n); safe_text(n, 24).delete("\n>"); end

    # [bytes, nodes]: the most JSON bytes and values a signed frame of this known type may have. A type
    # with only text and number fields gets both from its fields (a character may be escaped as \uXXXX: 6
    # bytes, 12 for a pair); an [Object, bytes] field names its own size; one with a list or table gets
    # MAX_FRAME bytes and FREE_NODES values unless TYPE_MAX / TYPE_NODES say less.
    def self.frame_limits(type)
      spec = TYPES[type]
      plain = spec.values.all? { |cls,| cls == String || cls == Integer }
      big = spec.values.any? { |cls, a| cls == Array || cls == Hash || (cls == Object && a.nil?) }
      bytes = TYPE_MAX[type] || (big ? MAX_FRAME : FRAME_SLACK + spec.sum { |k, (cls, a)| k.length + 16 + (cls == String ? a * 12 : cls == Object ? a : 24) })
      return [[bytes, MAX_FRAME].min, TYPE_NODES[type] || (plain ? spec.size + 32 : FREE_NODES)]
    end

    # the other game's version text: letters, digits and . + _ - only (it goes
    # through _INTL, where a backslash in an argument is read as a command)
    def self.shown_ver(v); v.to_s.gsub(/[^0-9A-Za-z.+_ -]/, "")[0, 16]; end

    # who a limit is counted for: the address; an IPv6 /64 (one household has
    # billions of addresses) counts as one, and ::ffff:a.b.c.d as a.b.c.d
    def self.addr_key(ip)
      a = ip.to_s.sub(/%.*\z/, "")
      return a unless a.include?(":")
      b = Addrinfo.ip(a).to_sockaddr.byteslice(8, 16).bytes
      return b[12, 4].join(".") if b[0, 10].all?(0) && b[10] == 0xff && b[11] == 0xff
      return b[0, 8].map { |x| format("%02x", x) }.join + "::/64"
    rescue StandardError
      return ip.to_s
    end

    # an address for the log: most of it hidden (the log is sent in bug reports)
    def self.mask_addr(ip)
      a = ip.to_s
      return a.split(".")[0, 2].join(".") + ".x.x" if a =~ /\A\d+\.\d+\.\d+\.\d+\z/
      return a.split(":")[0, 2].join(":") + ":x" if a.include?(":")
      return "?"
    end

    # :loopback, :private, :linklocal, :unspecified, :multicast, :public or
    # :invalid, for an address written as an IP number
    def self.addr_kind(ip)
      a = Addrinfo.ip(ip.to_s.sub(/%.*\z/, ""))
      if a.ipv4?
        o = a.ip_address.split(".").map(&:to_i)
        return :unspecified if o[0] == 0
        return :loopback if o[0] == 127
        return :linklocal if o[0] == 169 && o[1] == 254
        return :multicast if o[0].between?(224, 239)
        return :invalid if o[0] >= 240
        return :private if o[0] == 10 || (o[0] == 172 && o[1].between?(16, 31)) || (o[0] == 192 && o[1] == 168) ||
                           (o[0] == 100 && o[1].between?(64, 127))
        return :public
      end
      b = a.to_sockaddr.byteslice(8, 16).bytes
      return :unspecified if b.all?(0)
      return :loopback if b[0, 15].all?(0) && b[15] == 1
      return addr_kind(b[12, 4].join(".")) if b[0, 10].all?(0) && b[10] == 0xff && b[11] == 0xff   # ::ffff:a.b.c.d
      return :multicast if b[0] == 0xff
      return :linklocal if b[0] == 0xfe && (b[1] & 0xc0) == 0x80
      return :private if (b[0] & 0xfe) == 0xfc
      return :public
    rescue StandardError
      return :invalid
    end

    # a computer on this network or this one (what a LAN answer may come from)
    def self.near?(ip); [:loopback, :private, :linklocal].include?(addr_kind(ip)); end

    def self.available?
      return @available unless @available.nil?
      @available = begin
        require "socket"
        require "digest/sha2" unless defined?(Digest::SHA256)
        (defined?(TCPServer) && defined?(Digest::SHA256) && Random.respond_to?(:urandom)) ? true : false
      rescue LoadError, StandardError
        false
      end
    end

    def self.log(msg)
      KIF.log("Multiplayer: #{msg}") if defined?(KIF.log)
    rescue StandardError
      nil
    end

    def self.now; Process.clock_gettime(Process::CLOCK_MONOTONIC); end

    # One thread looks at every open line twice a second (Conn#check_limits).
    @watched ||= []
    @watch_lock ||= Mutex.new

    def self.watch(conn)
      @watch_lock.synchronize do
        @watched << conn
        unless @watchdog && @watchdog.alive?
          @watchdog = Thread.new do
            loop do
              sleep 0.5
              list = @watch_lock.synchronize { @watched.reject!(&:closed?); @watched.dup }
              list.each { |c| (c.check_limits rescue nil) }
            end
          end
          @watchdog.report_on_exception = false
        end
      end
    end

    #---------------------------------------------------------------------------
    # HMAC-SHA256 on Digest::SHA256 (the engine has no OpenSSL)
    #---------------------------------------------------------------------------
    module Crypto
      module_function

      def random(n); Random.urandom(n); end
      def sha256(s); Digest::SHA256.digest(s.b); end

      # HMAC with the key's pads made once (a key stream asks for thousands)
      class Mac
        def initialize(key)
          key = Crypto.sha256(key) if key.bytesize > 64
          key = key.b.ljust(64, "\0".b)
          @ipad = key.bytes.map { |b| b ^ 0x36 }.pack("C*")
          @opad = key.bytes.map { |b| b ^ 0x5c }.pack("C*")
        end

        def digest(msg); Crypto.sha256(@opad + Crypto.sha256(@ipad + msg.b)); end
      end

      def hmac(key, msg); Mac.new(key).digest(msg); end

      # n bytes of key stream for frame number seq: HMAC(key, seq + block number)
      def stream(mac, seq, n)
        head = [seq].pack("Q>")
        return ((n + 31) / 32).times.map { |i| mac.digest(head + [i].pack("N")) }.join.byteslice(0, n)
      end

      def xor(a, b)
        return "".b if a.empty?
        x = a.unpack1("H*").to_i(16) ^ b.unpack1("H*").to_i(16)
        return [x.to_s(16).rjust(a.bytesize * 2, "0")].pack("H*")
      end

      def same?(a, b)
        return false unless a.is_a?(String) && b.is_a?(String) && a.bytesize == b.bytesize
        r = 0
        a.bytes.each_with_index { |x, i| r |= x ^ b.getbyte(i) }
        return r == 0
      end

      def hex(s); s.unpack1("H*"); end
      def unhex(s); (s.is_a?(String) && s =~ /\A(?:[0-9a-f]{2})+\z/) ? [s].pack("H*") : nil; end
    end

    #---------------------------------------------------------------------------
    # SPAKE2 (the shape of RFC 9382) in the 2048-bit MODP group of RFC 3526:
    # p is a safe prime, 2 generates the subgroup of order q = (p-1)/2.
    # The join code's secret is never sent, and a recorded handshake can't be
    # used to test guesses of it: that needs x or y, which never leave the
    # games. Someone who connects gets one guess per try (rate-limited).
    # M and N are squares of hashes (nobody knows their logarithms). Their
    # elements must be 1 < e < p-1, and K = (their / base^w)^(2x): the 2
    # keeps K out of the order-2 subgroup. Exponents are 256 bits; the
    # w-powers and their inverses are made once a session.
    #---------------------------------------------------------------------------
    module Spake2
      P = ("FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B139B22514A08798E3404DD" \
           "EF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7ED" \
           "EE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3DC2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F" \
           "83655D23DCA3AD961C62F356208552BB9ED529077096966D670C354E4ABC9804F1746C08CA18217C32905E462E36CE3B" \
           "E39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9DE2BCBF6955817183995497CEA956AE515D2261898FA0510" \
           "15728E5A8AACAA68FFFFFFFFFFFFFFFF").to_i(16)
      Q = (P - 1) / 2
      G = 2
      HEX = 512   # an element on the wire: 256 bytes as hex

      module_function

      def to_group(label)
        n = (0...9).map { |i| Crypto.sha256("KIF SPAKE2 #{label} #{i}") }.join.unpack1("H*").to_i(16)
        return (n % P).pow(2, P)
      end

      def m; @m ||= to_group("M"); end
      def n; @n ||= to_group("N"); end

      def w(secret); Crypto.sha256("KIF SPAKE2 w".b + secret.b).unpack1("H*").to_i(16) % Q; end

      # what one side needs for the session: [w, mine^w, (theirs^w)^-1]
      def setup(secret, joiner)
        w = w(secret)
        mine, theirs = joiner ? [m, n] : [n, m]
        return [w, mine.pow(w, P), inverse(theirs.pow(w, P))]
      end

      # [secret exponent, element to send]
      def start(mine_w)
        x = Crypto.random(32).unpack1("H*").to_i(16) | 1
        return [x, G.pow(x, P) * mine_w % P]
      end

      # K, or nil for an element that isn't allowed. K is 1 only for someone who
      # sent +-base^w with the right w (the code's secret): it is used like any
      # other K. Refusing it would tell a guesser "right" by the host's silence,
      # with no proof sent and so nothing counted against him.
      def finish(x, theirs, theirs_w_inv)
        return nil unless theirs.is_a?(Integer) && theirs > 1 && theirs < P - 1
        return (theirs * theirs_w_inv % P).pow(2 * x, P)
      end

      def inverse(a)
        t, nt, r, nr = 0, 1, P, a % P
        while nr != 0
          q = r / nr
          t, nt = nt, t - q * nt
          r, nr = nr, r - q * nr
        end
        return t % P
      end

      def hex(i); i.to_s(16).rjust(HEX, "0"); end
      def read(s); (s.is_a?(String) && s.length == HEX && s =~ /\A[0-9a-f]+\z/) ? s.to_i(16) : nil; end

      def key(nj, nh, x_el, y_el, k, w)
        Crypto.sha256("KIF SPAKE2 v1".b + nj + nh + [hex(x_el), hex(y_el), hex(k), hex(w)].map { |h| [h].pack("H*") }.join)
      end
    end

    #---------------------------------------------------------------------------
    # JSON out (ASCII only, every non-ASCII character escaped) and in
    #---------------------------------------------------------------------------
    module Wire
      module_function

      def json(v)
        case v
        when Hash   then "{" + v.map { |k, x| "#{str(k.to_s)}:#{json(x)}" }.join(",") + "}"
        when Array  then "[" + v.map { |x| json(x) }.join(",") + "]"
        when String then str(v)
        when nil    then "null"
        when true, false, Integer then v.to_s
        when Float  then v.finite? ? v.to_s : "null"
        else raise ArgumentError, "can't send #{v.class}"
        end
      end

      def str(s)
        s = s.dup.force_encoding("UTF-8").scrub("?")
        body = s.gsub(/[\\"\x00-\x1f\u007f-\u{10ffff}]/) do |c|
          o = c.ord
          if o > 0xffff
            o -= 0x10000
            format("\\u%04x\\u%04x", 0xd800 + (o >> 10), 0xdc00 + (o & 0x3ff))
          else
            format("\\u%04x", o)
          end
        end
        return '"' + body + '"'
      end

      def frame(payload); [payload.bytesize].pack("N") + payload.b; end

      # Hash or nil; never raises. A message from the partner is read with max = MAX_VALUES.
      def parse(text, max = PARSE_MAX)
        return nil if text.to_s.count("\\") > MAX_ESCAPES
        return Parser.new(text, max).run
      end
    end

    class Parser
      DEPTH = 16
      WS  = /\G[ \t\r\n]*/
      NUM = /\G-?(?:0|[1-9]\d{0,17})(?:\.\d{1,30})?(?:[eE][+-]?\d{1,3})?/   # Float#to_s writes up to 20 digits after the point
      STR = /\G"((?:[^"\\\x00-\x1f]|\\["\\\/bfnrt]|\\u[0-9a-fA-F]{4})*)"/
      ESC = { "b" => "\b", "f" => "\f", "n" => "\n", "r" => "\r", "t" => "\t" }

      def initialize(text, max = PARSE_MAX)
        @s = text.to_s.b
        @i = 0
        @n = 0
        @max = max
      end

      def values; @n; end

      def run
        return nil if @s =~ /[\x80-\xff]/n
        @s = @s.dup.force_encoding("US-ASCII")
        v = value(0)
        ws
        return (@i == @s.length && v.is_a?(Hash)) ? v : nil
      rescue StandardError, SystemStackError
        return nil
      end

      private

      def ws; @i = WS.match(@s, @i).end(0); end


      def value(depth)
        raise "deep" if depth > DEPTH
        raise "many" if (@n += 1) > @max   # the cost of a message is bounded, not only its size
        ws
        case @s[@i]
        when "{"
          @i += 1
          h = {}
          ws
          return (@i += 1; h) if @s[@i] == "}"
          loop do
            ws
            raise "many" if (@n += 1) > @max   # a key counts like a value
            m = STR.match(@s, @i) or raise "key"
            @i = m.end(0)

            k = unescape(m[1])
            ws
            raise "colon" unless @s[@i] == ":"
            @i += 1
            h[k] = value(depth + 1)
            ws
            c = @s[@i]
            @i += 1
            return h if c == "}"
            raise "object" unless c == ","
          end
        when "["
          @i += 1
          a = []
          ws
          return (@i += 1; a) if @s[@i] == "]"
          loop do
            a << value(depth + 1)
            ws
            c = @s[@i]
            @i += 1
            return a if c == "]"
            raise "array" unless c == ","
          end
        when '"'
          m = STR.match(@s, @i) or raise "string"
          @i = m.end(0)
          return unescape(m[1])
        else
          %w[true false null].each do |w|
            next unless @s[@i, w.length] == w
            @i += w.length
            return { "true" => true, "false" => false, "null" => nil }[w]
          end
          m = NUM.match(@s, @i) or raise "value"
          @i = m.end(0)
          return m[0].to_i unless m[0] =~ /[.eE]/
          f = m[0].to_f
          raise "float" unless f.finite?   # 1e999 is not a number we hand on
          return f
        end
      end

      def unescape(raw)
        out = raw.gsub(/\\u([dD][89abAB][0-9a-fA-F]{2})\\u([dD][c-fC-F][0-9a-fA-F]{2})|\\u([0-9a-fA-F]{4})|\\(.)/) do
          if $1
            [0x10000 + ((($1.hex) - 0xd800) << 10) + ($2.hex - 0xdc00)].pack("U")
          elsif $3
            o = $3.hex
            raise "surrogate" if o.between?(0xd800, 0xdfff)
            [o].pack("U")
          else
            ESC[$4] || $4
          end
        end
        return out.force_encoding("UTF-8")
      end
    end

    # Fields of a known type, checked; nil if anything doesn't fit
    def self.check_fields(type, h)
      spec = TYPES[type] or return nil
      out = { "t" => type }
      spec.each do |k, (cls, a, b)|
        v = h[k]
        next if v.nil? && a == :opt   # a field marked [cls, :opt] may be left out
        if cls == String
          return nil unless v.is_a?(String) && v.valid_encoding? && v.length <= a && v !~ /[\x00-\x1f\u007f]/
        elsif cls == Integer
          return nil unless v.is_a?(Integer) && v >= a && v <= b
        elsif cls == Array
          return nil unless v.is_a?(Array) && v.length <= (a.is_a?(Integer) ? a : ARRAY_MAX)
        elsif cls == Hash
          return nil unless v.is_a?(Hash) && v.length <= (a.is_a?(Integer) ? a : HASH_MAX)
        else   # Object: anything, but it has to be there, and a list or table in it stays small
          return nil unless h.key?(k)
          return nil if v.is_a?(Array) && v.length > OBJ_ARRAY_MAX
          return nil if v.is_a?(Hash) && v.length > OBJ_HASH_MAX
        end
        out[k] = v
      end
      return out
    end

    #---------------------------------------------------------------------------
    # Join codes: Crockford base32 + a 10-bit check, grouped by 4
    #   KIF-  IPv4(4) port(2) secret(4)    18 chars  KIF-XXXX-XXXX-XXXX-XXXX-XX
    #   KIF6- IPv6(16) port(2) secret(4)   38 chars
    #   KIFR- room(8) secret(16)           41 chars (relay address typed apart)
    #---------------------------------------------------------------------------
    module JoinCode
      ALPHA = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
      KINDS = { v4: ["KIF", 10], v6: ["KIF6", 22], relay: ["KIFR", 24] }
      CHECK_BITS = 10

      module_function

      def chars_for(nbytes); (nbytes * 8 + CHECK_BITS + 4) / 5; end

      def check(prefix, bytes)
        Crypto.sha256("KIF join #{prefix}".b + bytes).unpack1("B*")[0, CHECK_BITS]
      end

      def make(kind, ip: nil, port: nil, secret:, room: nil)
        prefix, = KINDS[kind]
        bytes = case kind
                when :v4    then ip.split(".").map(&:to_i).pack("C4") + [port].pack("n") + secret
                when :v6    then v6_bytes(ip) + [port].pack("n") + secret
                when :relay then room + secret
                end
        bits = bytes.unpack1("B*") + check(prefix, bytes)
        bits += "0" * (-bits.length % 5)
        chars = bits.scan(/.{5}/).map { |b| ALPHA[b.to_i(2)] }.join
        return prefix + "-" + chars.scan(/.{1,4}/).join("-")
      end

      # Hash (kind, ip, port, secret, room), :typo (looks like a code, a
      # character is wrong) or :invalid
      def read(text)
        t = text.to_s.scrub("").upcase.gsub(/[\s\-_.]/, "")
        KINDS.each do |kind, (prefix, nbytes)|
          body = t[prefix.length..-1]
          next unless t.start_with?(prefix) && body.length == chars_for(nbytes)
          body = body.tr("ILO", "110")
          return :typo unless body =~ /\A[#{ALPHA}]+\z/
          bits = body.chars.map { |c| format("%05b", ALPHA.index(c)) }.join
          data = [bits[0, nbytes * 8]].pack("B*")
          return :typo unless bits[nbytes * 8, CHECK_BITS] == check(prefix, data) &&
                              bits[(nbytes * 8 + CHECK_BITS)..-1] !~ /1/
          case kind
          when :v4    then return { kind: kind, ip: data.unpack("C4").join("."), port: data.unpack1("@4n"), secret: data.byteslice(6, 4) }
          when :v6    then return { kind: kind, ip: data.byteslice(0, 16).unpack("n8").map { |x| x.to_s(16) }.join(":"),
                                    port: data.unpack1("@16n"), secret: data.byteslice(18, 4) }
          when :relay then return { kind: kind, room: data.byteslice(0, 8), secret: data.byteslice(8, 16) }
          end
        end
        return t =~ /\AKIF[6R]?[0-9A-Z]{10,}\z/ ? :typo : :invalid
      end

      # 16 bytes of an IPv6 address (sockaddr_in6 holds them at byte 8)
      def v6_bytes(ip); Addrinfo.ip(ip).to_sockaddr.byteslice(8, 16); end
    end

    #---------------------------------------------------------------------------
    # What a line does with signed frames (TCP and Steam lines alike)
    #---------------------------------------------------------------------------
    module Sealed
      # from now on every message is signed and hidden (the writer thread does it)
      def keys(tx_mac, tx_enc, rx_mac, rx_enc)
        @rx_mac = Crypto::Mac.new(rx_mac)
        @rx_enc = Crypto::Mac.new(rx_enc)
        @enc = Crypto::Mac.new(tx_enc)
        @mac = Crypto::Mac.new(tx_mac)   # last: the writer looks at this one
      end

      # payload of a signed frame: MAC + number + hidden JSON
      def seal(json, seq)
        n = [seq].pack("Q>")
        ct = Crypto.xor(json.b, Crypto.stream(@enc, seq, json.bytesize))
        return @mac.digest(n + ct) + n + ct
      end

      # [number, hidden JSON] when the MAC is right, else nil
      def verify(payload)
        return nil if payload.bytesize < 41 || @rx_mac.nil?
        n = payload.byteslice(32, 8)
        ct = payload.byteslice(40, payload.bytesize - 40)
        return nil unless Crypto.same?(@rx_mac.digest(n + ct), payload.byteslice(0, 32))
        return [n.unpack1("Q>"), ct]
      end

      def reveal(ct, seq); Crypto.xor(ct, Crypto.stream(@rx_enc, seq, ct.bytesize)); end
    end

    #---------------------------------------------------------------------------
    # One TCP line: reader and writer threads, frames in, frames out
    #---------------------------------------------------------------------------
    class Conn
      include Sealed

      # what the reader lets through: a burst, then a steady rate (bytes a
      # second), and how much may sit unread (frames, bytes). Before the
      # handshake is through the room is small.
      PRE  = { burst: 8_192, refill: 2_048, frames: 16, bytes: 16_384 }
      OPEN = { burst: 1_572_864, refill: 196_608, frames: 16_384, bytes: 4_194_304 }

      attr_reader :inbox, :addr, :last_rx, :arrived
      attr_accessor :cap, :ping_every, :deadline

      def initialize(sock)
        @sock = sock
        @addr = (sock.remote_address.ip_address rescue "?")
        @inbox = Queue.new
        @arrivals = Queue.new   # when each frame in @inbox arrived (same order; events have none)
        @out = Queue.new
        @cap = MAX_PRE
        @ping_every = 5.0
        @mac = @enc = @rx_mac = @rx_enc = nil
        @seq = 0
        @last_rx = @last_tx = Net.now

        @closed = false
        @opened = false
        @deadline = nil      # the handshake has to be through by then (the reader sees to it)
        @write_since = nil   # a write began then and hasn't finished
        @got = 0             # bytes of frames queued (reader thread) and taken (game thread)
        @taken = 0
        @reader = Thread.new { read_loop }
        @writer = Thread.new { write_loop }
        [@reader, @writer].each { |t| t.report_on_exception = false }
        Net.watch(self)
      end

      def closed?; @closed; end

      # called about twice a second by Net.watch's thread: a handshake that took
      # too long, a write that makes no progress. Closing ends the reader.
      def check_limits
        return if @closed
        why = watch or return
        @inbox << [:error, why]
        hard_close
      end

      # the next queued frame (a String), or an event ([:error, why], [:closed]), or nil
      def next_frame
        f = (@inbox.pop(true) rescue nil)
        if f.is_a?(String)
          @taken += f.bytesize
          @arrived = (@arrivals.pop(true) rescue Net.now)
        end
        return f
      end

      # the handshake is through: bigger frames, a bigger room
      def open_up
        @cap = MAX_FRAME
        @deadline = nil
        @opened = true
      end

      def send_raw(hash); put([:raw, Wire.json(hash)]); end
      def send_msg(hash); put([:msg, hash]); end
      def send_bytes(bytes); put([:bytes, bytes]); end   # tests only
      def send_json(text); put([:json, text]); end       # tests only: this exact JSON text, sealed with the next number

      # closes once what's queued is written (at most 1 s later)
      def finish
        return if @closed
        @out << [:close]
        Thread.new { sleep 1.0; hard_close }.report_on_exception = false
      end

      # bye: sent before the line closes
      def close(bye = false)
        return if @closed
        return hard_close unless bye && @mac
        send_msg({ "t" => "bye" })
        finish
      end

      def hard_close
        @closed = true
        (@sock.close rescue nil)
      end

      private

      def put(item)
        return if @closed
        if @out.size >= MAX_OUT   # the other end isn't taking what we send
          @inbox << [:error, :stalled]
          return hard_close
        end
        @out << item
      end

      # why the line has to go
      def watch
        now = Net.now
        return :timeout if @deadline && now > @deadline
        return :stalled if @write_since && now - @write_since > WRITE_TIMEOUT
        return nil
      end

      def read_loop
        buf = "".b
        count = 0
        second = Net.now.floor
        lim = PRE
        tokens = lim[:burst].to_f
        at = Net.now
        loop do
          if @opened && lim.equal?(PRE)
            lim = OPEN
            tokens = lim[:burst].to_f
          end
          chunk = @sock.readpartial(16_384)
          @last_rx = Net.now
          buf << chunk
          while buf.bytesize >= 4
            n = buf.unpack1("N")
            if n == 0 || n > @cap
              @inbox << [:error, :oversized]
              return hard_close
            end
            break if buf.bytesize < 4 + n
            now = Net.now
            tokens = [tokens + (now - at) * lim[:refill], lim[:burst]].min
            at = now
            tokens -= 4 + n
            sec = now.floor
            count = 0 if sec != second
            second = sec
            count += 1
            if tokens < 0 || count > MAX_RATE || @inbox.size >= lim[:frames] || @got - @taken + n > lim[:bytes]
              @inbox << [:error, :flood]
              return hard_close
            end
            @arrivals << now
            @inbox << buf.byteslice(4, n)
            @got += n
            buf = buf.byteslice(4 + n, buf.bytesize - 4 - n)
          end
        end
      rescue EOFError, IOError, SystemCallError, StandardError
        @inbox << [:closed]
        @closed = true
      end

      def write_loop
        until @closed
          item = (@out.pop(true) rescue nil)
          if item.nil?
            if @mac && Net.now - @last_tx >= @ping_every
              item = [:msg, { "t" => "ping" }]
            else

              sleep 0.02
              next
            end
          end
          case item[0]
          when :close then return hard_close
          when :raw   then write(Wire.frame(item[1]))
          when :bytes then write(item[1])
          when :json
            @seq += 1
            write(Wire.frame(seal(item[1], @seq)))
          when :msg
            @seq += 1
            json = Wire.json({ "t" => item[1]["t"] }.merge(item[1]))
            write(Wire.frame(seal(json, @seq)))
          end
        end
      rescue StandardError
        hard_close
      end

      def write(bytes)
        @write_since = Net.now
        @sock.write(bytes)
        @write_since = nil
        @last_tx = Net.now
      end
    end

    #---------------------------------------------------------------------------
    # One Steam line (NetSteam.rb has the layer): the same frames as Conn, each
    # one Steam message (ISteamNetworkingMessages, reliable). The session's
    # Steam thread calls #push with what arrived and #flush to send, so pings
    # and timeouts work while the game thread is busy, as on TCP. Same limits
    # as Conn's reader, same signed and hidden frames.
    #---------------------------------------------------------------------------
    class SteamConn
      include Sealed

      attr_reader :inbox, :addr, :last_rx, :peer, :arrived
      attr_accessor :cap, :ping_every, :deadline

      def initialize(steam, peer)
        @steam = steam
        @peer = peer
        @addr = "steam:" + Crypto.hex(Crypto.sha256(peer.to_s))[0, 10]   # the wrong-code count's key; logs never show a Steam ID
        @inbox = Queue.new
        @arrivals = Queue.new
        @out = Queue.new
        @lock = Mutex.new
        @cap = MAX_PRE
        @ping_every = 5.0
        @mac = @enc = @rx_mac = @rx_enc = nil
        @seq = 0
        @last_rx = @last_tx = Net.now
        @closed = false
        @opened = false
        @lim = Conn::PRE
        @tokens = @lim[:burst].to_f
        @at = Net.now
        @second = @count = 0
        @got = @taken = 0
      end

      def closed?; @closed; end
      def send_raw(hash); put([:raw, Wire.json(hash)]); end
      def send_msg(hash); put([:msg, hash]); end
      def send_bytes(bytes); put([:bytes, bytes]); end   # tests only

      # the next queued frame (a String), or an event ([:error, why], [:closed]), or nil
      def next_frame
        f = (@inbox.pop(true) rescue nil)
        if f.is_a?(String)
          @taken += f.bytesize
          @arrived = (@arrivals.pop(true) rescue Net.now)
        end
        return f
      end

      # the handshake is through: bigger frames, a bigger room
      def open_up
        @cap = MAX_FRAME
        @deadline = nil
        @opened = true
      end

      # sends what's queued now, then closes
      def finish
        return if @closed
        flush
        @closed = true
      end

      def close(bye = false)
        return if @closed
        return hard_close unless bye && @mac
        send_msg({ "t" => "bye" })
        finish
      end

      def hard_close; @closed = true; end

      # a message from the peer: the same caps and budgets as Conn's reader
      def push(data)
        return if @closed
        now = @last_rx = Net.now
        n = data.bytesize
        return fail_with(:oversized) if n == 0 || n > @cap
        lim = @opened ? Conn::OPEN : Conn::PRE
        unless lim.equal?(@lim)
          @lim = lim
          @tokens = lim[:burst].to_f
        end
        @tokens = [@tokens + (now - @at) * lim[:refill], lim[:burst]].min
        @at = now
        @tokens -= 4 + n
        sec = now.floor
        @count = 0 if sec != @second
        @second = sec
        @count += 1
        return fail_with(:flood) if @tokens < 0 || @count > MAX_RATE || @inbox.size >= lim[:frames] || @got - @taken + n > lim[:bytes]
        @arrivals << now
        @inbox << data
        @got += n
      end

      # what's queued, and a ping after ping_every of quiet (one sender at a time: sequence numbers stay in order)
      def flush
        @lock.synchronize do
          return if @closed
          @out << [:msg, { "t" => "ping" }] if @out.empty? && @mac && Net.now - @last_tx >= @ping_every
          while (bytes = @held || next_bytes)
            @held = nil
            r = @steam.send_to(@peer, bytes)
            break @held = bytes if r == :full   # Steam's send buffer is full: the same bytes go next flush (TCP waits too)
            unless r
              @inbox << [:closed]
              return hard_close
            end
            @last_tx = Net.now
          end
        end
      end

      private

      def put(item)
        return if @closed
        if @out.size >= MAX_OUT   # the other end isn't taking what we send
          @inbox << [:error, :stalled]
          return hard_close
        end
        @out << item
      end

      def fail_with(why)
        @inbox << [:error, why]
        hard_close
      end

      # the next queued message's bytes (signed and hidden with the next number), or nil
      def next_bytes
        item = (@out.pop(true) rescue nil) or return nil
        return item[1] unless item[0] == :msg
        @seq += 1
        return seal(Wire.json({ "t" => item[1]["t"] }.merge(item[1])), @seq)
      end
    end

    #---------------------------------------------------------------------------
    # One line of a session and where its handshake stands. A joiner has one;
    # a host runs a few handshakes at once (@pending) and keeps the one whose
    # proof was right as the partner's line.
    #---------------------------------------------------------------------------
    class Line
      attr_accessor :conn, :hs, :started, :bad, :rx_seq, :ke, :nj, :nh, :my_nonce, :x, :xe, :hint, :gone, :key

      def initialize(conn)
        @conn = conn
        @started = Net.now
        @bad = 0
        @rx_seq = 0
        @gone = false
        @budget = VALUE_BURST   # what the messages may still cost to read
        @budget_at = @started
      end

      # false when the partner's messages cost more than the budget lets them. `at` is when
      # the frame arrived: the budget fills with the clock, not with polls, so what piled up
      # while the game was busy is only what the partner sent in that time.
      def pay(cost, at = Net.now)
        at = @budget_at if at < @budget_at
        @budget = [@budget + (at - @budget_at) * VALUE_RATE, VALUE_BURST].min - cost
        @budget_at = at
        return @budget >= 0
      end
    end

    #---------------------------------------------------------------------------
    # A session: hosting (one partner in v1), joining, or either through a
    # relay or Steam. Events from #poll:
    #   [:join_request, name]   (host) someone with the code: #accept or #decline
    #   [:connected, name]      handshake done, partner said hello
    #   [:message, type, hash]  a checked message
    #   [:disconnected, why]    :bye, :timeout, :closed, :error, :flood,
    #                           :oversized, :stalled
    #   [:failed, why]          joining failed: :unreachable, :code, :busy,
    #                           :wait, :timeout, :host_code, :closed, :relay,
    #                           :declined; :steam (no lobby made), :not_host
    #                           (the Steam friend only joined someone else's lobby)
    #   [:rejected, address]    (host) someone with a wrong code
    # States: :idle, :listening, :connecting, :handshake, :asking (host: the
    # player is asked), :waiting (joiner: for the answer), :connected, :closed
    # Over Steam (via :steam) the host makes a friends-only lobby. Its lobby
    # data holds only the tags friends see (version, mode...); the secret is
    # in the host's member data, which only lobby members can read, and the
    # same handshake still has to pass. Only lobby members get a line, a
    # joiner talks only to the lobby's owner (the friend picked), and
    # leaving the lobby ends it.
    #---------------------------------------------------------------------------
    class Session
      attr_reader :role, :partner, :partner_ver, :port, :via, :ports, :secret, :room, :relay, :lobby, :steam
      attr_accessor :ping_every, :timeout, :handshake_timeout, :answer_timeout, :hs_limit, :name, :ver
      attr_accessor :wave_at   # when the partner's last hello was shown (NetMenu)

      def initialize(name, ver)
        @name = name.to_s[0, 24]
        @ver = ver.to_s[0, 16]
        @state = :idle
        @events = Queue.new      # from threads
        @later = []              # made outside #poll (accept, decline)
        @ping_every = 5.0
        @timeout = 20.0
        @handshake_timeout = 10.0
        @answer_timeout = 60.0
        @hs_limit = HS_LIMIT
        @hs_log = []             # when a handshake failed (the last 10 s)
        @fails = {}              # address => [count, until]
        @seen = {}               # address => when it connected (the last 10 s)
        @seen_lock = Mutex.new
        @no_log = []             # when the player said no (the last 10 minutes)
        @prompts = []            # when the player was asked "Let <name> join?" (the last minute)
        @wrong_logged = 0
        @strangers = 0
        @line = nil              # the partner's line (a joiner's only line)
        @pending = []            # host: handshakes still running
        @servers = []
        @threads = []
        @acceptors = []
        @v6 = false
      end

      # a host with handshakes running and no partner reads as :handshake
      def state; (@state == :listening && !@pending.empty?) ? :handshake : @state; end

      def conn; l = @line || @pending.last; l && l.conn; end

      def connected?; @state == :connected; end
      def asking?; @state == :asking; end
      def hosting?; @role == :host && @state != :closed && @state != :idle; end

      # false when the thread that takes visitors is gone
      def accept_alive?; @acceptors.any?(&:alive?); end

      # host: let the asking player in
      def accept
        return false unless asking?
        @line.conn.send_msg({ "t" => "hello", "name" => @name, "ver" => @ver })
        @state = :connected
        @later << [:connected, @partner]
        renew_secrets if @via == :direct   # the code is used up: whoever saw it later needs a new one (the host screen shows it)
        return true
      end

      # host: say no (also after answer_timeout); hosting goes on. After a real No
      # the address (an IPv6 /64) is turned away for DECLINE_WAIT s and the code is
      # new, as after a join: whoever saw it later can't come back from another
      # address. Nothing of that after a timeout: nobody was there.
      def decline(timed_out = false)
        return false unless asking?
        Net.log("said no to #{@partner}")
        unless timed_out
          @fails[Net.addr_key(@line.conn.addr)] = [MAX_BAD, Net.now + DECLINE_WAIT] unless @via == :relay
          renew_secrets if @via == :direct
        end
        @no_log << Net.now
        @line.conn.send_msg({ "t" => "no", "why" => "declined" })
        drop_line(true)
        @partner = nil
        @state = :closed if @via == :relay   # the relay room is used up
        return true
      end

      # Listen on port (or the next free of PORT_TRIES); the port, or nil
      def host(secret, port: PORT, tries: PORT_TRIES, bind: "0.0.0.0", ipv6: true)
        @role = :host
        @secret = secret
        @via = :direct
        # all taken, or reserved: Windows with Hyper-V/WSL2/Docker keeps blocks of
        # 49152-65535 for itself (seen: 52344-52443). Then the same ports 10000
        # lower (outside that range, so a port opened by hand stays right), then
        # one Windows picks: the join code and the router mapping carry it.
        cands = (0...tries).map { |i| port + i }
        cands += cands.map { |x| x - 10_000 } if port > 11_024
        (cands << 0).each do |pt|
          begin
            @servers = [TCPServer.new(bind, pt)]
            @port = @servers[0].addr[1]
            break
          rescue SystemCallError
            next
          end
        end
        return nil unless @port
        begin
          if ipv6 && bind == "0.0.0.0"
            @servers << TCPServer.new("::", @port)
            @v6 = true
          end
        rescue SystemCallError, SocketError
          nil
        end
        @servers.each { |srv| listen_on(srv) }
        @state = :listening
        return @port
      end

      # The IPv6 door stays shut until the player asks for an IPv6 code
      def open_ipv6
        return true if @v6
        return false unless @role == :host && @via == :direct && @port && hosting?
        return false if @v6_try && Net.now - @v6_try < 5   # asked for on every screen refresh
        @v6_try = Net.now
        srv = TCPServer.new("::", @port)
        @servers << srv
        @v6 = true
        listen_on(srv)
        return true
      rescue SystemCallError, SocketError
        return false
      end

      def join(host, port, secret)
        @role = :join
        @secret = secret
        @via = :direct
        connect_out(host, port)
      end

      # Through a relay: the host waits there for the joiner with the same room
      def host_relay(rhost, rport, secret, room)
        @role = :host
        @secret = secret
        @room = room
        @via = :relay
        @relay = [rhost, rport]
        @strangers = 0
        connect_out(rhost, rport)
      end

      def join_relay(rhost, rport, secret, room)
        @role = :join
        @secret = secret
        @room = room
        @via = :relay
        @relay = [rhost, rport]
        connect_out(rhost, rport)
      end

      # steam: the Steam layer (KIF::Net::Steam, or a test's stand-in); tags: lobby data
      def host_steam(steam, tags = {}, slots = 4)
        @role = :host
        @secret = Crypto.random(16)
        @tags = tags
        steam_start(steam)
        steam.create_lobby(slots)   # more slots than players: someone who stays in it can't keep a friend out (one partner, as on TCP)
      end

      # friend: the friend picked or who invited (nil: whoever owns the lobby)
      def join_steam(steam, lobby, friend = nil)
        @role = :join
        @lobby = lobby
        @friend = friend
        steam_start(steam)
        steam.join_lobby(lobby)
      end

      def post(type, fields = {})
        return false unless connected?
        msg = Net.check_fields(type, fields.merge("t" => type)) or return false
        @line.conn.send_msg(msg)
        return true
      end

      def close
        @line.conn.close(connected?) if @line
        @line = nil
        @pending.each { |l| l.conn.close(false) }
        @pending = []
        if @lobby && @steam
          @steam.leave_lobby(@lobby)
          Net.log("left the Steam lobby")
          @lobby = nil
        end

        @threads.each { |t| (t.kill rescue nil) }
        @threads.each { |t| (t.join(0.5) rescue nil) } if @via == :steam   # out of Steam's calls before Steam may shut down
        @threads = []
        @acceptors = []
        @servers.each { |s| (s.close rescue nil) }
        @servers = []
        while (ev = (@events.pop(true) rescue nil))   # taken but never looked at
          (ev[1].close rescue nil) if ev[0] == :sock
        end
        @state = :closed
      end

      # Never waits: takes what the threads left and moves the state on. Works
      # for about POLL_BUDGET and leaves the rest queued for the next call.
      def poll
        out = @later
        @later = []
        steam_events(out) if @via == :steam && @state != :closed
        while (ev = (@events.pop(true) rescue nil))
          case ev[0]
          when :sock then accepted(ev[1], out)
          when :steam_msg then steam_msg(ev[1], ev[2], out)
          when :connect_failed
            out << [:failed, :unreachable] if @state == :connecting
            @state = :closed if @state == :connecting
          end
        end
        stop_at = Net.now + POLL_BUDGET
        catch(:budget) do
          ([@line] + @pending).compact.each do |line|
            until line.gone || out.length >= BACKLOG
              f = line.conn.next_frame or break
              f.is_a?(Array) ? line_ended(line, f[1] || :closed, out) : frame(line, f, out)
              throw :budget if Net.now > stop_at
            end
          end
        end
        check_time(out)
        return out
      end

      # events Net.update had no time for: first in the next poll
      def defer(list); @later = list + @later; end

      private

      # takes visitors; a failed accept is not the end of it
      def listen_on(srv)
        t = Thread.new do
          loop do
            begin
              s = srv.accept
            rescue IOError
              break   # closed
            rescue SystemCallError, SocketError
              break if srv.closed?
              sleep 0.1   # a visitor that left before we looked, or out of descriptors
              next
            end
            if !room_for(s) || @events.size >= MAX_SOCKS   # too many from one address, or the game isn't looking
              (s.close rescue nil)
            else
              @events << [:sock, s]
            end
          end
        end
        t.report_on_exception = false
        @threads << t
        @acceptors << t
      end

      # a connect-and-drop loop can't fill the queue or wear the table out: an
      # address (an IPv6 /64) opens MAX_CONNECTS connections in 10 s (accept threads)
      def room_for(sock)
        key = Net.addr_key(sock.remote_address.ip_address) rescue "?"
        now = Net.now
        @seen_lock.synchronize do
          recent = (@seen[key] ||= [])
          recent.reject! { |t| now - t > 10 }
          return false if recent.length >= MAX_CONNECTS
          recent << now
          @seen.delete_if { |_, v| now - v.last > 10 } if @seen.length > 64
        end
        return true
      end

      def connect_out(host, port)
        @state = :connecting
        @threads.delete_if { |t| !t.alive? }
        t = Thread.new do
          s = TCPSocket.new(host, port, connect_timeout: 6)
          @events << [:sock, s]
        rescue StandardError
          @events << [:connect_failed]
        end
        t.report_on_exception = false
        @threads << t
      end

      def new_line(conn)
        conn.ping_every = @ping_every
        return Line.new(conn)
      end

      def refuse(sock, why)
        (sock.write(Wire.frame(Wire.json({ "t" => "no", "why" => why }))) rescue nil)
        (sock.close rescue nil)
      end

      def accepted(sock, out)
        if @role == :join || @via == :relay
          return (sock.close rescue nil) unless @state == :connecting
          @line = new_line(Conn.new(sock))
          @state = :handshake
          if @via == :relay
            @line.hs = :relay_wait
            @line.conn.send_raw({ "t" => "relay", "room" => Crypto.hex(@room), "role" => @role.to_s })
          else
            @line.conn.deadline = Net.now + @handshake_timeout
            send_hi(@line)
          end
          return
        end
        return (sock.close rescue nil) if @state == :closed
        key = Net.addr_key((sock.remote_address.ip_address rescue "?"))
        why = host_room(key)
        return refuse(sock, why) if why
        host_line(Conn.new(sock), key)
      end

      # host, a new visitor: why it is turned away ("wait") or nil, and room made
      # for it (the table is not full, the address has its share)
      def host_room(key)
        now = Net.now
        f = @fails[key]
        @hs_log.reject! { |t| now - t > 10 }
        # an address that guessed wrong too often, or too many failed handshakes
        # lately. (Whether the host is busy is only told to someone with the code.)
        @prompts.reject! { |t| now - t > 60 }
        return "wait" if (f && f[0] >= MAX_BAD && now < f[1]) || @hs_log.length >= @hs_limit || @prompts.length >= ASK_LIMIT
        @fails.delete(key) if f && now >= f[1]
        @fails.delete_if { |_, v| now >= v[1] } if @fails.length > 64
        # room for this one: an address with its share loses its oldest line; a full
        # table loses the oldest line of the address holding the most, so a few quiet
        # connections from other addresses can't push a real joiner out
        mine = @pending.select { |l| l.key == key }
        drop_pending(mine.first) if mine.length >= MAX_PER_ADDR
        if @pending.length >= MAX_PENDING
          held = @pending.group_by(&:key).transform_values(&:length)
          drop_pending(@pending.find { |l| held[l.key] == held.values.max })
        end
        return nil
      end

      def host_line(conn, key)
        line = new_line(conn)
        line.key = key
        line.hs = :wait_hi
        conn.deadline = Net.now + @handshake_timeout
        @pending << line
        return line
      end

      # [w, my base^w, inverse of their base^w], once per secret
      def pake; @pake ||= Spake2.setup(@secret, @role == :join); end

      # new join code: the old one was seen by whoever was told it, or shown
      def renew_secrets
        @secret = Crypto.random(4)
        @pake = nil
      end

      def send_hi(line)
        line.my_nonce = Crypto.random(16)
        line.x, line.xe = Spake2.start(pake[1])
        line.conn.send_raw({ "t" => "hi", "v" => PROTO, "n" => Crypto.hex(line.my_nonce), "x" => Spake2.hex(line.xe) })
        line.hs = :wait_hi
      end

      def proof(line, who); Crypto.hmac(line.ke, "KIF2 #{who}"); end

      def frame(line, payload, out)
        return signed(line, payload, out) if line.hs == :done
        h = Wire.parse(payload, MAX_VALUES)
        return (@via == :steam ? nil : bad_hs(line, out, :closed)) unless h   # Steam: a late signed message of an old line
        if h["t"] == "no" && line.hs != :relay_wait && (@role == :join || @via == :relay)
          return give_up(out, [:failed, NO_WHY[h["why"]] || :closed]) if @via == :steam   # Steam names the sender and has no line to close
          # not signed, so anyone on the path could have sent it: a hint for
          # when the line ends, and the handshake goes on
          line.hint = NO_WHY[h["why"]] || line.hint
          return
        end
        case line.hs
        when :relay_wait
          unless h["t"] == "relay_ok"
            busy = h["t"] == "relay_no" && %w[busy full].include?(h["why"])   # a limit, not a wrong address
            return give_up(out, [:failed, busy ? :relay_busy : :relay])
          end
          line.started = Net.now
          line.conn.deadline = Net.now + @handshake_timeout
          @role == :join ? send_hi(line) : (line.hs = :wait_hi)
        when :wait_hi
          n = Crypto.unhex(h["n"])
          return bad_hs(line, out, :closed) unless h["t"] == "hi" && h["v"] == PROTO && n && n.bytesize == 16
          theirs = Spake2.read(h[@role == :host ? "x" : "y"])
          if @role == :host
            line.nj = n
            line.nh = Crypto.random(16)
            y, ye = Spake2.start(pake[1])
            k = Spake2.finish(y, theirs, pake[2]) or return bad_hs(line, out, :closed)
            line.ke = Spake2.key(line.nj, line.nh, theirs, ye, k, pake[0])
            line.conn.send_raw({ "t" => "hi", "v" => PROTO, "n" => Crypto.hex(line.nh), "y" => Spake2.hex(ye) })
          else
            line.nj = line.my_nonce
            line.nh = n
            k = Spake2.finish(line.x, theirs, pake[2]) or return give_up(out, [:failed, :host_code])
            line.ke = Spake2.key(line.nj, line.nh, line.xe, theirs, k, pake[0])
            line.x = nil
            line.conn.send_raw({ "t" => "auth", "p" => Crypto.hex(proof(line, "join")) })
          end
          line.hs = :wait_auth
        when :wait_auth
          p = Crypto.unhex(h["p"])
          return bad_hs(line, out, :closed) unless h["t"] == "auth"
          if @role == :host
            return wrong_code(line, out) unless Crypto.same?(p, proof(line, "join"))
            line.conn.send_raw({ "t" => "auth", "p" => Crypto.hex(proof(line, "host")) })
          else
            return give_up(out, [:failed, :host_code]) unless Crypto.same?(p, proof(line, "host"))
          end
          key = Crypto.hmac(line.ke, "KIF2 key".b + line.nj + line.nh)
          j2h = Crypto.hmac(key, "j2h")
          h2j = Crypto.hmac(key, "h2j")
          ej2h = Crypto.hmac(key, "j2h enc")
          eh2j = Crypto.hmac(key, "h2j enc")
          if @role == :host
            line.conn.keys(h2j, eh2j, j2h, ej2h)
          else
            line.conn.keys(j2h, ej2h, h2j, eh2j)
          end
          line.conn.open_up
          line.hs = :done
          line.started = Net.now
          if @role == :host
            admit(line) unless @via == :relay   # its hello waits for the player's answer
          else
            line.conn.send_msg({ "t" => "hello", "name" => @name, "ver" => @ver })
            @state = :waiting
          end
        end
      end

      # host: the proof was right. One partner at a time: a second one hears
      # "busy" (signed, so only someone with the code hears it).
      def admit(line)
        @pending.delete(line)
        if @line
          line.conn.send_msg({ "t" => "no", "why" => "busy" })
          line.gone = true
          line.conn.finish
        else
          @line = line
          @state = :handshake
        end
      end

      # host: a wrong proof
      def wrong_code(line, out)
        addr = line.conn.addr
        count = 1
        unless @via == :relay
          f = (@fails[line.key] ||= [0, 0])
          f[0] += 1
          f[1] = Net.now + 600
          count = f[0]
        end
        @hs_log << Net.now
        out << [:rejected, addr]
        if @wrong_logged < 5   # the log is sent in bug reports: no flood, no whole address
          @wrong_logged += 1
          Net.log("wrong code from #{Net.mask_addr(addr)} (#{count})")
        end
        line.conn.send_raw({ "t" => "no", "why" => "code" })
        return stranger_left(line, out, true) if @via == :relay
        drop_pending(line, true)
      end

      def signed(line, payload, out)
        return unless line.equal?(@line)
        seq, ct = line.conn.verify(payload)
        return bad_frame(line, out, "bad signature") unless seq
        return bad_frame(line, out, "old number") unless seq > line.rx_seq
        if seq != line.rx_seq + 1   # numbered 1, 2, 3... on an ordered line: a hole means one was cut out on the way
          Net.log("a message from the partner is missing")
          return line_ended(line, :error, out)
        end
        line.rx_seq = seq
        json = line.conn.reveal(ct, seq)
        # every sender writes "t" first: the type is read without parsing, and a frame that doesn't start
        # with one is bad. A message longer than its type allows is dropped unparsed.
        type = json[/\A\{"t":"(\w{1,24})"/, 1] or return bad_frame(line, out, "no type first")
        cost = Net.cost(json)
        unless TYPES.key?(type)   # a newer version's message: ignored, but not for free
          afford?(line, cost, out)
          return
        end
        # until the player has said yes only a short hello (once), no, bye or ping means anything: the rest is dropped unparsed
        unless @state == :connected || (json.bytesize <= 1024 &&
               (type == "hello" ? (@state == :handshake || @state == :waiting) : %w[ping bye no].include?(type)))
          return bad_frame(line, out, "#{type} before the player said yes")
        end
        bytes, nodes = Net.frame_limits(type)
        return bad_frame(line, out, "longer than a #{type} can be") if json.bytesize > bytes || cost > FRAME_VALUES
        return unless afford?(line, cost, out)   # a stream of heavy messages: 62 KB of values take the parser 100-200 ms; the line is cut, not just the frame
        h = Wire.parse(json, [nodes, MAX_VALUES].min)
        return bad_frame(line, out, "unreadable") unless h
        return bad_frame(line, out, "two types") unless h["t"] == type
        msg = Net.check_fields(type, h) or return bad_frame(line, out, "#{type} doesn't fit")
        case type
        when "ping" then nil
        when "bye"  then line_ended(line, :bye, out)
        when "hello"
          return unless @state == :handshake || @state == :waiting
          @partner = Net.shown_name(msg["name"])
          @partner_ver = Net.shown_ver(msg["ver"])
          if @role == :host
            @no_log.reject! { |t| Net.now - t > 600 }
            if @no_log.length >= MAX_ASKS   # told no again and again: no more questions
              Net.log("not asking again (#{MAX_ASKS} no's in 10 minutes)")
              line.conn.send_msg({ "t" => "no", "why" => "declined" })
              drop_line(true)
              @partner = nil
              @state = :closed if @via == :relay
              return
            end
            @state = :asking
            @asking_since = Net.now
            @prompts << Net.now
            out << [:join_request, @partner]
          else
            @state = :connected
            out << [:connected, @partner]
          end
        when "no"
          give_up(out, [:failed, NO_WHY[msg["why"]] || :closed]) if @role == :join && @state != :connected
        else
          out << [:message, type, msg] if @state == :connected
        end
      end

      # false (and the line closed as a flood) when the partner's messages cost more to read than the budget allows
      def afford?(line, cost, out)
        return true if line.pay(cost, line.conn.arrived)
        Net.log("the partner's messages cost too much to read")
        line_ended(line, :flood, out)
        return false
      end

      def bad_frame(line, out, why)
        line.bad += 1
        Net.log("dropped a message from the partner (#{why})")
        line_ended(line, :error, out) if line.bad >= MAX_BAD
      end

      # a handshake message that doesn't fit
      def bad_hs(line, out, why)
        @hs_log << Net.now
        return give_up(out, [:failed, why]) if @role == :join || line.hs == :relay_wait
        return stranger_left(line, out) if @via == :relay
        drop_pending(line)
      end

      def give_up(out, ev)
        out << ev
        drop_line
        @state = :closed
      end

      # relay host: someone got into the room who isn't the friend. The room
      # is used again (the relay made it new when it paired them), a few times.
      def stranger_left(line, out, gently = false)
        @strangers += 1
        drop_line(gently)
        if @strangers > MAX_STRANGERS
          out << [:failed, :code]
          @state = :closed
        else
          connect_out(*@relay)
        end
      end

      # the partner's line goes; a direct host goes on listening
      def drop_line(gently = false)
        if @line
          @line.gone = true
          gently ? @line.conn.finish : @line.conn.close(false)
        end
        @line = nil
        @state = :listening if @role == :host && @via != :relay
      end

      # A line that got the host's hi and went without a proof is a guess nobody
      # judged. It counts like a wrong proof; a silent connection costs nothing.
      def unproven(line)
        return unless line.hs == :wait_auth && line.key
        @hs_log << Net.now
        f = (@fails[line.key] ||= [0, 0])
        f[0] += 1
        f[1] = Net.now + 600
      end

      def drop_pending(line, gently = false)
        line.gone = true
        gently ? line.conn.finish : line.conn.close(false)
        @pending.delete(line)
      end

      def line_ended(line, why, out)
        return if line.gone
        unless line.equal?(@line)   # a handshake nobody finished: a scan, a stranger
          [:oversized, :flood].include?(why) ? (@hs_log << Net.now) : unproven(line)
          return drop_pending(line)
        end
        was = @state
        return stranger_left(line, out) if @role == :host && @via == :relay && [:wait_hi, :wait_auth].include?(line.hs)
        hint = line.hint
        drop_line
        if was == :connected
          out << [:disconnected, why]
          @partner = nil
        elsif @role == :join || @via == :relay
          out << [:failed, why == :bye ? :closed : (hint && [:closed, :timeout].include?(why) ? hint : why)]
        end
        @state = :closed if @role == :join || @via == :relay
      end

      def check_time(out)
        now = Net.now
        @pending.dup.each do |l|
          next unless now - l.started > @handshake_timeout
          unproven(l)
          drop_pending(l)
        end
        l = @line or return
        # a relay that takes the connection and never answers (a joiner waits for the room's other player at most RELAY_WAIT; a host may wait longer)
        return give_up(out, [:failed, :relay]) if @state == :handshake && l.hs == :relay_wait && @role == :join && now - l.started > RELAY_WAIT
        if @state == :handshake && l.hs != :relay_wait && now - l.started > @handshake_timeout
          return give_up(out, [:failed, l.hint || :timeout]) if @role == :join
          return stranger_left(l, out) if @via == :relay && l.hs != :done
          return @via == :relay ? give_up(out, [:failed, :timeout]) : drop_line
        end
        if @state == :asking && now - @asking_since > @answer_timeout
          decline(true)
          return out << [:failed, :declined] if @state == :closed
          return
        end
        return give_up(out, [:failed, :declined]) if @state == :waiting && now - l.started > @answer_timeout + @handshake_timeout
        line_ended(l, :timeout, out) if [:connected, :asking, :waiting].include?(@state) && now - l.conn.last_rx > @timeout
      end

      #-------------------------------------------------------------------------
      # Steam
      #-------------------------------------------------------------------------
      def steam_start(steam)
        @via = :steam
        @steam = steam
        @state = :connecting
        @steam_t0 = Net.now
        @asks = {}   # peer => when Steam asked for a line not let in yet
        steam.receive   # Steam keeps one stream per pair of players: what an old line left isn't this one's
        # moves bytes only, like Conn's threads: what arrives from the line's
        # peer goes to it, from anyone else to #poll
        t = Thread.new do
          loop do
            steam.receive.each do |data, peer|
              c = steam_conn(peer)
              c ? c.push(data) : @events << [:steam_msg, peer, data]
            end
            steam_conns.each(&:flush)
            sleep 0.02
          end
        rescue StandardError => e
          Net.log("the Steam line stopped (#{e.class})")
        end
        t.report_on_exception = false
        @threads << t
      end

      def steam_conns; ([@line] + @pending).compact.map(&:conn).grep(SteamConn); end
      def steam_conn(peer); steam_conns.find { |c| c.peer == peer && !c.closed? }; end
      def steam_line(peer); ([@line] + @pending).compact.find { |l| l.conn.is_a?(SteamConn) && l.conn.peer == peer }; end

      def steam_events(out)
        @steam.take(:lobby_created, :lobby_enter, :member, :session_request, :session_failed).each do |ev|
          case ev[0]
          when :lobby_created
            _, ok, lobby = ev
            unless @role == :host && @state == :connecting && !@lobby
              @steam.leave_lobby(lobby) if ok   # one this session didn't ask for (hosting started again quickly)
              next
            end
            unless ok
              Net.log("Steam didn't make a lobby")
              give_up(out, [:failed, :steam])
              next
            end
            @lobby = lobby
            @tags.each { |k, v| @steam.set_lobby_data(lobby, k.to_s, v.to_s) }
            @steam.set_member_data(lobby, "key", Crypto.hex(@secret))
            @state = :listening
            Net.log("Steam lobby made (friends only)")
          when :lobby_enter
            _, lobby, resp = ev
            next unless @role == :join && lobby == @lobby && @state == :connecting && !@entered
            if resp == 1
              @entered = true
              Net.log("entered the Steam lobby")
            else
              Net.log("couldn't enter the Steam lobby (#{resp})")
              give_up(out, [:failed, resp == 4 ? :busy : :unreachable])   # 4: full
            end
          when :member
            _, lobby, user, bits = ev
            line = lobby == @lobby && bits & 0x1e != 0 && steam_line(user) or next   # left, disconnected, kicked, banned
            Net.log("the Steam partner left the lobby")
            line_ended(line, :bye, out)   # leaving is their goodbye (it can come before the bye message)
          when :session_request
            peer = ev[1]
            next if @asks.key?(peer) || @asks.size >= 8 || steam_accept(peer)
            @asks[peer] = Net.now   # asked again below: Steam can tell the host of a joiner before its member list has them
            Net.log(@role == :host ? "a Steam player who isn't in the lobby asked for a line (let in if they join it within 5 s)"
                                   : "ignored a Steam player who isn't the host")
          when :session_failed
            line = steam_line(ev[1]) or next
            Net.log("the Steam line failed")
            line_ended(line, :closed, out)
          end
        end
        @asks.delete_if { |peer, t| steam_accept(peer) || Net.now - t > 5 } unless @asks.empty?
        steam_hello(out) if @entered && !@line && @state == :connecting
        if @state == :connecting && Net.now - @steam_t0 > @handshake_timeout
          give_up(out, [:failed, @role == :host ? :steam : (@entered ? :host_code : :unreachable)])
        end
      end

      # a Steam line only from a lobby member (host) or the lobby's owner (joiner)
      def steam_accept(peer)
        ok = @role == :host ? @lobby && peer != @steam.me && @steam.lobby_members(@lobby).include?(peer) : peer == @peer
        @steam.accept(peer) if ok
        return ok
      end

      # joiner in the lobby: the secret from the owner's member data (it can
      # come a moment after the lobby), then the same handshake as TCP. The
      # owner must be the friend picked or who invited: one who only joined
      # someone else's lobby would connect this game to that stranger.
      def steam_hello(out)
        owner = @steam.lobby_owner(@lobby)
        return if owner == 0 || owner == @steam.me
        if @friend && owner != @friend
          Net.log("the Steam friend isn't the lobby's host")
          return give_up(out, [:failed, :not_host])
        end
        key = Crypto.unhex(@steam.member_data(@lobby, owner, "key").to_s)
        return unless key && key.bytesize == 16
        @secret = key
        @peer = owner
        @line = new_line(SteamConn.new(@steam, owner))
        @state = :handshake
        @line.conn.deadline = Net.now + @handshake_timeout
        send_hi(@line)
      end

      # host: a message from a peer with no line yet (a joiner's first "hi")
      def steam_msg(peer, data, out)
        c = steam_conn(peer)
        return c.push(data) if c   # came before its line was made
        return unless @role == :host && @lobby && @state != :closed && @state != :connecting
        return unless peer != @steam.me && @steam.lobby_members(@lobby).include?(peer)
        h = Wire.parse(data) if data.bytesize <= MAX_PRE
        return unless h && h["t"] == "hi"   # a line starts with a hi; a late message of an old line isn't one
        conn = SteamConn.new(@steam, peer)
        why = host_room(conn.addr)
        return @steam.send_to(peer, Wire.json({ "t" => "no", "why" => why })) if why
        host_line(conn, conn.addr)
        conn.push(data)
      end
    end

    #---------------------------------------------------------------------------
    # "Find on this network": UDP broadcast on LAN_PORT. An answer says the
    # game's name and port; the join code's secret is never in it (the joiner
    # types the code), and the address is the one the answer came from. The
    # question is 64 bytes, the longest answer is no longer, so a spoofed
    # asker gets nothing bigger than it sent.
    #---------------------------------------------------------------------------
    module LAN
      ASK = ("KIF-FIND 2 " + "-" * 53).freeze
      MAX_FIND = 8

      module_function

      # Host: answers askers on this network with its name and the port of
      # `code` (the rest of the code, the secret, stays home). One answer a
      # second to each asker, ten a second in all.
      def responder(name, code, port: LAN_PORT)
        info = JoinCode.read(code)
        return nil unless info.is_a?(Hash) && info[:kind] != :relay
        nm = name.to_s[0, 24]
        reply = Wire.json({ "t" => "kif_host", "name" => nm, "port" => info[:port] })
        while reply.bytesize > ASK.bytesize && !nm.empty?
          nm = nm[0, nm.length - 1]
          reply = Wire.json({ "t" => "kif_host", "name" => nm, "port" => info[:port] })
        end
        u = UDPSocket.new
        u.bind("0.0.0.0", port)
        t = Thread.new do
          seen = {}
          recent = []
          loop do
            begin
              data, from = u.recvfrom(256)
            rescue IOError
              break   # closed
            rescue SystemCallError, SocketError
              break if u.closed?
              sleep 0.05   # an answer that bounced (Windows reports it here)
              next
            end
            next unless data == ASK && from && Net.near?(from[3])
            now = Net.now
            next if seen[from[3]] && now - seen[from[3]] < 1.0
            recent.reject! { |x| now - x > 1.0 }
            next if recent.length >= 10
            seen.delete_if { |_, x| now - x > 1.0 } if seen.length > 64
            seen[from[3]] = now
            recent << now
            (u.send(reply, 0, from[3], from[1]) rescue nil)
          end
        end
        t.report_on_exception = false
        return u
      rescue StandardError
        (u.close rescue nil)
        return nil
      end

      # Joiner: a Thread whose value is [[name, {kind:, ip:, port:, secret: nil}], ...]:
      # at most MAX_FIND games, each once, at the address its answer came from
      def find(to: "255.255.255.255", port: LAN_PORT, wait: 1.5)
        t = Thread.new do
          found = {}
          u = nil
          begin
            u = UDPSocket.new
            u.setsockopt(Socket::SOL_SOCKET, Socket::SO_BROADCAST, true)
            u.send(ASK, 0, to, port)
            stop = Net.now + wait
            while found.length < MAX_FIND && (left = stop - Net.now) > 0
              next unless IO.select([u], nil, nil, left)
              data, from = (u.recvfrom(512) rescue nil)
              next unless data && from && from[1] == port && Net.near?(from[3])
              h = Parser.new(data).run
              next unless h && h["t"] == "kif_host" && h["name"].is_a?(String)
              gport = h["port"]
              if !gport.is_a?(Integer) && h["code"].is_a?(String)   # an answer with a code: only its port is used
                info = JoinCode.read(h["code"])
                gport = info[:port] if info.is_a?(Hash) && info[:kind] != :relay
              end
              next unless gport.is_a?(Integer) && gport.between?(1, 65_535)
              ip = from[3].sub(/%.*\z/, "")
              name = Net.shown_name(h["name"])
              name = ip if name.empty?
              found[[ip, gport]] ||= [name, { kind: ip.include?(":") ? :v6 : :v4, ip: ip, port: gport, secret: nil }]
            end
          rescue StandardError
            nil   # no network (ENETUNREACH, no adapter, a refused socket...): what was found so far (the menu says "no games found")
          ensure
            (u.close rescue nil)
          end
          found.values
        end
        t.report_on_exception = false
        return t
      end
    end
  end
end
