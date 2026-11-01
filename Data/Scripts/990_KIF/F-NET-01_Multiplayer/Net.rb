#===============================================================================
# F-NET-01 – Multiplayer, phase 1: the connection between two games
# (new in KIF 1.3, 2026-10-23; design: Claude Docs/Base KIF/MULTIPLAYER_PLAN.md)
#
# Peer to peer, no server: one game hosts (TCP 52411, or the next free of
# 52412-52415), the other joins with a join code. Optional community relay
# (Tools/kif_relay.rb) for players who can't host; none is built in.
#
# Wire: every frame is a 4-byte big-endian length + payload.
#   Handshake (plain JSON, max 1 KB a frame), SPAKE2 (module Spake2 below):
#     joiner -> host  {"t":"hi","v":2,"n":nJ,"x":X}    nJ, nH: 16 random bytes
#     host -> joiner  {"t":"hi","v":2,"n":nH,"y":Y}    X = g^x M^w, Y = g^y N^w
#     joiner -> host  {"t":"auth","p":HMAC(Ke, "KIF2 join")}   Ke = SHA-256(nJ, nH,
#     host -> joiner  {"t":"auth","p":HMAC(Ke, "KIF2 host")}   X, Y, K = g^2xy, w)
#     The joiner proves first. A wrong proof: {"t":"no","why":"code"} and the
#     line closes; 5 wrong proofs from one address and it's ignored for 10
#     minutes; at most 10 handshakes start in 10 seconds.
#   Then the joiner says hello and the host's player is asked "Let <name>
#   join?". The host answers with its own hello, or a signed
#   {"t":"no","why":"declined"} (also after 60 s without an answer).
#   After the proofs (max 64 KB a frame): payload = 32-byte MAC + JSON object
#     {"t":type,"s":seq,...}; MAC = HMAC-SHA256(direction key, JSON); keys
#     come from Ke and both nonces. A frame with a wrong MAC, an old
#     sequence number (replay) or fields that don't fit its type is dropped;
#     a type this version doesn't know is ignored. 5 bad frames close the line.
#   The first signed message each way is "hello" (name, KIF version).
#   "ping" every 5 s of quiet; 20 s without a byte = lost. "bye" = clean close.
#
# Peer data is never Marshal-loaded or eval'd: only JSON text (ASCII, nesting
# limited) read by the small parser below into Hash/Array/String/Integer/
# Float/true/false/nil, then checked against TYPES.
#
# Threads: an accept thread (host), a connect thread (join), and a reader
# and a writer thread per connection. They only move bytes; everything else
# runs on the game's thread in Session#poll, which never waits.
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
    PROTO      = 3
    MAX_QUEUED = 8_000_000   # bytes of frames waiting for the game thread; more and the line closes
    STALL_BYTES = 524_288    # ... or this many while the game thread has not polled for STALL_SECS (a screen that doesn't poll)
    STALL_SECS  = 2.0
    POLL_TIME  = 0.01    # game-thread time for one poll, and again for what Net.update does with its messages; the rest waits for the next frame (the first always runs)
    MAX_VALUES = 4_200   # values (numbers, strings, lists, objects, keys) in one message; real ones hold under 1,500, a mod's 8 KB at most 4,100; 4,200 take about 35 ms to read
    MAX_ESCAPES = 8_000  # backslashes in one message (each letter outside ASCII is one); a 64 KB string of them takes 50 ms to unescape
    BACKLOG    = 64      # events waiting for Net.update: nothing more is read from the line meanwhile
    HS_LIMIT   = 10      # handshakes a host starts in 10 s

    # Message types after the handshake: field => [class, max length] or
    # [Integer, min, max]. Later features (Soul Link, trading) add theirs.
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
    NO_WHY = { "code" => :code, "busy" => :busy, "wait" => :wait, "declined" => :declined }

    # a name from the other game, safe to show in a PIF message (no \ codes)
    def self.shown_name(n); n.to_s.gsub(/[\\<>\x00-\x1f]/, "")[0, 24]; end

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

    #---------------------------------------------------------------------------
    # HMAC-SHA256 on Digest::SHA256 (the engine has no OpenSSL)
    #---------------------------------------------------------------------------
    module Crypto
      module_function

      def random(n); Random.urandom(n); end
      def sha256(s); Digest::SHA256.digest(s.b); end

      def hmac(key, msg)
        key = sha256(key) if key.bytesize > 64
        key = key.b.ljust(64, "\0".b)
        ipad = key.bytes.map { |b| b ^ 0x36 }.pack("C*")
        opad = key.bytes.map { |b| b ^ 0x5c }.pack("C*")
        return sha256(opad + sha256(ipad + msg.b))
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

      # K, or nil for an element that isn't allowed
      def finish(x, theirs, theirs_w_inv)
        return nil unless theirs.is_a?(Integer) && theirs > 1 && theirs < P - 1
        k = (theirs * theirs_w_inv % P).pow(2 * x, P)
        return k > 1 ? k : nil
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

      # Hash or nil; never raises. More than `limit` values (nil: any number): nil, reading them is what costs time
      def parse(text, limit = nil)
        return nil if limit && text.to_s.count("\\") > MAX_ESCAPES
        return Parser.new(text, limit).run
      end
    end

    class Parser
      DEPTH = 16
      WS  = /\G[ \t\r\n]*/
      NUM = /\G-?(?:0|[1-9]\d{0,17})(?:\.\d{1,17})?(?:[eE][+-]?\d{1,3})?/
      STR = /\G"((?:[^"\\\x00-\x1f]|\\["\\\/bfnrt]|\\u[0-9a-fA-F]{4})*)"/
      ESC = { "b" => "\b", "f" => "\f", "n" => "\n", "r" => "\r", "t" => "\t" }

      def initialize(text, limit = nil)
        @s = text.to_s.b
        @i = 0
        @n = 0
        @limit = limit   # nil: no cap on the values
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

      def count
        @n += 1
        raise "many" if @limit && @n > @limit
      end

      def value(depth)
        raise "deep" if depth > DEPTH
        count
        ws
        case @s[@i]
        when "{"
          @i += 1
          h = {}
          ws
          return (@i += 1; h) if @s[@i] == "}"
          loop do
            ws
            m = STR.match(@s, @i) or raise "key"
            @i = m.end(0)
            count   # (a key costs as much to read as a value)
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
          return m[0] =~ /[.eE]/ ? m[0].to_f : m[0].to_i
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
        else
          return nil unless v.is_a?(cls)
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
        t = text.to_s.upcase.gsub(/[\s\-_.]/, "")
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
    # One TCP line: reader and writer threads, frames in, frames out
    #---------------------------------------------------------------------------
    class Conn
      attr_reader :inbox, :addr, :last_rx
      attr_accessor :cap, :ping_every

      def initialize(sock)
        @sock = sock
        @addr = (sock.remote_address.ip_address rescue "?")
        @inbox = Queue.new
        @got = @took = 0   # bytes queued by the reader thread / taken out by the game thread (each written by one only)
        @poll_at = Net.now
        @out = Queue.new
        @cap = MAX_PRE
        @ping_every = 5.0
        @key = nil
        @seq = 0
        @last_rx = @last_tx = Net.now
        @closed = false
        @reader = Thread.new { read_loop }
        @writer = Thread.new { write_loop }
        [@reader, @writer].each { |t| t.report_on_exception = false }
      end

      def closed?; @closed; end
      def flooded?; @flooded ? true : false; end
      def polled; @poll_at = Net.now; end   # game thread, each poll
      def took(frame); @took += frame.bytesize if frame.is_a?(String); end   # game thread

      # from now on every message is signed with this key (writer thread signs)
      def sign_with(key); @key = key; end

      def send_raw(hash); @out << [:raw, Wire.json(hash)] unless @closed; end
      def send_msg(hash); @out << [:msg, hash] unless @closed; end
      def send_bytes(bytes); @out << [:bytes, bytes] unless @closed; end   # tests only

      # closes once what's queued is written (at most 1 s later)
      def finish
        return if @closed
        @out << [:close]
        Thread.new { sleep 1.0; hard_close }.report_on_exception = false
      end

      # bye: sent before the line closes
      def close(bye = false)
        return if @closed
        return hard_close unless bye && @key
        send_msg({ "t" => "bye" })
        finish
      end

      def hard_close
        @closed = true
        (@sock.close rescue nil)
      end

      private

      def read_loop
        buf = "".b
        count = 0
        second = Net.now.floor
        loop do
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
            @inbox << buf.byteslice(4, n)
            @got += n
            if @got - @took > MAX_QUEUED
              @flooded = true
              return hard_close
            end
            buf = buf.byteslice(4 + n, buf.bytesize - 4 - n)
            sec = Net.now.floor
            count = 0 if sec != second
            second = sec
            count += 1
            if count > MAX_RATE
              @inbox << [:error, :flood]
              return hard_close
            end
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
            if @key && Net.now - @last_tx >= @ping_every
              item = [:msg, { "t" => "ping" }]
            else
              if @got - @took > STALL_BYTES && Net.now - @poll_at > STALL_SECS   # a lot unread and nobody reading
                @flooded = true
                return hard_close
              end
              sleep 0.02
              next
            end
          end
          case item[0]
          when :close then return hard_close
          when :raw   then write(Wire.frame(item[1]))
          when :bytes then write(item[1])
          when :msg
            @seq += 1
            json = Wire.json(item[1].merge("s" => @seq))
            write(Wire.frame(Crypto.hmac(@key, json) + json))
          end
        end
      rescue StandardError
        hard_close
      end

      def write(bytes)
        @sock.write(bytes)
        @last_tx = Net.now
      end
    end

    #---------------------------------------------------------------------------
    # A session: hosting (one partner in v1), joining, or either through a
    # relay. Events from #poll:
    #   [:join_request, name]   (host) someone with the code: #accept or #decline
    #   [:connected, name]      handshake done, partner said hello
    #   [:message, type, hash]  a checked message
    #   [:disconnected, why]    :bye, :timeout, :closed, :error
    #   [:failed, why]          joining failed: :unreachable, :code, :busy,
    #                           :wait, :timeout, :host_code, :closed, :relay,
    #                           :declined
    #   [:rejected, address]    (host) someone with a wrong code
    # States: :idle, :listening, :connecting, :handshake, :asking (host: the
    # player is asked), :waiting (joiner: for the answer), :connected, :closed
    #---------------------------------------------------------------------------
    class Session
      attr_reader :state, :role, :partner, :partner_ver, :port, :via, :ports, :secret, :room, :conn, :relay
      attr_accessor :ping_every, :timeout, :handshake_timeout, :answer_timeout, :hs_limit, :name, :ver

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
        @hs_log = []
        @fails = {}              # address => [count, until]
        @servers = []
        @threads = []
      end

      def connected?; @state == :connected; end
      def asking?; @state == :asking; end
      def hosting?; @role == :host && @state != :closed && @state != :idle; end

      # host: let the asking player in
      def accept
        return false unless asking?
        @conn.send_msg({ "t" => "hello", "name" => @name, "ver" => @ver })
        @state = :connected
        @later << [:connected, @partner]
        return true
      end

      # host: say no (also after answer_timeout); hosting goes on
      def decline
        return false unless asking?
        Net.log("said no to #{@partner}")
        @conn.send_msg({ "t" => "no", "why" => "declined" })
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
          @servers << TCPServer.new("::", @port) if ipv6 && bind == "0.0.0.0"
        rescue SystemCallError, SocketError
          nil
        end
        @servers.each do |srv|
          t = Thread.new do
            loop { @events << [:sock, srv.accept] }
          rescue StandardError
            nil
          end
          t.report_on_exception = false
          @threads << t
        end
        @state = :listening
        return @port
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

      def post(type, fields = {})
        return false unless connected?
        msg = Net.check_fields(type, fields.merge("t" => type)) or return false
        @conn.send_msg(msg)
        return true
      end

      def close
        @conn.close(connected?) if @conn
        @servers.each { |s| (s.close rescue nil) }
        @servers = []
        @threads.each { |t| (t.kill rescue nil) }
        @threads = []
        @state = :closed
      end

      # Never waits: takes what the threads left and moves the state on
      def poll
        out = @later
        @later = []
        while (ev = (@events.pop(true) rescue nil))
          case ev[0]
          when :sock then accepted(ev[1], out)
          when :connect_failed
            out << [:failed, :unreachable] if @state == :connecting
            @state = :closed if @state == :connecting
          end
        end
        if @conn
          @conn.polled
          if @conn.flooded?   # more waiting than the game can read: what is queued is dropped with the line
            @conn.inbox.clear
            line_ended(:flood, out)
          end
          t0 = Net.now
          while @conn && out.length < BACKLOG && (f = (@conn.inbox.pop(true) rescue nil))
            @conn.took(f)
            f.is_a?(Array) ? line_ended(f[1] || :closed, out) : frame(f, out)
            break if Net.now - t0 > POLL_TIME   # the rest next frame: a flood of costly frames can't hold the game
          end
          check_time(out) if @conn
        end
        return out
      end

      # events Net.update had no time for: first in the next poll
      def defer(list); @later = list + @later; end

      private

      def connect_out(host, port)
        @state = :connecting
        t = Thread.new do
          s = TCPSocket.new(host, port, connect_timeout: 6)
          @events << [:sock, s]
        rescue StandardError
          @events << [:connect_failed]
        end
        t.report_on_exception = false
        @threads << t
      end

      def accepted(sock, out)
        if @role == :join || @via == :relay
          return (sock.close rescue nil) unless @state == :connecting
          start(sock)
          if @via == :relay
            @hs_state = :relay_wait
            @conn.send_raw({ "t" => "relay", "room" => Crypto.hex(@room), "role" => @role.to_s })
          else
            send_hi
          end
          return
        end
        addr = (sock.remote_address.ip_address rescue "?")
        f = @fails[addr]
        @hs_log.reject! { |t| Net.now - t > 10 }
        # the same address again while its handshake hasn't finished: a retry (its
        # first try gave up while this game wasn't polling, e.g. in a battle)
        again = @conn && @state == :handshake && @conn.addr == addr
        why = if (f && f[0] >= MAX_BAD && Net.now < f[1]) || @hs_log.length >= @hs_limit then "wait"
              elsif @conn && !again then "busy"
              end
        if why
          (sock.write(Wire.frame(Wire.json({ "t" => "no", "why" => why }))) rescue nil)
          return (sock.close rescue nil)
        end
        @fails.delete(addr) if f && Net.now >= f[1]
        @hs_log << Net.now
        drop_line if again
        start(sock)
        @hs_state = :wait_hi
      end

      def start(sock)
        @conn = Conn.new(sock)
        @conn.ping_every = @ping_every
        @hs_started = Net.now
        @state = :handshake
        @bad = 0
        @rx_seq = 0
      end

      # [w, my base^w, inverse of their base^w], once a session
      def pake; @pake ||= Spake2.setup(@secret, @role == :join); end

      def send_hi
        @my_nonce = Crypto.random(16)
        @x, @xe = Spake2.start(pake[1])
        @conn.send_raw({ "t" => "hi", "v" => PROTO, "n" => Crypto.hex(@my_nonce), "x" => Spake2.hex(@xe) })
        @hs_state = :wait_hi
      end

      def proof(who); Crypto.hmac(@ke, "KIF2 #{who}"); end

      def frame(payload, out)
        return signed(payload, out) if @hs_state == :done
        h = Wire.parse(payload)
        return bad_hs(out, :closed) unless h
        if h["t"] == "no" && (@role == :join || @via == :relay)
          return give_up(out, [:failed, NO_WHY[h["why"]] || :closed])
        end
        case @hs_state
        when :relay_wait
          return give_up(out, [:failed, :relay]) unless h["t"] == "relay_ok"
          @hs_started = Net.now
          @role == :join ? send_hi : (@hs_state = :wait_hi)
        when :wait_hi
          n = Crypto.unhex(h["n"])
          return bad_hs(out, :closed) unless h["t"] == "hi" && h["v"] == PROTO && n && n.bytesize == 16
          theirs = Spake2.read(h[@role == :host ? "x" : "y"])
          if @role == :host
            @nj = n
            @nh = Crypto.random(16)
            y, ye = Spake2.start(pake[1])
            k = Spake2.finish(y, theirs, pake[2]) or return bad_hs(out, :closed)
            @ke = Spake2.key(@nj, @nh, theirs, ye, k, pake[0])
            @conn.send_raw({ "t" => "hi", "v" => PROTO, "n" => Crypto.hex(@nh), "y" => Spake2.hex(ye) })
          else
            @nj = @my_nonce
            @nh = n
            k = Spake2.finish(@x, theirs, pake[2]) or return give_up(out, [:failed, :host_code])
            @ke = Spake2.key(@nj, @nh, @xe, theirs, k, pake[0])
            @x = nil
            @conn.send_raw({ "t" => "auth", "p" => Crypto.hex(proof("join")) })
          end
          @hs_state = :wait_auth
        when :wait_auth
          p = Crypto.unhex(h["p"])
          return bad_hs(out, :closed) unless h["t"] == "auth"
          if @role == :host
            unless Crypto.same?(p, proof("join"))
              f = (@fails[@conn.addr] ||= [0, 0])
              f[0] += 1
              f[1] = Net.now + 600
              out << [:rejected, @conn.addr]
              Net.log("wrong code from #{@conn.addr} (#{f[0]})")
              @conn.send_raw({ "t" => "no", "why" => "code" })
              drop_line(true)
              return if @via == :direct
              out << [:failed, :code]   # through a relay the room is used up
              return @state = :closed
            end
            @conn.send_raw({ "t" => "auth", "p" => Crypto.hex(proof("host")) })
          else
            return give_up(out, [:failed, :host_code]) unless Crypto.same?(p, proof("host"))
          end
          key = Crypto.hmac(@ke, "KIF2 key".b + @nj + @nh)
          @rx_key = Crypto.hmac(key, @role == :host ? "j2h" : "h2j")
          @conn.sign_with(Crypto.hmac(key, @role == :host ? "h2j" : "j2h"))
          @conn.cap = MAX_FRAME
          @hs_state = :done
          return if @role == :host   # its hello waits for the player's answer
          @conn.send_msg({ "t" => "hello", "name" => @name, "ver" => @ver })
          @state = :waiting
          @hs_started = Net.now
        end
      end

      def signed(payload, out)
        mac = payload.byteslice(0, 32)
        json = payload.byteslice(32, payload.bytesize - 32).to_s
        h = Crypto.same?(Crypto.hmac(@rx_key, json), mac) ? Wire.parse(json, MAX_VALUES) : nil
        return bad_frame(out, "bad signature") unless h
        seq = h["s"]
        return bad_frame(out, "old or missing number") unless seq.is_a?(Integer) && seq > @rx_seq
        @rx_seq = seq
        type = h["t"]
        return unless TYPES.key?(type)   # a newer version's message: ignored
        msg = Net.check_fields(type, h) or return bad_frame(out, "#{type} doesn't fit")
        case type
        when "ping" then nil
        when "bye"  then line_ended(:bye, out)
        when "hello"
          return unless @state == :handshake || @state == :waiting
          @partner = Net.shown_name(msg["name"])
          @partner_ver = msg["ver"]
          if @role == :host
            @state = :asking
            @asking_since = Net.now
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

      def bad_frame(out, why)
        @bad += 1
        Net.log("dropped a message from the partner (#{why})")
        line_ended(:error, out) if @bad >= MAX_BAD
      end

      def bad_hs(out, why)
        return give_up(out, [:failed, why]) if @role == :join || @via == :relay
        drop_line
      end

      def give_up(out, ev)
        out << ev
        drop_line
        @state = :closed
      end

      # host: the line goes, hosting goes on
      def drop_line(gently = false)
        (gently ? @conn.finish : @conn.close(false)) if @conn
        @conn = nil
        @hs_state = nil
        @state = :listening if @role == :host && @via == :direct
      end

      def line_ended(why, out)
        was = @state
        drop_line
        if was == :connected
          out << [:disconnected, why]
        elsif @role == :join || @via == :relay
          out << [:failed, why == :bye ? :closed : why]
        end
        @partner = nil if was == :connected
        @state = :closed if @role == :join || @via == :relay
      end

      def check_time(out)
        if @state == :handshake && @hs_state != :relay_wait && Net.now - @hs_started > @handshake_timeout
          return @role == :join || @via == :relay ? give_up(out, [:failed, :timeout]) : drop_line
        end
        if @state == :asking && Net.now - @asking_since > @answer_timeout
          decline
          return out << [:failed, :declined] if @state == :closed
          return
        end
        return give_up(out, [:failed, :declined]) if @state == :waiting && Net.now - @hs_started > @answer_timeout + @handshake_timeout
        line_ended(:timeout, out) if [:connected, :asking, :waiting].include?(@state) && Net.now - @conn.last_rx > @timeout
      end
    end

    #---------------------------------------------------------------------------
    # "Find on this network": UDP broadcast on LAN_PORT
    #---------------------------------------------------------------------------
    module LAN
      ASK = "KIF-FIND 1"

      module_function

      # Host: answers askers with its name and its code for this network.
      # The code holds the secret, so anyone on the same network can join
      # while a place is free (as with LAN games).
      def responder(name, code, port: LAN_PORT)
        u = UDPSocket.new
        u.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)
        u.bind("0.0.0.0", port)
        reply = Wire.json({ "t" => "kif_host", "name" => name.to_s[0, 24], "code" => code })
        t = Thread.new do
          loop do
            data, from = u.recvfrom(64)
            next unless data == ASK
            (u.send(reply, 0, from[3], from[1]) rescue nil)
          end
        rescue StandardError
          nil
        end
        t.report_on_exception = false
        return u
      rescue StandardError
        return nil
      end

      # Joiner: a Thread whose value is [[name, code_info], ...]
      def find(to: "255.255.255.255", port: LAN_PORT, wait: 1.5)
        t = Thread.new do
          found = {}
          u = UDPSocket.new
          begin
            u.setsockopt(Socket::SOL_SOCKET, Socket::SO_BROADCAST, true)
            u.send(ASK, 0, to, port)
            stop = Net.now + wait
            while (left = stop - Net.now) > 0
              next unless IO.select([u], nil, nil, left)
              data, = (u.recvfrom(512) rescue nil)
              h = Parser.new(data).run if data
              next unless h && h["t"] == "kif_host" && h["name"].is_a?(String) && h["code"].is_a?(String)
              info = JoinCode.read(h["code"])
              found[h["code"]] = [Net.shown_name(h["name"]), info] if info.is_a?(Hash) && info[:kind] != :relay
            end
          ensure
            u.close
          end
          found.values
        end
        t.report_on_exception = false
        return t
      end
    end
  end
end
