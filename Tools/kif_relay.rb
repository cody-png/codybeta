# KIF relay: passes messages between two KIF games that can't reach each
# other directly (for example when both internet providers share one address).
#
#   ruby kif_relay.rb [port] [bind]
#       port  default 52413
#       bind  default 0.0.0.0 (IPv4, every network card). Give one address to
#             listen on that card only (127.0.0.1 = this machine only). Give ::
#             to listen on IPv6 (Linux then takes IPv4 too, Windows does not).
#
# Needs only a normal Ruby (2.7 or newer). Players type this machine's address in
# Multiplayer > Use a relay. Each game sends one short line saying which room
# it's in and whether it hosts or joins; when both sides of a room are there,
# the relay passes bytes along and nothing else.
#
# What the relay can do: it never gets the game's secret, so it can't forge or
# change a message. It can see every message (they are signed, not encrypted),
# both players' addresses and the room id, and it can delay, drop or cut messages.
#
# SAFE DEPLOYMENT (read before you run this for other people)
#  * This is a public service with no login: anyone who can reach the port can
#    connect. Run it on a rented server or a spare machine (a Raspberry Pi works),
#    not on the PC you play on. Forward only TCP 52413 to it. Never use the
#    router's DMZ or "expose host".
#  * Run it as a normal user, never as root or Administrator. On Linux use a
#    systemd unit with DynamicUser=yes NoNewPrivileges=yes ProtectSystem=strict
#    ProtectHome=yes MemoryMax=256M TasksMax=512 LimitNOFILE=4096 Restart=on-failure.
#  * Tell your players that you can read what they send and see their addresses.
#  * It keeps nothing on disk and writes no addresses to its log. Limits per
#    address and in total are the constants below. Many players share one address
#    on mobile and shared home internet, so keep the per-address limits loose.
#  * Also put a firewall rate limit in front (for example iptables connlimit or
#    hashlimit). This script cannot stop a flood that comes from many addresses.
#  * If it stops, restart it. Do not run other programs on the same machine's
#    open ports.
require "socket"
require "monitor"
require "ipaddr"

class KIFRelay
  HELLO_MAX  = 256          # bytes in the first frame
  HELLO_WAIT = 10           # seconds to send it
  WAIT_MAX   = 10 * 60      # seconds a room waits for its second player
  MAX_ROOMS  = 200          # rooms waiting for a second player
  MAX_PAIRS  = 100          # sessions being relayed at once
  MAX_CONNS  = 400          # open sockets in total
  MAX_PER_IP = 16           # open sockets from one address (one IPv6 /64 counts as one)
  MAX_WAITING_PER_IP = 4    # waiting rooms from one address
  HELLOS_PER_MIN = 30       # rooms one address may open or join per minute
  IDLE_MAX   = 120          # seconds without a byte either way (the games ping every 5)
  PAIR_MAX   = 6 * 3600     # longest session
  WRITE_WAIT = 15           # seconds a player may refuse to read before the line is cut
  RATE       = 256 * 1024   # bytes a second each way, for a session
  BURST      = 2 * 1024 * 1024
  REAP_EVERY = 2            # seconds between looks at the waiting rooms
  TICK       = 5            # seconds between idle and age checks on a session
  HELLO = /\A\{"t":"relay","room":"([0-9a-f]{16})","role":"(host|join)"\}\z/

  attr_reader :port

  def initialize(port = 52413, bind = "0.0.0.0", log: $stdout)
    @port = port
    @bind = bind
    @log = log
    @rooms = {}   # room => { "host" or "join" => [sock, time] }: one waiting player
    @conns = {}   # every open socket => its address key
    @per_ip = Hash.new(0)
    @hellos = {}  # address key => times of its accepted hellos in the last minute
    @pairs = 0
    @lock = Monitor.new
  end

  def start
    @server = TCPServer.new(@bind, @port)
    @port = @server.addr[1]
    @thread = Thread.new { accept_loop }
    @reaper = Thread.new { loop { sleep REAP_EVERY; (reap rescue nil) } }
    say("relay listening on port #{@port}")
    return self
  end

  def stop
    (@server.close rescue nil)
    @reaper&.kill
    @lock.synchronize do
      @conns.each_key { |s| (s.close rescue nil) }
      @conns.clear
      @per_ip.clear
      @rooms.clear
    end
  end

  def run
    start
    @thread.join
  end

  private

  def say(text); (@log&.puts("#{Time.now.strftime('%H:%M:%S')} #{text}")) rescue nil; end

  def mono; Process.clock_gettime(Process::CLOCK_MONOTONIC); end

  def frame(text); [text.bytesize].pack("N") + text; end

  # one accept at a time; a failed accept or admit skips that socket only
  def accept_loop
    loop do
      c = begin
        @server.accept
      rescue StandardError
        break if @server.closed?
        sleep 0.2   # out of descriptors, aborted connection: try again
        next
      end
      begin
        admit(c)
      rescue StandardError
        drop(c)
      end
    end
  end

  def admit(c)
    (c.setsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, true)) rescue nil
    key = key_of(c)
    ok = @lock.synchronize do
      if @conns.length >= MAX_CONNS || @per_ip[key] >= MAX_PER_IP then false
      else
        @conns[c] = key
        @per_ip[key] += 1
        true
      end
    end
    return refuse(c, "busy") unless ok
    Thread.new(c) { |s| handle(s) }
  end

  # who counts as the same player machine: the IPv4 address or the IPv6 /64
  def key_of(sock)
    ip = sock.remote_address.ip_address.sub(/%.*\z/, "").sub(/\A::ffff:/i, "")
    ip.include?(":") ? IPAddr.new(ip).mask(64).to_s : ip
  rescue StandardError
    "?"   # the peer already reset the line
  end

  # the only way a socket is closed, so the counts stay right
  def drop(sock)
    @lock.synchronize do
      key = @conns.delete(sock)
      @per_ip.delete(key) if key && (@per_ip[key] -= 1) <= 0
    end
    (sock.close rescue nil)
  end

  def refuse(sock, why)
    (sock.write_nonblock(frame(%({"t":"relay_no","why":"#{why}"})), exception: false)) rescue nil
    drop(sock)
  end

  def read_exact(sock, n, stop)
    buf = "".b
    while buf.bytesize < n
      left = stop - mono
      return nil if left <= 0 || !IO.select([sock], nil, nil, left)
      buf << sock.readpartial(n - buf.bytesize)
    end
    buf
  end

  # a peer that stops reading cannot hold the thread: WRITE_WAIT, then error
  def write_all(sock, data)
    stop = mono + WRITE_WAIT
    until data.empty?
      n = sock.write_nonblock(data, exception: false)
      if n == :wait_writable
        left = stop - mono
        raise IOError, "write timed out" if left <= 0 || !IO.select(nil, [sock], nil, left)
      else
        data = data.byteslice(n, data.bytesize - n)
      end
    end
  end

  def handle(sock)
    stop = mono + HELLO_WAIT
    len = read_exact(sock, 4, stop)&.unpack1("N")
    text = len && len <= HELLO_MAX ? read_exact(sock, len, stop) : nil
    m = text && text.b.match(HELLO)
    return refuse(sock, "bad") unless m
    room, role = m[1], m[2]
    why, other = @lock.synchronize { join_room(sock, room, role) }
    return refuse(sock, why) if why
    return say("room #{room[0, 4]}...: #{role} waiting") unless other
    say("room #{room[0, 4]}...: paired")
    run_pair(sock, other[0])
  rescue StandardError
    drop(sock)
  end

  # lock held. Returns [why it was refused, nil] or [nil, the waiting player to pair with]
  def join_room(sock, room, role)
    t = mono
    key = @conns[sock] or return ["busy", nil]
    r = @rooms[room]
    l = (@hellos[key] ||= [])
    l.shift while l.first && t - l.first > 60
    return ["taken", nil] if r && r[role]
    return ["busy", nil] if l.length >= HELLOS_PER_MIN
    return ["full", nil] if r ? @pairs >= MAX_PAIRS : @rooms.length >= MAX_ROOMS
    return ["busy", nil] if !r && @rooms.each_value.count { |w| @conns[w.values[0][0]] == key } >= MAX_WAITING_PER_IP
    l << t
    r ||= (@rooms[room] = {})
    r[role] = [sock, t]
    other = r[role == "host" ? "join" : "host"]
    if other
      @rooms.delete(room)
      @pairs += 1
    end
    [nil, other]
  end

  def run_pair(a, b)
    pr = { last: mono, born: mono }
    [a, b].each { |s| write_all(s, frame('{"t":"relay_ok"}')) }
    t = Thread.new { pump(b, a, pr) }
    pump(a, b, pr)
    t.join
  rescue StandardError
    nil
  ensure
    drop(a)
    drop(b)
    @lock.synchronize { @pairs -= 1 if @pairs > 0 }
  end

  # copies one way until either side ends; ends the whole session when it stops
  def pump(from, to, pr)
    tokens = BURST.to_f
    filled = mono
    loop do
      t = mono
      break if from.closed? || to.closed? || t - pr[:last] > IDLE_MAX || t - pr[:born] > PAIR_MAX
      next unless IO.select([from], nil, nil, TICK)
      data = from.readpartial(16_384)
      t = mono
      pr[:last] = t
      tokens = [BURST, tokens + (t - filled) * RATE].min - data.bytesize
      filled = t
      if tokens < 0   # over the byte budget: slow this direction down
        sleep(-tokens / RATE)
        tokens = 0.0
        filled = mono
      end
      write_all(to, data)
    end
  rescue StandardError   # EOF, a reset line, a closed socket
    nil
  ensure
    drop(from)
    drop(to)
  end

  # waiting players send nothing: a readable (or closed) socket means they left, or sent junk
  def left?(sock)
    IO.select([sock], nil, nil, 0) ? true : false
  rescue StandardError
    true
  end

  def reap
    @lock.synchronize do
      t = mono
      @rooms.delete_if do |_, r|
        s, since = r.values[0]
        gone = t - since > WAIT_MAX || left?(s)
        drop(s) if gone
        gone
      end
      @hellos.delete_if { |_, l| l.last.nil? || t - l.last > 60 }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  port = (ARGV[0] || 52413).to_i
  bind = ARGV[1] || "0.0.0.0"
  begin
    KIFRelay.new(port, bind).run
  rescue SystemCallError, SocketError => e
    abort "kif_relay: can't listen on #{bind} port #{port}: #{e.message}"
  end
end
