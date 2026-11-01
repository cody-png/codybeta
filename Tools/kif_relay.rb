# KIF relay: passes messages between two KIF games that can't reach each
# other directly (for example when both internet providers share one address).
#
#   ruby kif_relay.rb [port]        default port 52413 (open it on this PC's router)
#
# Needs only a normal Ruby (2.7 or newer). Players type this PC's address in
# Multiplayer > Use a relay. Each game sends one short line saying which room
# it's in and whether it hosts or joins; when both sides of a room are there,
# the relay passes bytes along and nothing else. It never gets the game's
# secret, so it can't read the join code's key, forge or change messages (the
# games sign and hide them); it can see who talks to whom, how much and when,
# and it can cut the line.
#
# Limits, so one visitor can't take the relay from everyone: 400 sockets in
# all, 20 from one address (an IPv6 /64 counts as one), 3 waiting rooms from
# one address, a room waits 5 minutes for its second player, a pair is cut
# after 5 minutes without a byte and passes about 256 KB a second each way.
require "socket"
require "ipaddr"

class KIFRelay
  HELLO_MAX  = 256          # bytes in the first frame
  HELLO_WAIT = 10           # seconds to send it
  WAIT_MAX   = 5 * 60       # seconds a room waits for its second player
  MAX_ROOMS  = 200
  MAX_CONNS  = 400          # sockets in all: saying hello, waiting or paired
  PER_ADDR   = 20           # ... from one address
  ROOMS_PER_ADDR = 3        # waiting rooms from one address
  IDLE_MAX   = 5 * 60       # seconds without a byte before a pair is cut
  RATE       = 256 * 1024   # bytes a second each way, after the burst
  BURST      = 2 * 1024 * 1024
  HELLO = /\A\{"t":"relay","room":"([0-9a-f]{16})","role":"(host|join)"\}\z/

  attr_reader :port

  def initialize(port = 52413, bind = "0.0.0.0", log: $stdout)
    @port = port
    @bind = bind
    @log = log
    @rooms = {}   # room => { "host" => [sock, time, address], "join" => [sock, time, address] }
    @live = {}    # every open socket => its address
    @pairs = []   # [socket, socket, [time of the last byte]] of every pair passing bytes
    @lock = Mutex.new
  end

  def start
    @server = TCPServer.new(@bind, @port)
    @port = @server.addr[1]
    @thread = Thread.new do
      loop do
        begin
          c = @server.accept
        rescue IOError
          break   # closed
        rescue SystemCallError
          break if @server.closed?
          sleep 0.1   # out of descriptors, or a visitor that left before we looked
          next
        end
        take(c)
      end
    end
    @sweeper = Thread.new do   # rooms nobody waits in any more, pairs gone quiet
      loop do
        sleep 10
        @lock.synchronize do
          now = Time.now
          sweep(now)
          @pairs.delete_if do |a, b, act|
            quiet = now - act[0] > IDLE_MAX
            [a, b].each { |s| (s.close rescue nil) } if quiet
            quiet || (a.closed? && b.closed?)
          end
        end
      end
    end
    say("relay listening on port #{@port}")
    return self
  end

  def stop
    (@server.close rescue nil)
    @sweeper&.kill
    @lock.synchronize do
      @rooms.each_value { |r| r.each_value { |s, _| (s.close rescue nil) } }
      @rooms.clear
      @live.each_key { |s| (s.close rescue nil) }
      @live.clear
    end
  end

  def run
    start
    @thread.join
  end

  private

  def say(text); @log&.puts("#{Time.now.strftime('%H:%M:%S')} #{text}"); end

  def frame(text); [text.bytesize].pack("N") + text; end

  # who a socket counts as: its address (an IPv6 /64 is one visitor)
  def key_of(sock)
    ip = sock.peeraddr[3].to_s
    a = IPAddr.new(ip.sub(/%.*\z/, ""))
    return a.ipv6? && !a.ipv4_mapped? ? a.mask(64).to_s : ip
  rescue StandardError
    return "?"
  end

  # a new socket: within the limits it gets a thread, else it is turned away
  def take(c)
    key = key_of(c)
    ok = @lock.synchronize do
      @live.delete_if { |s, _| s.closed? }
      if @live.length >= MAX_CONNS || @live.count { |_, k| k == key } >= PER_ADDR
        false
      else
        @live[c] = key
        true
      end
    end
    return refuse(c, "full") unless ok
    (c.setsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, true) rescue nil)   # a vanished peer is noticed
    Thread.new(c) { |s| handle(s) }.report_on_exception = false
  end

  def read_exact(sock, n, stop)
    buf = "".b
    while buf.bytesize < n
      left = stop - Time.now
      return nil if left <= 0 || !IO.select([sock], nil, nil, left)
      buf << sock.readpartial(n - buf.bytesize)
    end
    buf
  end

  # rooms whose waiting player left or waited too long go
  def sweep(now)
    @rooms.delete_if do |_, r|
      dead = r.values.any? { |s, t, _| now - t > WAIT_MAX || ((IO.select([s], nil, nil, 0) rescue true) ? true : false) }
      r.each_value { |s, _| (s.close rescue nil) } if dead
      dead
    end
  end

  def handle(sock)
    other = nil
    stop = Time.now + HELLO_WAIT
    len = read_exact(sock, 4, stop)&.unpack1("N")
    text = len && len <= HELLO_MAX ? read_exact(sock, len, stop) : nil
    m = text && text.b.match(HELLO)   # bytes, not text: anything that isn't a hello is just refused
    return refuse(sock, "bad") unless m
    room, role = m[1], m[2]
    key = @lock.synchronize { @live[sock] } || "?"
    why = @lock.synchronize do
      now = Time.now
      sweep(now)
      r = @rooms[room]
      if r && r[role] then "taken"
      elsif !r && @rooms.length >= MAX_ROOMS then "full"
      elsif !r && @rooms.count { |_, x| x.values.any? { |e| e[2] == key } } >= ROOMS_PER_ADDR then "full"
      else
        r ||= (@rooms[room] = {})
        r[role] = [sock, now, key]
        other = r[role == "host" ? "join" : "host"]
        @rooms.delete(room) if other
        nil
      end
    end
    return refuse(sock, why) if why
    return say("room #{room[0, 4]}...: #{role} waiting") unless other
    say("room #{room[0, 4]}...: paired")
    a, b = sock, other[0]
    [a, b].each { |s| s.write(frame('{"t":"relay_ok"}')) }
    act = [Time.now]
    @lock.synchronize { @pairs << [a, b, act] }
    t = Thread.new { pump(b, a, act) }
    pump(a, b, act)
    t.join
  rescue StandardError
    (sock.close rescue nil)
    (other[0].close rescue nil) if other   # paired but couldn't tell them: neither waits for nothing
  end

  def refuse(sock, why)
    (sock.write(frame(%({"t":"relay_no","why":"#{why}"}))) rescue nil)
    (sock.close rescue nil)
  end

  # bytes one way; slowed to RATE after a burst. (A blocking read, so closing
  # the socket from another thread ends it; the sweeper cuts a quiet pair.)
  def pump(from, to, act)
    tokens = BURST.to_f
    at = Time.now
    loop do
      data = from.readpartial(16_384)
      now = Time.now
      act[0] = now
      tokens = [tokens + (now - at) * RATE, BURST].min - data.bytesize
      at = now
      if tokens < 0
        sleep(-tokens / RATE)
        tokens = 0.0
        at = Time.now
      end
      to.write(data)
    end
  rescue IOError, SystemCallError
    nil
  ensure
    (from.close rescue nil)
    (to.close rescue nil)
  end
end

KIFRelay.new((ARGV[0] || 52413).to_i).run if $PROGRAM_NAME == __FILE__
